namespace WindowsISOBuilder.Gui.Models;

internal sealed class AppSettings
{
    public double? Left { get; set; }
    public double? Top { get; set; }
    public double? Width { get; set; }
    public double? Height { get; set; }
    public bool IsMaximized { get; set; }
    public string? Language { get; set; }
    public string? Theme { get; set; }
    public string? UpdateChannel { get; set; }
}
