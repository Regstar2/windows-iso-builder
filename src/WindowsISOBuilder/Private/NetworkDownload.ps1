# Policy-aware file download adapter. Windows PowerShell 5.1 Invoke-WebRequest is
# retained as the file-download seam so existing controlled tests can intercept
# it, while Direct and Custom modes still use the global Network Policy.

function Invoke-WibHttpDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [ValidateSet('GET','POST')][string]$Method = 'GET',
        [hashtable]$Headers = @{},
        [AllowNull()][hashtable]$FormBody = $null,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [int]$TimeoutSeconds = 300
    )

    $policy = Get-WibNetworkPolicy
    $bridge = $null
    try {
        # Direct must explicitly bypass both Windows and inherited proxy state.
        # The HttpClient core has UseProxy=false and therefore provides the
        # strongest direct semantics for this mode.
        if ([string]$policy.mode -eq 'direct') {
            Invoke-WibHttpRequestCore -Uri $Uri -Method $Method -Headers $Headers -FormBody $FormBody -TimeoutSeconds $TimeoutSeconds -OutFile $OutFile | Out-Null
            return
        }

        $arguments = @{
            Method=$Method
            Uri=$Uri
            OutFile=$OutFile
            UseBasicParsing=$true
            TimeoutSec=$TimeoutSeconds
            Headers=$Headers
            ErrorAction='Stop'
        }
        if ($null -ne $FormBody) { $arguments['Body'] = $FormBody }

        if ([string]$policy.mode -eq 'custom') {
            # Authenticated HTTP and all SOCKS5 downloads are exposed to
            # Invoke-WebRequest only as an unauthenticated loopback HTTP proxy.
            # Upstream credentials remain in memory inside the bridge.
            $needsBridge = ([string]$policy.proxyType -eq 'socks5') -or
                -not [string]::IsNullOrWhiteSpace([string]$policy.username) -or [bool]$policy.hasCredential
            if ($needsBridge) {
                $bridge = Start-WibNetworkProxyBridge -Policy $policy
                $arguments['Proxy'] = ('http://127.0.0.1:{0}' -f [int]$bridge.Port)
            }
            else {
                $arguments['Proxy'] = ('http://{0}:{1}' -f [string]$policy.host, [int]$policy.port)
            }
        }
        # System intentionally supplies no -Proxy parameter so Windows
        # PowerShell uses its declared system/default web proxy behavior.
        Invoke-WebRequest @arguments | Out-Null
    }
    catch {
        $knownCode = ''
        try { if ($_.Exception.Data.Contains('WibErrorCode')) { $knownCode = [string]$_.Exception.Data['WibErrorCode'] } } catch { }
        if (-not [string]::IsNullOrWhiteSpace($knownCode)) { throw }
        if ([string]$policy.mode -eq 'custom') {
            throw (New-WibErrorException -Code 'PROXY_CONNECTION_FAILED' -Message 'Custom proxy file download failed.' -Stage 'network' -PublicMessage 'The configured custom proxy could not complete the download.')
        }
        throw
    }
    finally {
        if ($null -ne $bridge) { try { $bridge.Dispose() } catch { } }
    }
}
