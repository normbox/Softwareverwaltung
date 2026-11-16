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
        private const string Everyone = "S-1-1-0";
        private const string CreatorOwner = "S-1-3-0";
        private const string CreatorGroup = "S-1-3-1";

        public bool Exists(string path) => Directory.Exists(path);

        public bool IsReparsePoint(string path) => (File.GetAttributes(path) & FileAttributes.ReparsePoint) != 0;

        public string OwnerSid(string path) =>
            new DirectoryInfo(path).GetAccessControl(AccessControlSections.Owner).GetOwner(typeof(SecurityIdentifier))?.Value;

        public IReadOnlyList<string> WriteAccessSids(string path)
        {
            var bytes = new DirectoryInfo(path).GetAccessControl(AccessControlSections.Access).GetSecurityDescriptorBinaryForm();
            return WriteSidsFromDescriptor(new RawSecurityDescriptor(bytes, 0));
        }

        /// <summary>
        /// SIDs, die ein Schreib-Recht für den Ordner oder für Dateien darin bekommen. Fail-closed: Ohne DACL darf jeder
        /// alles (Jeder), und Erlauben-Einträge, die sich nicht einfach auswerten lassen (Objekt-, Callback- oder
        /// Compound-Einträge), zählen als <see cref="AclRules.UnsupportedAce"/>. Nur vererbte Einträge („nur Unterobjekte“)
        /// zählen mit, weil Dateien, die der Helfer später im Ordner anlegt, sie erben; ausgenommen sind die Platzhalter
        /// ERSTELLER-BESITZER und ERSTELLER-GRUPPE, die beim Erben zum Ersteller (hier ein Administrator) werden.
        /// Verweigern-Einträge werden ignoriert (das ist strenger, nie lockerer).
        /// </summary>
        public static IReadOnlyList<string> WriteSidsFromDescriptor(RawSecurityDescriptor descriptor)
        {
            var result = new List<string>();
            var acl = descriptor.DiscretionaryAcl;
            if (acl is null)
            {
                result.Add(Everyone);
                return result;
            }
            foreach (GenericAce ace in acl)
            {
                switch (ace.AceType)
                {
                    case AceType.AccessAllowed:
                        var common = (CommonAce)ace;
                        if (!AclRules.IsWriteMask(unchecked((uint)common.AccessMask)))
                        {
                            break;
                        }
                        var inheritOnly = (ace.AceFlags & AceFlags.InheritOnly) != 0;
                        var inherits = (ace.AceFlags & (AceFlags.ObjectInherit | AceFlags.ContainerInherit)) != 0;
                        if (inheritOnly && !inherits)
                        {
                            break;
                        }
                        var sid = common.SecurityIdentifier.Value;
                        if (inheritOnly && (sid == CreatorOwner || sid == CreatorGroup))
                        {
                            break;
                        }
                        result.Add(sid);
                        break;
                    case AceType.AccessAllowedCompound:
                    case AceType.AccessAllowedObject:
                    case AceType.AccessAllowedCallback:
                    case AceType.AccessAllowedCallbackObject:
                        result.Add(AclRules.UnsupportedAce);
                        break;
                }
            }
            return result;
        }
    }
}
