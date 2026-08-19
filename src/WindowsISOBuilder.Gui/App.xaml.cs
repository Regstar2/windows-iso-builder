using System.Diagnostics;
using System.Windows;
using WindowsISOBuilder.Gui.Services;

namespace WindowsISOBuilder.Gui;

public partial class App : Application
{
    private readonly GuiLogger _logger = new();

    protected override void OnStartup(StartupEventArgs e)
    {
        DispatcherUnhandledException += (_, args) =>
        {
            _logger.Error("Unhandled UI exception", args.Exception);
            var openLog = MessageBox.Show(
                "Произошла ошибка интерфейса Windows ISO Builder.\n\nОткрыть журнал GUI перед завершением приложения?",
                "Windows ISO Builder",
                MessageBoxButton.YesNo,
                MessageBoxImage.Error);
            if (openLog == MessageBoxResult.Yes && File.Exists(_logger.LogPath))
            {
                Process.Start(new ProcessStartInfo(_logger.LogPath) { UseShellExecute = true });
            }
            args.Handled = true;
            Shutdown(2);
        };

        AppDomain.CurrentDomain.UnhandledException += (_, args) =>
            _logger.Error("Unhandled application exception", args.ExceptionObject as Exception);
        TaskScheduler.UnobservedTaskException += (_, args) =>
        {
            _logger.Error("Unobserved task exception", args.Exception);
            args.SetObserved();
        };

        if (e.Args.Contains("--backend-smoke", StringComparer.OrdinalIgnoreCase))
        {
            Shutdown(BackendSmoke.RunAsync(e.Args, _logger).GetAwaiter().GetResult());
            return;
        }

        base.OnStartup(e);
        MainWindow = new MainWindow();
        MainWindow.Show();
    }
}
