#!/bin/sh
# Claude Code status line for TokenCoach.
# Claude Code passes session info as JSON on stdin; we save it so the menu bar app
# can read the official 5-hour / 7-day limit numbers, then print a short status line.
dir="$HOME/Library/Application Support/TokenCoach"
mkdir -p "$dir"
input=$(cat)
printf '%s' "$input" > "$dir/statusline.json.tmp" && mv "$dir/statusline.json.tmp" "$dir/statusline.json"
printf '%s' "$input" | /usr/bin/python3 -c '
import json,sys
d=json.load(sys.stdin); r=d.get("rate_limits") or {}
five=(r.get("five_hour") or {}).get("used_percentage"); ctx=(d.get("context_window") or {}).get("used_percentage")
parts=[(d.get("model") or {}).get("display_name","")]
if five is not None: parts.append(f"5h {five:.0f}%")
if ctx is not None: parts.append(f"chat {ctx:.0f}% full")
print(" · ".join(p for p in parts if p))' 2>/dev/null
