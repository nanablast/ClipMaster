#!/bin/bash
set -e

APP_NAME="ClipMaster"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
APP_PATH="${BUILD_DIR}/${APP_BUNDLE}"

echo "=== 构建 Release 版本 ==="
swift build -c release

echo "=== 创建 .app 包 ==="
rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"

# 复制可执行文件
cp "${BUILD_DIR}/${APP_NAME}" "${APP_PATH}/Contents/MacOS/${APP_NAME}"

# 复制 Info.plist
cp Info.plist "${APP_PATH}/Contents/Info.plist"

# 复制资源包（GRDB 等依赖的 bundle）
for bundle in "${BUILD_DIR}"/*.bundle; do
    if [ -d "$bundle" ]; then
        cp -R "$bundle" "${APP_PATH}/Contents/Resources/"
    fi
done

# 生成 PkgInfo
echo -n "APPL????" > "${APP_PATH}/Contents/PkgInfo"

chmod -R u+w "${APP_PATH}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "${SIGN_IDENTITY}" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development:/ {print $2; exit}')"
fi
if [ -z "${SIGN_IDENTITY}" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/^[[:space:]]*[0-9]+\)/ {print $2; exit}')"
fi
if [ -n "${SIGN_IDENTITY}" ]; then
    echo "=== 签名应用（稳定证书: ${SIGN_IDENTITY}）==="
    codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_PATH}"
else
    echo "=== 签名应用（未找到可用代码签名证书，回退 ad-hoc）==="
    codesign --force --deep --sign - "${APP_PATH}"
fi
codesign --verify --deep --strict "${APP_PATH}"

echo "=== 构建完成 ==="
echo "应用位置: ${APP_PATH}"
echo ""
echo "安装方法:"
echo "  cp -R \"${APP_PATH}\" /Applications/"
echo ""
echo "或者直接运行:"
echo "  open \"${APP_PATH}\""
