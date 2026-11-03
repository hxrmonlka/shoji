#!/bin/sh
dirs="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}:/run/current-system/sw/share"
echo "$dirs" | tr ':' '\n' | while read -r d; do
    [ -n "$d" ] || continue
    for f in "$d"/wayland-sessions/*.desktop; do
        [ -f "$f" ] || continue
        awk -v id="$(basename "$f" .desktop)" '
            /^\[/ { sec = $0 }
            sec == "[Desktop Entry]" && /^Name=/ && n == "" { n = substr($0, 6) }
            sec == "[Desktop Entry]" && /^Exec=/ && e == "" { e = substr($0, 6) }
            sec == "[Desktop Entry]" && /^Hidden=true/ { h = 1 }
            END { if (n != "" && e != "" && !h) printf "%s\t%s\t%s\n", n, e, id }
        ' "$f"
    done
done | awk -F'\t' '!seen[$2]++'
