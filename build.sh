#!/bin/zsh
# Builds build/Snoob.app for Apple silicon and Intel. The Swift product stays Snowhush.
# Signs ad hoc for local use; set IDENTITY to a "Developer ID Application" identity for a release build.
set -euo pipefail
cd "$(dirname "$0")"

# 双架构要走 xcbuild。只有命令行工具的 Mac 没有这份工具：平时只编当前架构；
# UNIVERSAL=1（release.sh 会设）时两种架构分开编，再用 lipo 合成一个。
lipo_from=()
if [[ -x /Library/Developer/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild ]]; then
    flags=(-c release --arch arm64 --arch x86_64)
elif [[ -n "${UNIVERSAL:-}" ]]; then
    for arch in arm64 x86_64; do
        archflags=(-c release --triple "$arch-apple-macosx14.0" --build-system native --scratch-path ".build/$arch")
        swift build "${archflags[@]}"
        lipo_from+=("$(swift build "${archflags[@]}" --show-bin-path)/Snowhush")
    done
    flags=(-c release --triple "arm64-apple-macosx14.0" --build-system native --scratch-path .build/arm64)
else
    flags=(-c release --arch "$(uname -m)" --build-system native)
fi
swift build "${flags[@]}"
products="$(swift build "${flags[@]}" --show-bin-path)"

app=build/Snoob.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
if (( ${#lipo_from} )); then
    lipo -create "${lipo_from[@]}" -output "$app/Contents/MacOS/Snoob"
else
    cp "$products/Snowhush" "$app/Contents/MacOS/Snoob"
fi
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
