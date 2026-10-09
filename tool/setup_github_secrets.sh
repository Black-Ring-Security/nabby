#!/usr/bin/env bash
# Uploads the local release signing key to the GitHub repo's Actions secrets,
# so the Release workflow can sign builds. Run once from the project root:
#   bash tool/setup_github_secrets.sh Black-Ring-Security/nabby
set -euo pipefail
REPO="${1:?usage: $0 owner/repo}"
PROPS=android/key.properties
JKS=android/app/nabby-release.jks
[ -f "$PROPS" ] && [ -f "$JKS" ] || { echo "Missing $PROPS or $JKS" >&2; exit 1; }
get() { grep "^$1=" "$PROPS" | cut -d= -f2-; }
base64 -w0 "$JKS" | gh secret set ANDROID_KEYSTORE_BASE64 --repo "$REPO"
get storePassword | gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$REPO"
get keyAlias | gh secret set ANDROID_KEY_ALIAS --repo "$REPO"
get keyPassword | gh secret set ANDROID_KEY_PASSWORD --repo "$REPO"
echo "Signing secrets saved to $REPO"
