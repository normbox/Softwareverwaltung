using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Linq;
using System.Management;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Security.Principal;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using Microsoft.Win32;

[assembly: DefaultDllImportSearchPaths(DllImportSearchPath.System32)]

namespace SoftwareInventory.Helper
{
    /// <summary>
    /// Führt einen Plan des Moduls aus. Trifft keine eigenen Entscheidungen außer den Prüfungen in
    /// <see cref="HelperRules"/>. Auf der Kommandozeile steht nur der Name der Pipe; der Plan kommt erst
    /// nach dem Handschlag über die Pipe. Ohne Gegenstelle läuft nichts.
    /// </summary>
    internal static class Program
    {
        private const uint LoadLibrarySearchSystem32 = 0x00000800;

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetDefaultDllDirectories(uint directoryFlags);

        private static int Main(string[] args)
        {
            SetDefaultDllDirectories(LoadLibrarySearchSystem32);
            if (args.Length != 2 || args[0] != "--pipe")
            {
                return 2;
            }
            try
            {
                new HelperRun(args[1]).Execute();
                return 0;
            }
            catch (Exception)
            {
                return 1;
            }
        }
    }

    /// <summary>Verbindung zum Modul. Asynchron geöffnet, damit Lesen und Schreiben sich nicht blockieren.</summary>
    internal sealed class HelperChannel : IDisposable
    {
        private readonly NamedPipeClientStream _pipe;
        private readonly StreamReader _reader;
        private readonly StreamWriter _writer;
        private readonly JavaScriptSerializer _json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
        private Task<string>? _pending;

        public HelperChannel(string pipeName)
        {
            _pipe = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.Asynchronous);
            _pipe.Connect(30000);
            var utf8 = new UTF8Encoding(false);
            _reader = new StreamReader(_pipe, utf8);
            _writer = new StreamWriter(_pipe, utf8) { AutoFlush = true };
        }

        public bool Closed { get; private set; }

        public void Write(object value) => _writer.WriteLine(_json.Serialize(value));

        public Dictionary<string, object?>? Parse(string line) => _json.DeserializeObject(line) as Dictionary<string, object?>;

        /// <summary>Wartet auf die nächste Zeile; null, wenn die Verbindung weg ist.</summary>
        public string? ReadLine()
        {
            var task = _pending ?? _reader.ReadLineAsync();
            _pending = null;
            try
            {
                return task.GetAwaiter().GetResult();
            }
            catch (Exception)
            {
                return null;
            }
        }

        /// <summary>Ohne zu warten: Kam „cancel“? Ist die Verbindung weg, läuft die Aktion einfach weiter.</summary>
        public bool CancelRequested()
        {
            if (Closed)
            {
                return false;
            }
            _pending ??= _reader.ReadLineAsync();
            if (!_pending.IsCompleted)
            {
                return false;
            }
            var line = ReadLine();
            if (line is null)
            {
                Closed = true;
                return false;
            }
            return line == "cancel";
        }

        public void MarkClosed() => Closed = true;

        public void Drain() => _pipe.WaitForPipeDrain();

