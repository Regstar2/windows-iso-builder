namespace WindowsISOBuilder.Gui.ViewModels;

public sealed partial class MainViewModel
{
    public void ReportFrontendActionError(Exception exception) => Fail(exception);
}
