namespace SoftwareInventory
{
    /// <summary>
    /// Bauart dieser DLL. Nur Debug-Builds dürfen die geschützte Kopie des Helfers über den Hash anerkennen;
    /// im Release zählt ausschließlich die Signatur.
    /// </summary>
    public static class BuildInfo
    {
#if DEBUG
        public static bool IsDebugBuild => true;
#else
        public static bool IsDebugBuild => false;
#endif
    }
}
