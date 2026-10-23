#!/bin/bash
# Submit a zip/dmg for notarization, wait, and print Apple's log if it is not accepted.
# Needs APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD, APPLE_TEAM_ID.
set -euo pipefail

FILE="$1"
RESULT=$(xcrun notarytool submit "$FILE" \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_SPECIFIC_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" \
  --wait --timeout 30m --output-format json)
echo "$RESULT"

STATUS=$(echo "$RESULT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')
if [ "$STATUS" != "Accepted" ]; then
  ID=$(echo "$RESULT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')
  [ -n "$ID" ] && xcrun notarytool log "$ID" --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID" || true
  echo "::error::Notarization of $(basename "$FILE") finished with status: $STATUS"
  exit 1
fi
