#!/usr/bin/env bash
#
# Packages an unsigned .xcarchive into an installable .ipa.
# Sideloadly / AltStore sign the IPA with your own Apple ID afterwards.
#
#   ./scripts/package-ipa.sh build/ChessEnginePro.xcarchive build/ChessEnginePro.ipa
#
set -euo pipefail

ARCHIVE="${1:-artifacts/ChessEnginePro.xcarchive}"
OUT="${2:-artifacts/ChessEnginePro.ipa}"

APP="$ARCHIVE/Products/Applications/ChessEnginePro.app"

if [[ ! -d "$APP" ]]; then
    echo "!! App nicht im Archiv gefunden: $APP" >&2
    ls -R "$ARCHIVE/Products" 2>/dev/null || true
    exit 1
fi

mkdir -p "$(dirname "$OUT")"
OUT_DIR="$(cd "$(dirname "$OUT")" && pwd)"
OUT_ABS="$OUT_DIR/$(basename "$OUT")"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"

rm -f "$OUT_ABS"
( cd "$STAGE" && /usr/bin/zip -qry "$OUT_ABS" Payload )

if [[ ! -s "$OUT_ABS" ]]; then
    echo "!! IPA konnte nicht erstellt werden" >&2
    exit 1
fi

SIZE="$(du -h "$OUT_ABS" | cut -f1)"
echo "IPA erstellt: $OUT_ABS ($SIZE)"
