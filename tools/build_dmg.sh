#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/console-typist.XXXXXXXX")"
trap 'rm -r "$work"' EXIT
cd "$root"
app="$work/image/CMDPutin.app"
resources="$app/Contents/Resources"
iconset="$work/CMDPutin.iconset"
mkdir -p "$iconset" "$resources" "$app/Contents/MacOS" "$root/dist"
xcrun swiftc -O -target "$(uname -m)-apple-macos13.0" macOS/main.swift macOS/ConsoleKeyboard.swift -o "$app/Contents/MacOS/CMDPutin"
cp macOS/Info.plist "$app/Contents/Info.plist"
for icon in logo pin refresh send; do
    sips -s format png -z 96 96 "assets/$icon.svg" --out "$resources/$icon.png" >/dev/null
done
for points in 16 32 128 256 512; do
    for scale in 1 2; do
        side=$((points * scale))
        suffix=''; if [[ $scale == 2 ]]; then suffix='@2x'; fi
        sips -s format png -z "$side" "$side" assets/logo.svg --out "$iconset/icon_${points}x${points}${suffix}.png" >/dev/null
    done
done
iconutil -c icns "$iconset" -o "$resources/CMDPutin.icns"
codesign --force --sign "${CODE_SIGN_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
ln -s /Applications "$work/image/Applications"
hdiutil create -volname 'CMDPutin' -srcfolder "$work/image" -format UDZO "$work/CMDPutin-macOS.dmg"
hdiutil verify "$work/CMDPutin-macOS.dmg"
mv "$work/CMDPutin-macOS.dmg" "$root/dist/"
