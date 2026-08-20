$script:WibNetworkSchemaVersion = 1
$script:WibNetworkEntropy = [Text.Encoding]::UTF8.GetBytes('WindowsISOBuilder.ProxyCredential.v1')
$script:WibProxyBridgeTypeLoaded = $false

function Get-WibNetworkStateRoot {
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localAppData)) {
        return (Join-Path ([IO.Path]::GetTempPath()) 'WindowsISOBuilder')
    }
    return (Join-Path $localAppData 'WindowsISOBuilder')
}

function Get-WibNetworkPolicyPath {
    return (Join-Path (Get-WibNetworkStateRoot) 'network.json')
}

function Get-WibProxyCredentialPath {
    return (Join-Path (Get-WibNetworkStateRoot) 'proxy-credential.bin')
}

function New-WibDefaultNetworkPolicy {
    return [pscustomobject][ordered]@{
        schemaVersion = $script:WibNetworkSchemaVersion
        mode = 'system'
        proxyType = $null
        host = $null
        port = $null
        username = $null
        hasCredential = $false
    }
}

function ConvertTo-WibNormalizedNetworkPolicy {
    param([Parameter(Mandatory = $true)]$Policy)

    $schemaVersion = if ($null -ne $Policy.PSObject.Properties['schemaVersion']) { [int]$Policy.schemaVersion } else { 0 }
    if ($schemaVersion -ne $script:WibNetworkSchemaVersion) {
        throw (New-WibErrorException -Code 'PROXY_CONFIGURATION_INVALID' -Message 'Unsupported network policy schema.' -Stage 'network' -PublicMessage 'Network proxy settings are invalid.')
    }

    $mode = if ($null -eq $Policy.PSObject.Properties['mode']) { 'system' } else { ([string]$Policy.mode).Trim().ToLowerInvariant() }
    if ([string]::IsNullOrWhiteSpace($mode)) { $mode = 'system' }
    if (@('system','direct','custom') -notcontains $mode) {
        throw (New-WibErrorException -Code 'PROXY_CONFIGURATION_INVALID' -Message 'Unsupported network mode.' -Stage 'network' -PublicMessage 'Network proxy settings are invalid.')
    }

    if ($mode -ne 'custom') {
        return [pscustomobject][ordered]@{
            schemaVersion=$script:WibNetworkSchemaVersion; mode=$mode; proxyType=$null; host=$null; port=$null; username=$null; hasCredential=$false
        }
    }

    $proxyType = if ($null -eq $Policy.PSObject.Properties['proxyType']) { '' } else { ([string]$Policy.proxyType).Trim().ToLowerInvariant() }
    if (@('http','socks5') -notcontains $proxyType) {
        throw (New-WibErrorException -Code 'PROXY_CONFIGURATION_INVALID' -Message 'Unsupported custom proxy type.' -Stage 'network' -PublicMessage 'Custom proxy type is invalid.')
    }

    $host = if ($null -eq $Policy.PSObject.Properties['host']) { '' } else { ([string]$Policy.host).Trim() }
    if ([string]::IsNullOrWhiteSpace($host) -or $host.Length -gt 255 -or $host -match '\s|://|/|\\|@') {
        throw (New-WibErrorException -Code 'PROXY_CONFIGURATION_INVALID' -Message 'Custom proxy host is invalid.' -Stage 'network' -PublicMessage 'Custom proxy host is invalid.')
    }

    $port = 0
    if ($null -eq $Policy.PSObject.Properties['port'] -or -not [int]::TryParse([string]$Policy.port, [ref]$port) -or $port -lt 1 -or $port -gt 65535) {
        throw (New-WibErrorException -Code 'PROXY_CONFIGURATION_INVALID' -Message 'Custom proxy port is invalid.' -Stage 'network' -PublicMessage 'Custom proxy port is invalid.')
    }

    $username = if ($null -eq $Policy.PSObject.Properties['username']) { '' } else { ([string]$Policy.username).Trim() }
    if ($username.Length -gt 256 -or $username -match '[\r\n]') {
        throw (New-WibErrorException -Code 'PROXY_CONFIGURATION_INVALID' -Message 'Custom proxy username is invalid.' -Stage 'network' -PublicMessage 'Custom proxy username is invalid.')
    }
    if ([string]::IsNullOrWhiteSpace($username)) { $username = $null }

    $hasCredential = $false
    if ($null -ne $Policy.PSObject.Properties['hasCredential']) { $hasCredential = [bool]$Policy.hasCredential }
    if ($hasCredential -and [string]::IsNullOrWhiteSpace([string]$username)) {
        throw (New-WibErrorException -Code 'PROXY_CONFIGURATION_INVALID' -Message 'A saved proxy password requires a username.' -Stage 'network' -PublicMessage 'Proxy username is required when a password is saved.')
    }

    return [pscustomobject][ordered]@{
        schemaVersion=$script:WibNetworkSchemaVersion
        mode='custom'
        proxyType=$proxyType
        host=$host
        port=$port
        username=$username
        hasCredential=$hasCredential
    }
}

