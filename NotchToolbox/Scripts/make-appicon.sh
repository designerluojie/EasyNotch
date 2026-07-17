#!/bin/bash
# 从 Logo.svg 生成整套 macOS 应用图标。
#
#   用法： Scripts/make-appicon.sh [path/to/Logo.svg]
#   依赖： rsvg-convert  (brew install librsvg)
#
# 两个关键点：
#
# 1. 留白：macOS 图标不铺满画布——图形占 824/1024 (80.5%) 居中，四周留白。
#    铺满的图标在程序坞里会比原生图标大一圈。
#
# 2. 留白靠扩 viewBox 实现，不能用 <g transform="scale()"> 包一层：
#    Logo 里的渐变是 gradientUnits="userSpaceOnUse"（坐标写死 y=0→256），
#    transform 不会带着渐变坐标走，图形会落到渐变终点之外被钳成纯黑。
#    扩 viewBox 则保持图形内部坐标不变，渐变照常对齐。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="${1:-$ROOT/Logo.svg}"
SET="$ROOT/NotchToolbox/Assets.xcassets/AppIcon.appiconset"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

command -v rsvg-convert >/dev/null || { echo "缺少 rsvg-convert：brew install librsvg"; exit 1; }
[ -f "$SVG" ] || { echo "找不到 SVG：$SVG"; exit 1; }

# 图形 256 单位 → 占 80.5%；画布 = 256/0.805 = 318.14；每边留白 = (318.14-256)/2 = 31.07
sed '1s|<svg width="256" height="256" viewBox="0 0 256 256"|<svg width="1024" height="1024" viewBox="-31.07 -31.07 318.14 318.14"|' \
  "$SVG" > "$TMP/padded.svg"

grep -q 'viewBox="-31.07' "$TMP/padded.svg" || { echo "viewBox 替换失败——SVG 根节点格式是否变了？"; exit 1; }

# 每个尺寸都从矢量直接渲染（比缩放锐利）
for px in 16 32 64 128 256 512 1024; do
  rsvg-convert -w $px -h $px "$TMP/padded.svg" -o "$TMP/$px.png"
done

cp "$TMP/16.png"   "$SET/icon_16x16.png"
cp "$TMP/32.png"   "$SET/icon_16x16@2x.png"
cp "$TMP/32.png"   "$SET/icon_32x32.png"
cp "$TMP/64.png"   "$SET/icon_32x32@2x.png"
cp "$TMP/128.png"  "$SET/icon_128x128.png"
cp "$TMP/256.png"  "$SET/icon_128x128@2x.png"
cp "$TMP/256.png"  "$SET/icon_256x256.png"
cp "$TMP/512.png"  "$SET/icon_256x256@2x.png"
cp "$TMP/512.png"  "$SET/icon_512x512.png"
cp "$TMP/1024.png" "$SET/icon_512x512@2x.png"

echo "已从 $(basename "$SVG") 生成 10 个尺寸 → $SET"
echo "记得重新 Archive + 公证：改图标会让旧签名和公证票据失效。"
