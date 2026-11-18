#!/usr/bin/env awk -f
# shoji-cli tests -- extract IpcHandler targets/functions from shell.qml.
#
# Usage: awk -f qml_ipc.awk shell.qml
# Output: one "target<TAB>function" line per handler function.

/^[[:space:]]*IpcHandler[[:space:]]*\{/ {
        in_ipc = 1
        target = ""
        next
}
in_ipc && /target:[[:space:]]*"/ {
        line = $0
        sub(/.*target:[[:space:]]*"/, "", line)
        sub(/".*/, "", line)
        target = line
        next
}
in_ipc && /^[[:space:]]*function[[:space:]]+[A-Za-z]/ {
        line = $0
        sub(/^[[:space:]]*function[[:space:]]+/, "", line)
        idx = index(line, "(")
        if (idx > 0 && target != "")
                print target "\t" substr(line, 1, idx - 1)
        next
}
in_ipc && /^    \}[[:space:]]*$/ {
        # IpcHandler blocks close at exactly 4 spaces; function bodies nest deeper.
        in_ipc = 0
        target = ""
        next
}
