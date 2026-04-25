#!/usr/bin/env bash
# build.sh - KFM + rustFrida 一键构建脚本
# 产出：ksu-frida-manager-v2.0.0.zip（可直接在 KSU/Magisk 刷入）
#
# 前置条件：
#   - Android NDK 25+ 已安装
#   - Rust toolchain + aarch64-linux-android target
#   - Python 3
#   - .cargo/config.toml 已配置（rustFrida 仓库自带）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUSTFRIDA_DIR="${RUSTFRIDA_DIR:-$SCRIPT_DIR/../rustFrida-master}"
MODULE_DIR="$SCRIPT_DIR"
BUILD_DIR="$SCRIPT_DIR/build"
OUTPUT_NAME="ksu-frida-manager-v2.0.0"

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[-]${NC} $1"; exit 1; }

# ============================================
# 0. 环境检查
# ============================================
info "Checking build environment..."

command -v cargo  >/dev/null 2>&1 || error "cargo not found. Install Rust toolchain."
command -v python3 >/dev/null 2>&1 || error "python3 not found."
rustup target list --installed 2>/dev/null | grep -q aarch64-linux-android || \
    error "aarch64-linux-android target not installed. Run: rustup target add aarch64-linux-android"

[ -d "$RUSTFRIDA_DIR" ] || error "rustFrida source not found at: $RUSTFRIDA_DIR"

# ============================================
# 1. 构建 loader shellcode
# ============================================
info "Building loader shellcode..."
cd "$RUSTFRIDA_DIR"

if [ -f "loader/build_helpers.py" ]; then
    python3 loader/build_helpers.py
    [ -f "loader/build/bootstrapper.bin" ] || error "bootstrapper.bin not generated"
    [ -f "loader/build/rustfrida-loader.bin" ] || error "rustfrida-loader.bin not generated"
    info "Loader shellcode built successfully"
else
    warn "build_helpers.py not found, assuming loader already built"
fi

# ============================================
# 2. 构建 agent (libagent.so)
# ============================================
info "Building agent (libagent.so)..."
cd "$RUSTFRIDA_DIR"
cargo build -p agent --release
[ -f "target/aarch64-linux-android/release/libagent.so" ] || error "libagent.so not found"
info "Agent built successfully"

# ============================================
# 3. 构建 rustfrida 主程序
# ============================================
info "Building rustfrida binary..."
cd "$RUSTFRIDA_DIR"
cargo build -p rust_frida --release
[ -f "target/aarch64-linux-android/release/rustfrida" ] || error "rustfrida binary not found"
info "rustfrida built successfully"

# ============================================
# 4. 组装模块 zip
# ============================================
info "Assembling module package..."

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/$OUTPUT_NAME"

# 复制模块文件
cd "$MODULE_DIR"
cp -r META-INF system scripts assets \
      module.prop customize.sh service.sh post-fs-data.sh \
      uninstall.sh sepolicy.rule \
      "$BUILD_DIR/$OUTPUT_NAME/"

# 复制 rustfrida 二进制到 system/bin
cp "$RUSTFRIDA_DIR/target/aarch64-linux-android/release/rustfrida" \
   "$BUILD_DIR/$OUTPUT_NAME/system/bin/rustfrida"

# 确保权限
chmod 755 "$BUILD_DIR/$OUTPUT_NAME/system/bin/rustfrida"
chmod 755 "$BUILD_DIR/$OUTPUT_NAME/system/bin/kfm"
chmod -R 755 "$BUILD_DIR/$OUTPUT_NAME/scripts"

# ============================================
# 5. 打包 zip
# ============================================
info "Creating zip package..."
cd "$BUILD_DIR/$OUTPUT_NAME"
zip -r "$BUILD_DIR/$OUTPUT_NAME.zip" . -x '*.DS_Store' '*.git*'

ZIP_SIZE=$(du -h "$BUILD_DIR/$OUTPUT_NAME.zip" | cut -f1)
info "Build complete!"
echo ""
echo "============================================"
echo "  Output: $BUILD_DIR/$OUTPUT_NAME.zip"
echo "  Size:   $ZIP_SIZE"
echo "============================================"
echo ""
echo "Install:"
echo "  adb push $BUILD_DIR/$OUTPUT_NAME.zip /sdcard/Download/"
echo "  # KSU-Next Manager → Modules → Install from storage"
echo "  # Or: Magisk Manager → Modules → Install from storage"
echo ""
echo "Verify after reboot:"
echo "  adb shell \"su -c 'kfm version'\""
echo "  adb shell \"su -c 'kfm help'\""
echo ""
