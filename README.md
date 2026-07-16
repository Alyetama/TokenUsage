# TokenUsage

A menu-bar app that tracks token usage across your AI coding agents — Claude,
Codex, Kimi, MiniMax, opencode, and Antigravity — by reading their local logs.
No network calls, no API keys, nothing leaves your machine.

![TokenUsage screenshot](docs/mockup.png)

## Download

**[⬇︎ Download for macOS](https://github.com/Alyetama/TokenUsage/releases/latest/download/TokenUsage.dmg)**

`https://github.com/Alyetama/TokenUsage/releases/latest/download/TokenUsage.dmg`
always points at the newest release, because the DMG filename carries no
version — see [Releases](https://github.com/Alyetama/TokenUsage/releases) for
the changelog.

## Features

- Running token total in the menu bar, with a tap-to-expand breakdown per agent
- A resizable dashboard window listing every agent and model, sorted by usage
- Today / 7 Days / 30 Days / All time ranges
- Per-model input, output, cache-read, and cache-write breakdown
- Estimated cost per agent, with real cost pulled straight from the source
  where the agent records it
- Updates within seconds of an agent writing to its logs (FSEvents-driven),
  with a relaxed fallback poll — no constant re-scanning
- Reads local log files only: `~/.claude`, `~/.codex`, `~/.kimi-code`,
  `~/.minimax`, `~/.local/share/opencode`

## First launch (opening an unsigned app)

**TokenUsage isn't signed with an Apple Developer ID**, so macOS blocks it the
first time you open it. This is expected — you only need to do one of the
following once, and it opens normally afterward.

**1. Right-click to open.** In Finder, **Control-click** (or right-click)
`TokenUsage`, choose **Open**, then click **Open** again in the dialog.

**2. If macOS still won't let you (newer versions):** open
**System Settings → Privacy & Security**, scroll down to the message about
`TokenUsage` being blocked, and click **Open Anyway**. Confirm with
**Open Anyway** (and Touch ID or your password if asked).

**3. Terminal fallback.** If neither works, remove the quarantine flag and open
it normally:

```bash
/usr/bin/xattr -dr com.apple.quarantine /Applications/TokenUsage.app
```

(Adjust the path if you keep the app somewhere other than `/Applications`.)

## Build from source

```bash
git clone https://github.com/Alyetama/TokenUsage.git
cd TokenUsage
./build.sh
```

## License

[MIT](LICENSE) © 2026 Alyetama