function Get-WibNetworkPolicy {
    [CmdletBinding()]
    param()

    $path = Get-WibNetworkPolicyPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return (New-WibDefaultNetworkPolicy) }
    try {
        $policy = Read-WibJsonFile -Path $path
        if ($null -eq $policy) { throw 'Network policy is empty.' }
        return (ConvertTo-WibNormalizedNetworkPolicy -Policy $policy)
    }
    catch {
        $knownCode = ''
        try { if ($_.Exception.Data.Contains('WibErrorCode')) { $knownCode = [string]$_.Exception.Data['WibErrorCode'] } } catch { }
        if (-not [string]::IsNullOrWhiteSpace($knownCode)) { throw }
        throw (New-WibErrorException -Code 'PROXY_CONFIGURATION_INVALID' -Message ('Network policy could not be read: {0}' -f $_.Exception.GetType().Name) -Stage 'network' -PublicMessage 'Network proxy settings could not be read.')
    }
}

function ConvertFrom-WibSecureString {
    param([Parameter(Mandatory = $true)][Security.SecureString]$SecureString)
    $pointer = [IntPtr]::Zero
    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    }
}

function Protect-WibProxyCredentialText {
    param([Parameter(Mandatory = $true)][string]$Password)
    try {
        Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
        $bytes = [Text.Encoding]::UTF8.GetBytes($Password)
        return [Security.Cryptography.ProtectedData]::Protect($bytes, $script:WibNetworkEntropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    }
    catch {
        throw (New-WibErrorException -Code 'PROXY_CREDENTIAL_UNAVAILABLE' -Message 'Proxy credential could not be protected with Windows DPAPI.' -Stage 'network' -PublicMessage 'Proxy credential could not be saved securely.')
    }
}

function Get-WibProxyCredentialText {
    param([Parameter(Mandatory = $true)]$Policy)

    if (-not [bool]$Policy.hasCredential) { return $null }
    $path = Get-WibProxyCredentialPath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw (New-WibErrorException -Code 'PROXY_CREDENTIAL_UNAVAILABLE' -Message 'Network policy references a missing proxy credential.' -Stage 'network' -PublicMessage 'Saved proxy credential is unavailable.')
    }
    try {
        Add-Type -AssemblyName System.Security -ErrorAction SilentlyContinue
        $protectedBytes = [IO.File]::ReadAllBytes($path)
        $bytes = [Security.Cryptography.ProtectedData]::Unprotect($protectedBytes, $script:WibNetworkEntropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        return [Text.Encoding]::UTF8.GetString($bytes)
    }
    catch {
        throw (New-WibErrorException -Code 'PROXY_CREDENTIAL_UNAVAILABLE' -Message 'Saved proxy credential could not be decrypted with Windows DPAPI.' -Stage 'network' -PublicMessage 'Saved proxy credential is unavailable.')
    }
}

function Save-WibProxyCredential {
    param([Parameter(Mandatory = $true)][Security.SecureString]$Password)

    $root = Get-WibNetworkStateRoot
    if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
    $path = Get-WibProxyCredentialPath
    $temporary = $path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    $plain = ConvertFrom-WibSecureString -SecureString $Password
    try {
        $protected = Protect-WibProxyCredentialText -Password $plain
        [IO.File]::WriteAllBytes($temporary, $protected)
        Move-Item -LiteralPath $temporary -Destination $path -Force
    }
    finally {
        $plain = $null
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
    }
}

function Clear-WibProxyCredential {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param()

    $path = Get-WibProxyCredentialPath
    if ((Test-Path -LiteralPath $path) -and $PSCmdlet.ShouldProcess($path, 'Remove saved proxy credential')) {
        Remove-Item -LiteralPath $path -Force
    }

    $policy = Get-WibNetworkPolicy
    if ($policy.mode -eq 'custom' -and [bool]$policy.hasCredential) {
        $policy.hasCredential = $false
        Save-WibNetworkPolicyFile -Policy $policy
    }
}

function Save-WibNetworkPolicyFile {
    param([Parameter(Mandatory = $true)]$Policy)
    $normalized = ConvertTo-WibNormalizedNetworkPolicy -Policy $Policy
    $root = Get-WibNetworkStateRoot
    if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root -Force | Out-Null }
    $path = Get-WibNetworkPolicyPath
    $temporary = $path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    try {
        Write-WibJsonFile -Value $normalized -Path $temporary -Depth 6
        Move-Item -LiteralPath $temporary -Destination $path -Force
    }
    finally { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    return $normalized
}

function Set-WibNetworkPolicy {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('System','Direct','Custom')][string]$Mode,
        [ValidateSet('HTTP','SOCKS5')][string]$ProxyType = 'HTTP',
        [string]$Host = '',
        [int]$Port = 0,
        [string]$Username = '',
        [Security.SecureString]$Password
    )

    $modeValue = $Mode.ToLowerInvariant()
    $credentialPath = Get-WibProxyCredentialPath
    $hasExistingCredential = Test-Path -LiteralPath $credentialPath -PathType Leaf
    $hasNewCredential = $null -ne $Password
    $policy = [pscustomobject][ordered]@{
        schemaVersion=$script:WibNetworkSchemaVersion
        mode=$modeValue
        proxyType=if ($modeValue -eq 'custom') { $ProxyType.ToLowerInvariant() } else { $null }
        host=if ($modeValue -eq 'custom') { $Host } else { $null }
        port=if ($modeValue -eq 'custom') { $Port } else { $null }
        username=if ($modeValue -eq 'custom') { $Username } else { $null }
        hasCredential=if ($modeValue -eq 'custom') { [bool]($hasExistingCredential -or $hasNewCredential) } else { $false }
    }
    $normalized = ConvertTo-WibNormalizedNetworkPolicy -Policy $policy

    if (-not $PSCmdlet.ShouldProcess((Get-WibNetworkPolicyPath), ('Set network mode to {0}' -f $Mode))) { return $normalized }
    if ($hasNewCredential) { Save-WibProxyCredential -Password $Password }
    if ($modeValue -ne 'custom' -and $hasExistingCredential) {
        Remove-Item -LiteralPath $credentialPath -Force -ErrorAction SilentlyContinue
    }
    return (Save-WibNetworkPolicyFile -Policy $normalized)
}

