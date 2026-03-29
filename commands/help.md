---
description: "Show golden harvest loop help and available commands"
---

# Golden Harvest Loop — Help

## Available Commands

| Command | Description |
|---------|-------------|
| `/golden-loop REFERENCE [OPTIONS]` | Start a golden master testing loop |
| `/golden-status` | View current loop status |
| `/golden-cancel` | Cancel active loop (preserves output) |
| `/golden-help` | Show this help |

## Quick Start

```bash
# Extract tests from reference project (read-only)
/golden-loop ~/projects/vllm --mode read-only

# Full pipeline: extract → normalize → implement → verify
/golden-loop ~/projects/vllm --target ~/projects/my-engine

# Just build the golden suite
/golden-loop ~/projects/vllm --mode golden-only

# Verify existing suite against target
/golden-loop ~/projects/vllm --target ~/projects/my-engine --mode verify-only
```

## Pipeline Phases

```
/golden-loop ~/projects/reference --target ~/projects/target
     |
     v
+--------------------------------------------------------------+
|  Phase 1: READ       (max 4 iter)                             |
|  Extract tests, fixtures, contracts from reference codebase   |
+--------------------------------------------------------------+
|  Phase 2: GOLDEN     (max 3 iter)                             |
|  Normalize into portable golden suite, classify by domain     |
+--------------------------------------------------------------+
|  Phase 3: GREEN      (max 5 iter)                             |
|  Drive target implementation to pass golden tests             |
+--------------------------------------------------------------+
|  Phase 4: VERIFY     (max 4 iter)                             |
|  Differential testing, fuzz, benchmarks, regression           |
+--------------------------------------------------------------+
|  Phase 5: REPORT     (max 2 iter)                             |
|  Consolidation: compatibility matrix, coverage, figures       |
+--------------------------------------------------------------+
     |                           ^
     |    +----------------------+
     |    | Loop-back (budget permitting)
     |    | When VERIFY reveals golden
     v    | tests too coupled to reference
```

## Modes

| Mode | Description | Phases |
|------|-------------|--------|
| **full** | Complete pipeline (default) | 1-5 |
| **read-only** | Extract tests only | 1, 5 |
| **golden-only** | Extract + normalize | 1, 2, 5 |
| **verify-only** | Green + verify (assumes golden suite exists) | 3, 4, 5 |

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `--target <path>` | (none) | Target codebase path |
| `--mode <mode>` | full | Pipeline mode |
| `--max-iterations <n>` | 60 | Max global iterations |
| `--output-dir <path>` | ./golden-output | Output directory |
| `--completion-promise '<text>'` | "GOLDEN HARVEST COMPLETE" | Promise phrase |

## Technical Foundation

- **Golden Master Testing** — Capture reference behavior as ground truth
- **Test Harvesting** — Extract tests from existing systems
- **Differential Testing** — Compare outputs between implementations
- **Characterization Testing** — Capture what IS, not what SHOULD BE
- **Ralph Wiggum Loop** — Autonomous agent via stop hook
- **Autoresearch Pattern** — Quality gates with keep/discard
