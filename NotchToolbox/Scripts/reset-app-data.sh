#!/bin/bash
# 清空 EasyNotch 的本地数据，用于从头验收（新手引导会重新触发）。
#
#   用法： Scripts/reset-app-data.sh debug     # 清工程/Debug 版数据
#          Scripts/reset-app-data.sh release   # 清正式包数据
#
# 只碰对应的 bundle id，不影响另一套、也不影响别的 app。
# 清的东西：Application Support 数据、偏好、缓存、HTTPStorages、Keychain。
# （注意：辅助功能/自动化等 TCC 授权不在这里，系统设置里单独管。）

set -euo pipefail

TARGET="${1:-}"
case "$TARGET" in
    debug)   BID="com.luojie.NotchToolbox.debug"; APPDIR="NotchToolbox-debug" ;;
    release) BID="com.luojie.NotchToolbox";       APPDIR="NotchToolbox" ;;
    *) echo "用法: Scripts/reset-app-data.sh [debug|release]"; exit 1 ;;
esac

echo "重置 $TARGET（$BID）..."

# 关掉在跑的实例（按可执行文件里的 bundle id 匹配不到进程名，用 osascript 温和退出）
osascript -e 'quit app "EasyNotch"' >/dev/null 2>&1 || true
sleep 1

rm -rf "$HOME/Library/Application Support/$APPDIR"
rm -f  "$HOME/Library/Preferences/$BID.plist"
rm -rf "$HOME/Library/Caches/$BID" "$HOME/Library/HTTPStorages/$BID"
defaults delete "$BID" >/dev/null 2>&1 || true

n=0
while security delete-generic-password -s "$BID" >/dev/null 2>&1; do
    n=$((n + 1)); [ "$n" -ge 20 ] && break
done

killall cfprefsd >/dev/null 2>&1 || true

echo "✅ 已清 $TARGET：Application Support / 偏好 / 缓存 / Keychain（$n 项）"
echo "   打开 EasyNotch（$TARGET）即从新手引导开始。"
