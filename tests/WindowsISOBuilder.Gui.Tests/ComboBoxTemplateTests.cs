using System.Reflection;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Markup;

namespace WindowsISOBuilder.Gui.Tests;

[TestClass]
public sealed class ComboBoxTemplateTests
{
    [TestMethod]
    public void DarkComboBoxTemplateKeepsDropdownInteractive()
    {
        Exception? failure = null;
        var completed = false;

        var thread = new Thread(() =>
        {
            try
            {
                var resourcePath = FindRepositoryFile("src", "WindowsISOBuilder.Gui", "Resources", "ComboBoxStyles.xaml");
                using var stream = File.OpenRead(resourcePath);
                var resources = (ResourceDictionary)XamlReader.Load(stream);

                var style = resources[typeof(ComboBox)] as Style;
                Assert.IsNotNull(style);

                var comboBox = new ComboBox
                {
                    Style = style,
                    Width = 220
                };
                comboBox.Items.Add("One");
                comboBox.Items.Add("Two");
                comboBox.SelectedIndex = 0;
                comboBox.ApplyTemplate();

                var toggle = comboBox.Template.FindName("PART_DropDownToggle", comboBox) as ToggleButton;
                Assert.IsNotNull(toggle);
                Assert.IsFalse(comboBox.IsDropDownOpen);

                var onClick = typeof(ToggleButton).GetMethod("OnClick", BindingFlags.Instance | BindingFlags.NonPublic);
                Assert.IsNotNull(onClick);
                onClick.Invoke(toggle, null);

                Assert.IsTrue(comboBox.IsDropDownOpen, "The themed ComboBox toggle must open the dropdown.");
                comboBox.IsDropDownOpen = false;
            }
            catch (Exception ex)
            {
                failure = ex;
            }
            finally
            {
                completed = true;
            }
        });

        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        Assert.IsTrue(thread.Join(TimeSpan.FromSeconds(10)), "The WPF ComboBox interaction test timed out.");
        Assert.IsTrue(completed);

        if (failure is not null)
        {
            Assert.Fail(failure.ToString());
        }
    }

    private static string FindRepositoryFile(params string[] segments)
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            var candidate = Path.Combine(new[] { directory.FullName }.Concat(segments).ToArray());
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new FileNotFoundException($"Could not locate repository file: {Path.Combine(segments)}");
    }
}
