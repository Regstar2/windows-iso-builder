# Windows PowerShell 5.1 compatibility hardening for form-encoded HttpClient requests.
#
# New-Object expands an enumerable supplied through its positional constructor
# syntax. Passing List<KeyValuePair<string,string>> to FormUrlEncodedContent that
# way therefore becomes N constructor arguments (one per form field). Keep the
# collection wrapped as one -ArgumentList element instead.

function New-WibFormUrlEncodedContent {
    param([Parameter(Mandatory = $true)][hashtable]$FormBody)

    Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
    $pairs = New-Object 'System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string,string]]'
    foreach ($key in $FormBody.Keys) {
        $pair = New-Object 'System.Collections.Generic.KeyValuePair[string,string]'([string]$key, [string]$FormBody[$key])
        $pairs.Add($pair)
    }

    # The unary comma is intentional. Without it, Windows PowerShell 5.1
    # enumerates $pairs and tries to call a non-existent N-argument constructor.
    return (New-Object -TypeName Net.Http.FormUrlEncodedContent -ArgumentList (,$pairs))
}

# Override the core declared in Network.ps1. This copy intentionally changes
# only form-content construction so network-policy/error behavior stays intact.
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
            $request.Content = New-WibFormUrlEncodedContent -FormBody $FormBody
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
