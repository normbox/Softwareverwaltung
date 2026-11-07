using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security;

namespace SoftwareInventory
{
    /// <summary>
    /// Generische Einträge der Windows-Anmeldeinformationsverwaltung, nur für den angemeldeten Benutzer.
    /// Benutzertexte erzeugt das Modul (SoftwareInventory.Strings.psd1); Ausnahmen hier sind Entwicklertexte.
    /// </summary>
    public static class CredentialStore
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct Credential
        {
            public uint Flags;
            public uint Type;
            public string TargetName;
            public string? Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public uint CredentialBlobSize;
            public IntPtr CredentialBlob;
            public uint Persist;
            public uint AttributeCount;
            public IntPtr Attributes;
            public string? TargetAlias;
            public string UserName;
        }

        private const uint Generic = 1;
        private const uint PersistLocalMachine = 2;
        private const int NotFound = 1168;

        /// <summary>Größte erlaubte Länge eines Schlüssels in Zeichen (2560 Bytes, Grenze von Windows).</summary>
        public const int MaxSecretLength = 1280;

        [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);

        [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredWrite(ref Credential credential, uint flags);

        [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredDelete(string target, uint type, uint flags);

        [DllImport("advapi32.dll")]
        private static extern void CredFree(IntPtr buffer);

        /// <summary>Schlüssel zum Ziel oder null, wenn es keinen Eintrag gibt.</summary>
        public static string? Read(string target)
        {
            if (!CredRead(target, Generic, 0, out var pointer))
            {
                var error = Marshal.GetLastWin32Error();
                if (error == NotFound)
                {
                    return null;
                }
                throw new Win32Exception(error);
            }
            try
            {
                var credential = Marshal.PtrToStructure<Credential>(pointer);
                if (credential.CredentialBlobSize == 0 || credential.CredentialBlob == IntPtr.Zero)
                {
                    return null;
                }
                return Marshal.PtrToStringUni(credential.CredentialBlob, (int)credential.CredentialBlobSize / 2);
            }
            finally
            {
                CredFree(pointer);
            }
        }

        /// <summary>Schreibt den Schlüssel; der Klartext liegt nur kurz in nicht verwaltetem Speicher und wird genullt.</summary>
        public static void Write(string target, string userName, SecureString secret)
        {
            if (secret is null || secret.Length == 0 || secret.Length > MaxSecretLength)
            {
                throw new ArgumentException("Secret is empty or longer than " + MaxSecretLength + " characters.", nameof(secret));
            }
            var blob = Marshal.SecureStringToGlobalAllocUnicode(secret);
            try
            {
                var credential = new Credential
                {
                    Type = Generic,
                    TargetName = target,
                    UserName = userName,
                    CredentialBlobSize = (uint)(secret.Length * 2),
                    CredentialBlob = blob,
                    Persist = PersistLocalMachine,
                };
                if (!CredWrite(ref credential, 0))
                {
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                }
            }
            finally
            {
                Marshal.ZeroFreeGlobalAllocUnicode(blob);
            }
        }

        /// <summary>Löscht den Eintrag; false, wenn es keinen gab.</summary>
        public static bool Delete(string target)
        {
            if (CredDelete(target, Generic, 0))
            {
                return true;
            }
            var error = Marshal.GetLastWin32Error();
            if (error == NotFound)
            {
                return false;
            }
            throw new Win32Exception(error);
        }
    }
}