        public void Dispose() => _pipe.Dispose();
    }

    internal sealed class ProcessTarget : ICancelTarget
    {
        private readonly Process _process;

        public ProcessTarget(Process process)
        {
            _process = process;
        }

        public int Id => _process.Id;

        public void Kill() => _process.Kill();

        public bool WaitForExit(int milliseconds) => _process.WaitForExit(milliseconds);
    }

    internal sealed class WmiRestorePointApi : IRestorePointApi
    {
        private static readonly ManagementScope Scope = new ManagementScope(@"\\.\root\default");

        public long LatestSequence()
        {
            using (var searcher = new ManagementObjectSearcher(Scope, new ObjectQuery("SELECT SequenceNumber FROM SystemRestore")))
            {
                return searcher.Get().Cast<ManagementBaseObject>().Select(o => Convert.ToInt64(o["SequenceNumber"])).DefaultIfEmpty(0).Max();
            }
        }

        public long Create(string description, uint type)
        {
            try
            {
                using (var cls = new ManagementClass(Scope, new ManagementPath("SystemRestore"), null))
                using (var input = cls.GetMethodParameters("CreateRestorePoint"))
                {
                    input["Description"] = description;
                    input["RestorePointType"] = type;
                    input["EventType"] = 100u;
                    using (var output = cls.InvokeMethod("CreateRestorePoint", input, null))
                    {
                        return Convert.ToInt64(output["ReturnValue"]);
                    }
                }
            }
            catch (ManagementException ex)
            {
                throw new RestorePointApiException(ex.Message, new[] { ex.HResult, unchecked((int)ex.ErrorCode) });
            }
            catch (COMException ex)
            {
                throw new RestorePointApiException(ex.Message, new[] { ex.HResult });
            }
        }

        public bool ProtectionDisabled()
        {
            // RPSessionInterval = 0 bedeutet: Computerschutz ist ausgeschaltet. Fehlt der Wert, gilt „unbekannt“.
            using (var key = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64).OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"))
            {
                return key?.GetValue("RPSessionInterval") is int value && value == 0;
            }
        }
    }

    /// <summary>Authenticode-Prüfung einer Datei; liefert den Herausgeber oder null, wenn die Signatur nicht gültig ist.</summary>
    internal static class SignatureCheck
    {
        private static readonly Guid GenericVerifyV2 = new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct FileInfoData
        {
            public int Size;
            public string FilePath;
            public IntPtr File;
            public IntPtr KnownSubject;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct TrustData
        {
            public int Size;
            public IntPtr PolicyCallback;
            public IntPtr SipClient;
            public int UiChoice;
            public int RevocationChecks;
            public int UnionChoice;
            public IntPtr File;
            public int StateAction;
            public IntPtr StateData;
            public IntPtr UrlReference;
            public int ProviderFlags;
            public int UiContext;
            public IntPtr SignatureSettings;
        }

        [DllImport("wintrust.dll", CharSet = CharSet.Unicode)]
        private static extern int WinVerifyTrust(IntPtr window, [MarshalAs(UnmanagedType.LPStruct)] Guid action, ref TrustData data);

        private static bool IsTrusted(string path)
        {
            const int UiNone = 2;
            const int ChoiceFile = 1;
            var file = new FileInfoData { Size = Marshal.SizeOf<FileInfoData>(), FilePath = path };
            var pointer = Marshal.AllocHGlobal(file.Size);
            try
            {
                Marshal.StructureToPtr(file, pointer, false);
                var data = new TrustData { Size = Marshal.SizeOf<TrustData>(), UiChoice = UiNone, UnionChoice = ChoiceFile, File = pointer };
                return WinVerifyTrust(new IntPtr(-1), GenericVerifyV2, ref data) == 0;
            }
            finally
            {
                Marshal.DestroyStructure<FileInfoData>(pointer);
                Marshal.FreeHGlobal(pointer);
            }
        }

        public static string? Publisher(string path)
        {
            try
            {
                if (!File.Exists(path) || !IsTrusted(path))
                {
                    return null;
                }
                using (var certificate = new X509Certificate2(X509Certificate.CreateFromSignedFile(path)))
                {
                    return certificate.Subject;
                }
            }
            catch (CryptographicException)
            {
                return null;
            }
        }
    }

    internal sealed class HelperRun
    {
        private readonly string _pipeName;
        private readonly HelperPaths _paths = HelperPaths.Current();
        private readonly bool _elevated = new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator);
        private readonly IRestorePointApi _restorePoints = new WmiRestorePointApi();

        public HelperRun(string pipeName)
        {
            _pipeName = pipeName;
        }

        public void Execute()
        {
            using (var channel = new HelperChannel(_pipeName))
            {
                channel.Write(new Dictionary<string, object?> { ["Kind"] = "Hello", ["HelperVersion"] = 4 });
                var first = channel.ReadLine();
                if (first is null || first == "stop")
                {
                    return;
                }
                var plan = channel.Parse(first);
                if (plan is null)
                {
                    return;
                }
                if (Flag(plan, "RemoveOtherHelperCopies"))
                {
                    RemoveOlderCopies();
                }
                if (plan.TryGetValue("Steps", out var steps) && steps is object[] { Length: > 0 } list)
                {
                    RunBatch(channel, plan, list);
                }
                else
                {
                    RunSingle(channel, plan);
                }
                channel.Drain();
            }
        }

        private void RunSingle(HelperChannel channel, Dictionary<string, object?> plan)
        {
            var result = NewResult(plan, "Result");
            try
            {
                if (Text(plan, "Operation") == "ReplaceHelperCopy")
                {
                    ReplaceHelperCopy(plan, result);
                    channel.Write(result);
                    return;
                }
                if (Flag(plan, "RestorePoint"))
                {
                    AddRestorePoint(result, plan);
                }
                if (Text(plan, "FilePath") is not null)
                {
                    RunChecked(channel, plan, Text(plan, "Nonce") ?? "", result);
                }
            }
            catch (Exception ex)
            {
                SetError(result, "HelperException", ex.Message);
            }
            channel.Write(result);
        }

        /// <summary>
        /// Mehrere Programme mit einer einzigen UAC-Abfrage. Vor jedem Schritt wartet der Helfer auf eine
        /// Zeile: „next“ führt ihn aus, alles andere beendet den Stapel.
        /// </summary>
        private void RunBatch(HelperChannel channel, Dictionary<string, object?> plan, object[] steps)
        {
            var start = NewResult(plan, "Start");
            try
            {
                if (Flag(plan, "RestorePoint"))
                {
                    AddRestorePoint(start, plan);
                }
            }
            catch (Exception ex)
            {
                SetError(start, "HelperException", ex.Message);
            }
            channel.Write(start);

            var index = 0;
            foreach (var step in steps.OfType<Dictionary<string, object?>>())
            {
                if (channel.ReadLine() != "next")
                {
                    break;
                }
                var result = NewResult(plan, "Step");
                result["Index"] = index;
                try
                {
                    RunChecked(channel, step, $"{Text(plan, "Nonce")}-{index}", result);
                }
                catch (Exception ex)
                {
                    SetError(result, "HelperException", ex.Message);
                }
                channel.Write(result);
                index++;
            }
            channel.Write(new Dictionary<string, object?> { ["Kind"] = "End", ["Nonce"] = Text(plan, "Nonce") });
        }

        private static string OwnPath()
        {
            using (var process = Process.GetCurrentProcess())
            {
                return process.MainModule!.FileName!;
            }
        }

        /// <summary>
        /// Neue Version in einen eigenen Ordner neben diese Exe legen. Die Quelle liegt im beschreibbaren App-Ordner,
        /// deshalb zählt die Prüfung der fertigen Kopie unter Program Files, nicht die der Quelle.
        /// </summary>
        private void ReplaceHelperCopy(Dictionary<string, object?> plan, Dictionary<string, object?> result)
        {
            var own = OwnPath();
            var source = Text(plan, "SourcePath");
            var version = Text(plan, "TargetVersion");
            var ownPublisher = SignatureCheck.Publisher(own);
            var problem = HelperCopyRules.CheckReplace(own, _paths.ProgramFiles, source!, version!, ownPublisher!, SignatureCheck.Publisher(source!)!);
            if (problem is not null)
            {
                result["ErrorCode"] = problem.Code;
                result["ErrorArgs"] = problem.Args;
                return;
            }
            var folder = Path.Combine(HelperCopyRules.CopyRoot(own, _paths.ProgramFiles), version!);
            Directory.CreateDirectory(folder);
            var target = Path.Combine(folder, HelperCopyRules.FileName);
            var temporary = target + ".tmp";
            File.Copy(source!, temporary, true);
            if (SignatureCheck.Publisher(temporary) != ownPublisher)
            {
                File.Delete(temporary);
                SetError(result, "HelperCopyUntrusted");
                return;
            }
            File.Delete(target);
            File.Move(temporary, target);
            result["Replaced"] = true;
        }

        /// <summary>Räumt nach einem Austausch auf; der alte Ordner war belegt, solange die alte Exe lief.</summary>
        private void RemoveOlderCopies()
        {
            if (!_elevated)
            {
                return;
            }
            var own = OwnPath();
            var root = HelperCopyRules.CopyRoot(own, _paths.ProgramFiles);
            if (root is null)
            {
                return;
            }
            foreach (var directory in HelperCopyRules.OlderSiblings(Path.GetFileName(Path.GetDirectoryName(own)), Directory.GetDirectories(root)))
            {
                try
                {
                    Directory.Delete(directory, true);
                }
                catch (IOException)
                {
                    // Aufräumen ist eine Zugabe; beim nächsten Lauf erneut.
                }
                catch (UnauthorizedAccessException)
                {
                    // Ebenso.
                }
            }
        }

        private void RunChecked(HelperChannel channel, Dictionary<string, object?> plan, string logId, Dictionary<string, object?> result)
        {
            var file = Text(plan, "FilePath");
            var problem = HelperRules.CheckFilePath(file!, _elevated, _paths)
                ?? HelperRules.CheckCommand(Text(plan, "Method")!, file!, Text(plan, "Arguments")!, Text(plan, "RegistryKey")!, _elevated, _paths, ReadUninstallValue);
            if (problem is not null)
            {
                result["ErrorCode"] = problem.Code;
                result["ErrorArgs"] = problem.Args;
                return;
            }
            RunProcess(channel, plan, logId, result);
        }

        private static string? ReadUninstallValue(string registryKey, string valueName)
        {
            var path = registryKey.Substring(@"HKLM:\".Length);
            using (var key = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64).OpenSubKey(path))
            {
                return key?.GetValue(valueName) as string;
            }
        }

        private void AddRestorePoint(Dictionary<string, object?> result, Dictionary<string, object?> plan)
        {
            var outcome = RestorePointRules.Run(_restorePoints, Text(plan, "RestorePointDescription") ?? "", Convert.ToUInt32(plan["RestorePointType"]));
            result["RestorePoint"] = outcome.Status;
            result["RestorePointCode"] = outcome.Code;
            result["RestorePointArgs"] = outcome.Args;
        }

        /// <summary>Startet das Programm ohne Shell und wartet höchstens TimeoutSeconds.</summary>
        private static void RunProcess(HelperChannel channel, Dictionary<string, object?> plan, string logId, Dictionary<string, object?> result)
        {
            var file = Text(plan, "FilePath")!;
            var arguments = Text(plan, "Arguments") ?? "";
            string? logPath = null;
            if (Flag(plan, "MsiLog"))
            {
                logPath = Path.Combine(Path.GetTempPath(), "SoftwareInventory-" + logId + ".log");
                arguments = (arguments + " /l*v \"" + logPath + "\"").Trim();
            }

            var info = new ProcessStartInfo(file, arguments)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8,
            };

            try
            {
                using (var process = Process.Start(info)!)
                {
                    result["Started"] = true;
                    var stdout = process.StandardOutput.ReadToEndAsync();
                    var stderr = process.StandardError.ReadToEndAsync();
                    var limit = Convert.ToInt64(plan["TimeoutSeconds"]) * 1000;
                    var clock = Stopwatch.StartNew();
                    var cancelHandled = false;
                    var exited = false;
                    while (true)
                    {
                        if (process.WaitForExit(500))
                        {
                            exited = true;
                            break;
                        }
                        if (clock.ElapsedMilliseconds >= limit)
                        {
                            break;
                        }
                        if (!cancelHandled && channel.CancelRequested())
                        {
                            cancelHandled = true;
                            HandleCancel(channel, process, file, plan, result);
                        }
                    }
                    if (exited)
                    {
                        result["ExitCode"] = process.ExitCode;
                        // Begrenzt: Ein weiterlaufender Kindprozess kann die Ausgabe sonst beliebig lange offen halten.
                        try
                        {
                            if (Task.WaitAll(new Task[] { stdout, stderr }, 10000))
                            {
                                result["Output"] = HelperRules.OutputTail(stdout.Result + "\n" + stderr.Result);
                            }
                        }
                        catch (AggregateException)
                        {
                            result["Output"] = null;
                        }
                    }
                    else
                    {
                        // Nicht beenden: Ein halb abgebrochenes Deinstallationsprogramm ist schlimmer.
                        result["TimedOut"] = true;
                    }
                }
            }
            finally
            {
                if (logPath is not null && File.Exists(logPath))
                {
                    try
                    {
                        result["InstallerLog"] = HelperRules.OutputTail(File.ReadAllText(logPath), 2000);
                    }
                    catch (IOException)
                    {
                        result["InstallerLog"] = null;
                    }
                    try
                    {
                        File.Delete(logPath);
                    }
                    catch (IOException)
                    {
                        // Temp räumt Windows auf; das Ergebnis der Aktion hängt nicht daran.
                    }
                }
            }
        }

        private static void HandleCancel(HelperChannel channel, Process process, string file, Dictionary<string, object?> plan, Dictionary<string, object?> result)
        {
            var outcome = CancelRules.Request(file, new ProcessTarget(process), ChildProcessNames);
            if (outcome == CancelRules.Stopped)
            {
                result["Cancelled"] = true;
            }
            else if (outcome == CancelRules.Orphaned)
            {
                SetError(result, "ActionCancelOrphaned");
            }
            // Die Aktion läuft auch weiter, wenn niemand mehr zuhört.
            try
            {
                channel.Write(new Dictionary<string, object?> { ["Kind"] = "CancelReply", ["Nonce"] = Text(plan, "Nonce"), ["Outcome"] = outcome });
            }
            catch (IOException)
            {
                channel.MarkClosed();
            }
        }

        private static IEnumerable<string> ChildProcessNames(int parentId)
        {
            using (var searcher = new ManagementObjectSearcher($"SELECT Name FROM Win32_Process WHERE ParentProcessId = {parentId}"))
            {
                return searcher.Get().Cast<ManagementBaseObject>().Select(o => (string)o["Name"]).ToList();
            }
        }

        private static Dictionary<string, object?> NewResult(Dictionary<string, object?> plan, string kind) => new Dictionary<string, object?>
        {
            ["Kind"] = kind,
            ["Nonce"] = Text(plan, "Nonce"),
            ["HelperVersion"] = 4,
            ["RestorePoint"] = "NotRequested",
            ["RestorePointCode"] = null,
            ["RestorePointArgs"] = new object[0],
            ["Started"] = false,
            ["ExitCode"] = null,
            ["TimedOut"] = false,
            ["Cancelled"] = false,
            ["Output"] = null,
            ["InstallerLog"] = null,
            ["ErrorCode"] = null,
            ["ErrorArgs"] = new object[0],
        };

        private static void SetError(Dictionary<string, object?> result, string code, params object[] args)
        {
            result["ErrorCode"] = code;
            result["ErrorArgs"] = args;
        }

        private static string? Text(Dictionary<string, object?> plan, string name) =>
            plan.TryGetValue(name, out var value) ? value as string : null;

        private static bool Flag(Dictionary<string, object?> plan, string name) =>
            plan.TryGetValue(name, out var value) && value is true;
    }
}
