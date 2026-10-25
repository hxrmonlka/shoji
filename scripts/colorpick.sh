#!/bin/sh
cmd="$1"
shift

fail() {
    notify-send -a shoji -u critical "Color picker failed" "$1" 2>/dev/null
    exit 1
}

case "$cmd" in
    capture)
        dir="$1"
        stamp="$2"
        shift 2
        command -v grim >/dev/null 2>&1 || fail "grim is not installed"
        mkdir -p "$dir" || fail "cannot create $dir"
        rm -f "$dir"/pick-*.png
        pids=""
        for name in "$@"; do
            grim -l 0 -o "$name" "$dir/pick-$stamp-$name.png" &
            pids="$pids $!"
        done
        status=0
        for p in $pids; do
            wait "$p" || status=1
        done
        [ "$status" -eq 0 ] || fail "grim failed"
        ;;
    copy)
        hex="$1"
        swatch="$2"
        command -v wl-copy >/dev/null 2>&1 || fail "wl-copy is not installed"
        printf '%s' "$hex" | wl-copy >/dev/null 2>&1
        if [ -n "$swatch" ]; then
            notify-send -a shoji -i "$swatch" -h string:x-canonical-private-synchronous:shoji-color "Color copied" "$hex" 2>/dev/null
        fi
        ;;
    clean)
        rm -f "$1"/pick-*.png
        ;;
    *)
        fail "unknown command: $cmd"
        ;;
esac
exit 0
