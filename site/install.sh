#!/bin/bash
# TokenCoach installer: puts TokenCoach in Applications, turns on the limit reading, and opens it.
# Run with:  curl -fsSL https://tokencoach.vercel.app/install.sh | bash
set -euo pipefail

BASE="${TOKENCOACH_URL:-https://tokencoach.vercel.app}"
say() { printf '\033[1m%s\033[0m\n' "$*"; }

# 1. Check the Mac
if [ "$(uname)" != "Darwin" ]; then echo "TokenCoach only runs on a Mac."; exit 1; fi
major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -lt 14 ]; then echo "TokenCoach needs macOS 14 (Sonoma) or newer. You have $(sw_vers -productVersion)."; exit 1; fi
if [ ! -d "$HOME/.claude" ]; then
    echo "Heads up: Claude Code doesn't look installed yet (no ~/.claude folder)."
    echo "TokenCoach will install, but it has nothing to show until you use Claude Code."
fi

# 2. Download and put the app in Applications
say "Downloading TokenCoach…"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$BASE/TokenCoach.zip" -o "$tmp/TokenCoach.zip"
ditto -x -k "$tmp/TokenCoach.zip" "$tmp"

dest="${TOKENCOACH_DEST:-/Applications}"
[ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
pkill -x TokenCoach 2>/dev/null && sleep 1 || true
rm -rf "$dest/TokenCoach.app"
mv "$tmp/TokenCoach.app" "$dest/TokenCoach.app"
xattr -dr com.apple.quarantine "$dest/TokenCoach.app" 2>/dev/null || true
say "Installed to $dest/TokenCoach.app"

# 3. Status line, so TokenCoach can show your official 5-hour and weekly limits
support="$HOME/Library/Application Support/TokenCoach"
mkdir -p "$support"
curl -fsSL "$BASE/statusline.sh" -o "$support/statusline.sh"
chmod +x "$support/statusline.sh"

settings="$HOME/.claude/settings.json"
mkdir -p "$HOME/.claude"
[ -s "$settings" ] || echo '{}' > "$settings"
current=$(plutil -extract statusLine.command raw -o - "$settings" 2>/dev/null || true)
if [ -z "$current" ]; then
    cp "$settings" "$settings.before-tokencoach"
    # JavaScript for Automation ships with every Mac and keeps the file nicely formatted.
    osascript -l JavaScript - "$settings" "$support/statusline.sh" <<'JS'
ObjC.import('Foundation');
function run(argv) {
    const s = JSON.parse($.NSString.stringWithContentsOfFileEncodingError(argv[0], $.NSUTF8StringEncoding, null).js);
    s.statusLine = { type: 'command', command: argv[1] };
    $(JSON.stringify(s, null, 2) + '\n').writeToFileAtomicallyEncodingError(argv[0], true, $.NSUTF8StringEncoding, null);
}
JS
    say "Turned on the limit reading (Claude Code status line)."
elif [ "$current" = "$support/statusline.sh" ]; then
    say "Limit reading already on."
else
    echo "You already have your own Claude Code status line, so I left it alone."
    echo "TokenCoach will show chat sizes, but not your 5-hour / weekly %."
fi

# 4. Open it
open "$dest/TokenCoach.app"
echo
say "Done! Look for TokenCoach in your menu bar (top right) and the floating box in the corner."
echo "Your limit % shows up after your next Claude Code message."
