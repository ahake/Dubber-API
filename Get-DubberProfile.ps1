#Requires -Version 5.1
<#
.SYNOPSIS
  Request a Dubber bearer token, then GET /profile.

.DESCRIPTION
  Uses the OAuth2 Resource Owner Password Credentials grant, then calls GET /profile.

  Set these environment variables before running:
    DUBBER_CLIENT_ID      Mashery Client ID for the SAME region (developer.dubber.net)
    DUBBER_CLIENT_SECRET  Mashery Client Secret
    DUBBER_AUTH_ID        Auth ID from the Dubber portal API tab
    DUBBER_AUTH_TOKEN     Auth Token from the Dubber portal API tab
    DUBBER_REGION         Optional. Defaults to "au". Examples: au, sandbox, us

.EXAMPLE
  $env:DUBBER_CLIENT_ID     = "your-mashery-client-id"
  $env:DUBBER_CLIENT_SECRET = "your-mashery-client-secret"
  $env:DUBBER_AUTH_ID       = "your-auth-id"
  $env:DUBBER_AUTH_TOKEN    = "your-auth-token"
  $env:DUBBER_REGION        = "au"
  .\Get-DubberProfile.ps1
#>

$ErrorActionPreference = "Stop"

$required = @(
    "DUBBER_CLIENT_ID",
    "DUBBER_CLIENT_SECRET",
    "DUBBER_AUTH_ID",
    "DUBBER_AUTH_TOKEN"
)

$missing = $required | Where-Object { [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($_)) }
if ($missing) {
    Write-Error ("Missing required environment variable(s): {0}. Set them in this session before running the script." -f ($missing -join ", "))
    exit 1
}

# Trim accidental whitespace/newlines from copy-paste
$clientId     = $env:DUBBER_CLIENT_ID.Trim()
$clientSecret = $env:DUBBER_CLIENT_SECRET.Trim()
$authId       = $env:DUBBER_AUTH_ID.Trim()
$authToken    = $env:DUBBER_AUTH_TOKEN.Trim()

$region = if ([string]::IsNullOrWhiteSpace($env:DUBBER_REGION)) { "au" } else { $env:DUBBER_REGION.Trim().ToLowerInvariant() }
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

Write-Host "Requesting access token from $baseUrl/token ..."
$token = Invoke-RestMethod -Method Post -Uri "$baseUrl/token" `
    -ContentType "application/x-www-form-urlencoded" `
    -Body $form

if ([string]::IsNullOrWhiteSpace($token.access_token)) {
    Write-Error "Token response did not include access_token."
    exit 1
}

Write-Host ("Token received (expires_in={0}s). Fetching profile..." -f $token.expires_in)

$dubberprofile = Invoke-RestMethod -Method Get -Uri "$baseUrl/profile" `
    -Headers @{ Authorization = "Bearer $($token.access_token)" }

$dubberprofile | ConvertTo-Json -Depth 6