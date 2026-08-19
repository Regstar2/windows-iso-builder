using System.Windows;
using WindowsISOBuilder.Gui.Models;

namespace WindowsISOBuilder.Gui.Views;

public partial class PreflightDetailsWindow : Window
{
    public PreflightDetailsWindow(IEnumerable<PreflightCheckDto> checks)
    {
        InitializeComponent();
        DataContext = checks.ToArray();
    }
}
