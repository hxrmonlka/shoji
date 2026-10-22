#!/bin/sh
mode="$1"
dir="$2"
geometry="$3"

case "$dir" in
    "~"*) dir="$HOME${dir#\~}" ;;
esac

fail() {
    notify-send -a shoji -u critical "Screenshot failed" "$1" 2>/dev/null
    exit 1
}

command -v grim >/dev/null 2>&1 || fail "grim is not installed"
mkdir -p "$dir" || fail "cannot create $dir"
file="$dir/$(date +%Y%m%d-%H%M%S).png"

window_geometry() {
    if command -v jq >/dev/null 2>&1; then
        g=$(mmsg get focusing-client 2>/dev/null | jq -r 'select(.width != null) | "\(.x),\(.y) \(.width)x\(.height)"' 2>/dev/null)
        [ -n "$g" ] && { echo "$g"; return; }
    fi
    raw=$(mmsg -g -x 2>/dev/null) || return
    x=$(echo "$raw" | grep -oE '(^|[^a-z])x[ :=]+-?[0-9]+' | grep -oE '\-?[0-9]+$' | head -n1)
    y=$(echo "$raw" | grep -oE '(^|[^a-z])y[ :=]+-?[0-9]+' | grep -oE '\-?[0-9]+$' | head -n1)
    w=$(echo "$raw" | grep -oE 'width[ :=]+[0-9]+' | grep -oE '[0-9]+$' | head -n1)
    h=$(echo "$raw" | grep -oE 'height[ :=]+[0-9]+' | grep -oE '[0-9]+$' | head -n1)
    [ -n "$x" ] && [ -n "$y" ] && [ -n "$w" ] && [ -n "$h" ] && echo "$x,$y ${w}x${h}"
}

case "$mode" in
    fullscreen)
        if [ -n "$geometry" ]; then
            grim -o "$geometry" "$file" || fail "grim failed"
        else
            grim "$file" || fail "grim failed"
        fi
        ;;
    window)
        g=$(window_geometry)
        [ -n "$g" ] || fail "no focused window geometry from mmsg"
        grim -g "$g" "$file" || fail "grim failed"
        ;;
    region)
        [ -n "$geometry" ] || fail "no region given"
        grim -g "$geometry" "$file" || fail "grim failed"
        ;;
    *)
        fail "unknown mode: $mode"
        ;;
esac

command -v wl-copy >/dev/null 2>&1 && wl-copy --type image/png < "$file"
notify-send -a shoji -i "$file" "Screenshot saved" "$file" 2>/dev/null
echo "$file"
