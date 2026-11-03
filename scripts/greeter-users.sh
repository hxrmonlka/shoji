#!/bin/sh
faces="$HOME/.local/share/shoji-greeter/faces"
tab="$(printf '\t')"
getent passwd | awk -F: '$3 >= 1000 && $3 < 60000 && $7 !~ /(nologin|false)$/ { split($5, g, ","); print $1 "\t" g[1] }' | while IFS="$tab" read -r name real; do
    icon=""
    for c in "$faces/$name" "/var/lib/AccountsService/icons/$name"; do
        if [ -f "$c" ]; then
            icon="$c"
            break
        fi
    done
    printf '%s\t%s\t%s\n' "$name" "$real" "$icon"
done
