---
description: "Cancel active golden harvest loop"
allowed-tools: ["Bash(rm:*)", "Bash(cat:*)"]
---

Cancel the active golden harvest loop. Output files are preserved.

```!
if [ -f .claude/golden-loop.local.md ]; then
  OUTPUT_DIR=$(grep 'output_dir:' .claude/golden-loop.local.md | sed 's/output_dir: *//' | sed 's/^"\(.*\)"$/\1/')
  rm .claude/golden-loop.local.md
  echo "Golden harvest loop cancelled."
  echo "Output files preserved at: $OUTPUT_DIR/"
else
  echo "No active golden harvest loop to cancel."
fi
```
