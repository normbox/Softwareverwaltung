#nullable disable
using System.Collections.Generic;
using System.IO;
using System.Security.AccessControl;
using System.Security.Principal;

namespace SoftwareInventory.Helper
{
    /// <summary>Die echte Umsetzung von <see cref="IDirectoryInspector"/> über die Zugriffssteuerungsliste des Ordners.</summary>
    public sealed class WindowsDirectoryInspector : IDirectoryInspector
    {
        private const FileSystemRights WriteRights =
            FileSystemRights.WriteData | FileSystemRights.AppendData | FileSystemRights.WriteExtendedAttributes |
            FileSystemRights.WriteAttributes | FileSystemRights.Delete | FileSystemRights.DeleteSubdirectoriesAndFiles |
            FileSystemRights.ChangePermissions | FileSystemRights.TakeOwnership;

        public bool Exists(string path) => Directory.Exists(path);

        public bool IsReparsePoint(string path) => (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;

        public string OwnerSid(string path) =>
            new DirectoryInfo(path).GetAccessControl(AccessControlSections.Owner).GetOwner(typeof(SecurityIdentifier))?.Value;

        public IReadOnlyList<string> WriteAccessSids(string path)
        {
            var result = new List<string>();
            var security = new DirectoryInfo(path).GetAccessControl(AccessControlSections.Access);
            foreach (FileSystemAccessRule rule in security.GetAccessRules(true, true, typeof(SecurityIdentifier)))
            {
                if (rule.AccessControlType == AccessControlType.Allow
                    && (rule.PropagationFlags & PropagationFlags.InheritOnly) == 0
                    && (rule.FileSystemRights & WriteRights) != 0)
                {
                    result.Add(rule.IdentityReference.Value);
                }
            }
            return result;
        }
    }
}
