#!/bin/sh
src="$1"
out="$2"

[ -d "$src" ] || exit 1
mkdir -p "$out" || exit 1

if command -v magick >/dev/null 2>&1; then
    tool=magick
elif command -v convert >/dev/null 2>&1; then
    tool=convert
elif command -v ffmpeg >/dev/null 2>&1; then
    tool=ffmpeg
else
    exit 3
fi

for f in "$src"/*; do
    [ -f "$f" ] || continue
    case "${f##*.}" in
        jpg|jpeg|png|webp|bmp|JPG|JPEG|PNG|WEBP|BMP) ;;
        *) continue ;;
    esac

    t="$out/$(printf %s "$f" | tr / +).jpg"
    if [ -s "$t" ] && [ ! "$f" -nt "$t" ]; then
        continue
    fi

    tmp="$t.tmp.jpg"
    case "$tool" in
        magick)
            magick -define jpeg:size=800x512 "${f}[0]" -thumbnail 400x256^ -gravity center -extent 400x256 -quality 85 "$tmp"
            ;;
        convert)
            convert -define jpeg:size=800x512 "${f}[0]" -thumbnail 400x256^ -gravity center -extent 400x256 -quality 85 "$tmp"
            ;;
        ffmpeg)
            ffmpeg -v error -y -i "$f" -vf "scale=400:256:force_original_aspect_ratio=increase,crop=400:256" -frames:v 1 -update 1 -q:v 4 "$tmp"
            ;;
    esac

    if [ -s "$tmp" ]; then
        mv -f "$tmp" "$t"
    else
        rm -f "$tmp"
    fi
done

exit 0
