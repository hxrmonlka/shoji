#!/bin/sh
shell="$1"
state="$2"
img="$3"
enabled="$4"
radius="${5:-12}"
scheme="${6:-scheme-tonal-spot}"
mode="${7:-dark}"

case " scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow scheme-tonal-spot scheme-vibrant " in
    *" $scheme "*) ;;
    *) scheme="scheme-tonal-spot" ;;
esac

case "$mode" in
    light) ;;
    *) mode="dark" ;;
esac

conf="${XDG_CONFIG_HOME:-$HOME/.config}"
cfg="$state/matugen.toml"
tpl="$state/templates"

mkdir -p "$state" "$tpl" || exit 1

has() {
    case " $enabled " in
        *" $1 "*) return 0 ;;
    esac
    return 1
}

active=""

has mango && command -v mmsg >/dev/null 2>&1 && active="$active mango"
has kitty && command -v kitty >/dev/null 2>&1 && active="$active kitty"
has btop && command -v btop >/dev/null 2>&1 && active="$active btop"
has equicord && [ -d "$conf/Equicord" ] && active="$active equicord"
has gtk && active="$active gtk"
has helium && [ -w /etc/chromium/policies/managed/shoji-color.json ] && active="$active helium"
has spotify && command -v shoji-spicetify-apply >/dev/null 2>&1 && active="$active spotify"

rb=$((radius * 2 / 3))
for v in 3 4; do
    sed -e "s/__RB__/$rb/g" -e "s/__R__/$radius/g" "$shell/matugen/templates/gtk$v.css" > "$tpl/gtk$v.css"
done

{
    cat <<'TOML'
[config]

[config.custom_colors]
red = "#e5545f"
green = "#6fbf73"
yellow = "#e0b64a"
blue = "#5f9be8"
magenta = "#c678dd"
cyan = "#4fb8c9"

[templates.shoji]
TOML
    printf 'input_path = "%s/matugen/colors.json"\n' "$shell"
    printf 'output_path = "%s/colors.json"\n\n' "$state"
    for id in $active; do
        sed -e "s#SHELL_DIR#$shell#g" -e "s#CONFIG_DIR#$conf#g" -e "s#STATE_DIR#$state#g" "$shell/matugen/configs/$id.toml"
        printf '\n'
    done
    if [ -f "$conf/matugen/config.toml" ]; then
        awk '/^\[/ { keep = ($0 ~ /^\[templates\./ && $0 !~ /^\[templates\.shoji/) } keep { print }' "$conf/matugen/config.toml"
    fi
} > "$cfg.tmp" && mv "$cfg.tmp" "$cfg" || exit 1

matugen image "$img" --mode "$mode" --type "$scheme" --source-color-index 0 --config "$cfg"
rc=$?
[ "$rc" -eq 0 ] || exit "$rc"

for id in $active; do
    case "$id" in
        mango)
            [ -n "${MANGO_INSTANCE_SIGNATURE:-}" ] && mmsg dispatch reload_config >/dev/null 2>&1
            ;;
        kitty)
            pkill -USR1 -f '(^|/)\.?kitty(-wrapped)?( |$)' >/dev/null 2>&1
            ;;
        btop)
            pkill -USR2 -x btop >/dev/null 2>&1
            ;;
        gtk)
            if command -v gsettings >/dev/null 2>&1; then
                if [ "$mode" = "light" ]; then
                    prefer="prefer-light"
                else
                    prefer="prefer-dark"
                fi
                gsettings set org.gnome.desktop.interface color-scheme default >/dev/null 2>&1
                gsettings set org.gnome.desktop.interface color-scheme "$prefer" >/dev/null 2>&1
            fi
            ;;
        helium)
            command -v helium >/dev/null 2>&1 && timeout 5 helium --refresh-platform-policy --no-startup-window >/dev/null 2>&1
            ;;
        spotify)
            shoji-spicetify-apply "$state/spotify-colors.json" || printf '%s\n' "Shoji: Spotify color update failed" >&2
            ;;
    esac
done
exit 0
