#!/bin/bash
set -e

APP_NAME="ClipMaster"
BUNDLE_ID="com.clipmaster.app"
SOURCE_APP=".build/release/${APP_NAME}.app"
TARGET_DIR="/Volumes/External/Applications"
TARGET_APP="${TARGET_DIR}/${APP_NAME}.app"
RESET_PERMISSIONS=false

for arg in "$@"; do
    case "${arg}" in
        --reset-permissions)
            RESET_PERMISSIONS=true
            ;;
        *)
            echo "未知参数: ${arg} (支持: --reset-permissions)" >&2
            exit 1
            ;;
    esac
done

if [ ! -d "${SOURCE_APP}" ]; then
    echo "未找到 ${SOURCE_APP}，请先执行: bash build.sh"
    exit 1
fi

if [ "${RESET_PERMISSIONS}" = true ]; then
    echo "=== 重置辅助功能与录屏权限 (--reset-permissions) ==="
    tccutil reset Accessibility "${BUNDLE_ID}" || true
    tccutil reset ScreenCapture "${BUNDLE_ID}" || true
fi

SIGN_INFO="$(codesign -dv "${SOURCE_APP}" 2>&1 || true)"

echo "=== 关闭旧进程 ==="
pkill -x "${APP_NAME}" 2>/dev/null || true
sleep 1

echo "=== 部署新版本 ==="
rm -rf "${TARGET_APP}"
cp -R "${SOURCE_APP}" "${TARGET_DIR}/"

echo "=== 启动应用 ==="
open "${TARGET_APP}"

echo "=== 部署完成 ==="
echo "已部署到: ${TARGET_APP}"
if echo "${SIGN_INFO}" | grep -q "Signature=adhoc"; then
    echo "⚠️ 当前构建使用 ad-hoc 签名，系统通常需要重新授予 辅助功能/录屏 权限。"
else
    echo "✅ 当前构建已使用稳定开发证书签名，后续覆盖更新将自动保留 辅助功能/录屏 权限。"
    echo "   （仅当首次从旧 ad-hoc 版本迁移至此证书版本时，需在 系统设置 → 隐私与安全性 中最后一次确认授权。）"
fi
