#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION=release
INSTALL=0
for argument in "$@"; do
    case "$argument" in
        debug|release) CONFIGURATION="$argument" ;;
        --install) INSTALL=1 ;;
        *) echo "Usage: $0 [debug|release] [--install]" >&2; exit 1 ;;
    esac
done

cd "$ROOT"
SPM_ARGUMENTS=()
if [[ "${LINKWAY_SPM_NO_SANDBOX:-0}" == 1 ]]; then
    SPM_ARGUMENTS+=(--disable-sandbox)
fi
swift build -c "$CONFIGURATION" ${SPM_ARGUMENTS[@]+"${SPM_ARGUMENTS[@]}"}
BIN_PATH="$(swift build -c "$CONFIGURATION" ${SPM_ARGUMENTS[@]+"${SPM_ARGUMENTS[@]}"} --show-bin-path)"
APP_PATH="$ROOT/build/Linkway.app"
rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/Linkway" "$APP_PATH/Contents/MacOS/Linkway"
cp "$ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
codesign --force --sign - "$APP_PATH"

if [[ "$INSTALL" == 1 ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Linkway.app"
    ditto "$APP_PATH" "$HOME/Applications/Linkway.app"
    APP_PATH="$HOME/Applications/Linkway.app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH"
fi
echo "$APP_PATH"
