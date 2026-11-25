#Requires -Version 5.1
<#
.SYNOPSIS
  Authenticate to Dubber and download the account recordings list to JSON.

.DESCRIPTION
  Requests a bearer token, then pages through GET /accounts/{id}/recordings
  (count=100 + before_id) and writes all recordings to a local JSON file.

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
  Optional. Defaults to "au".

.PARAMETER AccountId
  Optional. Defaults to "35511".

.PARAMETER OutFile
  Optional. Defaults to ".\recordings.json" next to this script.

.EXAMPLE
  .\Get-DubberRecordings.ps1 -ClientId "..." -ClientSecret "..." -AuthId "..." -AuthToken "..."
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

    [string]$Region = "au",

    [string]$AccountId = "35511",

    [string]$OutFile
)

$ErrorActionPreference = "Stop"

$clientId     = $ClientId.Trim()
$clientSecret = $ClientSecret.Trim()
$authId       = $AuthId.Trim()
$authToken    = $AuthToken.Trim()
$region       = $Region.Trim().ToLowerInvariant()
$accountId    = $AccountId.Trim()

if ([string]::IsNullOrWhiteSpace($region)) {
    $region = "au"
}
if ([string]::IsNullOrWhiteSpace($accountId)) {
    $accountId = "35511"
}
if ([string]::IsNullOrWhiteSpace($OutFile)) {
    $outFile = Join-Path $PSScriptRoot "recordings.json"
}
else {
    $outFile = $OutFile.Trim()
}

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
