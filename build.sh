#!/bin/zsh
# Builds build/Snoob.app for Apple silicon and Intel. The Swift product stays Snowhush.
# Signs ad hoc for local use; set IDENTITY to a "Developer ID Application" identity for a release build.
set -euo pipefail
cd "$(dirname "$0")"

# 双架构要走 xcbuild。只有命令行工具的 Mac 没有这份工具，改编当前架构。
if [[ -x /Library/Developer/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild ]]; then
    flags=(-c release --arch arm64 --arch x86_64)
else
    flags=(-c release --arch "$(uname -m)" --build-system native)
fi
swift build "${flags[@]}"
products="$(swift build "${flags[@]}" --show-bin-path)"

app=build/Snoob.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$products/Snowhush" "$app/Contents/MacOS/Snoob"
ditto "$products/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$app/Contents/"
cp Resources/AppIcon.icns "$app/Contents/Resources/"

if [[ -n "${IDENTITY:-}" ]]; then
    # Sparkle's helpers are signed inside out, each with the hardened runtime, as notarization requires.
    sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
    sign=(codesign --force --options runtime --timestamp --sign "$IDENTITY")
    "${sign[@]}" "$sparkle/XPCServices/Installer.xpc"
    "${sign[@]}" --preserve-metadata=entitlements "$sparkle/XPCServices/Downloader.xpc"
    "${sign[@]}" "$sparkle/Autoupdate"
    "${sign[@]}" "$sparkle/Updater.app"
    "${sign[@]}" "$app/Contents/Frameworks/Sparkle.framework"
    "${sign[@]}" "$app"
else
    codesign --force --deep --sign - "$app"
fi
codesign --verify --deep --strict "$app"
echo "Built $app"
