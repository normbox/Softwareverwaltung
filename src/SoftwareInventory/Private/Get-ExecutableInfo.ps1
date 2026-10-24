function Get-ExecutableInfo {
    <#
    .SYNOPSIS
        Liest Versionsinformationen, Signatur und SHA256 einer .exe, ohne sie auszuführen.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        # Der Hash liest die ganze Datei und kostet bei großen Dateien spürbar Zeit.
        [switch] $SkipHash
    )

    $file = Get-Item -LiteralPath $Path -ErrorAction Stop
    $fvi = $file.VersionInfo
    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction SilentlyContinue

    [pscustomobject] @{
        Path            = $file.FullName
        Directory       = $file.DirectoryName
        Length          = $file.Length
        Name            = ConvertTo-NullIfEmpty $fvi.ProductName
        Description     = ConvertTo-NullIfEmpty $fvi.FileDescription
        Company         = ConvertTo-NullIfEmpty $fvi.CompanyName
        Version         = Get-FileVersionString $fvi
        Sha256          = if (-not $SkipHash) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash }
        SignatureStatus = if ($signature) { [string] $signature.Status } else { $null }
        Signer          = if ($signature -and $signature.SignerCertificate) {
            ConvertFrom-DistinguishedName ($signature.SignerCertificate.Subject -replace '^.*?CN=', 'CN=')
        }
        Machine         = Get-PeMachine $Path
    }
}

function Get-FileVersionString {
    # Bevorzugt die numerischen Felder; ProductVersion enthält oft Zusätze wie Commit-Hashes.
    param([System.Diagnostics.FileVersionInfo] $Info)
    $product = @($Info.ProductMajorPart, $Info.ProductMinorPart, $Info.ProductBuildPart, $Info.ProductPrivatePart)
    if (($product | Measure-Object -Sum).Sum -gt 0) { return $product -join '.' }
    $fileParts = @($Info.FileMajorPart, $Info.FileMinorPart, $Info.FileBuildPart, $Info.FilePrivatePart)
    if (($fileParts | Measure-Object -Sum).Sum -gt 0) { return $fileParts -join '.' }
    ConvertTo-NullIfEmpty $Info.ProductVersion
}

function Get-PeMachine {
    # Liest die Zielarchitektur aus dem PE-Kopf (nur die ersten Bytes, ohne Ausführung).
    param([string] $Path)
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        try {
            $reader = [System.IO.BinaryReader]::new($stream)
            if ($stream.Length -lt 64) { return $null }
            $stream.Position = 0x3C
            $peOffset = $reader.ReadInt32()
            if ($peOffset -lt 0 -or $peOffset + 6 -gt $stream.Length) { return $null }
            $stream.Position = $peOffset + 4
            switch ($reader.ReadUInt16()) {
                0x8664 { 'X64' }
                0x014C { 'X86' }
                0xAA64 { 'Arm64' }
                default { $null }
            }
        }
        finally { $stream.Dispose() }
    }
    catch { $null }
}
