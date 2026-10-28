#!/bin/sh
src="$1"
mode="${2:-dark}"
if [ "$#" -ge 2 ]; then
    shift 2
else
    shift
fi
wanted="$*"

all="scheme-tonal-spot scheme-vibrant scheme-content scheme-expressive scheme-fidelity scheme-fruit-salad scheme-monochrome scheme-neutral scheme-rainbow"
known=" SchemeContent SchemeExpressive SchemeFidelity SchemeFruitSalad SchemeMonochrome SchemeNeutral SchemeRainbow SchemeTonalSpot SchemeVibrant "
[ -n "$wanted" ] || wanted="$all"

[ -n "$src" ] || exit 2
command -v matugen >/dev/null 2>&1 || exit 127

case "$mode" in
    light) ;;
    *) mode="dark" ;;
esac

dir="${XDG_CACHE_HOME:-$HOME/.cache}/shoji/preview"
mkdir -p "$dir" || exit 1
cfg="$dir/config.toml"
tpl="$dir/preview.tpl"

pascal() {
    printf '%s\n' "$1" | sed -e 's/-/ /g' | awk '{
        out = ""
        for (i = 1; i <= NF; i++)
            out = out toupper(substr($i, 1, 1)) substr($i, 2)
        print out
    }'
}

printf '%s\n' '{{colors.primary.default.hex}} {{colors.secondary.default.hex}} {{colors.tertiary.default.hex}}' > "$tpl" || exit 1
rm -f "$dir"/*.txt

{
    printf '[config]\n\n'
    n=0
    for s in $wanted; do
        p=$(pascal "$s")
        case "$known" in
            *" $p "*) ;;
            *) continue ;;
        esac
        n=$((n + 1))
        printf '[templates.preview_%s]\n' "$(printf '%s' "$s" | tr '.-' '__')"
        printf 'type = "%s"\n' "$p"
        printf 'input_path = "%s"\n' "$tpl"
        printf 'output_path = "%s/%s.txt"\n' "$dir" "$s"
        printf '\n'
    done
} > "$cfg.tmp" && mv "$cfg.tmp" "$cfg" || exit 1
[ "$n" -gt 0 ] || exit 2

case "$src" in
    \#*)
        matugen color hex "$src" --mode "$mode" --quiet --config "$cfg" || exit 1
        ;;
    *)
        [ -f "$src" ] || exit 2
        matugen image "$src" --mode "$mode" --source-color-index 0 --quiet --config "$cfg" || exit 1
        ;;
esac

for s in $wanted; do
    f="$dir/$s.txt"
    [ -f "$f" ] || continue
    p=""
    q=""
    r=""
    read -r p q r < "$f"
    [ -n "$p" ] || continue
    [ -n "$q" ] || q="$p"
    [ -n "$r" ] || r="$q"
    printf '{"value":"%s","primary":"%s","secondary":"%s","tertiary":"%s"}\n' "$s" "$p" "$q" "$r"
done
exit 0
