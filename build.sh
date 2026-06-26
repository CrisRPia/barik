#!/usr/bin/env bash
# Build Barik.app with SwiftPM + Command Line Tools only (no full Xcode).
#
# Produces ./Barik.app, ad-hoc code-signed with the entitlements declared in
# Barik/Barik.entitlements. Pass --install to also copy it to /Applications.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="release"
APP="Barik.app"
BIN_NAME="Barik"
INSTALL=0

for arg in "$@"; do
	case "$arg" in
		--debug) CONFIG="debug" ;;
		--install) INSTALL=1 ;;
		*) echo "unknown arg: $arg" >&2; exit 2 ;;
	esac
done

echo ">> swift build ($CONFIG)"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$BIN_NAME"
[ -x "$BIN_PATH" ] || { echo "binary not found: $BIN_PATH" >&2; exit 1; }

echo ">> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$BIN_NAME"
cp Packaging/Info.plist "$APP/Contents/Info.plist"

# Bundle any SwiftPM-generated resource bundles (e.g. MarkdownUI assets).
BIN_DIR="$(dirname "$BIN_PATH")"
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
	cp -R "$bundle" "$APP/Contents/Resources/"
done
shopt -u nullglob

echo ">> ad-hoc codesign"
codesign --force --sign - \
	--entitlements Barik/Barik.entitlements \
	--options runtime \
	"$APP"

echo ">> built $APP"

if [ "$INSTALL" -eq 1 ]; then
	echo ">> installing to /Applications"
	rm -rf "/Applications/$APP"
	cp -R "$APP" /Applications/
	echo ">> installed /Applications/$APP"
fi
