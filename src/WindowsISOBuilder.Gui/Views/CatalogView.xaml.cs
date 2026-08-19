using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using WindowsISOBuilder.Gui.Models;
using WindowsISOBuilder.Gui.Services;
using WindowsISOBuilder.Gui.ViewModels;

namespace WindowsISOBuilder.Gui.Views;

public partial class CatalogView : UserControl
{
    public event EventHandler? BuildActivated;
    public CatalogView() => InitializeComponent();
    private MainViewModel ViewModel => (MainViewModel)DataContext;

    private void CatalogGrid_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (e.OriginalSource is DependencyObject source && ItemsControl.ContainerFromElement(CatalogGrid, source) is DataGridRow) UseSelected();
    }
    private void UseCatalogBuild_Click(object sender, RoutedEventArgs e) => UseSelected();

    private void UseSelected()
    {
        if (ViewModel.SelectedCatalogBuild is not BuildDto build) return;
        if (!build.EntryType.Equals("Windows", StringComparison.OrdinalIgnoreCase))
        {
            var loc = LocalizationService.Instance;
            MessageBox.Show(Window.GetWindow(this), loc.Get("CatalogServicingMessage"), loc.Get("CatalogServicingTitle"), MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        ViewModel.Product = build.Product;
        ViewModel.Architecture = build.Architecture;
        ViewModel.SelectedBuild = build;
        BuildActivated?.Invoke(this, EventArgs.Empty);
    }
}
