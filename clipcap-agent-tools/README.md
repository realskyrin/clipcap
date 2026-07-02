# clipcap-agent-tools

Annotate existing image files with the clipcap command-line agent.

```bash
CLIPCAP="/Applications/clipcap.app/Contents/MacOS/clipcap"
"$CLIPCAP" agent annotate --input input.png --spec marks.json --out output.png --meta output.json --pretty
```

This helper is annotate-only. It does not capture the screen, list windows, read Finder selection, or request macOS privacy permissions.
