#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_BIN="/tmp/earphone_useage_mac_preview"

echo "正在编译 earphone useage Mac 原生预览版（纯 SwiftUI）..."
swiftc \
  -parse-as-library \
  -framework SwiftUI \
  -framework Charts \
  -framework AppKit \
  -framework UniformTypeIdentifiers \
  "$SCRIPT_DIR"/EarPulse/*.swift \
  "$SCRIPT_DIR"/EarPulse/*/*.swift \
  -o "$OUT_BIN"

chmod +x "$OUT_BIN"
pkill -f "$OUT_BIN" 2>/dev/null || true

echo "启动中（393x852 iPhone 比例窗口）..."
exec "$OUT_BIN"
