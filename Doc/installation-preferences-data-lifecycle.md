# Installation Preferences Data Lifecycle

This document describes how the demo's Favorite Food and #Cats values move from the iOS form to the development database. It covers the local implementation; the schema migration and PHP endpoint must be applied and deployed separately before a hosted write can succeed.

## Data Contract

The app collects two required values:

| Meaning | Swift value | JSON field | Database column | Rules |
| --- | --- | --- | --- | --- |
| Favorite Food | `String` | `favorite_food` | `favorite_food VARCHAR(255)` | Trimmed, nonempty, at most 255 Unicode scalar values; control characters are rejected by the API. |
| Number of cats | `Int` | `cat_count` | `cat_count INT UNSIGNED` | Whole number from 1 through 4,294,967,295. |

The request does not contain an installation identifier. The API reads and validates `installation_id` from private server configuration so the client cannot choose which installation's row to overwrite.

## Write Lifecycle

1. The user enters Favorite Food and a positive #Cats count in the SwiftUI form.
2. The app trims surrounding whitespace from Favorite Food, checks the 255-scalar limit, parses #Cats as an integer, and disables submission until both values are valid.
3. On **Save Preferences**, the app loads the app token from Keychain and sends an HTTPS `POST` to `preferences.php` with a Bearer authorization header and JSON content type. The body contains only `favorite_food` and `cat_count`.
4. The PHP endpoint requires POST, validates private token configuration and the installation UUID, authenticates the app token before connecting to MySQL, and rejects the reader token for this app-only operation.
5. The endpoint validates the JSON body and both values, then uses PDO with a prepared statement to insert the installation's row or update that same row when its primary key already exists.
6. A successful write sets `updated_at` using `UTC_TIMESTAMP(6)` and returns `{"saved":true}`. The app reports success only when it receives HTTP 200 and decodes `saved: true`.

## Persistence Semantics

`installation_preferences` has one row per `installation_id`, which is its primary key. Each successful submission replaces that installation's current food and cat count and refreshes `updated_at`. The table is a current-state record, not a submission history. It is deliberately separate from `installation_status`, which stores sequenced application status reports.

The current demo implements the write path only. Bootstrap does not return these preferences, and no reader endpoint for this table exists yet. A successful POST confirms the server accepted the write; verify persisted values separately in phpMyAdmin until a restricted read endpoint is designed.

## Failure Behavior

| Condition | HTTP status | API response behavior |
| --- | --- | --- |
| Missing, malformed, or unknown Bearer token | 401 | Generic `unauthorized`; database connection is not opened. |
| Valid reader token on this app-only endpoint | 403 | Generic `forbidden`; no write occurs. |
| Wrong method | 405 | `Allow: POST`. |
| Missing or malformed JSON | 400 | Generic `invalid_json`. |
| Request body larger than 8 KiB | 413 | `request_too_large`. |
| Non-JSON content type | 415 | `unsupported_media_type`. |
| Invalid fields or out-of-range values | 422 | Field or payload error code; no write occurs. |
| Configuration, database, or unexpected server error | 500 | Generic `server_error`; internal details are not returned. |

The app presents separate feedback for absent or unreadable Keychain data, authentication and authorization failures, rejected input, server errors, connectivity/timeouts, and an invalid success response. It never displays or logs the token.

## Deployment And Verification

Local sources:

- Schema migration: `Server/002_installation_preferences.sql`
- API endpoint: `Server/api-dev/preferences.php`

Before testing a hosted write:

1. Review the migration, then apply it once to the dedicated development database through the separate schema-administration workflow. Do not rerun `001_initial.sql`.
2. Deploy `preferences.php` to `/home2/justirl2/public_html/plenact/api-dev/`.
3. Confirm private configuration remains outside the public web root and retains its restrictive permissions. Do not copy populated configuration into this repository or an archive.
4. In the app, submit a valid food and cat count. Confirm the success message and inspect the row for the configured installation ID in phpMyAdmin.
5. Change both values and submit again. Confirm the same row was updated, not duplicated, and that `updated_at` advanced in UTC.
6. Check that an invalid count is blocked by the app and rejected by the API, and that unauthenticated and reader-token requests do not write.

No migration has been applied and no endpoint deployment is performed by local code changes. The app-token scheme is for this controlled development demonstration; it is not a production user-authorization design.