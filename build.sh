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

echo "=== 构建完成 ==="
echo "应用位置: ${APP_PATH}"
echo ""
echo "安装方法:"
echo "  cp -R \"${APP_PATH}\" /Applications/"
echo ""
echo "或者直接运行:"
echo "  open \"${APP_PATH}\""
