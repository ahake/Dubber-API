# Dubber API

PowerShell scripts that sign in to the [Dubber](https://www.dubber.net/) API and call account endpoints. Pass credentials as parameters. Downloaded data is written locally and is not meant to be committed.

## Requirements

- [PowerShell 5.1](https://learn.microsoft.com/powershell/) or later (Windows PowerShell or [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell))

## Credentials

Each script uses the OAuth 2.0 resource-owner password grant, then calls the API with the bearer token.

You need four values, all for the **same region**:

| Value | Where to get it |
| --- | --- |
| Client ID and client secret | A Mashery application on [developer.dubber.net](https://developer.dubber.net/) |
| Auth ID and auth token | The API tab in the Dubber portal |

The easiest way to supply them without environment variables is a local runner that stays out of git.

### Local credentials file

1. Copy the example file:

```powershell
Copy-Item .\Dubber.local.ps1.example .\Dubber.local.ps1
```

2. Edit `Dubber.local.ps1` and fill in your values. Set `$Command` to `Profile`, `Recordings`, or `Audio`.
3. Run:

```powershell
.\Dubber.local.ps1
```

`Dubber.local.ps1` is listed in `.gitignore`. Do not commit it. The runner passes values as script parameters; it does not set environment variables.

You can also call any script directly and pass the same parameters yourself.

The API base URL is `https://api.dubber.net/{region}/v1`. If `Region` is omitted, the scripts use `au`.

## Scripts

### Get the signed-in profile

`Get-DubberProfile.ps1` requests a token, calls `GET /profile`, and prints the JSON response.

```powershell
.\Get-DubberProfile.ps1 `
  -ClientId "your-mashery-client-id" `
  -ClientSecret "your-mashery-client-secret" `
  -AuthId "your-auth-id" `
  -AuthToken "your-auth-token" `
  -Region "au"
```

### Download the recordings list

`Get-DubberRecordings.ps1` requests a token, then pages through `GET /accounts/{id}/recordings` (`count=100`, then `before_id` of the last recording on each page). It writes one JSON file.

```powershell
.\Get-DubberRecordings.ps1 `
  -ClientId "your-mashery-client-id" `
  -ClientSecret "your-mashery-client-secret" `
  -AuthId "your-auth-id" `
  -AuthToken "your-auth-token" `
  -Region "au" `
  -AccountId "your-account-id" `
  -OutFile ".\recordings.json"
```

| Parameter | Required | Default |
| --- | --- | --- |
| `ClientId` | Yes | |
| `ClientSecret` | Yes | |
| `AuthId` | Yes | |
| `AuthToken` | Yes | |
| `Region` | No | `au` |
| `AccountId` | No | `35511` |
| `OutFile` | No | `recordings.json` next to the script |

The output file looks like this:

```json
{
  "account_id": "your-account-id",
  "region": "au",
  "fetched_at": "2026-01-01T00:00:00.0000000Z",
  "count": 2,
  "recordings": []
}
```

`fetched_at` is UTC. `recordings` is every recording returned by the API for that account.

### Download call audio for one day

`Get-DubberRecordingAudio.ps1` pages the same recordings list, keeps calls whose `start_time` falls on `Date`, and saves each mp3. `Date` is a calendar day in the timezone of the computer running the script. Dubber sends `start_time` in UTC, and the script converts local midnight before it compares.

The file link is returned only when `Listener` is the email of a Dubber user who can open that recording. Files land in `recordings/<date>/` as `{recording-id}.mp3`. A file that is already there is left in place.

```powershell
.\Get-DubberRecordingAudio.ps1 `
  -ClientId "your-mashery-client-id" `
  -ClientSecret "your-mashery-client-secret" `
  -AuthId "your-auth-id" `
  -AuthToken "your-auth-token" `
  -Listener "agent@example.com" `
  -Date "2026-10-16" `
  -OutDir ".\recordings\2026-10-16"
```

| Parameter | Required | Default |
| --- | --- | --- |
| `Listener` | Yes | |
| `Date` | Yes | `yyyy-MM-dd` in the local timezone |
| `OutDir` | No | `recordings/<date>/` next to the script |

`Region` and `AccountId` use the same defaults as `Get-DubberRecordings.ps1`.

## What stays out of git

`.gitignore` excludes script output and local-only files, including:

- `Dubber.local.ps1` (your filled-in credentials runner)
- `recordings.json` and other `*.json`, `*.csv`, and `*.xml` exports
- `recordings/` and `*.mp3` audio downloads
- `output/` and `exports/`
- `.env` files
- `curl.sh` (local scratch; do not add it)

Do not commit client secrets, auth tokens, or recording dumps. If a secret was ever pushed, revoke it in the Dubber portal and issue a new one.
