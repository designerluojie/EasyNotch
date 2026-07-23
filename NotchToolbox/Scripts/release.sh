#!/bin/bash
# 一键发版：archive → 公证 app → 打 DMG → 公证 DMG → staple，全自动。
#
#   用法： Scripts/release.sh [版本号] [--build-number N] [--appcast-feed-url URL] [--appcast-output-dir DIR --appcast-download-url-prefix URL] [--release-notes FILE]
#     Scripts/release.sh 1.1 --build-number 12     # 产出 ~/Downloads/EasyNotch-1.1.dmg
#     Scripts/release.sh         # 用工程当前 MARKETING_VERSION 命名
#
#   可选 appcast 参数会把已公证 DMG 复制到官网仓库的 public/updates
#   并生成 appcast.xml；脚本不会替你提交或推送官网仓库。
#
#   一次性前置（都已配好，换机器才需重做）：
#     · 钥匙串里有 Developer ID Application 证书
#     · 公证凭据：
#         xcrun notarytool store-credentials "EasyNotchNotary" \
#           --apple-id 494620815@qq.com --team-id 7KRN87P2S6 --password <App专用密码>
#     · brew install create-dmg librsvg
#
#   首次运行时 codesign 会弹一次钥匙串授权，点「始终允许」后不再弹。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/NotchToolbox.xcodeproj"
SCHEME="NotchToolbox"
NOTARY_PROFILE="EasyNotchNotary"
BUILD="$ROOT/build"                       # 一次性构建产物，.gitignore 已忽略

VERSION=""
BUILD_NUMBER=""
APPCAST_FEED_URL=""
APPCAST_OUTPUT_DIR=""
APPCAST_DOWNLOAD_URL_PREFIX=""
RELEASE_NOTES=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-number) BUILD_NUMBER="${2:-}"; shift 2 ;;
        --appcast-feed-url) APPCAST_FEED_URL="${2:-}"; shift 2 ;;
        --appcast-output-dir) APPCAST_OUTPUT_DIR="${2:-}"; shift 2 ;;
        --appcast-download-url-prefix) APPCAST_DOWNLOAD_URL_PREFIX="${2:-}"; shift 2 ;;
        --release-notes) RELEASE_NOTES="${2:-}"; shift 2 ;;
        -h|--help)
            sed -n '1,18p' "$0"
            exit 0
            ;;
        -*) echo "❌ 未知参数：$1" >&2; exit 2 ;;
        *)
            [[ -z "$VERSION" ]] || { echo "❌ 只能提供一个版本号" >&2; exit 2; }
            VERSION="$1"
            shift
            ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    VERSION="$(xcodebuild -showBuildSettings -project "$PROJECT" -scheme "$SCHEME" -configuration Release 2>/dev/null \
        | awk -F ' = ' '$1 ~ /MARKETING_VERSION$/ { print $2; exit }')"
fi

[[ -n "$VERSION" ]] || { echo "❌ 无法读取 Release MARKETING_VERSION" >&2; exit 1; }
if [[ -z "$BUILD_NUMBER" ]]; then
    BUILD_NUMBER="$(xcodebuild -showBuildSettings -project "$PROJECT" -scheme "$SCHEME" -configuration Release 2>/dev/null \
        | awk -F ' = ' '$1 ~ /CURRENT_PROJECT_VERSION$/ { print $2; exit }')"
fi
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || { echo "❌ 构建号必须是正整数" >&2; exit 2; }
if [[ -n "$APPCAST_FEED_URL" ]]; then
    [[ "$APPCAST_FEED_URL" == https://* ]] || { echo "❌ 更新源必须使用 HTTPS" >&2; exit 2; }
fi
if [[ -n "$APPCAST_OUTPUT_DIR" || -n "$APPCAST_DOWNLOAD_URL_PREFIX" ]]; then
    [[ -n "$APPCAST_OUTPUT_DIR" && -n "$APPCAST_DOWNLOAD_URL_PREFIX" ]] || {
        echo "❌ appcast 参数必须同时提供 --appcast-output-dir 和 --appcast-download-url-prefix" >&2
        exit 2
    }
fi
if [[ -n "$RELEASE_NOTES" ]]; then
    [[ -n "$APPCAST_OUTPUT_DIR" ]] || { echo "❌ --release-notes 需要同时提供 appcast 输出参数" >&2; exit 2; }
    [[ -f "$RELEASE_NOTES" ]] || { echo "❌ 找不到更新说明：$RELEASE_NOTES" >&2; exit 1; }
fi
DMG="$HOME/Downloads/EasyNotch-$VERSION.dmg"

BUILD_SETTINGS=("MARKETING_VERSION=$VERSION" "CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
if [[ -n "$APPCAST_FEED_URL" ]]; then
    BUILD_SETTINGS+=("EASYNOTCH_APPCAST_FEED_URL=$APPCAST_FEED_URL")
fi

# 提交公证并确认 Accepted（notarytool 完成即返回，需自行校验状态）。
notarize() {
    local file="$1" out
    echo "→ 公证提交：$(basename "$file")（上传 + 等苹果扫描，几分钟）"
    out="$(xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait 2>&1)"
    echo "$out" | grep -E "id:|status:" | tail -4
    echo "$out" | grep -q "status: Accepted" || {
        echo "❌ 公证未通过。查日志：xcrun notarytool log <id> --keychain-profile \"$NOTARY_PROFILE\""
        return 1
    }
}

echo "==== EasyNotch $VERSION 发版 ===="
rm -rf "$BUILD"; mkdir -p "$BUILD"

echo "[1/5] Archive（Release）"
xcodebuild archive -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$BUILD/EasyNotch.xcarchive" \
    -allowProvisioningUpdates -quiet "${BUILD_SETTINGS[@]}"

echo "[2/5] 导出（Developer ID 签名）"
xcodebuild -exportArchive -archivePath "$BUILD/EasyNotch.xcarchive" \
    -exportOptionsPlist "$ROOT/exportOptions.plist" \
    -exportPath "$BUILD/export" \
    -allowProvisioningUpdates -quiet
APP="$BUILD/export/EasyNotch.app"
[ -d "$APP" ] || { echo "❌ 没导出 EasyNotch.app"; exit 1; }

echo "[3/5] 公证 app + staple"
ditto -c -k --keepParent "$APP" "$BUILD/EasyNotch.zip"
notarize "$BUILD/EasyNotch.zip"
xcrun stapler staple "$APP"

echo "[4/5] 打签名 DMG"
"$ROOT/Scripts/make-dmg.sh" "$APP" "$DMG"

echo "[5/5] 公证 DMG + staple"
notarize "$DMG"
xcrun stapler staple "$DMG"

echo
echo "==== 完成 ===="
echo "产物：$DMG"
xcrun stapler validate "$DMG" 2>&1 | tail -1
spctl -a -vvv -t open --context context:primary-signature "$DMG" 2>&1 | grep -E "accepted|source=" | head -2
shasum -a 256 "$DMG"

if [[ -n "$APPCAST_OUTPUT_DIR" ]]; then
    APPCAST_ARGS=(
        --archive "$DMG" \
        --download-url-prefix "$APPCAST_DOWNLOAD_URL_PREFIX" \
        --output-dir "$APPCAST_OUTPUT_DIR"
    )
    if [[ -n "$RELEASE_NOTES" ]]; then
        APPCAST_ARGS+=(--release-notes "$RELEASE_NOTES")
    fi
    "$ROOT/Scripts/make-appcast.sh" "${APPCAST_ARGS[@]}"
    echo "→ appcast 已生成；请在官网仓库复核并手动提交、推送。"
fi
