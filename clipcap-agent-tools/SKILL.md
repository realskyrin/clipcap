---
name: clipcap-agent-tools
description: Annotate existing image files with the clipcap command-line agent. Use only when the user supplies an image file and wants deterministic arrows, boxes, labels, mosaic blocks, or callouts rendered into a PNG. This skill must not capture the screen or request macOS privacy permissions.
---

# clipcap-agent-tools

Use clipcap as an annotate-only image tool:

```bash
CLIPCAP="/Applications/clipcap.app/Contents/MacOS/clipcap"
"$CLIPCAP" agent annotate --input input.png --spec marks.json --out output.png --meta output.json --pretty
```

If the app is not installed, build it from the repository first:

```bash
bash scripts/rebuild-and-open.sh
```

The agent accepts existing image files only. Do not use this skill for screen capture, window enumeration, Finder selection, or any task that would require system privacy prompts.
