#nullable disable
using System;
using System.Collections.Generic;
using System.Text;
using System.Web.Script.Serialization;

namespace SoftwareInventory.Helper
{
    /// <summary>
    /// Liest die Bytes einer Begleitdatei (&lt;Id&gt;.json, Format von Write-RegistryBackupSidecar bzw.
    /// <see cref="RegistryRemoval.BuildSidecar"/>). Nur .NET Framework (JavaScriptSerializer); getestet im net472-Testprojekt.
    /// </summary>
    public static class SidecarParser
    {
        /// <summary>Größte erlaubte Begleitdatei (wie $script:RegistryBackupSidecarMaxBytes im Modul).</summary>
        public const int MaxBytes = 64 * 1024;

        /// <summary>Die Angaben, oder null, wenn die Bytes leer, zu groß, kein gültiges UTF-8 oder kein JSON-Objekt sind.</summary>
        public static BackupSidecar Parse(byte[] bytes)
        {
            if (bytes is null || bytes.Length == 0 || bytes.Length > MaxBytes)
            {
                return null;
            }
            Dictionary<string, object> data;
            try
            {
                var json = new UTF8Encoding(false, true).GetString(bytes);
                data = new JavaScriptSerializer().DeserializeObject(json) as Dictionary<string, object>;
            }
            catch (Exception ex) when (ex is ArgumentException || ex is InvalidOperationException)
            {
                return null;
            }
            if (data is null)
            {
                return null;
            }
            string Text(string name) => data.TryGetValue(name, out var value) ? value as string : null;
            return new BackupSidecar
            {
                SchemaVersion = data.TryGetValue("SchemaVersion", out var version) && version is int number ? number : 0,
                ActionId = Text("ActionId"),
                NativeKey = Text("NativeKey"),
                Scope = Text("Scope"),
            };
        }
    }
}
