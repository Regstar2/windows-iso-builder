using System.Runtime.InteropServices;
using System.Text;

namespace WindowsISOBuilder.Gui.Services;

internal sealed class ProxyCredentialStore
{
    private const int CryptProtectUiForbidden = 0x1;
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("WindowsISOBuilder.ProxyCredential.v1");
    private readonly string _path;

    public ProxyCredentialStore(string? path = null) => _path = path ?? GetDefaultPath();

    internal string Path => _path;
    internal bool Exists => File.Exists(_path);

    public void Save(string password)
    {
        ArgumentNullException.ThrowIfNull(password);
        var protectedBytes = Protect(Encoding.UTF8.GetBytes(password));
        var directory = System.IO.Path.GetDirectoryName(_path);
        if (!string.IsNullOrWhiteSpace(directory)) Directory.CreateDirectory(directory);
        var temporaryPath = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            File.WriteAllBytes(temporaryPath, protectedBytes);
            File.Move(temporaryPath, _path, true);
        }
        finally
        {
            try { if (File.Exists(temporaryPath)) File.Delete(temporaryPath); } catch { }
        }
    }

    public string? Load()
    {
        if (!File.Exists(_path)) return null;
        try
        {
            var bytes = File.ReadAllBytes(_path);
            return Encoding.UTF8.GetString(Unprotect(bytes));
        }
        catch (Exception exception) when (exception is not NetworkPolicyException)
        {
            throw new NetworkPolicyException("PROXY_CREDENTIAL_UNAVAILABLE", "Saved proxy credential could not be decrypted.");
        }
    }

    public void Clear()
    {
        try { if (File.Exists(_path)) File.Delete(_path); }
        catch (Exception exception)
        {
            throw new NetworkPolicyException("PROXY_CREDENTIAL_UNAVAILABLE", $"Saved proxy credential could not be removed: {exception.GetType().Name}.");
        }
    }

    private static byte[] Protect(byte[] value) => InvokeDpapi(value, protect: true);
    private static byte[] Unprotect(byte[] value) => InvokeDpapi(value, protect: false);

    private static byte[] InvokeDpapi(byte[] value, bool protect)
    {
        DataBlob input = default;
        DataBlob entropy = default;
        DataBlob output = default;
        try
        {
            input = Allocate(value);
            entropy = Allocate(Entropy);
            var ok = protect
                ? CryptProtectData(ref input, null, ref entropy, IntPtr.Zero, IntPtr.Zero, CryptProtectUiForbidden, out output)
                : CryptUnprotectData(ref input, IntPtr.Zero, ref entropy, IntPtr.Zero, IntPtr.Zero, CryptProtectUiForbidden, out output);
            if (!ok) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            var result = new byte[output.Size];
            if (output.Size > 0) Marshal.Copy(output.Data, result, 0, output.Size);
            return result;
        }
        finally
        {
            FreeAllocated(ref input);
            FreeAllocated(ref entropy);
            if (output.Data != IntPtr.Zero) LocalFree(output.Data);
        }
    }

    private static DataBlob Allocate(byte[] value)
    {
        if (value.Length == 0) return default;
        var pointer = Marshal.AllocHGlobal(value.Length);
        Marshal.Copy(value, 0, pointer, value.Length);
        return new DataBlob { Size = value.Length, Data = pointer };
    }

    private static void FreeAllocated(ref DataBlob blob)
    {
        if (blob.Data != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(blob.Data);
            blob.Data = IntPtr.Zero;
            blob.Size = 0;
        }
    }

    private static string GetDefaultPath()
    {
        var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var root = string.IsNullOrWhiteSpace(localAppData)
            ? System.IO.Path.Combine(System.IO.Path.GetTempPath(), "WindowsISOBuilder")
            : System.IO.Path.Combine(localAppData, "WindowsISOBuilder");
        return System.IO.Path.Combine(root, "proxy-credential.bin");
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DataBlob
    {
        public int Size;
        public IntPtr Data;
    }

    [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptProtectData(
        ref DataBlob dataIn,
        string? description,
        ref DataBlob optionalEntropy,
        IntPtr reserved,
        IntPtr promptStruct,
        int flags,
        out DataBlob dataOut);

    [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CryptUnprotectData(
        ref DataBlob dataIn,
        IntPtr description,
        ref DataBlob optionalEntropy,
        IntPtr reserved,
        IntPtr promptStruct,
        int flags,
        out DataBlob dataOut);

    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr memory);
}
