#!/usr/bin/env bash
# vim:ft=bash

TEMPFILE=$(mktemp)
trap 'rm -f $TEMPFILE' EXIT

cat parsers.txt > "$TEMPFILE"

while read -r line; do
    test -z "$line" && continue
    case "$line" in "#"*) continue ;; esac
 
    treesitter=$( echo "$line" | cut -d'/' -f 5 )
    version="$(grep -oP 'v?\d+(\.\d+)+' <<< "$line")"

    IFS='.' read -r m n r <<< "$version"

    echo "🚀 try update $treesitter $version"
    if test -n "$r"; then
        if curl -fsSL "${line//$version/$m.$n.$((r+1))}" >/dev/null; then
            echo -e "✅ updated $treesitter to $m.$n.$((r+1))"
            sed -i "/$treesitter/s/$version/$m.$n.$((r+1))/" parsers.txt
        elif curl -fsSL "${line//$version/$m.$((n+1)).0}" >/dev/null; then
            echo -e "✅ updated $treesitter to $m.$((n+1)).0"
            sed -i "/$treesitter/s/$version/$m.$((n+1)).0/" parsers.txt
        fi
    elif test -n "$n"; then
        if curl -fsSL "${line//$version/$m.$((n+1))}" >/dev/null; then
            echo -e "✅ updated $treesitter to $m.$((n+1))"
            sed -i "/$treesitter/s/$version/$m.$((n+1))/" parsers.txt
        fi
    fi
    echo ""
done < "$TEMPFILE"
