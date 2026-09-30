# Plenact Database Demo — HTTPS baseline

Native SwiftUI app testing a PHP endpoint on Bluehost

## Server setup

Upload server/health.php to public_html/plenact/api-dev/health.php

The endpoint is intentionally public and returns fixed JSON. It contains no credentials and does not access the database

## App setup

- Open Database Demo.xcodeproj in Xcode

- Select your signing team and an available bundle identifier

- Select an iPhone simulator or connected iPhone, then run

- Tap Test API

## Verification

curl --include --connect-timeout 10 --max-time 20 https://plenact.com/api-dev/health.php

Expected: HTTP 200, application/json, Cache-Control: no-store,
and {"service":"plenact-dev","ok":true}

Verified in the simulator and on a physical iPhone.
With airplane mode enabled and Wi-Fi off, the app displays an error.
Restoring connectivity and retrying returns success

Database access, authentication, configuration, notices, and status
uploads are not implemented yet

