# TokenCoach

A Mac menu bar app that shows how much Claude Code usage you've used, what's eating it, and when to start a fresh chat.

Reads your local Claude Code chat files (`~/.claude/projects`). No login, nothing leaves your Mac.

## Run

```bash
swift run -c release TokenCoach      # menu bar app
swift run -c release spike           # print today's usage and the coach's tips in the terminal
scripts/make-app.sh && open .build/TokenCoach.app   # real app bundle, needed for Mac notifications
```

## Coach tips and warnings

The popup shows one tip for right now (big chat → wrap up and /clear, near the 5-hour limit, a tool eating a lot...).
Warnings also send one Mac notification each (once per chat / per 5-hour window, not repeated).

Test with a lower threshold, then put it back:

```bash
defaults write com.tokencoach.app chatSoft -int 10000      # app
TOKENCOACH_CHAT_SOFT=10000 swift run -c release spike       # spike
defaults delete com.tokencoach.app chatSoft
```

Other settings: `chatHard` (300000), `limitWarn` (80), `limitAlert` (90), `idleMinutes` (60), `toolShare` (0.10).

## Official 5-hour / weekly %

Point Claude Code's status line at `scripts/statusline.sh` (in `~/.claude/settings.json`):

```json
"statusLine": { "type": "command", "command": "/Users/YOU/Projects/tokencoach/scripts/statusline.sh" }
```

Without it, the menu bar shows the current chat's size instead.
