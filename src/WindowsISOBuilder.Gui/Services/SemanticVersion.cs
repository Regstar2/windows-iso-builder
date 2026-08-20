using System.Globalization;

namespace WindowsISOBuilder.Gui.Services;

internal sealed class SemanticVersion : IComparable<SemanticVersion>, IEquatable<SemanticVersion>
{
    private readonly string[] _prerelease;

    private SemanticVersion(int major, int minor, int patch, string[] prerelease)
    {
        Major = major;
        Minor = minor;
        Patch = patch;
        _prerelease = prerelease;
    }

    public int Major { get; }
    public int Minor { get; }
    public int Patch { get; }
    public bool IsPrerelease => _prerelease.Length > 0;

    public static bool TryParse(string? value, out SemanticVersion? version)
    {
        version = null;
        if (string.IsNullOrWhiteSpace(value)) return false;

        var text = value.Trim();
        if (text.StartsWith('v')) text = text[1..];
        if (text.Length == 0) return false;

        var buildIndex = text.IndexOf('+');
        if (buildIndex >= 0)
        {
            var build = text[(buildIndex + 1)..];
            if (!ValidateIdentifiers(build, allowNumericLeadingZeros: true)) return false;
            text = text[..buildIndex];
        }

        string[] prerelease = [];
        var prereleaseIndex = text.IndexOf('-');
        if (prereleaseIndex >= 0)
        {
            var rawPrerelease = text[(prereleaseIndex + 1)..];
            if (!ValidateIdentifiers(rawPrerelease, allowNumericLeadingZeros: false)) return false;
            prerelease = rawPrerelease.Split('.');
            text = text[..prereleaseIndex];
        }

        var core = text.Split('.');
        if (core.Length != 3 ||
            !TryParseCoreNumber(core[0], out var major) ||
            !TryParseCoreNumber(core[1], out var minor) ||
            !TryParseCoreNumber(core[2], out var patch))
        {
            return false;
        }

        version = new SemanticVersion(major, minor, patch, prerelease);
        return true;
    }

    public int CompareTo(SemanticVersion? other)
    {
        if (other is null) return 1;
        var result = Major.CompareTo(other.Major);
        if (result != 0) return result;
        result = Minor.CompareTo(other.Minor);
        if (result != 0) return result;
        result = Patch.CompareTo(other.Patch);
        if (result != 0) return result;

        if (_prerelease.Length == 0 && other._prerelease.Length == 0) return 0;
        if (_prerelease.Length == 0) return 1;
        if (other._prerelease.Length == 0) return -1;

        var count = Math.Min(_prerelease.Length, other._prerelease.Length);
        for (var index = 0; index < count; index++)
        {
            result = ComparePrereleaseIdentifier(_prerelease[index], other._prerelease[index]);
            if (result != 0) return result;
        }
        return _prerelease.Length.CompareTo(other._prerelease.Length);
    }

    public bool Equals(SemanticVersion? other) => other is not null && CompareTo(other) == 0;
    public override bool Equals(object? obj) => obj is SemanticVersion other && Equals(other);
    public override int GetHashCode()
    {
        var hash = new HashCode();
        hash.Add(Major);
        hash.Add(Minor);
        hash.Add(Patch);
        foreach (var identifier in _prerelease) hash.Add(identifier, StringComparer.Ordinal);
        return hash.ToHashCode();
    }

    private static bool TryParseCoreNumber(string value, out int number)
    {
        number = 0;
        if (value.Length == 0 || value.Length > 1 && value[0] == '0') return false;
        return int.TryParse(value, NumberStyles.None, CultureInfo.InvariantCulture, out number) && number >= 0;
    }

    private static bool ValidateIdentifiers(string value, bool allowNumericLeadingZeros)
    {
        if (value.Length == 0) return false;
        foreach (var identifier in value.Split('.'))
        {
            if (identifier.Length == 0) return false;
            var numeric = true;
            foreach (var character in identifier)
            {
                if (!char.IsAsciiLetterOrDigit(character) && character != '-') return false;
                if (!char.IsAsciiDigit(character)) numeric = false;
            }
            if (!allowNumericLeadingZeros && numeric && identifier.Length > 1 && identifier[0] == '0') return false;
        }
        return true;
    }

    private static int ComparePrereleaseIdentifier(string left, string right)
    {
        var leftNumeric = left.All(char.IsAsciiDigit);
        var rightNumeric = right.All(char.IsAsciiDigit);
        if (leftNumeric && rightNumeric)
        {
            var length = left.Length.CompareTo(right.Length);
            return length != 0 ? length : string.CompareOrdinal(left, right);
        }
        if (leftNumeric) return -1;
        if (rightNumeric) return 1;
        return string.CompareOrdinal(left, right);
    }
}
