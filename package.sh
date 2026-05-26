#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="ScreenColorAlert"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME"
DMG_FILE="$BUILD_DIR/$DMG_NAME.dmg"
DMG_TMP="$BUILD_DIR/dmg_temp"
VOLUME_NAME="屏幕颜色监测"

# 清理残余挂载
for v in /Volumes/"$VOLUME_NAME"*; do
    hdiutil detach "$v" -force 2>/dev/null || true
done
sleep 1

echo "=== 1. 编译 Release 版本 ==="
swift build -c release --disable-sandbox

echo "=== 2. 打包 .app ==="
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

# 使用 NSWorkspace 直接将图标写入 bundle 的 Finder 元数据
# 绕过 CFBundleIconFile 机制，这是最可靠的图标设置方式
swift -e '
import AppKit
let iconPath = "'"$APP_BUNDLE"'/Contents/Resources/AppIcon.icns"
let appPath = "'"$APP_BUNDLE"'"
guard let icon = NSImage(contentsOfFile: iconPath) else {
    fatalError("无法加载图标文件: \(iconPath)")
}
let ok = NSWorkspace.shared.setIcon(icon, forFile: appPath, options: [])
if !ok { fatalError("图标写入失败") }
print("图标已嵌入 app bundle")
' || { echo "图标设置失败"; exit 1; }

touch "$APP_BUNDLE"

cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ScreenColorAlert</string>
    <key>CFBundleDisplayName</key>
    <string>屏幕颜色监测</string>
    <key>CFBundleIdentifier</key>
    <string>com.screen-color-alert.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>ScreenColorAlert</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>屏幕颜色监测需要截取屏幕内容来识别指定区域的颜色。</string>
</dict>
</plist>
PLIST

echo "=== 3. 创建 DMG ==="
rm -rf "$DMG_TMP" "$DMG_FILE"

mkdir -p "$DMG_TMP"
cp -R "$APP_BUNDLE" "$DMG_TMP/"
ln -s /Applications "$DMG_TMP/Applications"

# 创建临时可读写 dmg 用于布局
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_TMP" \
  -ov \
  -format UDRW \
  -size 100m \
  "$BUILD_DIR/tmp.dmg"

# 挂载
hdiutil attach -readwrite -noverify -noautoopen "$BUILD_DIR/tmp.dmg" > /dev/null
MOUNT_POINT="/Volumes/$VOLUME_NAME"

echo "已挂载: $MOUNT_POINT"

# 用 AppleScript 设置窗口布局
osascript << 'APPLESCRIPT'
tell application "Finder"
    set volumeName to "屏幕颜色监测"
    set mountPoint to POSIX file ("/Volumes/" & volumeName) as alias

    tell disk volumeName
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {400, 200, 900, 500}

        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 72
        set text size of theViewOptions to 12

        -- 图标位置: App 在左，Applications 在右
        set position of item "ScreenColorAlert.app" to {120, 120}
        set position of item "Applications" to {380, 120}

        close
        open
        update without registering applications
    end tell
end tell
APPLESCRIPT

# 等待 Finder 完成
sleep 2

# 卸载
hdiutil detach "$MOUNT_POINT" -force
sleep 2

# 转换为压缩只读 dmg
echo "=== 4. 压缩 DMG ==="
hdiutil convert "$BUILD_DIR/tmp.dmg" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$DMG_FILE" || {
    sleep 3
    hdiutil convert "$BUILD_DIR/tmp.dmg" \
      -format UDZO \
      -imagekey zlib-level=9 \
      -o "$DMG_FILE"
}

# 清理
rm -f "$BUILD_DIR/tmp.dmg"
rm -rf "$DMG_TMP"

# 复制到历史版本文件夹
HISTORY_DIR="$PROJECT_DIR/../ScreenColorAlert_历史版本"
mkdir -p "$HISTORY_DIR"

# 自动递增版本号
NEXT_VERSION=1
for f in "$HISTORY_DIR"/"$APP_NAME"_v*.dmg; do
    [ -f "$f" ] || continue
    v=$(echo "$f" | sed 's/.*_v\([0-9]*\)\.dmg/\1/')
    if [ "$v" -ge "$NEXT_VERSION" ]; then
        NEXT_VERSION=$((v + 1))
    fi
done

HISTORY_FILE="$HISTORY_DIR/${APP_NAME}_v${NEXT_VERSION}.dmg"
cp "$DMG_FILE" "$HISTORY_FILE"

echo ""
echo "========================================="
echo "  打包完成！"
echo "  DMG: $DMG_FILE"
echo "  大小: $(du -h "$DMG_FILE" | awk '{print $1}')"
echo "  历史版本: $HISTORY_FILE (v${NEXT_VERSION})"
echo "========================================="
