Documentation accuracy pass, plus one corrected in-app message.

- Antigravity is no longer described as an agent whose token usage is tracked.
  It is detected when installed, but its conversation databases store every
  payload as an opaque blob with no token, usage, or cost column, so no usage
  can be read. The note shown in the app said the counts were kept server-side;
  they are local but unreadable, and it now says so.
- The input/output/cache split is documented where it actually renders: per
  agent and for the running total. Per-model rows show total tokens and cost.
- The "reads local files only" list now includes `~/.gemini`, which the
  Antigravity scanner probes.
- Added Limitations and Requirements sections to the README (macOS 14+).

No change to scanning, aggregation, pricing, or the UI beyond that one message.

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
