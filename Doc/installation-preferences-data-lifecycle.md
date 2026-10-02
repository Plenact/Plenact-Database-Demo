# Installation Preferences Data Lifecycle

This document describes how the demo's Food, #Cats, Gender, Gender description, and Excited values move between the iOS form, HTTPS API, and development database. The original Food/#Cats write and read flow is deployed and tested. Migration `003` and the expanded Gender/Excited endpoint contract are local changes and still require application and deployment.

## Data Contract

The app collects two required values and three additional values:

| Meaning | Swift value | JSON field | Database column | Rules |
| --- | --- | --- | --- | --- |
| Favorite Food | `String` | `favorite_food` | `favorite_food VARCHAR(255)` | Trimmed, nonempty, at most 255 Unicode scalar values; control characters are rejected by the API. |
| Number of cats | `Int` | `cat_count` | `cat_count INT UNSIGNED` | Whole number from 1 through 4,294,967,295. |
| Gender | optional category | `gender` | `gender VARCHAR(32) NULL` | Optional; `woman`, `man`, `non_binary`, `self_describe`, or `prefer_not_to_say`. |
| Gender description | optional string | `gender_description` | `gender_description VARCHAR(100) NULL` | Required only for `self_describe`; trimmed, nonempty, at most 100 Unicode scalar values. |
| Excited | `Bool` | `is_excited` | `is_excited TINYINT UNSIGNED` | Required JSON boolean; stored as 0 or 1, defaults to 0 for existing rows. |

The request does not contain an installation identifier. The API reads and validates `installation_id` from private server configuration so the client cannot choose which installation's row to overwrite.

## Write Lifecycle

1. The user enters Favorite Food, a positive #Cats count, an optional Gender choice, a conditional self-description, and the Excited checkbox state.
2. The app trims text inputs, enforces the 255-scalar food and 100-scalar self-description limits, parses #Cats as a positive integer, and disables submission while required values are invalid.
3. On **Save Preferences**, the app loads the app token from Keychain and sends an HTTPS `POST` to `preferences.php` with a Bearer authorization header and JSON content type. The body contains `favorite_food`, `cat_count`, `gender`, `gender_description`, and `is_excited`.
4. The PHP endpoint requires POST, validates private token configuration and the installation UUID, authenticates the app token before connecting to MySQL, and rejects the reader token for this app-only operation.
5. The endpoint validates the JSON body and all values, including the allowed Gender choices and the conditional Self-describe text, then uses PDO with a prepared statement to insert or update the installation's row.
6. A successful write sets `updated_at` using `UTC_TIMESTAMP(6)` and returns `{"saved":true}`. The app reports success only when it receives HTTP 200 and decodes `saved: true`.

## Persistence Semantics

`installation_preferences` has one row per `installation_id`, which is its primary key. Each successful submission replaces that installation's current preference values and refreshes `updated_at`. The table is a current-state record, not a submission history. It is deliberately separate from `installation_status`, which stores sequenced application status reports.

Migration `003_installation_preference_profile.sql` adds nullable Gender fields and an Excited flag with a default of 0. Existing Food/#Cats values are unchanged; existing rows read back with no Gender selection and Excited unchecked. Gender is personal data: collect it only for an explicit product purpose, keep it optional, and never use it for authorization.

The write endpoint is app-token protected. The updated bootstrap source also reads the configured installation's preferences for the app, but that change must be deployed before **Load Database Data** can populate the form. There is no separate reader endpoint for external clients yet. A successful POST confirms the server accepted the write; the bootstrap response will provide app readback after redeployment.

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

The app presents separate feedback for absent or unreadable Keychain data, authentication and authorization failures, rejected input, server errors, connectivity/timeouts, and an invalid success response. It never displays or logs the token or preference values.

## Deployment And Verification

Local sources:

- Schema migration: `Server/002_installation_preferences.sql`
- Profile fields migration: `Server/003_installation_preference_profile.sql`
- API endpoint: `Server/api-dev/preferences.php`
- Bootstrap readback: `Server/api-dev/bootstrap.php`

Migration `002` has been applied once to the development database, and the Food/#Cats save request succeeded in the Simulator and on a physical iPhone. Migration `003` and the expanded Gender/Excited endpoint contracts are not yet applied or deployed.

1. Apply migration `003` once through the separate schema-administration workflow. Do not rerun migrations `001` or `002`.
2. Deploy the updated `preferences.php` and `bootstrap.php` to `/home2/justirl2/public_html/plenact/api-dev/`.
3. Rebuild the app; confirm existing Food/#Cats values remain intact, Gender is unselected, and Excited is unchecked for existing rows.
4. Test every Gender choice, require a bounded description for Self-describe, test Excited both checked and unchecked, then save and load the values on the Simulator and physical iPhone.
5. Save changed values again and confirm the same row updates, not duplicates, and `updated_at` advances in UTC.
6. Keep private configuration outside the public web root with restrictive permissions. Never copy populated configuration into this repository or an archive.

No migration or deployment is performed by local code changes. The app-token scheme is for this controlled development demonstration; it is not a production user-authorization design.