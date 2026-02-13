#!/bin/bash
set -e

APP_NAME="ClipMaster"
BUNDLE_ID="com.clipmaster.app"
SOURCE_APP=".build/release/${APP_NAME}.app"
TARGET_DIR="/Volumes/External/Applications"
TARGET_APP="${TARGET_DIR}/${APP_NAME}.app"

if [ ! -d "${SOURCE_APP}" ]; then
    echo "未找到 ${SOURCE_APP}，请先执行: bash build.sh"
    exit 1
fi

echo "=== 重置辅助功能权限（Accessibility）==="
tccutil reset Accessibility "${BUNDLE_ID}" || true

echo "=== 重置录屏权限（ScreenCapture）==="
tccutil reset ScreenCapture "${BUNDLE_ID}" || true

echo "=== 关闭旧进程 ==="
pkill -f "${APP_NAME}" 2>/dev/null || true
sleep 1

echo "=== 部署新版本 ==="
rm -rf "${TARGET_APP}"
cp -R "${SOURCE_APP}" "${TARGET_DIR}/"

echo "=== 启动应用 ==="
open "${TARGET_APP}"

echo "=== 部署完成 ==="
echo "已部署到: ${TARGET_APP}"
echo "请在 系统设置 → 隐私与安全性 → 辅助功能 中重新授权 ${APP_NAME}.app"
