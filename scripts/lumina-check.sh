#!/bin/sh
export LC_ALL=C
export GIT_TERMINAL_PROMPT=0

dir="${ALICE_DOTFILES:-$1}"
case "$dir" in
    "~") dir="$HOME" ;;
    "~/"*) dir="$HOME/${dir#"~/"}" ;;
esac

lock="$dir/flake.lock"
[ -n "$dir" ] && [ -f "$lock" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 3
command -v git >/dev/null 2>&1 || exit 3

node='.nodes[.nodes.root.inputs.lumina]'
rev=$(jq -r "$node.locked.rev // empty" "$lock")
kind=$(jq -r "$node.original.type // empty" "$lock")
owner=$(jq -r "$node.original.owner // empty" "$lock")
repo=$(jq -r "$node.original.repo // empty" "$lock")
ref=$(jq -r "$node.original.ref // empty" "$lock")

[ -n "$rev" ] && [ "$kind" = github ] && [ -n "$owner" ] && [ -n "$repo" ] || exit 4

if [ -n "$ref" ]; then
    want="refs/heads/$ref"
else
    want="HEAD"
fi

head=$(timeout 30 git ls-remote "https://github.com/$owner/$repo" "$want" | head -n1 | cut -f1)
[ -n "$head" ] || exit 5

echo "$rev $head"
