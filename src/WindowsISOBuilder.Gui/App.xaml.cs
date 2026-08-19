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
            var loc = LocalizationService.Instance;
            var openLog = MessageBox.Show(
                loc.Get("UnhandledUiMessage"),
                loc.Get("UnhandledUiTitle"),
                MessageBoxButton.YesNo,
                MessageBoxImage.Error);
            if (openLog == MessageBoxResult.Yes && File.Exists(_logger.LogPath))
            {
                try
                {
                    Process.Start(new ProcessStartInfo(_logger.LogPath) { UseShellExecute = true });
                }
                catch (Exception openException)
                {
                    _logger.Error("Failed to open GUI log", openException);
                }
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

        // Complete WPF application startup before either the headless smoke path or
        // normal window creation. App.xaml has no StartupUri, so this does not create
        // the GUI during --backend-smoke.
        base.OnStartup(e);

        if (e.Args.Contains("--backend-smoke", StringComparer.OrdinalIgnoreCase))
        {
            Shutdown(BackendSmoke.RunAsync(e.Args, _logger).GetAwaiter().GetResult());
            return;
        }

        var settingsService = new AppSettingsService(_logger);
        var settings = settingsService.Load();
        LocalizationService.Instance.Initialize(settings.Language);
        MainWindow = new MainWindow(settingsService, settings);
        MainWindow.Show();
    }
}
