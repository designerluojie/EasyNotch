#!/bin/bash
# 一键发版：archive → 公证 app → 打 DMG → 公证 DMG → staple，全自动。
#
#   用法： Scripts/release.sh [版本号]
#     Scripts/release.sh 1.1     # 产出 ~/Downloads/EasyNotch-1.1.dmg
#     Scripts/release.sh         # 用工程当前 MARKETING_VERSION 命名
#
#   （版本号只用于 DMG 文件名。要改 app 里显示的版本，先在 Xcode 改
#    MARKETING_VERSION / CURRENT_PROJECT_VERSION。）
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

VERSION="${1:-$(grep -m1 'MARKETING_VERSION' "$PROJECT/project.pbxproj" | sed 's/[^0-9.]//g')}"
DMG="$HOME/Downloads/EasyNotch-$VERSION.dmg"

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
    -allowProvisioningUpdates -quiet

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
