#Requires -Version 5.1
<#
.SYNOPSIS
  Authenticate to Dubber and download the account recordings list to JSON.

.DESCRIPTION
  Requests a bearer token, then pages through GET /accounts/{id}/recordings
  (count=100 + before_id) and writes all recordings to a local JSON file.

  Environment variables:
    DUBBER_CLIENT_ID, DUBBER_CLIENT_SECRET, DUBBER_AUTH_ID, DUBBER_AUTH_TOKEN
    DUBBER_REGION       Optional. Defaults to "au".
    DUBBER_ACCOUNT_ID   Optional. Defaults to "35511".
    DUBBER_OUT_FILE     Optional. Defaults to ".\recordings.json".

.EXAMPLE
  .\Get-DubberRecordings.ps1
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
    Write-Error ("Missing required environment variable(s): {0}." -f ($missing -join ", "))
    exit 1
}

$clientId     = $env:DUBBER_CLIENT_ID.Trim()
$clientSecret = $env:DUBBER_CLIENT_SECRET.Trim()
$authId       = $env:DUBBER_AUTH_ID.Trim()
$authToken    = $env:DUBBER_AUTH_TOKEN.Trim()

$region    = if ([string]::IsNullOrWhiteSpace($env:DUBBER_REGION)) { "au" } else { $env:DUBBER_REGION.Trim().ToLowerInvariant() }
$accountId = if ([string]::IsNullOrWhiteSpace($env:DUBBER_ACCOUNT_ID)) { "35511" } else { $env:DUBBER_ACCOUNT_ID.Trim() }
$outFile   = if ([string]::IsNullOrWhiteSpace($env:DUBBER_OUT_FILE)) { Join-Path $PSScriptRoot "recordings.json" } else { $env:DUBBER_OUT_FILE.Trim() }

$baseUrl = "https://api.dubber.net/$region/v1"

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

$headers = @{ Authorization = "Bearer $($token.access_token)" }
$all = [System.Collections.Generic.List[object]]::new()
$beforeId = $null
$page = 0

do {
    $page++
    $uri = "$baseUrl/accounts/$accountId/recordings?count=100"
    if ($beforeId) {
        $uri += "&before_id=$([uri]::EscapeDataString($beforeId))"
    }

    Write-Host "Fetching page $page : $uri"
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    $batch = @($response.recordings)
    if ($batch.Count -eq 0) {
        break
    }

    foreach ($rec in $batch) {
        $all.Add($rec)
    }

    Write-Host ("  got {0} (total {1})" -f $batch.Count, $all.Count)
    $beforeId = [string]$batch[-1].id
} while ($batch.Count -eq 100)

$result = [pscustomobject]@{
    account_id    = $accountId
    region        = $region
    fetched_at    = (Get-Date).ToUniversalTime().ToString("o")
    count         = $all.Count
    recordings    = $all
}

$result | ConvertTo-Json -Depth 8 | Set-Content -Path $outFile -Encoding utf8
Write-Host ("Wrote {0} recording(s) to {1}" -f $all.Count, $outFile)
