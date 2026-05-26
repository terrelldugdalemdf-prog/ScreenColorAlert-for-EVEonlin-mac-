#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="ScreenColorAlert"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "=== 编译 ScreenColorAlert ==="
swift build -c release --disable-sandbox

echo "=== 打包 .app ==="
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 复制可执行文件
cp "$BUILD_DIR/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"
cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true

# 生成 Info.plist
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

echo "=== 构建完成 ==="
echo "App: $APP_BUNDLE"
echo "运行: open $APP_BUNDLE"
