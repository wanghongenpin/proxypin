#!/usr/bin/env bash
# 交叉编译 Android 版 tcpdump（静态链接 libpcap），输出到 android/app/src/main/assets/tcpdump/<abi>/tcpdump
#
# 用法：
#   ANDROID_NDK_HOME=/path/to/android-ndk-r27c ./tool/tcpdump/build_tcpdump.sh [abi...]
# 默认 ABI：arm64-v8a armeabi-v7a（x86_64 可显式传入，模拟器用）
#
# 源码版本固定，下载自 https://www.tcpdump.org/release/
set -euo pipefail

LIBPCAP_VERSION=1.10.5
TCPDUMP_VERSION=4.99.5
API=24

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${WORK_DIR:-$ROOT/build/tcpdump}"
OUT="$ROOT/android/app/src/main/assets/tcpdump"
NDK="${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME}"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
ABIS=("$@")
[ ${#ABIS[@]} -eq 0 ] && ABIS=(arm64-v8a armeabi-v7a)

mkdir -p "$WORK"
cd "$WORK"
[ -d "libpcap-$LIBPCAP_VERSION" ] || curl -sSL "https://www.tcpdump.org/release/libpcap-$LIBPCAP_VERSION.tar.xz" | tar xJ
[ -d "tcpdump-$TCPDUMP_VERSION" ] || curl -sSL "https://www.tcpdump.org/release/tcpdump-$TCPDUMP_VERSION.tar.xz" | tar xJ

for ABI in "${ABIS[@]}"; do
  case "$ABI" in
    arm64-v8a) TARGET=aarch64-linux-android ;;
    armeabi-v7a) TARGET=armv7a-linux-androideabi ;;
    x86_64) TARGET=x86_64-linux-android ;;
    x86) TARGET=i686-linux-android ;;
    *) echo "unknown abi $ABI"; exit 1 ;;
  esac
  echo "==> $ABI"
  export CC="$TOOLCHAIN/bin/${TARGET}${API}-clang"
  export AR="$TOOLCHAIN/bin/llvm-ar"
  export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
  export STRIP="$TOOLCHAIN/bin/llvm-strip"
  export CFLAGS="-Os -fPIE -ffunction-sections -fdata-sections"
  export LDFLAGS="-pie -Wl,--gc-sections"
  PREFIX="$WORK/out/$ABI"

  rm -rf "build-pcap-$ABI" "build-tcpdump-$ABI"
  cp -r "libpcap-$LIBPCAP_VERSION" "build-pcap-$ABI"
  (cd "build-pcap-$ABI" &&
    ./configure --host="$TARGET" --prefix="$PREFIX" --with-pcap=linux --disable-shared \
      --disable-usb --disable-netmap --disable-bluetooth --disable-dbus --disable-rdma \
      --without-libnl --disable-remote --enable-ipv6 >/dev/null &&
    make -j"$(nproc)" >/dev/null && make install >/dev/null)

  cp -r "tcpdump-$TCPDUMP_VERSION" "build-tcpdump-$ABI"
  (cd "build-tcpdump-$ABI" &&
    PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" ./configure --host="$TARGET" --prefix="$PREFIX" \
      --with-crypto=no --without-smi --without-cap-ng --disable-local-libpcap \
      CPPFLAGS="-I$PREFIX/include" LIBS="-L$PREFIX/lib -lpcap" >/dev/null &&
    make -j"$(nproc)" >/dev/null)

  mkdir -p "$OUT/$ABI"
  cp "build-tcpdump-$ABI/tcpdump" "$OUT/$ABI/tcpdump"
  "$STRIP" --strip-all "$OUT/$ABI/tcpdump"
  ls -la "$OUT/$ABI/tcpdump"
done

cat > "$OUT/VERSION" <<EOF
tcpdump $TCPDUMP_VERSION
libpcap $LIBPCAP_VERSION
built with $(basename "$NDK"), android api $API
EOF
