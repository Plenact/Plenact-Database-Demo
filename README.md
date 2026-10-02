# Plenact Database Demo

A native SwiftUI learning project connecting to a PHP API on Bluehost over HTTPS. The API accesses a MySQL-compatible database; the app never connects directly to the database.

## Current progress

- The app performs a foreground, user-triggered health check with loading feedback and error handling.
- `TokenStore.swift` provides Keychain save, load, and delete operations. The app has secure token entry, local format validation, Keychain save/delete controls, and a stored-token indicator. Authenticated bootstrap retrieval has successfully displayed the live database configuration and notice on an iPhone. Saving a token does not validate it with the server.
- The app includes Favorite Food, #Cats, optional Gender, a conditional self-description, and an Excited checkbox with validation and authenticated save/load support. The existing Food/#Cats flow succeeded in the Simulator and on a physical iPhone. Migration `003` and the expanded Gender/Excited API contract are local source only; they still need applying and deployment.
- The deployed server has a public health endpoint and app-token-protected authentication and database-bootstrap endpoints.
- The database schema and initial configuration/notice data have been created and verified.
- Installation-status uploads and a separate reader endpoint are still pending.

## App setup

1. Open `Plenact Database Demo.xcodeproj` in Xcode.
2. Select your signing team and an available bundle identifier.
3. Select an iPhone simulator or connected iPhone, then run.
4. Tap **Test API**.
5. Store the app token in Keychain, then tap **Load Database Data** to request the bootstrap response.
6. After applying the required migrations and deploying the preference endpoints, enter the profile values and tap **Save Preferences**. Tap **Load Database** to reload them.

The `AppIcon` asset is configured for Debug and Release. App credentials will be entered at runtime and stored in Keychain; do not embed them in source or the app bundle.

## Server source and deployment

The local filesystem directory is `Server/`; existing Git entries use `server/`. On this case-insensitive Mac these refer to the same directory. The casing has not been changed as part of credential housekeeping.

Deploy the scripts from `Server/api-dev/` to `/home2/justirl2/public_html/plenact/api-dev/`:

| Endpoint | Purpose | Access |
| --- | --- | --- |
| `health.php` | Fixed service-health response | Public |
| `auth-check.php` | Verify app-role authentication | App token |
| `bootstrap.php` | Fetch configuration, notice, and optional preferences for this installation | App token; expanded profile response pending redeploy |
| `preferences.php` | Save the latest preferences for this installation | App token, POST; expanded profile request pending redeploy |

The duplicate `Server/health.php` is an earlier baseline copy; use `Server/api-dev/health.php` for deployment.

The server uses PHP 8.2 and Percona 5.7 (MySQL 5.7 compatible). The database user has SELECT, INSERT, and UPDATE privileges. Run schema changes through a separate administrative workflow. `Server/001_initial.sql` was already applied; do not rerun it against the existing database. The additive `Server/002_installation_preferences.sql` migration has been applied once; do not rerun it. `Server/003_installation_preference_profile.sql` adds Gender and Excited fields and has not yet been applied. Database timestamps represent UTC.

The PHP scripts resolve private configuration relative to their deployed directory. Local `Server/` is a deployment reference, not a runnable mirror of the hosting directory layout.

## Private configuration

Only placeholder examples belong in Git:

- `Server/plenact-private/database.example.json`
- `Server/plenact-private/api-auth.example.json`

Use these as structural references for the real `database.json` and `api-auth.json` stored on the host in `/home2/justirl2/plenact-private/`, outside the public web root. Replace every placeholder privately; the example token strings intentionally do not pass the server's token validation.

Use two distinct 64-character ASCII alphanumeric tokens and retain them in your password manager. The installation identifier is a UUID, not a credential. Restrict the private directory to `0700` and its configuration files to `0600`.

Local real configuration filenames are ignored, but ignore rules do not remove secrets from earlier commits or manually created archives. Do not package private configuration in shared ZIP files. Do not publish temporary probes from `Server/api-dev/.archived/`; a dot-prefixed folder alone is not proof that HTTP access is blocked.

## Credential rotation still required

Populated private configuration was included in a shared archive and tracked in Git history. Removing current tracked copies does not invalidate those values or erase that history.

Complete the following privately in cPanel and your password manager:

1. Generate a new database password and two distinct new API tokens. Do not paste them into chat or terminal commands.
2. Change the dedicated database user's password in cPanel and update the private server `database.json` immediately. Expect a brief interruption to database-backed requests between those changes.
3. Update the private server `api-auth.json` with both new tokens. Preserve the existing installation UUID. Update your password-manager records and any clients using the old tokens.
4. Verify bootstrap with the new app token, and confirm that the old app token is rejected. Keep private files at `0600`.
5. Before sharing or publishing the repository again, review where the affected commits and archives were distributed. Any history cleanup needs a separate, coordinated plan; rotation remains necessary even after history cleanup.

No credential rotation, deployment change, or Git history rewrite is performed by this local housekeeping change.

## Verification recorded so far

Public health check:

```sh
curl --include --connect-timeout 10 --max-time 20 https://plenact.com/api-dev/health.php
```

Expected: HTTP 200, JSON content type, `Cache-Control: no-store`, and `{"service":"plenact-dev","ok":true}`.

The health flow was previously verified in the simulator and on a physical iPhone. Disabling connectivity produced an error; restoring connectivity and retrying returned success.

Server authentication was previously verified: missing/invalid token returned 401, reader token returned 403 on app-only endpoints, and app token returned 200. These are recorded results, not a fresh deployment test.

Bootstrap returned:

```json
{
  "configuration": {
    "welcome_message": "Hello from the Plenact database!",
    "version": 1
  },
  "notice": {
    "id": 1,
    "message": "Development connection test: welcome aboard."
  }
}
```

`notice` may be null when no active notice exists.

The local `bootstrap.php` source returns a nullable `preferences` object containing the saved profile fields. The expanded Gender/Excited response and request contracts must be deployed after migration `003` before testing those fields on a device.

## Next milestone

Apply `Server/003_installation_preference_profile.sql` once, then deploy the updated `Server/api-dev/preferences.php` and `Server/api-dev/bootstrap.php`. Rebuild the app and test all Gender choices, the conditional self-description, and both Excited states on the Simulator and physical iPhone. Confirm existing Food/#Cats values remain unchanged and repeat a save to verify the same row updates. Keep profile preferences separate from `installation_status`; a separate restricted reader endpoint remains future work.