function Initialize-WibProxyBridgeType {
    if ($script:WibProxyBridgeTypeLoaded) { return }
    if ('WindowsISOBuilder.Network.WibProxyBridge' -as [type]) { $script:WibProxyBridgeTypeLoaded = $true; return }

    $source = @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

namespace WindowsISOBuilder.Network
{
    public sealed class WibProxyBridge : IDisposable
    {
        private readonly string mode;
        private readonly string proxyHost;
        private readonly int proxyPort;
        private readonly string username;
        private readonly string password;
        private readonly TcpListener listener;
        private readonly Thread acceptThread;
        private volatile bool stopping;

        public WibProxyBridge(string mode, string proxyHost, int proxyPort, string username, string password)
        {
            this.mode = (mode ?? "").ToLowerInvariant();
            this.proxyHost = proxyHost ?? "";
            this.proxyPort = proxyPort;
            this.username = username ?? "";
            this.password = password ?? "";
            listener = new TcpListener(IPAddress.Loopback, 0);
            listener.Start();
            Port = ((IPEndPoint)listener.LocalEndpoint).Port;
            acceptThread = new Thread(AcceptLoop);
            acceptThread.IsBackground = true;
            acceptThread.Name = "WindowsISOBuilder.ProxyBridge";
            acceptThread.Start();
        }

        public int Port { get; private set; }

        private void AcceptLoop()
        {
            while (!stopping)
            {
                TcpClient client = null;
                try { client = listener.AcceptTcpClient(); }
                catch { if (stopping) break; continue; }
                ThreadPool.QueueUserWorkItem(delegate { HandleClient(client); });
            }
        }

        private void HandleClient(TcpClient client)
        {
            using (client)
            {
                TcpClient upstream = null;
                try
                {
                    client.ReceiveTimeout = 30000;
                    client.SendTimeout = 30000;
                    NetworkStream clientStream = client.GetStream();
                    byte[] headerBytes = ReadHeaders(clientStream);
                    string header = Encoding.ASCII.GetString(headerBytes);
                    string[] lines = header.Split(new string[] { "\r\n" }, StringSplitOptions.None);
                    if (lines.Length == 0) return;
                    string[] first = lines[0].Split(new char[] { ' ' }, 3);
                    if (first.Length != 3) return;
                    string method = first[0];
                    string target = first[1];
                    string version = first[2];
                    string host;
                    int port;
                    Uri absoluteUri = null;
                    bool isConnect = string.Equals(method, "CONNECT", StringComparison.OrdinalIgnoreCase);
                    if (isConnect)
                    {
                        ParseAuthority(target, out host, out port);
                    }
                    else
                    {
                        if (Uri.TryCreate(target, UriKind.Absolute, out absoluteUri))
                        {
                            host = absoluteUri.Host;
                            port = absoluteUri.IsDefaultPort ? (absoluteUri.Scheme == "https" ? 443 : 80) : absoluteUri.Port;
                        }
                        else
                        {
                            string hostHeader = FindHeader(lines, "Host");
                            ParseAuthority(hostHeader, out host, out port);
                            if (port == 0) port = 80;
                            absoluteUri = new Uri("http://" + host + (port == 80 ? "" : ":" + port) + target);
                        }
                    }

                    string effectiveMode = mode;
                    string effectiveProxyHost = proxyHost;
                    int effectiveProxyPort = proxyPort;
                    if (effectiveMode == "system")
                    {
                        Uri destination = isConnect ? new Uri("https://" + FormatAuthority(host, port)) : absoluteUri;
                        IWebProxy systemProxy = WebRequest.DefaultWebProxy;
                        Uri proxy = systemProxy == null ? destination : systemProxy.GetProxy(destination);
                        if (proxy == null || systemProxy == null || systemProxy.IsBypassed(destination) || SameEndpoint(proxy, destination))
                        {
                            effectiveMode = "direct";
                        }
                        else
                        {
                            if (!string.Equals(proxy.Scheme, "http", StringComparison.OrdinalIgnoreCase)) throw new IOException("Unsupported system proxy scheme.");
                            effectiveMode = "http";
                            effectiveProxyHost = proxy.Host;
                            effectiveProxyPort = proxy.Port;
                        }
                    }

                    if (effectiveMode == "socks5")
                    {
                        upstream = ConnectTcp(effectiveProxyHost, effectiveProxyPort);
                        EstablishSocks5(upstream.GetStream(), host, port, username, password);
                        if (isConnect)
                        {
                            WriteAscii(clientStream, "HTTP/1.1 200 Connection Established\r\nProxy-Agent: WindowsISOBuilder\r\n\r\n");
                        }
                        else
                        {
                            WriteAscii(upstream.GetStream(), RewriteForOrigin(lines, method, absoluteUri, version));
                        }
                    }
                    else if (effectiveMode == "http")
                    {
                        upstream = ConnectTcp(effectiveProxyHost, effectiveProxyPort);
                        string forwarded = AddProxyAuthorization(header, username, password);
                        WriteAscii(upstream.GetStream(), forwarded);
                        if (isConnect)
                        {
                            byte[] responseHeader = ReadHeaders(upstream.GetStream());
                            clientStream.Write(responseHeader, 0, responseHeader.Length);
                            string responseText = Encoding.ASCII.GetString(responseHeader);
                            if (!IsSuccessConnect(responseText)) return;
                        }
                    }
                    else
                    {
                        upstream = ConnectTcp(host, port);
                        if (isConnect)
                        {
                            WriteAscii(clientStream, "HTTP/1.1 200 Connection Established\r\nProxy-Agent: WindowsISOBuilder\r\n\r\n");
                        }
                        else
                        {
                            WriteAscii(upstream.GetStream(), RewriteForOrigin(lines, method, absoluteUri, version));
                        }
                    }

                    Relay(client, upstream);
                }
                catch
                {
                    try { WriteAscii(client.GetStream(), "HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n"); } catch { }
                }
                finally { if (upstream != null) upstream.Close(); }
            }
        }

        private static TcpClient ConnectTcp(string host, int port)
        {
            TcpClient client = new TcpClient();
            IAsyncResult ar = client.BeginConnect(host, port, null, null);
            if (!ar.AsyncWaitHandle.WaitOne(10000)) { client.Close(); throw new IOException("Proxy connection timed out."); }
            client.EndConnect(ar);
            client.ReceiveTimeout = 30000;
            client.SendTimeout = 30000;
            return client;
        }

        private static void EstablishSocks5(NetworkStream stream, string host, int port, string username, string password)
        {
            bool auth = !string.IsNullOrEmpty(username);
            byte[] greeting = auth ? new byte[] { 5, 2, 0, 2 } : new byte[] { 5, 1, 0 };
            stream.Write(greeting, 0, greeting.Length);
            byte[] reply = ReadExact(stream, 2);
            if (reply[0] != 5 || reply[1] == 255) throw new IOException("SOCKS5 authentication method rejected.");
            if (reply[1] == 2)
            {
                byte[] u = Encoding.UTF8.GetBytes(username ?? "");
                byte[] p = Encoding.UTF8.GetBytes(password ?? "");
                if (u.Length > 255 || p.Length > 255) throw new IOException("SOCKS5 credential is too long.");
                byte[] authRequest = new byte[3 + u.Length + p.Length];
                authRequest[0] = 1; authRequest[1] = (byte)u.Length;
                Buffer.BlockCopy(u, 0, authRequest, 2, u.Length);
                authRequest[2 + u.Length] = (byte)p.Length;
                Buffer.BlockCopy(p, 0, authRequest, 3 + u.Length, p.Length);
                stream.Write(authRequest, 0, authRequest.Length);
                byte[] authReply = ReadExact(stream, 2);
                if (authReply[1] != 0) throw new IOException("SOCKS5 authentication failed.");
            }
            else if (reply[1] != 0)
            {
                throw new IOException("Unsupported SOCKS5 authentication method.");
            }

            byte[] hostBytes = Encoding.ASCII.GetBytes(host);
            if (hostBytes.Length == 0 || hostBytes.Length > 255) throw new IOException("SOCKS5 destination host is invalid.");
            byte[] request = new byte[7 + hostBytes.Length];
            request[0] = 5; request[1] = 1; request[2] = 0; request[3] = 3; request[4] = (byte)hostBytes.Length;
            Buffer.BlockCopy(hostBytes, 0, request, 5, hostBytes.Length);
            request[5 + hostBytes.Length] = (byte)((port >> 8) & 255);
            request[6 + hostBytes.Length] = (byte)(port & 255);
            stream.Write(request, 0, request.Length);

            byte[] head = ReadExact(stream, 4);
            if (head[0] != 5 || head[1] != 0) throw new IOException("SOCKS5 connection failed.");
            int addressLength;
            if (head[3] == 1) addressLength = 4;
            else if (head[3] == 4) addressLength = 16;
            else if (head[3] == 3) addressLength = ReadExact(stream, 1)[0];
            else throw new IOException("SOCKS5 returned an invalid address type.");
            ReadExact(stream, addressLength + 2);
        }

        private static byte[] ReadExact(Stream stream, int count)
        {
            byte[] bytes = new byte[count];
            int offset = 0;
            while (offset < count)
            {
                int read = stream.Read(bytes, offset, count - offset);
                if (read <= 0) throw new EndOfStreamException();
                offset += read;
            }
            return bytes;
        }

        private static byte[] ReadHeaders(Stream stream)
        {
            MemoryStream buffer = new MemoryStream();
            int state = 0;
            while (buffer.Length < 65536)
            {
                int value = stream.ReadByte();
                if (value < 0) throw new EndOfStreamException();
                buffer.WriteByte((byte)value);
                if ((state == 0 || state == 2) && value == 13) state++;
                else if ((state == 1 || state == 3) && value == 10) state++;
                else state = value == 13 ? 1 : 0;
                if (state == 4) return buffer.ToArray();
            }
            throw new IOException("Proxy request headers are too large.");
        }

        private static void ParseAuthority(string authority, out string host, out int port)
        {
            host = ""; port = 0;
            if (string.IsNullOrWhiteSpace(authority)) throw new IOException("Proxy destination is missing.");
            authority = authority.Trim();
            if (authority.StartsWith("["))
            {
                int close = authority.IndexOf(']');
                if (close < 0) throw new IOException("Invalid IPv6 authority.");
                host = authority.Substring(1, close - 1);
                if (close + 1 < authority.Length && authority[close + 1] == ':') int.TryParse(authority.Substring(close + 2), out port);
            }
            else
            {
                int colon = authority.LastIndexOf(':');
                if (colon > 0 && authority.IndexOf(':') == colon)
                {
                    host = authority.Substring(0, colon);
                    int.TryParse(authority.Substring(colon + 1), out port);
                }
                else host = authority;
            }
            if (port == 0) port = 443;
            if (string.IsNullOrWhiteSpace(host) || port < 1 || port > 65535) throw new IOException("Invalid proxy destination.");
        }

        private static string FindHeader(string[] lines, string name)
        {
            for (int i = 1; i < lines.Length; i++)
            {
                int colon = lines[i].IndexOf(':');
                if (colon > 0 && string.Equals(lines[i].Substring(0, colon).Trim(), name, StringComparison.OrdinalIgnoreCase))
                    return lines[i].Substring(colon + 1).Trim();
            }
            return "";
        }

        private static string RewriteForOrigin(string[] lines, string method, Uri uri, string version)
        {
            StringBuilder builder = new StringBuilder();
            string path = uri == null ? "/" : uri.PathAndQuery;
            if (string.IsNullOrEmpty(path)) path = "/";
            builder.Append(method).Append(' ').Append(path).Append(' ').Append(version).Append("\r\n");
            for (int i = 1; i < lines.Length; i++)
            {
                string line = lines[i];
                if (line.Length == 0) continue;
                if (line.StartsWith("Proxy-Authorization:", StringComparison.OrdinalIgnoreCase)) continue;
                if (line.StartsWith("Proxy-Connection:", StringComparison.OrdinalIgnoreCase)) continue;
                builder.Append(line).Append("\r\n");
            }
            builder.Append("\r\n");
            return builder.ToString();
        }

        private static string AddProxyAuthorization(string header, string username, string password)
        {
            if (string.IsNullOrEmpty(username)) return header;
            string value = Convert.ToBase64String(Encoding.UTF8.GetBytes(username + ":" + (password ?? "")));
            int marker = header.IndexOf("\r\n\r\n", StringComparison.Ordinal);
            if (marker < 0) return header;
            return header.Substring(0, marker) + "\r\nProxy-Authorization: Basic " + value + header.Substring(marker);
        }

        private static bool IsSuccessConnect(string response)
        {
            int end = response.IndexOf("\r\n", StringComparison.Ordinal);
            string first = end >= 0 ? response.Substring(0, end) : response;
            string[] parts = first.Split(' ');
            if (parts.Length < 2) return false;
            int code;
            return int.TryParse(parts[1], out code) && code >= 200 && code <= 299;
        }

        private static string FormatAuthority(string host, int port)
        {
            return host.IndexOf(':') >= 0 ? "[" + host + "]:" + port : host + ":" + port;
        }

        private static bool SameEndpoint(Uri left, Uri right)
        {
            return string.Equals(left.Scheme, right.Scheme, StringComparison.OrdinalIgnoreCase) &&
                   string.Equals(left.Host, right.Host, StringComparison.OrdinalIgnoreCase) && left.Port == right.Port;
        }

        private static void WriteAscii(Stream stream, string value)
        {
            byte[] bytes = Encoding.ASCII.GetBytes(value);
            stream.Write(bytes, 0, bytes.Length);
            stream.Flush();
        }

        private static void Relay(TcpClient client, TcpClient upstream)
        {
            NetworkStream a = client.GetStream();
            NetworkStream b = upstream.GetStream();
            Thread upload = new Thread(delegate { Copy(a, b); });
            upload.IsBackground = true;
            upload.Start();
            Copy(b, a);
            try { client.Close(); } catch { }
            try { upstream.Close(); } catch { }
            try { upload.Join(1000); } catch { }
        }

        private static void Copy(Stream source, Stream destination)
        {
            byte[] buffer = new byte[32768];
            try
            {
                while (true)
                {
                    int read = source.Read(buffer, 0, buffer.Length);
                    if (read <= 0) break;
                    destination.Write(buffer, 0, read);
                    destination.Flush();
                }
            }
            catch { }
        }

        public void Dispose()
        {
            stopping = true;
            try { listener.Stop(); } catch { }
            try { if (acceptThread != null && acceptThread.IsAlive) acceptThread.Join(1000); } catch { }
        }
    }
}
'@
    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
    $script:WibProxyBridgeTypeLoaded = $true
}

