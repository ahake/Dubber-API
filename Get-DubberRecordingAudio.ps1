#Requires -Version 5.1
<#
.SYNOPSIS
  Download Dubber call audio for one local calendar day.

.DESCRIPTION
  Requests a bearer token, pages through GET /accounts/{id}/recordings, and
  keeps recordings whose start_time falls on Date in the machine's local
  timezone. For each match, GET /recordings/{id} with the listener email and
  saves the mp3.

  The list is newest first. Pages newer than the date are skipped. Paging
  stops when a page ends before the date.

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

.PARAMETER Listener
  Email of a Dubber user who can access the recordings.

.PARAMETER Date
  Calendar day, yyyy-MM-dd, in the local timezone.

.PARAMETER Region
  Optional. Defaults to "au".

.PARAMETER AccountId
  Optional. Defaults to "35511".

.PARAMETER OutDir
  Optional. Defaults to ".\recordings\<date>" next to this script.

.EXAMPLE
  .\Get-DubberRecordingAudio.ps1 -ClientId "..." -ClientSecret "..." -AuthId "..." `
    -AuthToken "..." -Listener "agent@example.com" -Date "2026-10-16"
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

    [Parameter(Mandatory = $true)]
    [string]$Listener,

    [Parameter(Mandatory = $true)]
    [string]$Date,

    [string]$Region = "au",

    [string]$AccountId = "35511",

    [string]$OutDir
)

$ErrorActionPreference = "Stop"

function Get-RecordingStartUtc {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    try {
        return [datetimeoffset]::Parse($Text, [cultureinfo]::InvariantCulture).UtcDateTime
    }
    catch {
        return $null
    }
}

$clientId     = $ClientId.Trim()
$clientSecret = $ClientSecret.Trim()
$authId       = $AuthId.Trim()
$authToken    = $AuthToken.Trim()
$listener     = $Listener.Trim()
$dateText     = $Date.Trim()
$region       = $Region.Trim().ToLowerInvariant()
$accountId    = $AccountId.Trim()

if ([string]::IsNullOrWhiteSpace($region)) {
    $region = "au"
}
if ([string]::IsNullOrWhiteSpace($accountId)) {
    $accountId = "35511"
}

if ($listener -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
    Write-Error "Listener must be an email address."
    exit 1
}

$localDay = [datetime]::MinValue
$dateOk = [datetime]::TryParseExact(
    $dateText,
    "yyyy-MM-dd",
    [cultureinfo]::InvariantCulture,
    [Globalization.DateTimeStyles]::None,
    [ref]$localDay
)
if (-not $dateOk) {
    Write-Error "Date must be a calendar day in yyyy-MM-dd form."
    exit 1
}

$timeZone = [TimeZoneInfo]::Local
$localStart = [datetime]::SpecifyKind($localDay.Date, [DateTimeKind]::Unspecified)
$localEnd = $localStart.AddDays(1)
$startUtc = [TimeZoneInfo]::ConvertTimeToUtc($localStart, $timeZone)
$endUtc = [TimeZoneInfo]::ConvertTimeToUtc($localEnd, $timeZone)

if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $outDir = Join-Path $PSScriptRoot (Join-Path "recordings" $dateText)
}
else {
    $outDir = $OutDir.Trim()
}

$baseUrl = "https://api.dubber.net/$region/v1"

Write-Host ("Local date {0} ({1}): {2:o} to {3:o}" -f $dateText, $timeZone.Id, $startUtc, $endUtc)
Write-Host ("Saving mp3 files to {0}" -f $outDir)

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
$matched = [System.Collections.Generic.List[object]]::new()
$beforeId = $null
$page = 0

do {
    $page++
    $uri = "$baseUrl/accounts/$accountId/recordings?count=100"
    if ($beforeId) {
        $uri += "&before_id=$([uri]::EscapeDataString($beforeId))"
    }

    Write-Host "Fetching page $page ..."
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    $batch = @()
    if ($null -ne $response.recordings) {
        $batch = @($response.recordings)
    }
    if ($batch.Count -eq 0) {
        break
    }

    $lastStart = $null
    foreach ($rec in $batch) {
        $started = Get-RecordingStartUtc -Text ([string]$rec.start_time)
        if ($null -eq $started) {
            Write-Host ("  skipped {0}: start_time was missing or not a date" -f $rec.id)
            continue
        }

        $lastStart = $started
        if ($started -ge $endUtc) {
            continue
        }
        if ($started -ge $startUtc) {
            $matched.Add($rec)
        }
    }

    Write-Host ("  page {0}: {1} recording(s), {2} matched so far" -f $page, $batch.Count, $matched.Count)
    $beforeId = [string]$batch[-1].id

    if ($null -ne $lastStart -and $lastStart -lt $startUtc) {
        break
    }
} while ($batch.Count -eq 100)

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$saved = 0
$skipped = 0
$failed = [System.Collections.Generic.List[string]]::new()
$index = 0

foreach ($rec in $matched) {
    $index++
    $id = [string]$rec.id
    $dest = Join-Path $outDir ($id + ".mp3")

    if (Test-Path -LiteralPath $dest) {
        $skipped++
        Write-Host ("[{0}/{1}] {2} already exists" -f $index, $matched.Count, $id)
        continue
    }

    Write-Host ("[{0}/{1}] downloading {2}" -f $index, $matched.Count, $id)
    $partial = $dest + ".partial"

    try {
        $detailUri = "$baseUrl/recordings/$([uri]::EscapeDataString($id))?listener=$([uri]::EscapeDataString($listener))&content_disposition=$([uri]::EscapeDataString("attachment;filename=$id.mp3"))"
        $detail = Invoke-RestMethod -Method Get -Uri $detailUri -Headers $headers
        $audioUrl = [string]$detail.recording_url
        if ([string]::IsNullOrWhiteSpace($audioUrl)) {
            throw "Response did not include recording_url."
        }

        Invoke-WebRequest -Uri $audioUrl -OutFile $partial -UseBasicParsing
        Move-Item -LiteralPath $partial -Destination $dest
        $saved++
    }
    catch {
        if (Test-Path -LiteralPath $partial) {
            Remove-Item -LiteralPath $partial -Force
        }
        $failed.Add($id)
        $status = $null
        if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
            $status = [int]$_.Exception.Response.StatusCode
        }
        if ($status) {
            Write-Host ("  failed {0} (HTTP {1})" -f $id, $status)
        }
        else {
            Write-Host ("  failed {0}" -f $id)
        }
    }
}

Write-Host ("Matched {0}; saved {1}; skipped {2}; failed {3}." -f $matched.Count, $saved, $skipped, $failed.Count)
if ($failed.Count -gt 0) {
    Write-Host ("Failed recording id(s): {0}" -f ($failed -join ", "))
    exit 1
}
