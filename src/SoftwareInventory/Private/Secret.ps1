# API-Schlüssel und Tokens. Sie sind optional und dürfen nie in Protokollen, Snapshots,
# Berichten oder Fehlermeldungen erscheinen (siehe CLAUDE.md).
# Reihenfolge: Windows-Anmeldeinformationsverwaltung zuerst, dann Umgebungsvariable (für Skripte/Tests).

$script:SecretVariable = @{
    NVD     = 'NVD_API_KEY'
    GitHub  = 'GITHUB_TOKEN'
    Advisor = 'SOFTWAREINVENTORY_ADVISOR_KEY'   # optional, für lokale KI-Server mit Schlüssel (z. B. Unsloth Studio)
}
# Eintrag in der Anmeldeinformationsverwaltung: <Präfix>/<Dienst>, Typ „Generisch“, nur dieser Benutzer.
$script:CredentialPrefix = 'SoftwareInventory'

function Initialize-CredentialInterop {
    if ('SoftwareInventory.CredentialStore' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security;

namespace SoftwareInventory
{
    public static class CredentialStore
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct Credential
        {
            public uint Flags;
            public uint Type;
            public string TargetName;
            public string Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public uint CredentialBlobSize;
            public IntPtr CredentialBlob;
            public uint Persist;
            public uint AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }

        private const uint Generic = 1;
        private const uint PersistLocalMachine = 2;
        private const int NotFound = 1168;
        private const int MaxBlobBytes = 2560;

        [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);

        [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredWrite(ref Credential credential, uint flags);

        [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredDelete(string target, uint type, uint flags);

        [DllImport("advapi32.dll")]
        private static extern void CredFree(IntPtr buffer);

        public static string Read(string target)
        {
            IntPtr pointer;
            if (!CredRead(target, Generic, 0, out pointer))
            {
                int error = Marshal.GetLastWin32Error();
                if (error == NotFound) { return null; }
                throw new Win32Exception(error);
            }
            try
            {
                var credential = Marshal.PtrToStructure<Credential>(pointer);
                if (credential.CredentialBlobSize == 0 || credential.CredentialBlob == IntPtr.Zero) { return null; }
                return Marshal.PtrToStringUni(credential.CredentialBlob, (int)credential.CredentialBlobSize / 2);
            }
            finally
            {
                CredFree(pointer);
            }
        }

        public static void Write(string target, string userName, SecureString secret)
        {
            int bytes = secret.Length * 2;
            if (bytes == 0 || bytes > MaxBlobBytes) { throw new ArgumentException("Schlüssel ist leer oder zu lang."); }
            IntPtr blob = Marshal.SecureStringToGlobalAllocUnicode(secret);
            try
            {
                var credential = new Credential
                {
                    Type = Generic,
                    TargetName = target,
                    UserName = userName,
                    CredentialBlobSize = (uint)bytes,
                    CredentialBlob = blob,
                    Persist = PersistLocalMachine,
                };
                if (!CredWrite(ref credential, 0)) { throw new Win32Exception(Marshal.GetLastWin32Error()); }
            }
            finally
            {
                Marshal.ZeroFreeGlobalAllocUnicode(blob);
            }
        }

        public static bool Delete(string target)
        {
            if (CredDelete(target, Generic, 0)) { return true; }
            int error = Marshal.GetLastWin32Error();
            if (error == NotFound) { return false; }
            throw new Win32Exception(error);
        }
    }
}
'@
}

function Get-CredentialTarget {
    param([Parameter(Mandatory)] [string] $Service)
    "$script:CredentialPrefix/$Service"
}

function Read-StoredSecret {
    # Schlüssel aus der Anmeldeinformationsverwaltung oder $null. Lesefehler gelten als „kein Schlüssel“.
    param([Parameter(Mandatory)] [string] $Service)
    try {
        Initialize-CredentialInterop
        $value = [SoftwareInventory.CredentialStore]::Read((Get-CredentialTarget $Service))
    }
    catch {
        Write-Verbose "Anmeldeinformationsverwaltung nicht lesbar ($Service): $($_.Exception.Message)"
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    $value.Trim()
}

function Read-EnvironmentSecret {
    param([Parameter(Mandatory)] [string] $Service)
    $value = [Environment]::GetEnvironmentVariable($script:SecretVariable[$Service])
    if ([string]::IsNullOrWhiteSpace($value)) { return $null }
    $value.Trim()
}

function Get-ServiceSecret {
    # Liefert den Schlüssel oder $null. Der Rückgabewert darf nur in Request-Header wandern.
    param([Parameter(Mandatory)] [ValidateSet('NVD', 'GitHub', 'Advisor')] [string] $Service)
    $stored = Read-StoredSecret -Service $Service
    if ($stored) { return $stored }
    Read-EnvironmentSecret -Service $Service
}

function Protect-SecretText {
    <#
    .SYNOPSIS
        Ersetzt bekannte Schlüssel in einem Text durch „***“.
    .DESCRIPTION
        Schutznetz für Fehlermeldungen und ausführliche Ausgaben: Selbst wenn ein Schlüssel
        über eine Ausnahme in einen Text gerät, wird er vor der Ausgabe entfernt. Maskiert
        werden Schlüssel aus beiden Ablagen, auch wenn nur einer davon benutzt wird.
    #>
    param([AllowNull()] [AllowEmptyString()] [string] $Text)
    if (-not $Text) { return $Text }
    foreach ($service in $script:SecretVariable.Keys) {
        foreach ($secret in @((Read-StoredSecret -Service $service), (Read-EnvironmentSecret -Service $service))) {
            if ($secret) { $Text = $Text.Replace($secret, '***') }
        }
    }
    $Text
}
