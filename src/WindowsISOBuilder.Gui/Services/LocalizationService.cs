using System.Collections;
using System.ComponentModel;
using System.Globalization;
using System.Resources;

namespace WindowsISOBuilder.Gui.Services;

internal sealed class LocalizationService : INotifyPropertyChanged
{
    private static readonly CultureInfo EnglishCulture = CultureInfo.GetCultureInfo("en");
    private static readonly CultureInfo RussianCulture = CultureInfo.GetCultureInfo("ru");
    private static readonly ResourceManager[] ResourceManagers =
    [
        CreateManager("Core"),
        CreateManager("Pages"),
        CreateManager("LocalData"),
        CreateManager("Automation"),
        CreateManager("Errors"),
        CreateManager("Status")
    ];

    private CultureInfo _culture = EnglishCulture;
    public static LocalizationService Instance { get; } = new();
    public event PropertyChangedEventHandler? PropertyChanged;
    public event EventHandler? CultureChanged;
    public string CurrentLanguage => _culture.TwoLetterISOLanguageName;
    public string this[string key] => Get(key);
    private LocalizationService() { }

    public void Initialize(string? savedLanguage) =>
        SetCulture(string.IsNullOrWhiteSpace(savedLanguage) ? CultureInfo.CurrentUICulture.Name : savedLanguage);

    public void SetCulture(string? requestedLanguage)
    {
        var next = NormalizeLanguage(requestedLanguage) == "ru" ? RussianCulture : EnglishCulture;
        _culture = next;
        CultureInfo.CurrentUICulture = next;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs("Item[]"));
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(CurrentLanguage)));
        CultureChanged?.Invoke(this, EventArgs.Empty);
    }

    public string Get(string key)
    {
        if (string.IsNullOrWhiteSpace(key)) return string.Empty;
        foreach (var manager in ResourceManagers)
        {
            var value = manager.GetString(key, _culture) ?? manager.GetString(key, CultureInfo.InvariantCulture);
            if (value is not null) return value;
        }
        return string.Empty;
    }

    public string Format(string key, params object?[] args) =>
        args.Length == 0 ? Get(key) : string.Format(_culture, Get(key), args);

    internal static string NormalizeLanguage(string? requestedLanguage)
    {
        if (string.IsNullOrWhiteSpace(requestedLanguage)) return "en";
        try
        {
            var culture = CultureInfo.GetCultureInfo(requestedLanguage.Trim());
            return culture.TwoLetterISOLanguageName.Equals("ru", StringComparison.OrdinalIgnoreCase) ? "ru" : "en";
        }
        catch (CultureNotFoundException)
        {
            return "en";
        }
    }

    internal static IReadOnlyDictionary<string, string> GetResourceSnapshot(string language)
    {
        var culture = NormalizeLanguage(language) == "ru" ? RussianCulture : CultureInfo.InvariantCulture;
        var values = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var manager in ResourceManagers)
        {
            var set = manager.GetResourceSet(culture, true, false)
                ?? throw new InvalidOperationException($"Resource set '{language}' is unavailable.");
            foreach (DictionaryEntry item in set)
            {
                if (item.Key is string key && item.Value is string value) values[key] = value;
            }
        }
        return values;
    }

    private static ResourceManager CreateManager(string group) =>
        new($"WindowsISOBuilder.Gui.Resources.Strings.{group}", typeof(LocalizationService).Assembly);
}
