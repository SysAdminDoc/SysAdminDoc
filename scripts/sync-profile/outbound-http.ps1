# The single safe-outbound HTTP policy every public fetch goes through: HTTPS only,
# public destinations only, sockets pinned to validated addresses, redirects followed
# one validated hop at a time. Dot-sourced by scripts/sync-profile.ps1.

function Test-PublicIPAddress {
    param([System.Net.IPAddress]$Address)

    if ($null -eq $Address) { return $false }
    if ($Address.IsIPv4MappedToIPv6) {
        $Address = $Address.MapToIPv4()
    }

    $bytes = $Address.GetAddressBytes()
    if ($Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
        $first = [int]$bytes[0]
        $second = [int]$bytes[1]
        $third = [int]$bytes[2]

        if ($first -eq 0 -or $first -eq 10 -or $first -eq 127) { return $false }
        if ($first -eq 100 -and $second -ge 64 -and $second -le 127) { return $false }
        if ($first -eq 169 -and $second -eq 254) { return $false }
        if ($first -eq 172 -and $second -ge 16 -and $second -le 31) { return $false }
        if ($first -eq 192 -and $second -eq 0 -and $third -eq 0) { return $false }
        if ($first -eq 192 -and $second -eq 0 -and $third -eq 2) { return $false }
        if ($first -eq 192 -and $second -eq 88 -and $third -eq 99) { return $false }
        if ($first -eq 192 -and $second -eq 168) { return $false }
        if ($first -eq 198 -and ($second -eq 18 -or $second -eq 19)) { return $false }
        if ($first -eq 198 -and $second -eq 51 -and $third -eq 100) { return $false }
        if ($first -eq 203 -and $second -eq 0 -and $third -eq 113) { return $false }
        if ($first -ge 224) { return $false }
        return $true
    }

    if ($Address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetworkV6) { return $false }
    if ([System.Net.IPAddress]::IsLoopback($Address)) { return $false }
    if ($Address.Equals([System.Net.IPAddress]::IPv6Any) -or $Address.Equals([System.Net.IPAddress]::IPv6None)) { return $false }
    if ($Address.IsIPv6LinkLocal -or $Address.IsIPv6SiteLocal -or $Address.IsIPv6Multicast) { return $false }
    if (($bytes[0] -band 0xFE) -eq 0xFC) { return $false }
    if ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and $bytes[2] -eq 0x0D -and $bytes[3] -eq 0xB8) { return $false }

    # Only global-unicast IPv6 is eligible. This also excludes IPv4-compatible,
    # translation, documentation, and other special-purpose address families.
    if (($bytes[0] -band 0xE0) -ne 0x20) { return $false }

    # A 6to4 address carries its IPv4 destination in bytes 2 through 5. Apply
    # the same public-address test to prevent transition-address bypasses.
    if ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x02) {
        $embedded = [System.Net.IPAddress]::new([byte[]]@($bytes[2], $bytes[3], $bytes[4], $bytes[5]))
        return Test-PublicIPAddress -Address $embedded
    }

    # Teredo carries the client IPv4 address XORed with 0xff in its final bytes.
    if ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and $bytes[2] -eq 0x00 -and $bytes[3] -eq 0x00) {
        $embedded = [System.Net.IPAddress]::new([byte[]]@(
                ($bytes[12] -bxor 0xFF),
                ($bytes[13] -bxor 0xFF),
                ($bytes[14] -bxor 0xFF),
                ($bytes[15] -bxor 0xFF)
            ))
        return Test-PublicIPAddress -Address $embedded
    }

    return $true
}

