#!/bin/bash
# 把已导出（已公证）的 EasyNotch.app 打成带样式、已签名的分发 DMG。
#
#   用法： Scripts/make-dmg.sh <path/to/EasyNotch.app> [输出.dmg]
#   例子： Scripts/make-dmg.sh ~/Downloads/EasyNotch.app ~/Downloads/EasyNotch-1.1.dmg
#
#   依赖： create-dmg   (brew install create-dmg)
#          librsvg      (仅在 --regen-bg 重生成背景图时需要)
#
# 布局固定：窗口 600x400，图标 128，白底+文案+箭头，
# EasyNotch(150,228) → Applications(450,228)。背景图见 Scripts/dmg-assets/。
#
# 这一步只做「打包 + 签名」。它不做公证——DMG 公证是可选的单独一步，
# 见脚本末尾说明。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS="$ROOT/Scripts/dmg-assets"
IDENTITY="Developer ID Application: Dingjie Luo (7KRN87P2S6)"

APP="${1:-}"
OUT="${2:-$HOME/Downloads/EasyNotch.dmg}"

[ -n "$APP" ] || { echo "用法: Scripts/make-dmg.sh <EasyNotch.app> [输出.dmg]"; exit 1; }
[ -d "$APP" ] || { echo "找不到 app：$APP"; exit 1; }
command -v create-dmg >/dev/null || { echo "缺少 create-dmg：brew install create-dmg"; exit 1; }

# 可选：--regen-bg 从 SVG 重新生成背景图（改了文案/箭头后用）
if [ "${3:-}" = "--regen-bg" ] || [ "${1:-}" = "--regen-bg" ]; then
  command -v rsvg-convert >/dev/null || { echo "缺少 rsvg-convert：brew install librsvg"; exit 1; }
  rsvg-convert -w 600  -h 400 "$ASSETS/background.svg" -o "$ASSETS/bg_1x.png"
  rsvg-convert -w 1200 -h 800 "$ASSETS/background.svg" -o "$ASSETS/bg_2x.png"
  tiffutil -cathidpicheck "$ASSETS/bg_1x.png" "$ASSETS/bg_2x.png" -out "$ASSETS/background.tiff" >/dev/null
  rm -f "$ASSETS/bg_1x.png" "$ASSETS/bg_2x.png"
  echo "背景图已从 SVG 重新生成。"
  [ "${1:-}" = "--regen-bg" ] && exit 0
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/EasyNotch.app"

hdiutil detach /Volumes/EasyNotch >/dev/null 2>&1 || true
rm -f "$OUT"

create-dmg \
  --volname "EasyNotch" \
  --background "$ASSETS/background.tiff" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "EasyNotch.app" 150 228 \
  --app-drop-link 450 228 \
  --no-internet-enable \
  "$OUT" "$STAGE"

# 用 Developer ID 签名 DMG（会弹一次钥匙串授权，点「始终允许」）
codesign --force --sign "$IDENTITY" --timestamp "$OUT"

echo
echo "✅ DMG 已生成并签名：$OUT"
echo
echo "验证："
codesign --verify --verbose=1 "$OUT" 2>&1 | tail -1
echo
echo "对外正式发布前，建议给 DMG 也做公证（可选）："
echo "  xcrun notarytool submit \"$OUT\" --keychain-profile \"EasyNotchNotary\" --wait"
echo "  xcrun stapler staple \"$OUT\""
echo "（首次用 notarytool 需先存凭据：xcrun notarytool store-credentials \"EasyNotchNotary\" \\"
echo "   --apple-id <你的AppleID> --team-id 7KRN87P2S6 --password <App专用密码>）"
