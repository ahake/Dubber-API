#Requires -Version 5.1
<#
.SYNOPSIS
  Request a Dubber bearer token, then GET /profile.

.DESCRIPTION
  Uses the OAuth2 Resource Owner Password Credentials grant, then calls GET /profile.

  Pass credentials as parameters. Prefer Dubber.local.ps1 (gitignored) so secrets
  stay out of the repository.

.PARAMETER ClientId
  Mashery Client ID for the same region (developer.dubber.net).

.PARAMETER ClientSecret
  Mashery Client Secret.

.PARAMETER AuthId
  Auth ID from the Dubber portal API tab.

.PARAMETER AuthToken
  Auth Token from the Dubber portal API tab.

.PARAMETER Region
  Optional. Defaults to "au". Examples: au, sandbox, us.

.EXAMPLE
  .\Get-DubberProfile.ps1 -ClientId "..." -ClientSecret "..." -AuthId "..." -AuthToken "..."
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $true)]
    [string]$AuthId,

    [Parameter(Mandatory = $true)]
    [string]$AuthToken,

    [string]$Region = "au"
)

$ErrorActionPreference = "Stop"

# Trim accidental whitespace/newlines from copy-paste
$clientId     = $ClientId.Trim()
$clientSecret = $ClientSecret.Trim()
$authId       = $AuthId.Trim()
$authToken    = $AuthToken.Trim()
$region       = $Region.Trim().ToLowerInvariant()

if ([string]::IsNullOrWhiteSpace($region)) {
    $region = "au"
}

$baseUrl = "https://api.dubber.net/$region/v1"

Write-Host ("Using region={0}; client_id len={1} prefix={2}...; auth_id len={3} prefix={4}..." -f `
    $region, $clientId.Length, $clientId.Substring(0, [Math]::Min(4, $clientId.Length)), `
    $authId.Length, $authId.Substring(0, [Math]::Min(4, $authId.Length)))

# Explicit form body (avoids PowerShell hashtable/JSON quirks that can trigger 403 code 1020)
$form = @(
    "client_id=$([uri]::EscapeDataString($clientId))"
    "client_secret=$([uri]::EscapeDataString($clientSecret))"
    "username=$([uri]::EscapeDataString($authId))"
    "password=$([uri]::EscapeDataString($authToken))"
    "grant_type=password"
) -join "&"

# #region agent log
$__debugLog = Join-Path $PSScriptRoot ".cursor/debug-efda91.log"
function Write-AgentLog {
    param([string]$HypothesisId, [string]$Location, [string]$Message, [hashtable]$Data)
    $payload = [ordered]@{
        sessionId    = "efda91"
        runId        = "pre-fix"
        hypothesisId = $HypothesisId
        location     = $Location
        message      = $Message
        data         = $Data
        timestamp    = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    }
    ($payload | ConvertTo-Json -Compress -Depth 6) | Add-Content -LiteralPath $__debugLog -Encoding utf8
}
New-Item -ItemType Directory -Force -Path (Split-Path $__debugLog) | Out-Null
Write-AgentLog -HypothesisId "A" -Location "Get-DubberProfile.ps1:token-prep" -Message "token request shape" -Data @{
    region            = $region
    baseUrl           = $baseUrl
    tokenUri          = "$baseUrl/token"
    clientIdLen       = $clientId.Length
    clientIdPrefix    = $clientId.Substring(0, [Math]::Min(4, $clientId.Length))
    clientSecretLen   = $clientSecret.Length
    authIdLen         = $authId.Length
    authIdPrefix      = $authId.Substring(0, [Math]::Min(4, $authId.Length))
    authTokenLen      = $authToken.Length
    clientIdLooksLikeKey = ($clientId -match '^[a-z0-9]{20,}$')
    authIdLooksLikeKey   = ($authId -match '^[a-z0-9]{20,}$')
    formHasClientId      = $form.Contains("client_id=")
    formHasClientSecret  = $form.Contains("client_secret=")
    formHasUsername      = $form.Contains("username=")
    formHasPassword      = $form.Contains("password=")
    formHasGrantType     = $form.Contains("grant_type=password")
    formLength           = $form.Length
    contentType          = "application/x-www-form-urlencoded"
}
# #endregion

Write-Host "Requesting access token from $baseUrl/token ..."
try {
    $token = Invoke-RestMethod -Method Post -Uri "$baseUrl/token" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $form
}
catch {
    # #region agent log
    $errBody = $null
    $statusCode = $null
    try {
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
            $errBody = $reader.ReadToEnd()
            $reader.Dispose()
        }
    }
    catch { }
    if ([string]::IsNullOrWhiteSpace($errBody)) {
        $errBody = [string]$_.ErrorDetails.Message
    }
    $parsedCode = $null
    $parsedMessage = $null
    $parsedError = $null
    try {
        $errObj = $errBody | ConvertFrom-Json
        $parsedCode = $errObj.code
        $parsedMessage = $errObj.message
        $parsedError = $errObj.error
        if (-not $parsedMessage) { $parsedMessage = $errObj.error_description }
    }
    catch { }
    Write-AgentLog -HypothesisId "B" -Location "Get-DubberProfile.ps1:token-error" -Message "token request failed" -Data @{
        region        = $region
        tokenUri      = "$baseUrl/token"
        httpStatus    = $statusCode
        apiCode       = $parsedCode
        apiError      = $parsedError
        apiMessage    = $parsedMessage
        bodySnippet   = if ($errBody) { $errBody.Substring(0, [Math]::Min(240, $errBody.Length)) } else { $null }
    }
    # #endregion
    throw
}

# #region agent log
Write-AgentLog -HypothesisId "C" -Location "Get-DubberProfile.ps1:token-ok" -Message "token request succeeded" -Data @{
    region        = $region
    tokenUri      = "$baseUrl/token"
    hasAccessToken = -not [string]::IsNullOrWhiteSpace($token.access_token)
    expiresIn     = $token.expires_in
}
# #endregion

if ([string]::IsNullOrWhiteSpace($token.access_token)) {
    Write-Error "Token response did not include access_token."
    exit 1
}

Write-Host ("Token received (expires_in={0}s). Fetching profile..." -f $token.expires_in)

$dubberprofile = Invoke-RestMethod -Method Get -Uri "$baseUrl/profile" `
    -Headers @{ Authorization = "Bearer $($token.access_token)" }

$dubberprofile | ConvertTo-Json -Depth 6
