using Softwareverwaltung.App.Services;

namespace Softwareverwaltung.App.Tests;

public sealed class ErrorLogTests
{
    [Fact]
    public void WritesTypeMessageAndStackTrace()
    {
        var saved = ErrorLog.Directory;
        ErrorLog.Directory = Path.Combine(Path.GetTempPath(), "SoftwareverwaltungTests", Guid.NewGuid().ToString("N"));
        try
        {
            Exception captured;
            try { throw new InvalidOperationException("0"); }
            catch (Exception ex) { captured = ex; }

            var path = ErrorLog.Write("UI", captured);

            Assert.NotNull(path);
            var text = File.ReadAllText(path);
            Assert.Contains("UI", text);
            Assert.Contains("System.InvalidOperationException: 0", text);
            Assert.Contains(nameof(WritesTypeMessageAndStackTrace), text);
        }
        finally
        {
            Directory.Delete(ErrorLog.Directory, recursive: true);
            ErrorLog.Directory = saved;
        }
    }
}
