#!/bin/bash
set -e

# -------- toolchain --------
CC=arm-uclibc-linux-2.6.36-gcc
CXX=arm-uclibc-linux-2.6.36-g++
AR=arm-uclibc-linux-2.6.36-ar
RANLIB=arm-uclibc-linux-2.6.36-ranlib

# -------- versions --------
PCRE2_VER=10.37
MBEDTLS_VER=2.16.6
LIBSODIUM_VER=1.0.18
LIBEV_VER=4.33
CARES_VER=1.13.0
SS_VER=3.3.6

# -------- sources --------
PCRE2_URL="https://ftp.exim.org/pub/pcre/pcre2-$PCRE2_VER.tar.gz"
MBEDTLS_URL="https://gitlab.freifunk-stuttgart.de/firmware/ffs-openwrt-dl-cache/-/raw/master/mbedtls-2.16.6-gpl.tgz"
LIBSODIUM_URL="https://download.libsodium.org/libsodium/releases/libsodium-$LIBSODIUM_VER.tar.gz"
LIBEV_URL="http://dist.schmorp.de/libev/libev-$LIBEV_VER.tar.gz"
CARES_URL="https://c-ares.haxx.se/download/c-ares-$CARES_VER.tar.gz"
SS_GIT="https://github.com/shadowsocks/shadowsocks-libev"

# -------- args --------
host=""
prefix=""

while [ -n "$1" ]; do
  case "$1" in
    --host=*) host="${1#*=}" ;;
    --prefix=*) prefix="${1#*=}" ;;
  esac
  shift
done

[ -z "$prefix" ] && prefix="$(pwd)/dists"
[ -z "$host" ] && host="arm-uclibc-linux"

BUILD="$(pwd)/build"
NPROC="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)"
mkdir -p "$BUILD"

dl() { wget --no-check-certificate -q -O "$2" "$1"; }

# -------- pcre2 --------
build_pcre2() {
  [ -f "$prefix/pcre2/lib/libpcre2-8.a" ] && return
  cd "$BUILD"
  [ -d pcre2-$PCRE2_VER ] || {
    dl "$PCRE2_URL" pcre2.tar.gz
    tar xzf pcre2.tar.gz
  }
  cd pcre2-$PCRE2_VER
  mkdir -p build && cd build
  cmake \
    -DCMAKE_INSTALL_PREFIX="$prefix/pcre2" \
    -DCMAKE_C_COMPILER="$CC" \
    -DBUILD_SHARED_LIBS=OFF \
    -DPCRE2_BUILD_PCRE2_8=ON \
    -DPCRE2_BUILD_TESTS=OFF \
    ..
  make -j"$NPROC"
  make install
}

# -------- mbedtls --------
build_mbedtls() {
  [ -f "$prefix/mbedtls/lib/libmbedcrypto.a" ] && return
  cd "$BUILD"
  [ -d mbedtls-$MBEDTLS_VER ] || {
    dl "$MBEDTLS_URL" mbedtls.tgz
    tar xzf mbedtls.tgz
  }
  cd mbedtls-$MBEDTLS_VER
  make clean >/dev/null 2>&1 || true
  make CC="$CC" AR="$AR" -j"$NPROC"
  make DESTDIR="$prefix/mbedtls" PREFIX=/ install
}

# -------- libsodium --------
build_libsodium() {
  [ -f "$prefix/libsodium/lib/libsodium.a" ] && return
  cd "$BUILD"
  [ -d libsodium-$LIBSODIUM_VER ] || {
    dl "$LIBSODIUM_URL" libsodium.tar.gz
    tar xzf libsodium.tar.gz
  }
  cd libsodium-$LIBSODIUM_VER
  ./configure --prefix="$prefix/libsodium" --host="$host" --disable-shared
  make -j"$NPROC"
  make install
}

# -------- libev --------
build_libev() {
  [ -f "$prefix/libev/lib/libev.a" ] && return
  cd "$BUILD"
  [ -d libev-$LIBEV_VER ] || {
    dl "$LIBEV_URL" libev.tar.gz
    tar xzf libev.tar.gz
  }
  cd libev-$LIBEV_VER
  ./configure --prefix="$prefix/libev" --host="$host" --disable-shared
  make -j"$NPROC"
  make install
}

# -------- c-ares --------
build_cares() {
  [ -f "$prefix/libc-ares/lib/libcares.a" ] && return
  cd "$BUILD"
  [ -d c-ares-$CARES_VER ] || {
    dl "$CARES_URL" cares.tar.gz
    tar xzf cares.tar.gz
  }
  cd c-ares-$CARES_VER
  ./configure --prefix="$prefix/libc-ares" --host="$host" --disable-shared
  make -j"$NPROC"
  make install
}

# -------- shadowsocks --------
build_ss() {
  cd "$BUILD"
  rm -rf shadowsocks-libev
  git clone --branch v$SS_VER --depth 1 "$SS_GIT" shadowsocks-libev
  cd shadowsocks-libev

  # 去掉 -Werror
  sed -i 's/-Werror//g' CMakeLists.txt src/CMakeLists.txt 2>/dev/null || true
  sed -i -r 's/(add_library\([[:space:]]*shadowsocks-libev-shared[[:space:]]+)SHARED/\1STATIC/g' \
    CMakeLists.txt src/CMakeLists.txt 2>/dev/null || true

  mkdir build && cd build

  cmake \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSTEM_PROCESSOR=arm \
    -DCMAKE_C_COMPILER="$CC" \
    -DCMAKE_PREFIX_PATH="$prefix/mbedtls;$prefix/libsodium;$prefix/libc-ares;$prefix/libev;$prefix/pcre2" \
    -DLIBEV_INCLUDE_DIR="$prefix/libev/include" \
    -DLIBEV_LIBRARY="$prefix/libev/lib/libev.a" \
    -DCARES_INCLUDE_DIR="$prefix/libc-ares/include" \
    -DCARES_LIBRARY="$prefix/libc-ares/lib/libcares.a" \
    -DWITH_STATIC=ON \
    -DWITH_EMBEDDED_SRC=ON \
    ..

  make -j"$NPROC" ss-local ss-server ss-tunnel ss-redir

  mkdir -p "$prefix/shadowsocks-libev/bin"
  cp -f bin/ss-local bin/ss-server bin/ss-tunnel bin/ss-redir \
        "$prefix/shadowsocks-libev/bin/"
}

# -------- run --------
build_pcre2
build_mbedtls
build_libsodium
build_libev
build_cares
build_ss

ls -lh "$prefix/shadowsocks-libev/bin"

for f in ss-local ss-server ss-tunnel ss-redir; do
  arm-uclibc-linux-2.6.36-strip "$prefix/shadowsocks-libev/bin/$f"
done

