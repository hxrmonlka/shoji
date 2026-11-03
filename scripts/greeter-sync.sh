#!/bin/sh
dest="${1:?usage: greeter-sync.sh DEST_HOME [FINAL_HOME]}"
final="${2:-$dest}"
state="$HOME/.local/state/shoji"
out="$dest/.local/state/shoji"
data="$dest/.local/share/shoji-greeter"
fdata="$final/.local/share/shoji-greeter"
mkdir -p "$out" "$data/faces"

wp=""
if [ -f "$state/wallpaper.json" ]; then
    wp="$(sed -n 's/.*"path":"\([^"]*\)".*/\1/p' "$state/wallpaper.json")"
fi
if [ -n "$wp" ] && [ -f "$wp" ]; then
    ext="${wp##*.}"
    rm -f "$data"/wallpaper.*
    cp -f "$wp" "$data/wallpaper.$ext"
    printf '{"path":"%s","dir":"%s"}' "$fdata/wallpaper.$ext" "$fdata" > "$out/wallpaper.json"
    echo "wallpaper: $wp"
else
    echo "wallpaper: none found (wallpaper.json missing or file not readable: '$wp')"
fi

if [ -f "$state/colors.json" ]; then
    cp -f "$state/colors.json" "$out/colors.json"
    echo "colors: copied"
else
    echo "colors: none"
fi

for c in "$HOME/.face" "/var/lib/AccountsService/icons/$(id -un)"; do
    if [ -f "$c" ]; then
        cp -f "$c" "$data/faces/$(id -un)"
        echo "face: $c"
        break
    fi
done

chmod -R a+rX "$dest/.local"
