#!/bin/bash -e

NVIM_VERSION=0.11.5
NVIM_TAR="$PWD/neovim-$NVIM_VERSION.tar.gz"
NVIM_URLS=(
    https://pub.mtdcy.top/packages/neovim-$NVIM_VERSION.tar.gz
    https://github.com/neovim/neovim/archive/refs/tags/v$NVIM_VERSION.tar.gz
)

error() { echo -e "\n\\033[31m== $*\\033[39m"; }
info()  { echo -e "\n\\033[32m== $*\\033[39m"; }
warn()  { echo -e "\n\\033[33m== $*\\033[39m"; }

NVIM_ROOT="$PWD"
case "$OSTYPE" in
    darwin*) PREFIX="$PWD/prebuilts/$(uname -m)-apple-darwin" ;;
    *)       PREFIX="$PWD/prebuilts/$(uname -m)-$OSTYPE"      ;;
esac

NVIM_ARGS=(
    -DCMAKE_BUILD_TYPE=Release

    # install path
    -DCMAKE_INSTALL_PREFIX="$PREFIX"

    # bundled
    -DUSE_BUNDLED=ON
    -DUSE_BUNDLED_LUAJIT=ON # prefer luajit over lua
    #-DUSE_BUNDLED_LUA=ON

    # no multiple languages
    -DENABLE_LIBINTL=OFF
    -DENABLE_LANGUAGES=OFF

    -DBUILD_STATIC_LIBS=ON
    -DBUILD_SHARED_LIBS=OFF

    # cache deps package
    -DDEPS_DOWNLOAD_DIR="$PWD/packages"

    # we have trouble to build static nvim
    #  => luajit crashes because of dlopen
    -DCMAKE_EXE_LINKER_FLAGS=''
)

[[ "$OSTYPE" =~ ^darwin ]] && NVIM_ARGS+=(
    # build for old macOS
    -DMACOSX_DEPLOYMENT_TARGET=10.13
)

if which gcc && which cmake && which msgfmt && which nim; then
    info "build tools is good"
else
    info "prepare build tools"
    if which apk; then
        sudo apk update
        sudo apk add build-base cmake gettext
    elif which brew; then
        brew update
        brew install cmake gettext nim
    else
        sudo apt update
        sudo apt install -y build-essential cmake gettext
    fi
fi

info "prepare sources"
if ! test -f "$NVIM_TAR"; then
    for url in "${NVIM_URLS[@]}"; do
        info "download neovim < $url"
        curl -sL --fail --connect-timeout 3 -o "$NVIM_TAR" "$url" && break || true
    done
fi
[ -f "$NVIM_TAR" ] || exit 1

NVIM_OUT="${PREFIX//prebuilts/out}"
mkdir -pv "$NVIM_OUT" && cd "$NVIM_OUT"

tar -xf "$NVIM_TAR" && cd neovim-*/

# https://github.com/neovim/neovim/blob/master/BUILD.md

mkdir -p build .deps

info "patch nvim"

# $VIMROOT => $VIM => $VIMRUNTIME
cat << 'EOF' > cmake.config/pathdef.c.in
#include "${PROJECT_SOURCE_DIR}/src/nvim/vim.h"
char *default_vim_dir = "$VIMROOT/share/nvim";                  /* $VIM         */
char *default_vimruntime_dir = "$VIMROOT/share/nvim/runtime";   /* $VIMRUNTIME  */
char *default_lib_dir = "$VIMROOT/lib/nvim";                    /* runtime ABI  */
EOF
# quote 'EOF' to avoid variable expanding.

(
    info "build dependencies"
    cd .deps
    cmake ../cmake.deps && make
    # installed locally by custom command
)

info "build nvim"

cd build

cmake "${NVIM_ARGS[@]}" .. && make

# install
make install

info "check nvim binary"

if which otool >/dev/null; then
    otool -L "$PREFIX/bin/nvim"
else
    ldd "$PREFIX/bin/nvim"
fi

info "prepare app entry"

# app entry script
cat > "$PREFIX/nvim" << 'EOF'
#!/bin/bash
export LANG=${LANG:-en_US.UTF-8}
export LC_ALL=${LC_ALL:-$LANG}

export VIMROOT="$(dirname "$0")"
export VIM="$VIMROOT/share/nvim"    # default_vim_dir
export VIMRUNTIME="$VIM/runtime"    # default_vimruntime_dir

exec "$VIMROOT/bin/nvim" "$@"
EOF
chmod a+x "$PREFIX/nvim"

"$PREFIX/nvim" -V1 -v

info "make nvim-$NVIM_VERSION release"

RELEASE="${PREFIX/prebuilts/release}.tar"

mkdir -pv "$(dirname "$RELEASE")"

tar -C "$PREFIX" -cf "$RELEASE" .

# fruzzy official site has no prebuilt fruzzy_mod.so for Apple silicon
if [ "$(uname -s)" = "Darwin" ]; then
    info "prepare fruzzy native modules"

    pushd "$NVIM_ROOT/fruzzy"

    nimble refresh
    nimble install -y nimpy binaryheap

    relopt="-d:release -d:removelogger --os:macosx"
    [ "$(uname -m)" = "x86_64" ] && relopt+=" --cpu:amd64" || relopt+=" --cpu:arm64"

    make build relopt="$relopt"

    info "append fruzzy_mod.so to release"
    tar -C rplugin/python3 -rf "$RELEASE" fruzzy_mod.so

    popd
fi

info "gzip releases"
gzip -f "$RELEASE"
