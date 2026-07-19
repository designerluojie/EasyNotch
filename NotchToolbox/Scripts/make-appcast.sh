#!/bin/bash
# 为已公证的 EasyNotch DMG 生成已 EdDSA 签名的 Sparkle appcast。
#
# 用法：
#   Scripts/make-appcast.sh \
#     --archive ~/Downloads/EasyNotch-1.1.dmg \
#     --download-url-prefix https://cdn.example.com/easynotch \
#     --output-dir ~/Downloads/easynotch-update \
#     --release-notes release-notes.md
#
# output-dir 是待上传目录；为保留历史更新，请保留该目录原有的
# appcast.xml 和旧 DMG，再为新版本重复运行本脚本。

set -euo pipefail

ARCHIVE=""
DOWNLOAD_URL_PREFIX=""
OUTPUT_DIR=""
RELEASE_NOTES=""

usage() {
    printf '%s\n' \
        '用法：' \
        '  Scripts/make-appcast.sh \' \
        '    --archive ~/Downloads/EasyNotch-1.1.dmg \' \
        '    --download-url-prefix https://cdn.example.com/easynotch \' \
        '    --output-dir ~/Downloads/easynotch-update \' \
        '    --release-notes release-notes.md'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive) ARCHIVE="${2:-}"; shift 2 ;;
        --download-url-prefix) DOWNLOAD_URL_PREFIX="${2:-}"; shift 2 ;;
        --output-dir) OUTPUT_DIR="${2:-}"; shift 2 ;;
        --release-notes) RELEASE_NOTES="${2:-}"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "未知参数：$1" >&2; usage >&2; exit 2 ;;
    esac
done

[[ -f "$ARCHIVE" ]] || { echo "❌ 找不到 DMG：$ARCHIVE" >&2; exit 1; }
[[ "$ARCHIVE" == *.dmg ]] || { echo "❌ 更新归档必须是 .dmg：$ARCHIVE" >&2; exit 1; }
[[ "$DOWNLOAD_URL_PREFIX" == https://* ]] || { echo "❌ 下载地址必须使用 HTTPS" >&2; exit 1; }
[[ -n "$OUTPUT_DIR" ]] || { echo "❌ 必须提供 --output-dir" >&2; exit 1; }
[[ -z "$RELEASE_NOTES" || -f "$RELEASE_NOTES" ]] || { echo "❌ 找不到更新说明：$RELEASE_NOTES" >&2; exit 1; }

if [[ -n "${SPARKLE_GENERATE_APPCAST:-}" ]]; then
    GENERATE_APPCAST="$SPARKLE_GENERATE_APPCAST"
else
    GENERATE_APPCAST="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
        -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' \
        -type f -perm -u+x -print 2>/dev/null | sort | tail -1)"
fi

[[ -x "$GENERATE_APPCAST" ]] || {
    echo "❌ 未找到 Sparkle generate_appcast。先在 Xcode 解析依赖，或设置 SPARKLE_GENERATE_APPCAST。" >&2
    exit 1
}

mkdir -p "$OUTPUT_DIR"
ARCHIVE_NAME="$(basename "$ARCHIVE")"
ditto "$ARCHIVE" "$OUTPUT_DIR/$ARCHIVE_NAME"

if [[ -n "$RELEASE_NOTES" ]]; then
    NOTES_EXTENSION="${RELEASE_NOTES##*.}"
    [[ "$NOTES_EXTENSION" != "$RELEASE_NOTES" ]] || NOTES_EXTENSION="md"
    ditto "$RELEASE_NOTES" "$OUTPUT_DIR/${ARCHIVE_NAME%.dmg}.$NOTES_EXTENSION"
fi

"$GENERATE_APPCAST" \
    --download-url-prefix "${DOWNLOAD_URL_PREFIX%/}" \
    --embed-release-notes \
    --maximum-versions 3 \
    "$OUTPUT_DIR"

xmllint --noout "$OUTPUT_DIR/appcast.xml"
echo "✅ 已生成：$OUTPUT_DIR/appcast.xml"
