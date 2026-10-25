using System.Management.Automation;
using System.Windows.Threading;

namespace Softwareverwaltung.App.Tests;

internal static class TestHelpers
{
    /// <summary>PSObject mit Notizeigenschaften, wie es das Modul liefert.</summary>
    public static PSObject Ps(params (string Name, object? Value)[] properties)
    {
        var obj = new PSObject();
        foreach (var (name, value) in properties)
        {
            obj.Properties.Add(new PSNoteProperty(name, value));
        }
        return obj;
    }

    /// <summary>Führt Code wie in der App auf einem UI-Thread mit Dispatcher aus (ListCollectionView verlangt das).</summary>
    public static void RunOnDispatcher(Func<Task> action)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            var dispatcher = Dispatcher.CurrentDispatcher;
            SynchronizationContext.SetSynchronizationContext(new DispatcherSynchronizationContext(dispatcher));
            var frame = new DispatcherFrame();
            _ = Run();
            Dispatcher.PushFrame(frame);

            async Task Run()
            {
                try
                {
                    await action();
                }
                catch (Exception ex)
                {
                    failure = ex;
                }
                finally
                {
                    frame.Continue = false;
                }
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        if (!thread.Join(TimeSpan.FromSeconds(30)))
        {
            throw new TimeoutException("Test hat nicht rechtzeitig beendet.");
        }
        if (failure is not null)
        {
            System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
        }
    }
}
