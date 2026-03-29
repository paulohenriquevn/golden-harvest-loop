# Golden Harvest Loop

Autonomous Golden Master Testing laboratory for Claude Code. Point it at a reference codebase and it extracts tests, builds a portable Golden Suite, drives compatibility implementation, and validates behavioral equivalence via differential testing — producing a comprehensive compatibility report.

Combines four ideas:
- **[Ralph Wiggum](https://ghuntley.com/ralph/)** — self-referential AI loop via stop hook
- **[Autoresearch](https://github.com/karpathy/autoresearch)** (Karpathy) — autonomous experimentation: evaluate, keep/discard
- **Golden Master Testing** — capture reference behavior as ground truth
- **Test Harvesting + Differential Verification** — extract, normalize, compare

## Installation

### Step 1: Add the marketplace

```
/plugin marketplace add paulohenriquevn/golden-harvest-loop
```

### Step 2: Install the plugin

```
/plugin install golden-harvest-loop@golden-harvest-loop
```

### Step 3: Reload plugins

```
/reload-plugins
```

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

# Custom settings
/golden-loop ~/projects/vllm --target ~/projects/my-engine --max-iterations 100 --output-dir ./vllm-compat
```

## How It Works

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

## The READ → GOLDEN → GREEN → VERIFY Framework

### READ (Test Harvesting)
Extract tests and behavior from the reference system. Focus is on **preserving observable behavior**, not improving anything.

### GOLDEN (Golden Master Construction)
Transform extracted tests into a portable, implementation-agnostic Golden Suite. Remove coupling to reference internals. Classify by domain.

### GREEN (Compatibility-Driven Implementation)
Drive the target implementation to pass the golden suite. Critical tests first.

### VERIFY (Differential Verification)
Validate behavioral equivalence beyond the suite: differential testing, fuzz, benchmarks, regression analysis.

## Pipeline Modes

| Mode | Description | Phases |
|------|-------------|--------|
| **full** | Complete pipeline (default) | 1-5 |
| **read-only** | Extract tests only | 1, 5 |
| **golden-only** | Extract + normalize | 1, 2, 5 |
| **verify-only** | Green + verify (assumes golden suite exists) | 3, 4, 5 |

## When to Use

- Rewriting a system (e.g., Python → Rust)
- Creating compatible engines (e.g., vLLM vs TensorRT)
- Deep refactoring without breaking behavior
- Building "drop-in replacements"
- Migrating between frameworks or languages
- Substituting critical components

## Available Commands

### /golden-loop REFERENCE [OPTIONS]

Start a golden harvest loop.

```
/golden-loop ~/projects/vllm
/golden-loop ~/projects/vllm --target ~/projects/my-engine
/golden-loop ~/projects/vllm --mode golden-only
/golden-loop ~/projects/vllm --target ~/projects/my-engine --mode verify-only
```

**Options:**
- `--target <path>` — Target codebase (required for full and verify-only modes)
- `--mode <full|read-only|golden-only|verify-only>` — Pipeline mode (default: full)
- `--max-iterations <n>` — Max global iterations (default: 60)
- `--output-dir <path>` — Output directory (default: ./golden-output)
- `--completion-promise '<text>'` — Custom promise (default: "GOLDEN HARVEST COMPLETE")

### /golden-status

View current loop status.

### /golden-cancel

Cancel an active loop. Output files are preserved.

### /golden-help

Show help and available commands.

## Output Structure

```
golden-output/
├── golden.db                      SQLite database (source of truth)
├── harvested/
│   ├── test_catalog.md            Extracted test catalog
│   ├── fixture_inventory.md       Fixtures and test data
│   ├── contract_map.md            Behavioral contracts
│   └── by_domain/                 Tests grouped by domain
├── golden_suite/
│   ├── suite_manifest.md          Golden suite manifest
│   ├── portable_tests/            Normalized portable tests
│   └── by_domain/                 Suite organized by domain
├── green/
│   ├── progress.md                Implementation progress
│   ├── gap_analysis.md            Coverage gaps
│   └── test_results/              Pass/fail results
├── verify/
│   ├── differential_report.md     Differential testing report
│   ├── fuzz_results.md            Fuzz testing results
│   ├── benchmarks.md              Performance benchmarks
│   └── regression.md              Regression analysis
├── state/
│   └── meetings/                  Meeting minutes
└── figures/
    ├── compatibility_matrix.svg   Domain compatibility heatmap
    ├── test_progress.svg          Pass/fail over iterations
    ├── coverage_by_domain.svg     Coverage by domain
    └── differential_summary.svg   Match distribution
```

## Database

The plugin uses a SQLite database (`golden.db`) as the source of truth, managed via `golden_database.py`. It stores:
- Source tests extracted from reference with metadata
- Golden tests normalized and classified by domain
- Behavioral contracts with pre/postconditions
- Fixtures and test data with portability status
- Test run results (pass/fail/error/skip/timeout)
- Differential comparison results
- Coverage map by domain and area
- Quality gate scores per phase
- Agent coordination messages

## Agents

| Role | Agent | Specialty |
|------|-------|-----------|
| **Chief Harvester** | `chief-harvester` | Leads meetings, strategic decisions, task assignment |
| **Test Miner** | `test-miner` | Finds and extracts test files from reference |
| **Behavior Extractor** | `behavior-extractor` | Identifies behavioral contracts from tests |
| **Fixture Collector** | `fixture-collector` | Collects fixtures, test data, factories |
| **Contract Analyzer** | `contract-analyzer` | Maps implicit contracts and dependencies |
| **Suite Architect** | `suite-architect` | Designs golden suite structure |
| **Test Normalizer** | `test-normalizer` | Standardizes and portabilizes tests |
| **Portability Auditor** | `portability-auditor` | Audits implementation coupling |
| **Compatibility Coder** | `compatibility-coder` | Implements to pass golden tests |
| **Gap Detector** | `gap-detector` | Identifies coverage gaps |
| **Differential Tester** | `differential-tester` | Runs differential comparisons |
| **Fuzz Tester** | `fuzz-tester` | Edge case and fuzz testing |
| **Benchmark Runner** | `benchmark-runner` | Performance benchmarking |
| **Regression Validator** | `regression-validator` | Regression and stability testing |
| **Quality Evaluator** | `quality-evaluator` | Quality gates (keep/discard pattern) |
| **Report Writer** | `report-writer` | Final consolidation report |

## Technical Terms

| Term | Definition |
|------|-----------|
| **Golden Master Testing** | Using captured reference behavior as ground truth |
| **Test Harvesting** | Extracting tests from existing codebases |
| **Differential Testing** | Comparing outputs of two implementations |
| **Characterization Testing** | Capturing current behavior (even if buggy) |
| **Behavioral Contract** | What a system promises to do, independent of how |