function Start-WibNetworkProxyBridge {
    param([Parameter(Mandatory = $true)]$Policy)
    $normalized = ConvertTo-WibNormalizedNetworkPolicy -Policy $Policy
    if ($normalized.mode -eq 'direct') { return $null }
    Initialize-WibProxyBridgeType

    $bridgeMode = $normalized.mode
    $host = ''
    $port = 0
    $username = ''
    $password = ''
    if ($normalized.mode -eq 'custom') {
        $bridgeMode = [string]$normalized.proxyType
        $host = [string]$normalized.host
        $port = [int]$normalized.port
        $username = [string]$normalized.username
        $credential = Get-WibProxyCredentialText -Policy $normalized
        if ($null -ne $credential) { $password = [string]$credential }
    }
    try {
        return (New-Object WindowsISOBuilder.Network.WibProxyBridge($bridgeMode, $host, $port, $username, $password))
    }
    catch {
        throw (New-WibErrorException -Code 'PROXY_CONNECTION_FAILED' -Message ('Proxy bridge could not be started: {0}' -f $_.Exception.GetType().Name) -Stage 'network' -PublicMessage 'Proxy transport could not be started.')
    }
    finally { $password = '' }
}

function New-WibHttpClientContext {
    param([int]$TimeoutSeconds = 120)

    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    $policy = Get-WibNetworkPolicy
    $handler = New-Object Net.Http.HttpClientHandler
    $handler.AutomaticDecompression = [Net.DecompressionMethods]::GZip -bor [Net.DecompressionMethods]::Deflate
    $bridge = $null
    try {
        switch ([string]$policy.mode) {
            'direct' {
                $handler.UseProxy = $false
                $handler.Proxy = $null
            }
            'custom' {
                $handler.UseProxy = $true
                if ([string]$policy.proxyType -eq 'socks5') {
                    $bridge = Start-WibNetworkProxyBridge -Policy $policy
                    $handler.Proxy = New-Object Net.WebProxy(('http://127.0.0.1:{0}' -f $bridge.Port), $false)
                }
                else {
                    $proxy = New-Object Net.WebProxy(('http://{0}:{1}' -f $policy.host, $policy.port), $false)
                    if (-not [string]::IsNullOrWhiteSpace([string]$policy.username)) {
                        $password = Get-WibProxyCredentialText -Policy $policy
                        $proxy.Credentials = New-Object Net.NetworkCredential([string]$policy.username, [string]$password)
                        $password = $null
                    }
                    $handler.Proxy = $proxy
                }
            }
            default {
                $handler.UseProxy = $true
                $handler.Proxy = $null
            }
        }
        $client = New-Object Net.Http.HttpClient($handler, $true)
        $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)
        return [pscustomobject]@{ Client=$client; Bridge=$bridge; Policy=$policy }
    }
    catch {
        if ($null -ne $bridge) { $bridge.Dispose() }
        $handler.Dispose()
        throw
    }
}

