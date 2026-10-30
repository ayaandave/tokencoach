# TokenCoach

A Mac menu bar app that shows how much Claude Code usage you've used, what's eating it, and when to start a fresh chat.

Reads your local Claude Code chat files (`~/.claude/projects`). No login, nothing leaves your Mac.

## Run

```bash
swift run -c release TokenCoach      # menu bar app
swift run -c release spike           # print today's usage in the terminal
```

## Official 5-hour / weekly %

Point Claude Code's status line at `scripts/statusline.sh` (in `~/.claude/settings.json`):

```json
"statusLine": { "type": "command", "command": "/Users/YOU/Projects/tokencoach/scripts/statusline.sh" }
```

Without it, the menu bar shows the current chat's size instead.