function Resolve-SafeOutboundDestination {
    param(
        [string]$Url,
        [scriptblock]$ResolveHostScript
    )

    $blockedResult = {
        param(
            [string]$Reason,
            [bool]$PolicyBlocked = $true
        )
        return [ordered]@{
            ok = $false
            uri = $null
            host = $null
            addresses = @()
            error = "Blocked outbound request: $Reason"
            policyBlocked = $PolicyBlocked
        }
    }

    if ([string]::IsNullOrWhiteSpace($Url)) {
        return & $blockedResult "URL is empty"
    }

    $uri = $null
    if (-not [System.Uri]::TryCreate($Url, [System.UriKind]::Absolute, [ref]$uri)) {
        return & $blockedResult "URL is not an absolute URI"
    }
    if ($uri.Scheme -ne 'https') {
        return & $blockedResult "only HTTPS destinations are allowed"
    }
    if (-not [string]::IsNullOrEmpty($uri.UserInfo)) {
        return & $blockedResult "userinfo credentials are not allowed"
    }

    $escapedHost = $uri.GetComponents([System.UriComponents]::Host, [System.UriFormat]::UriEscaped)
    if ([string]::IsNullOrWhiteSpace($escapedHost) -or $escapedHost.Contains('%')) {
        return & $blockedResult "encoded or empty host names are not allowed"
    }

    $hostName = $uri.IdnHost.TrimEnd('.').ToLowerInvariant()
    if ($hostName -eq 'localhost' -or $hostName.EndsWith('.localhost')) {
        return & $blockedResult "localhost destinations are not allowed"
    }

    $resolvedValues = @()
    $literalAddress = $null
    if ([System.Net.IPAddress]::TryParse($hostName, [ref]$literalAddress)) {
        $resolvedValues = @($literalAddress)
    } else {
        try {
            $resolvedValues = @(if ($ResolveHostScript) {
                    & $ResolveHostScript $hostName
                } else {
                    [System.Net.Dns]::GetHostAddresses($hostName)
                })
        } catch {
            return & $blockedResult "DNS resolution failed for $hostName" $false
        }
    }

    if (@($resolvedValues).Count -eq 0) {
        return & $blockedResult "DNS returned no addresses for $hostName" $false
    }

    $validatedAddresses = [System.Collections.Generic.List[System.Net.IPAddress]]::new()
    foreach ($value in $resolvedValues) {
        $address = $null
        if ($value -is [System.Net.IPAddress]) {
            $address = $value
        } elseif (-not [System.Net.IPAddress]::TryParse([string]$value, [ref]$address)) {
            return & $blockedResult "DNS returned an invalid address for $hostName"
        }

        if (-not (Test-PublicIPAddress -Address $address)) {
            return & $blockedResult "DNS returned a non-public address for $hostName"
        }
        $validatedAddresses.Add($address)
    }

    $uniqueAddresses = @($validatedAddresses.ToArray() |
        Sort-Object -Property @{ Expression = { $_.AddressFamily.value__ } }, @{ Expression = { $_.ToString() } } -Unique)
    return [ordered]@{
        ok = $true
        uri = $uri
        host = $hostName
        addresses = $uniqueAddresses
        error = $null
        policyBlocked = $false
    }
}

function Initialize-SafeOutboundTransport {
    if ('SysAdminDoc.Networking.SafeOutboundHandlerFactory' -as [type]) { return }

    $source = @'
using System;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;

namespace SysAdminDoc.Networking
{
    public static class SafeOutboundHandlerFactory
    {
        public static SocketsHttpHandler Create(string[] addressStrings, int connectTimeoutSeconds)
        {
            IPAddress[] addresses = addressStrings.Select(IPAddress.Parse).ToArray();
            var handler = new SocketsHttpHandler
            {
                AllowAutoRedirect = false,
                UseProxy = false,
                ConnectTimeout = TimeSpan.FromSeconds(Math.Max(1, connectTimeoutSeconds)),
                AutomaticDecompression = DecompressionMethods.GZip | DecompressionMethods.Deflate | DecompressionMethods.Brotli
            };

            handler.ConnectCallback = async (context, cancellationToken) =>
            {
                Exception lastError = null;
                foreach (IPAddress address in addresses)
                {
                    var socket = new Socket(address.AddressFamily, SocketType.Stream, ProtocolType.Tcp);
                    try
                    {
                        await socket.ConnectAsync(
                            new IPEndPoint(address, context.DnsEndPoint.Port),
                            cancellationToken).ConfigureAwait(false);
                        return new NetworkStream(socket, ownsSocket: true);
                    }
                    catch (Exception ex)
                    {
                        lastError = ex;
                        socket.Dispose();
                    }
                }

                throw new HttpRequestException("Could not connect to a validated destination address.", lastError);
            };
            return handler;
        }
    }
}
'@

    try {
        [void](Add-Type -TypeDefinition $source -Language CSharp)
    } catch {
        if (-not ('SysAdminDoc.Networking.SafeOutboundHandlerFactory' -as [type])) { throw }
    }
}