function Close-WibHttpClientContext {
    param([AllowNull()]$Context)
    if ($null -eq $Context) { return }
    if ($null -ne $Context.Client) { try { $Context.Client.Dispose() } catch { } }
    if ($null -ne $Context.Bridge) { try { $Context.Bridge.Dispose() } catch { } }
}

function New-WibHttpFailureException {
    param([int]$StatusCode, [string]$Body, [string]$Message)
    $exception = New-Object Net.Http.HttpRequestException($Message)
    $exception.Data['WibHttpStatusCode'] = $StatusCode
    if (-not [string]::IsNullOrWhiteSpace($Body)) { $exception.Data['WibHttpErrorBody'] = $Body }
    return $exception
}

function Invoke-WibHttpRequestCore {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [ValidateSet('GET','POST')][string]$Method = 'GET',
        [hashtable]$Headers = @{},
        [AllowNull()][hashtable]$FormBody = $null,
        [int]$TimeoutSeconds = 120,
        [AllowNull()][string]$OutFile = $null
    )

    $context = $null
    $request = $null
    $response = $null
    try {
        $context = New-WibHttpClientContext -TimeoutSeconds $TimeoutSeconds
        $httpMethod = if ($Method -eq 'POST') { [Net.Http.HttpMethod]::Post } else { [Net.Http.HttpMethod]::Get }
        $request = New-Object Net.Http.HttpRequestMessage($httpMethod, $Uri)
        foreach ($key in $Headers.Keys) { $request.Headers.TryAddWithoutValidation([string]$key, [string]$Headers[$key]) | Out-Null }
        if ($null -ne $FormBody) {
            $pairs = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]'
            foreach ($key in $FormBody.Keys) { $pairs.Add((New-Object 'System.Collections.Generic.KeyValuePair[string,string]'([string]$key, [string]$FormBody[$key]))) }
            $request.Content = New-Object Net.Http.FormUrlEncodedContent($pairs)
        }
        $response = $context.Client.SendAsync($request).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            throw (New-WibHttpFailureException -StatusCode ([int]$response.StatusCode) -Body $body -Message ('HTTP request failed with status {0}.' -f ([int]$response.StatusCode)))
        }
        if (-not [string]::IsNullOrWhiteSpace($OutFile)) {
            $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $file = $null
            try {
                $file = [IO.File]::Open($OutFile, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
                $stream.CopyTo($file)
                $file.Flush()
            }
            finally {
                if ($null -ne $file) { $file.Dispose() }
                if ($null -ne $stream) { $stream.Dispose() }
            }
            return [pscustomobject]@{ StatusCode=[int]$response.StatusCode; Content=$null }
        }
        $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        return [pscustomobject]@{ StatusCode=[int]$response.StatusCode; Content=$content }
    }
    catch {
        $code = ''
        try { if ($_.Exception.Data.Contains('WibErrorCode')) { $code = [string]$_.Exception.Data['WibErrorCode'] } } catch { }
        if (-not [string]::IsNullOrWhiteSpace($code)) { throw }
        $policy = if ($null -ne $context) { $context.Policy } else { Get-WibNetworkPolicy }
        if ($policy.mode -eq 'custom') {
            $message = 'Custom proxy request failed.'
            throw (New-WibErrorException -Code 'PROXY_CONNECTION_FAILED' -Message $message -Stage 'network' -PublicMessage 'The configured custom proxy could not complete the network request.' -Details ([ordered]@{ proxyType=[string]$policy.proxyType; statusCode=(Get-WibHttpStatusCode -Exception $_.Exception) }))
        }
        throw
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
        if ($null -ne $request) { $request.Dispose() }
        Close-WibHttpClientContext -Context $context
    }
}

