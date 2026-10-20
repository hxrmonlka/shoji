#!/bin/sh
export LC_ALL=C

head -n1 /proc/stat
echo ---
grep -E '^(MemTotal|MemAvailable):' /proc/meminfo
echo ---

echo "t $(date +%s.%N)"

ct=""
for h in /sys/class/hwmon/hwmon*; do
    n=$(cat "$h/name" 2>/dev/null)
    case "$n" in
        k10temp|coretemp|zenpower|cpu_thermal)
            ct=$(cat "$h/temp1_input" 2>/dev/null)
            [ -n "$ct" ] && break
            ;;
    esac
done
[ -z "$ct" ] && ct=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
echo "cputemp $ct"

g=""
if command -v nvidia-smi >/dev/null 2>&1; then
    g=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ',')
    [ -n "$g" ] && echo "gpu $g"
fi
if [ -z "$g" ]; then
    for c in /sys/class/drm/card[0-9]; do
        d="$c/device"
        [ -r "$d/gpu_busy_percent" ] || continue
        b=$(cat "$d/gpu_busy_percent" 2>/dev/null)
        tm=$(cat "$d"/hwmon/hwmon*/temp1_input 2>/dev/null | head -n1)
        vu=$(cat "$d/mem_info_vram_used" 2>/dev/null)
        vt=$(cat "$d/mem_info_vram_total" 2>/dev/null)
        echo "gpu ${b:-0} $(( ${tm:-0} / 1000 )) $(( ${vu:-0} / 1048576 )) $(( ${vt:-0} / 1048576 ))"
        g=1
        break
    done
fi
[ -z "$g" ] && echo "gpu none"

awk '$3 ~ /^(nvme[0-9]+n[0-9]+|sd[a-z]+|vd[a-z]+|xvd[a-z]+|mmcblk[0-9]+)$/ { r += $6; w += $10 } END { print "disk", r + 0, w + 0 }' /proc/diskstats
awk -F'[: ]+' 'NR > 2 && $2 != "lo" && $2 !~ /^(veth|docker|br-|virbr)/ { rx += $3; tx += $11 } END { print "net", rx + 0, tx + 0 }' /proc/net/dev
echo ---
ps -eo pid,pcpu,rss,comm --sort=-pcpu | head -n 16
