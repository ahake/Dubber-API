# Dubber API

PowerShell scripts that sign in to the [Dubber](https://www.dubber.net/) API and call account endpoints. Credentials stay in environment variables for the current session. Downloaded data is written locally and is not meant to be committed.

## Requirements

- [PowerShell 5.1](https://learn.microsoft.com/powershell/) or later (Windows PowerShell or [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell))

## Credentials

Each script uses the OAuth 2.0 resource-owner password grant, then calls the API with the bearer token.

You need four values, all for the **same region**:

| Value | Where to get it |
| --- | --- |
| Client ID and client secret | A Mashery application on [developer.dubber.net](https://developer.dubber.net/) |
| Auth ID and auth token | The API tab in the Dubber portal |

Set them in the PowerShell session before you run a script. They are not stored by these scripts.

```powershell
$env:DUBBER_CLIENT_ID     = "your-mashery-client-id"
$env:DUBBER_CLIENT_SECRET = "your-mashery-client-secret"
$env:DUBBER_AUTH_ID       = "your-auth-id"
$env:DUBBER_AUTH_TOKEN    = "your-auth-token"
$env:DUBBER_REGION        = "au"   # optional; au, sandbox, us, and so on
```

The API base URL is `https://api.dubber.net/{region}/v1`. If `DUBBER_REGION` is unset, the scripts use `au`.

## Scripts

### Get the signed-in profile

`Get-DubberProfile.ps1` requests a token, calls `GET /profile`, and prints the JSON response.

```powershell
.\Get-DubberProfile.ps1
```

### Download the recordings list

`Get-DubberRecordings.ps1` requests a token, then pages through `GET /accounts/{id}/recordings` (`count=100`, then `before_id` of the last recording on each page). It writes one JSON file.

```powershell
$env:DUBBER_ACCOUNT_ID = "your-account-id"          # optional
$env:DUBBER_OUT_FILE   = ".\recordings.json"        # optional
.\Get-DubberRecordings.ps1
```

| Variable | Required | Default |
| --- | --- | --- |
| `DUBBER_CLIENT_ID` | Yes | |
| `DUBBER_CLIENT_SECRET` | Yes | |
| `DUBBER_AUTH_ID` | Yes | |
| `DUBBER_AUTH_TOKEN` | Yes | |
| `DUBBER_REGION` | No | `au` |
| `DUBBER_ACCOUNT_ID` | No | The account id set in `Get-DubberRecordings.ps1` |
| `DUBBER_OUT_FILE` | No | `recordings.json` next to the script |

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

## What stays out of git

`.gitignore` excludes script output and local-only files, including:

- `recordings.json` and other `*.json`, `*.csv`, and `*.xml` exports
- `output/` and `exports/`
- `.env` files
- `curl.sh` (local scratch; do not add it)

Do not commit client secrets, auth tokens, or recording dumps. If a secret was ever pushed, revoke it in the Dubber portal and issue a new one.
