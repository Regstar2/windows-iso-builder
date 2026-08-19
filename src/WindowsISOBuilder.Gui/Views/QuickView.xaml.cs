using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using WindowsISOBuilder.Gui.ViewModels;

namespace WindowsISOBuilder.Gui.Views;

public partial class QuickView : UserControl
{
    public QuickView() => InitializeComponent();
    private MainViewModel ViewModel => (MainViewModel)DataContext;

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog { InitialDirectory = ViewModel.OutputDirectory, Multiselect = false };
        if (dialog.ShowDialog(Window.GetWindow(this)) == true) ViewModel.OutputDirectory = dialog.FolderName;
    }

    private void Advanced_Click(object sender, RoutedEventArgs e) => new AdvancedOptionsWindow(ViewModel) { Owner = Window.GetWindow(this) }.ShowDialog();
    private void PreflightDetails_Click(object sender, RoutedEventArgs e) => new PreflightDetailsWindow(ViewModel.Checks) { Owner = Window.GetWindow(this) }.ShowDialog();
}
