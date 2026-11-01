#!/bin/zsh
# 打包 Snoob-<版本>.dmg，发到 GitHub Release。只能在 Mac 上跑。
#
# 用法：./release.sh <版本> ["这一版改了什么"]      例：./release.sh 1.0.0 "第一个公开版本"
#       ./release.sh <版本> --dry-run                只在 dist/ 里出 dmg，不改版本号、不发布，先自己装一遍看看
#
# 签名：钥匙串里有「Developer ID Application」证书，并且存过 notarytool 配置
# （xcrun notarytool store-credentials snoob --apple-id <apple-id> --team-id <team-id>，名字可用 NOTARY_PROFILE 改），
# 就签名加公证，用户双击直接能开；没有就出未签名的 dmg，用户第一次打开要放行一次（docs/INSTALL.md）。
# 发布要 gh 已登录，并且有 MengTang1114-open/m-snoob 的写权限。
set -euo pipefail
cd "$(dirname "$0")"

version=${1:?用法：./release.sh <版本> ["这一版改了什么"] [--dry-run]}
shift
dry=""
notes="雪噗噗 Snoob $version"
for arg in "$@"; do
    if [[ "$arg" == --dry-run ]]; then dry=1; else notes=$arg; fi
done
repository=MengTang1114-open/m-snoob
profile=${NOTARY_PROFILE:-snoob}
dmgbuild_version=1.6.7
dmgbuild=.build/dmgbuild/bin/dmgbuild
plist=Resources/Info.plist
app=build/Snoob.app
dist=dist
dmg=$dist/Snoob-$version.dmg

[[ "$(uname)" == Darwin ]] || { echo "只能在 Mac 上打包。" >&2; exit 1; }
if [[ -z "$dry" ]]; then
    [[ -z "$(git status --porcelain)" ]] || { echo "先提交或收起改动。" >&2; exit 1; }
    gh auth status >/dev/null 2>&1 || { echo "gh 没登录：gh auth login" >&2; exit 1; }
    ! gh release view "v$version" --repo "$repository" >/dev/null 2>&1 || { echo "v$version 已经发过了，换个版本号。" >&2; exit 1; }
fi

# 有证书才签名；证书在、公证配置不在，就停下来，免得发出一个签了名却没公证、照样被拦的包。
export IDENTITY=${IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')}
if [[ -n "$IDENTITY" ]]; then
    xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1 \
        || { echo "有证书但没有 notarytool 配置「$profile」：xcrun notarytool store-credentials $profile" >&2; exit 1; }
    echo "签名用：$IDENTITY"
else
    echo "没有 Developer ID 证书，出未签名的包（用户第一次打开要放行一次）。"
fi

if [[ ! -x "$dmgbuild" ]]; then
    python3 -m venv .build/dmgbuild
    .build/dmgbuild/bin/pip install -q "dmgbuild==$dmgbuild_version"
fi

# 版本号：每次发布 CFBundleVersion 加一。试打不改。
if [[ -z "$dry" ]]; then
    current=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
    if [[ "$current" != "$version" ]]; then
        build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
        /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" -c "Set :CFBundleVersion $((build + 1))" "$plist"
        git commit -qm "发布 v$version" "$plist"
    fi
fi

echo "编译（Apple 芯片 + Intel）…"
UNIVERSAL=1 ./build.sh
echo "架构：$(lipo -archs "$app/Contents/MacOS/Snoob")"

rm -rf "$dist"
mkdir -p "$dist"

notarize() {
    xcrun notarytool submit "$1" --keychain-profile "$profile" --wait
}

if [[ -n "$IDENTITY" ]]; then
    echo "公证 App…"
    ditto -c -k --keepParent "$app" "$dist/Snoob.zip"
    notarize "$dist/Snoob.zip"
    xcrun stapler staple "$app"
    rm "$dist/Snoob.zip"
fi

echo "打 dmg…"
artwork=$(mktemp -d)
swift scripts/make-dmg-background.swift "$artwork/background.png" 1 >/dev/null
swift scripts/make-dmg-background.swift "$artwork/background@2x.png" 2 >/dev/null
tiffutil -cathidpicheck "$artwork/background.png" "$artwork/background@2x.png" -out "$artwork/background.tiff" 2>/dev/null
"$dmgbuild" -s scripts/dmg-settings.py -D app="$app" -D background="$artwork/background.tiff" Snoob "$dmg" 2>/dev/null
rm -rf "$artwork"
if [[ -n "$IDENTITY" ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$dmg"
    notarize "$dmg"
    xcrun stapler staple "$dmg"
fi
(cd "$dist" && shasum -a 256 "$(basename "$dmg")" > "$(basename "$dmg").sha256")
echo "→ $dmg"

if [[ -n "$dry" ]]; then
    echo "试打完成，没有发布。双击 $dmg 装一遍看看。"
    exit 0
fi

if [[ -n "$IDENTITY" ]]; then
    install="下载 \`Snoob-$version.dmg\`，打开后把雪噗噗拖进「应用程序」，双击打开。"
else
    install="下载 \`Snoob-$version.dmg\`，打开后把雪噗噗拖进「应用程序」。这个版本还没有 Apple 开发者签名，第一次打开会被 macOS 拦一下，按 [安装说明](https://github.com/$repository/blob/main/docs/INSTALL.md) 放行一次就好。"
fi
body=$(mktemp)
cat > "$body" <<EOF
$notes

## 安装

$install

要求：macOS 14 或更新，Apple 芯片和 Intel 都可以。打开后它住在菜单栏（雪花图标），程序坞里没有它。
EOF

echo "发布 v$version…"
git push -q origin HEAD
gh release create "v$version" "$dmg" "$dmg.sha256" \
    --repo "$repository" --target "$(git rev-parse HEAD)" --title "雪噗噗 Snoob $version" --notes-file "$body"
rm "$body"
echo "已发布 https://github.com/$repository/releases/tag/v$version"
