#!/usr/bin/env bash

export LANG=${LANG:-en_US.UTF-8}
export LC_ALL=${LC_ALL:-$LANG}

export VIMROOT="$(dirname "$0")"
export VIM="$VIMROOT/share/nvim"    # default_vim_dir
export VIMRUNTIME="$VIM/runtime"    # default_vimruntime_dir

exec "$VIMROOT/bin/nvim" "$@"
