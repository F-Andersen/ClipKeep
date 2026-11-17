#!/bin/bash
# Збірка NotchClip.app
#   ./build.sh          — зібрати в build/NotchClip.app
#   ./build.sh install  — зібрати і встановити в /Applications, потім запустити
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="NotchClip"
APP="build/$APP_NAME.app"
ARCH="$(uname -m)"

# Іконка (генерується один раз)
if [ ! -f Resources/AppIcon.icns ]; then
    echo "→ Генерую іконку"
    mkdir -p Resources build/icon.iconset
    swift Tools/make-icon.swift build/icon-1024.png
    for s in 16 32 128 256 512; do
        sips -z $s $s build/icon-1024.png --out "build/icon.iconset/icon_${s}x${s}.png" >/dev/null
        d=$((s * 2))
        sips -z $d $d build/icon-1024.png --out "build/icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns build/icon.iconset -o Resources/AppIcon.icns
fi

echo "→ Компілюю ($ARCH)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 \
    -target "$ARCH-apple-macos14.0" \
    -framework AppKit -framework SwiftUI -framework Carbon -framework ServiceManagement \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/$APP_NAME"

cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Підпис. Сертифікат Apple Development (якщо є) дає стабільний підпис,
# тож дозвіл «Універсальний доступ» не скидається після кожного перезбирання.
# Інший сертифікат: SIGN_ID="<хеш або назва>" ./build.sh
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/ {print $1; exit}' | awk '{print $2}')}"
if [ -n "$SIGN_ID" ]; then
    codesign --force --sign "$SIGN_ID" "$APP"
    echo "✓ Підписано сертифікатом розробника"
else
    codesign --force --sign - "$APP" >/dev/null
    echo "! Підписано ad-hoc: дозвіл «Універсальний доступ» скидатиметься після перезбирання"
fi
echo "✓ Готово: $APP"

if [ "${1:-}" = "install" ]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    # прибрати версію зі старою назвою (ClipKeep), якщо лишилась
    pkill -x ClipKeep 2>/dev/null || true
    rm -rf /Applications/ClipKeep.app build/ClipKeep.app
    sleep 0.5
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/"
    open "/Applications/$APP_NAME.app"
    echo "✓ Встановлено в /Applications і запущено"
fi
