#!/bin/bash -e

NVIM_VERSION=0.10.4
NVIM_TAR=neovim-$NVIM_VERSION.tar.gz
NVIM_URLS=(
    https://pub.mtdcy.top/packages/neovim-$NVIM_VERSION.tar.gz
    https://github.com/neovim/neovim/archive/refs/tags/v$NVIM_VERSION.tar.gz
)

error() { echo -e "\n\\033[31m== $*\\033[39m"; }
info()  { echo -e "\n\\033[32m== $*\\033[39m"; }
warn()  { echo -e "\n\\033[33m== $*\\033[39m"; }

case "$OSTYPE" in
    darwin*) PREFIX="$PWD/prebuilts/$(uname -m)-apple-darwin" ;;
    *)       PREFIX="$PWD/prebuilts/$(uname -m)-$OSTYPE"      ;;
esac

NVIM_ARGS=(
    # install path
    -DCMAKE_INSTALL_PREFIX="$PREFIX"

    # bundled
    -DUSE_BUNDLED=ON
    -DUSE_BUNDLED_LUAJIT=ON # prefer luajit over lua
    #-DUSE_BUNDLED_LUA=ON

    -DENABLE_LIBINTL=OFF

    -DBUILD_STATIC_LIBS=ON
    -DBUILD_SHARED_LIBS=OFF

    # cache deps package
    -DDEPS_DOWNLOAD_DIR="$UPKG_ROOT/packages"

    # we have trouble to build static nvim
    #  => luajit crashes because of dlopen
    -DCMAKE_EXE_LINKER_FLAGS=''
)

[[ "$OSTYPE" =~ ^darwin ]] && NVIM_ARGS+=(
    # build for old macOS
    -DMACOSX_DEPLOYMENT_TARGET=10.13
)

info "prepare sources"

# prepare sources
for url in "${NVIM_URLS[@]}"; do
    curl -sL -o "$NVIM_TAR" "$url" && break
done

[ -f "$NVIM_TAR" ] || exit 1

tar -xvf "$NVIM_TAR" && cd neovim-*

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

if which -s otool; then
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

RELEASE="${PREFIX/prebuilts/release}.tar.gz"

mkdir -pv "$(dirname "$RELEASE")"

tar -C "$PREFIX" -czf "$RELEASE" .