function Invoke-SafeOutboundHttpHop {
    param(
        [string]$Uri,
        [ValidateSet('Head', 'Get')]
        [string]$Method = 'Get',
        [System.Net.IPAddress[]]$Addresses,
        [int]$TimeoutSec = 15,
        [int64]$MaxBytes = 0,
        [bool]$ReadBody = $false,
        [string]$UserAgent = 'SysAdminDoc-profile-sync',
        [string]$Accept = '*/*',
        [hashtable]$Headers = @{}
    )

    Initialize-SafeOutboundTransport
    $addressStrings = [string[]]@($Addresses | ForEach-Object { $_.ToString() })
    $handler = [SysAdminDoc.Networking.SafeOutboundHandlerFactory]::Create(
        $addressStrings,
        [Math]::Max(1, $TimeoutSec)
    )
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds([Math]::Max(1, $TimeoutSec))
    $request = $null
    $response = $null
    $stream = $null
    $memory = $null
    try {
        $httpMethod = if ($Method -eq 'Head') { [System.Net.Http.HttpMethod]::Head } else { [System.Net.Http.HttpMethod]::Get }
        $request = [System.Net.Http.HttpRequestMessage]::new($httpMethod, $Uri)
        if (-not [string]::IsNullOrWhiteSpace($UserAgent)) {
            [void]$request.Headers.TryAddWithoutValidation('User-Agent', $UserAgent)
        }
        if (-not [string]::IsNullOrWhiteSpace($Accept)) {
            [void]$request.Headers.TryAddWithoutValidation('Accept', $Accept)
        }
        foreach ($headerName in @($Headers.Keys)) {
            [void]$request.Headers.TryAddWithoutValidation([string]$headerName, [string]$Headers[$headerName])
        }

        $response = $client.Send($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead)
        $statusCode = [int]$response.StatusCode
        $location = if ($response.Headers.Location) { $response.Headers.Location.OriginalString } else { $null }
        $etag = if ($response.Headers.ETag) { $response.Headers.ETag.ToString() } else { $null }
        $lastModified = if ($response.Content -and $null -ne $response.Content.Headers.LastModified) {
            ([datetimeoffset]$response.Content.Headers.LastModified).ToString('R')
        } else {
            $null
        }
        $retryAfter = if ($response.Headers.RetryAfter) { $response.Headers.RetryAfter.ToString() } else { $null }
        $bytes = [byte[]]@()
        $text = $null
        $bytesRead = [int64]0

        if ($ReadBody -and $response.Content) {
            if ($MaxBytes -le 0) {
                throw [System.InvalidOperationException]::new('A positive response byte cap is required when reading a body.')
            }
            $contentLength = $response.Content.Headers.ContentLength
            if ($null -ne $contentLength -and [int64]$contentLength -gt $MaxBytes) {
                return [ordered]@{
                    statusCode = $statusCode; location = $location; etag = $etag; lastModified = $lastModified
                    retryAfter = $retryAfter; bytes = @(); text = $null; bytesRead = [int64]$contentLength
                    error = 'response exceeds the configured byte cap'
                }
            }

            $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $memory = [System.IO.MemoryStream]::new()
            $buffer = [byte[]]::new(81920)
            while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                if (($memory.Length + $read) -gt $MaxBytes) {
                    return [ordered]@{
                        statusCode = $statusCode; location = $location; etag = $etag; lastModified = $lastModified
                        retryAfter = $retryAfter; bytes = @(); text = $null; bytesRead = [int64]($memory.Length + $read)
                        error = 'response exceeds the configured byte cap'
                    }
                }
                $memory.Write($buffer, 0, $read)
            }
            $bytes = $memory.ToArray()
            $bytesRead = [int64]$bytes.Length
            $text = [System.Text.Encoding]::UTF8.GetString($bytes)
        }

        return [ordered]@{
            statusCode = $statusCode
            location = $location
            etag = $etag
            lastModified = $lastModified
            retryAfter = $retryAfter
            bytes = $bytes
            text = $text
            bytesRead = $bytesRead
            error = $null
        }
    } catch {
        return [ordered]@{
            statusCode = $null; location = $null; etag = $null; lastModified = $null; retryAfter = $null
            bytes = @(); text = $null; bytesRead = if ($memory) { [int64]$memory.Length } else { [int64]0 }
            error = $_.Exception.Message
        }
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($memory) { $memory.Dispose() }
        if ($response) { $response.Dispose() }
        if ($request) { $request.Dispose() }
        $client.Dispose()
        $handler.Dispose()
    }
}

