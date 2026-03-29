---
description: "View current golden harvest loop status"
allowed-tools: ["Bash(cat:*)", "Bash(grep:*)", "Bash(python3:*)"]
---

Check if a golden harvest loop is currently active and display its status.

```!
if [ -f .claude/golden-loop.local.md ]; then
  echo "=== Golden Harvest Loop Status ==="
  grep -E 'current_phase|phase_name|phase_iteration|global_iteration|max_global_iterations|mode|source_tests|golden_tests|contracts|tests_passing|tests_failing|differential' .claude/golden-loop.local.md | head -20
  echo ""
  echo "=== Database Stats ==="
  OUTPUT_DIR=$(grep 'output_dir:' .claude/golden-loop.local.md | sed 's/output_dir: *//' | sed 's/^"\(.*\)"$/\1/')
  PLUGIN_ROOT=$(dirname "$(dirname "$(readlink -f "$0")")" 2>/dev/null || echo "${CLAUDE_PLUGIN_ROOT}")
  if [ -f "$OUTPUT_DIR/golden.db" ]; then
    python3 "${CLAUDE_PLUGIN_ROOT}/scripts/golden_database.py" --db-path "$OUTPUT_DIR/golden.db" stats
  else
    echo "Database not found at $OUTPUT_DIR/golden.db"
  fi
else
  echo "No active golden harvest loop found."
  echo "Start one with: /golden-loop REFERENCE [--target TARGET]"
fi
```
