#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 /path/to/EasyNotchAppStore.app" >&2
    exit 64
fi

app_path=$1
info_path="$app_path/Contents/Info.plist"

if [ ! -d "$app_path" ] || [ ! -f "$info_path" ]; then
    echo "invalid app bundle: $app_path" >&2
    exit 65
fi

executable_name=$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$info_path")
executable_path="$app_path/Contents/MacOS/$executable_name"

if [ ! -x "$executable_path" ]; then
    echo "missing executable: $executable_path" >&2
    exit 66
fi

for forbidden_name in \
    Sparkle.framework \
    nowplaying-cli.bundle \
    MediaRemoteMini.dylib
do
    if /usr/bin/find "$app_path" -name "$forbidden_name" -print | /usr/bin/grep -q .; then
        echo "forbidden bundled component: $forbidden_name" >&2
        exit 67
    fi
done

for forbidden_key in SUFeedURL SUPublicEDKey SUEnableAutomaticChecks
do
    if /usr/bin/plutil -extract "$forbidden_key" raw -o - "$info_path" >/dev/null 2>&1; then
        echo "forbidden Info.plist key: $forbidden_key" >&2
        exit 68
    fi
done

for forbidden_pattern in \
    MediaRemote \
    nowplaying-cli \
    MediaRemoteMini \
    Sparkle \
    /usr/bin/osascript \
    com.tencent.QQMusicMac \
    com.netease.163music \
    com.kugou.mac.Music \
    com.soda.music
do
    if /usr/bin/strings "$executable_path" | /usr/bin/grep -F -q "$forbidden_pattern"; then
        echo "forbidden executable reference: $forbidden_pattern" >&2
        exit 69
    fi
done

if /usr/bin/strings "$app_path/Contents/Resources/Assets.car" \
    | /usr/bin/grep -E -q 'MusicPlayer(QQ|Netease|Kugou|Soda)'; then
    echo "domestic-player artwork is present in the App Store asset catalog" >&2
    exit 70
fi

sandbox_enabled=$(
    /usr/bin/codesign -d --entitlements :- "$app_path" 2>/dev/null \
        | /usr/bin/plutil -extract 'com\.apple\.security\.app-sandbox' raw -o - -
)
if [ "$sandbox_enabled" != "true" ]; then
    echo "App Sandbox entitlement is missing" >&2
    exit 71
fi

echo "App Store bundle validation passed: $app_path"