function Invoke-SafeOutboundHttpRequest {
    <#
    .SYNOPSIS
    Sends an HTTPS request only to DNS-validated, public addresses.
    .DESCRIPTION
    Automatic redirects are disabled. Every redirect is resolved and validated
    independently, and each connection is pinned to the addresses that passed
    policy so a second DNS answer cannot redirect the socket to a protected host.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url,
        [ValidateSet('Head', 'Get')]
        [string]$Method = 'Get',
        [ValidateRange(1, 300)]
        [int]$TimeoutSec = 15,
        [ValidateRange(0, 5)]
        [int]$MaxRedirects = 5,
        [int64]$MaxBytes = 0,
        [switch]$ReadBody,
        [string]$UserAgent = 'SysAdminDoc-profile-sync',
        [string]$Accept = '*/*',
        [hashtable]$Headers = @{},
        [scriptblock]$ResolveHostScript,
        [scriptblock]$SendRequestScript
    )

    $currentUrl = $Url
    $currentMethod = $Method
    $redirectCount = 0
    while ($true) {
        $destination = Resolve-SafeOutboundDestination -Url $currentUrl -ResolveHostScript $ResolveHostScript
        if (-not $destination.ok) {
            return [ordered]@{
                ok = $false; statusCode = $null; error = $destination.error; finalUrl = $currentUrl
                redirectCount = $redirectCount; policyBlocked = [bool]$destination.policyBlocked; bytes = @(); text = $null; bytesRead = [int64]0
                etag = $null; lastModified = $null; retryAfter = $null
            }
        }

        $requestArguments = @{
            Uri = $destination.uri.AbsoluteUri
            Method = $currentMethod
            Addresses = [System.Net.IPAddress[]]@($destination.addresses)
            TimeoutSec = $TimeoutSec
            MaxBytes = $MaxBytes
            ReadBody = [bool]$ReadBody
            UserAgent = $UserAgent
            Accept = $Accept
            Headers = $Headers
        }
        $hop = if ($SendRequestScript) {
            & $SendRequestScript @requestArguments
        } else {
            Invoke-SafeOutboundHttpHop @requestArguments
        }

        $hopError = [string](Get-MemberValue -Object $hop -Name 'error')
        if (-not [string]::IsNullOrWhiteSpace($hopError)) {
            return [ordered]@{
                ok = $false; statusCode = Get-MemberValue -Object $hop -Name 'statusCode'; error = $hopError
                finalUrl = $currentUrl; redirectCount = $redirectCount; policyBlocked = $false
                bytes = @(Get-MemberValue -Object $hop -Name 'bytes'); text = Get-MemberValue -Object $hop -Name 'text'
                bytesRead = [int64](Get-MemberValue -Object $hop -Name 'bytesRead')
                etag = Get-MemberValue -Object $hop -Name 'etag'
                lastModified = Get-MemberValue -Object $hop -Name 'lastModified'
                retryAfter = Get-MemberValue -Object $hop -Name 'retryAfter'
            }
        }

        $statusCode = [int](Get-MemberValue -Object $hop -Name 'statusCode')
        $location = [string](Get-MemberValue -Object $hop -Name 'location')
        $isRedirect = $statusCode -in @(301, 302, 303, 307, 308) -and -not [string]::IsNullOrWhiteSpace($location)
        if ($isRedirect) {
            if ($redirectCount -ge $MaxRedirects) {
                return [ordered]@{
                    ok = $false; statusCode = $statusCode; error = "redirect limit of $MaxRedirects exceeded"
                    finalUrl = $currentUrl; redirectCount = $redirectCount; policyBlocked = $true
                    bytes = @(); text = $null; bytesRead = [int64]0; etag = $null; lastModified = $null; retryAfter = $null
                }
            }

            try {
                $currentUrl = [System.Uri]::new($destination.uri, $location).AbsoluteUri
            } catch {
                return [ordered]@{
                    ok = $false; statusCode = $statusCode; error = 'redirect location is not a valid URI'
                    finalUrl = $currentUrl; redirectCount = $redirectCount; policyBlocked = $true
                    bytes = @(); text = $null; bytesRead = [int64]0; etag = $null; lastModified = $null; retryAfter = $null
                }
            }
            $redirectCount++
            if ($statusCode -eq 303) { $currentMethod = 'Get' }
            continue
        }

        return [ordered]@{
            ok = [bool]($statusCode -ge 200 -and $statusCode -lt 400)
            statusCode = $statusCode
            error = if ($statusCode -ge 400) { "HTTP $statusCode" } else { $null }
            finalUrl = $currentUrl
            redirectCount = $redirectCount
            policyBlocked = $false
            bytes = @(Get-MemberValue -Object $hop -Name 'bytes')
            text = Get-MemberValue -Object $hop -Name 'text'
            bytesRead = [int64](Get-MemberValue -Object $hop -Name 'bytesRead')
            etag = Get-MemberValue -Object $hop -Name 'etag'
            lastModified = Get-MemberValue -Object $hop -Name 'lastModified'
            retryAfter = Get-MemberValue -Object $hop -Name 'retryAfter'
        }
    }
}