function Invoke-WibHttpJsonRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [ValidateSet('GET','POST')][string]$Method = 'GET',
        [hashtable]$Headers = @{},
        [AllowNull()][hashtable]$FormBody = $null,
        [int]$TimeoutSeconds = 120
    )
    $response = Invoke-WibHttpRequestCore -Uri $Uri -Method $Method -Headers $Headers -FormBody $FormBody -TimeoutSeconds $TimeoutSeconds
    try { return ($response.Content | ConvertFrom-Json) }
    catch { throw (New-WibErrorException -Code 'NETWORK_ERROR' -Message 'Remote service returned malformed JSON.' -Stage 'network' -PublicMessage 'The remote service returned an invalid response.') }
}

function Invoke-WibHttpDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [ValidateSet('GET','POST')][string]$Method = 'GET',
        [hashtable]$Headers = @{},
        [AllowNull()][hashtable]$FormBody = $null,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [int]$TimeoutSeconds = 300
    )
    Invoke-WibHttpRequestCore -Uri $Uri -Method $Method -Headers $Headers -FormBody $FormBody -TimeoutSeconds $TimeoutSeconds -OutFile $OutFile | Out-Null
}

function Get-WibManagedDownloadProxyPrefix {
    param([Parameter(Mandatory = $true)]$Policy, [AllowNull()]$Bridge)

    $clear = 'set "HTTP_PROXY=" & set "HTTPS_PROXY=" & set "ALL_PROXY=" & set "http_proxy=" & set "https_proxy=" & set "all_proxy="'
    if ([string]$Policy.mode -eq 'direct') { return $clear }
    if ($null -eq $Bridge) { throw (New-WibErrorException -Code 'PROXY_CONNECTION_FAILED' -Message 'Proxy bridge is unavailable for managed download.' -Stage 'download' -PublicMessage 'Proxy transport is unavailable for the downloader.') }
    $local = 'http://127.0.0.1:{0}' -f [int]$Bridge.Port
    return ($clear + ' & set "HTTP_PROXY=' + $local + '" & set "HTTPS_PROXY=' + $local + '" & set "ALL_PROXY=' + $local + '" & set "http_proxy=' + $local + '" & set "https_proxy=' + $local + '" & set "all_proxy=' + $local + '"')
}

function Test-WibNetworkConnection {
    [CmdletBinding()]
    param([int]$TimeoutSeconds = 15)

    $uri = 'https://api.uupdump.net/listid.php?search=Windows%2011&sortByDate=1'
    $response = Invoke-WibHttpJsonRequest -Uri $uri -Method GET -TimeoutSeconds $TimeoutSeconds -Headers @{
        'User-Agent'=('WindowsISOBuilder/{0} network-test' -f $script:WibApplicationVersion)
        'Accept'='application/json'
    }
    if ($null -eq $response -or $null -eq $response.response) {
        throw (New-WibErrorException -Code 'NETWORK_ERROR' -Message 'Network test received an unexpected response.' -Stage 'network' -PublicMessage 'The network test returned an unexpected response.')
    }
    $policy = Get-WibNetworkPolicy
    return [pscustomobject]@{ Success=$true; Mode=[string]$policy.mode; ProxyType=[string]$policy.proxyType }
}
