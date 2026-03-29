#!/bin/bash

# Golden Harvest Loop - Setup Script
# Creates state file and output directory for the golden master testing pipeline.

set -euo pipefail

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
REFERENCE_PARTS=()
TARGET_PARTS=()
MODE="full"
MAX_ITERATIONS=60
OUTPUT_DIR="./golden-output"
COMPLETION_PROMISE="GOLDEN HARVEST COMPLETE"
PARSING_TARGET=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Golden Harvest Loop - Autonomous Golden Master Testing Pipeline

USAGE:
  /golden-loop REFERENCE [--target TARGET] [OPTIONS]

ARGUMENTS:
  REFERENCE    Path to the reference codebase (source of tests)

OPTIONS:
  --target <path>              Path to the target codebase (new implementation)
                               If omitted, only READ and GOLDEN phases run
  --mode <full|read-only|golden-only|verify-only>
                               Pipeline mode (default: full)
  --max-iterations <n>         Max global iterations (default: 60)
  --output-dir <path>          Output directory (default: ./golden-output)
  --completion-promise '<text>' Promise phrase (default: "GOLDEN HARVEST COMPLETE")
  -h, --help                   Show this help message

DESCRIPTION:
  Starts an autonomous Golden Master Testing pipeline that iterates through
  5 phases: READ, GOLDEN, GREEN, VERIFY, REPORT.

  The agent extracts tests from a reference system, transforms them into
  a portable golden suite, drives implementation to pass those tests,
  validates behavioral equivalence via differential testing, and produces
  a comprehensive compatibility report.

MODES:
  full           Complete 5-phase pipeline (default). Requires --target.
  read-only      Only READ phase: extract and catalog tests (phases 1, 5).
  golden-only    READ + GOLDEN: extract and normalize suite (phases 1, 2, 5).
  verify-only    Assume golden suite exists, run GREEN + VERIFY (phases 3, 4, 5).
                 Requires --target.

PHASES:
  1. READ        Extract tests, fixtures, contracts from reference codebase
  2. GOLDEN      Normalize into portable golden suite, classify by domain
  3. GREEN       Drive new implementation to pass golden tests
  4. VERIFY      Differential testing, fuzz, benchmarks, regression
  5. REPORT      Consolidation: compatibility matrix, coverage, figures

EXAMPLES:
  /golden-loop ~/projects/vllm
  /golden-loop ~/projects/vllm --target ~/projects/my-engine
  /golden-loop ~/projects/vllm --target ~/projects/my-engine --mode full
  /golden-loop ~/projects/vllm --mode read-only
  /golden-loop ~/projects/vllm --mode golden-only --output-dir ./vllm-golden
  /golden-loop . --target ../new-impl --mode verify-only

OUTPUT:
  golden-output/
  ├── golden.db                    SQLite database (source of truth)
  ├── harvested/
  │   ├── test_catalog.md          Extracted test catalog
  │   ├── fixture_inventory.md     Fixtures and test data
  │   ├── contract_map.md          Behavioral contracts
  │   └── by_domain/               Tests grouped by domain
  ├── golden_suite/
  │   ├── suite_manifest.md        Golden suite manifest
  │   ├── portable_tests/          Normalized portable tests
  │   └── by_domain/               Suite organized by domain
  ├── green/
  │   ├── progress.md              Implementation progress
  │   ├── gap_analysis.md          Coverage gaps
  │   └── test_results/            Pass/fail results
  ├── verify/
  │   ├── differential_report.md   Differential testing report
  │   ├── fuzz_results.md          Fuzz testing results
  │   ├── benchmarks.md            Performance benchmarks
  │   └── regression.md            Regression analysis
  ├── state/
  │   └── meetings/                Meeting minutes
  └── figures/
HELP_EOF
      exit 0
      ;;
    --target)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --target requires a path argument" >&2
        exit 1
      fi
      TARGET_PARTS+=("$2")
      shift 2
      ;;
    --mode)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --mode requires an argument (full|read-only|golden-only|verify-only)" >&2
        exit 1
      fi
      case "$2" in
        full|read-only|golden-only|verify-only)
          MODE="$2"
          ;;
        *)
          echo "Error: --mode must be one of: full, read-only, golden-only, verify-only (got: '$2')" >&2
          exit 1
          ;;
      esac
      shift 2
      ;;
    --max-iterations)
      if [[ -z "${2:-}" ]] || ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: --max-iterations requires a positive integer (got: '${2:-}')" >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --output-dir)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --output-dir requires a path argument" >&2
        exit 1
      fi
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --completion-promise)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --completion-promise requires a text argument" >&2
        exit 1
      fi
      COMPLETION_PROMISE="$2"
      shift 2
      ;;
    *)
      REFERENCE_PARTS+=("$1")
      shift
      ;;
  esac
done

REFERENCE="${REFERENCE_PARTS[*]}"
TARGET="${TARGET_PARTS[*]:-}"

if [[ -z "$REFERENCE" ]]; then
  echo "Error: No reference codebase path provided" >&2
  echo "" >&2
  echo "   Examples:" >&2
  echo "     /golden-loop ~/projects/vllm" >&2
  echo "     /golden-loop ~/projects/vllm --target ~/projects/my-engine" >&2
  echo "" >&2
  echo "   For all options: /golden-loop --help" >&2
  exit 1
fi

# Resolve reference path
REFERENCE_PATH="$(cd "$REFERENCE" 2>/dev/null && pwd)" || {
  echo "Error: Reference path does not exist: $REFERENCE" >&2
  exit 1
}

# Resolve target path (if provided)
TARGET_PATH=""
if [[ -n "$TARGET" ]]; then
  TARGET_PATH="$(cd "$TARGET" 2>/dev/null && pwd)" || {
    echo "Error: Target path does not exist: $TARGET" >&2
    exit 1
  }
fi

# Validate mode requirements
if [[ "$MODE" == "full" ]] || [[ "$MODE" == "verify-only" ]]; then
  if [[ -z "$TARGET_PATH" ]]; then
    echo "Error: Mode '$MODE' requires --target <path> for the new implementation" >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Resolve prompt template
# ---------------------------------------------------------------------------
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMPT_TEMPLATE="$PLUGIN_ROOT/templates/golden-prompt.md"

if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
  echo "Error: Golden prompt template not found at $PROMPT_TEMPLATE" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Replace placeholders in template
# ---------------------------------------------------------------------------
GOLDEN_PROMPT=$(sed \
  -e "s|{{REFERENCE_PATH}}|$REFERENCE_PATH|g" \
  -e "s|{{TARGET_PATH}}|$TARGET_PATH|g" \
  -e "s|{{OUTPUT_DIR}}|$OUTPUT_DIR|g" \
  -e "s|{{COMPLETION_PROMISE}}|$COMPLETION_PROMISE|g" \
  -e "s|{{PLUGIN_ROOT}}|$PLUGIN_ROOT|g" \
  -e "s|{{MODE}}|$MODE|g" \
  "$PROMPT_TEMPLATE")

# ---------------------------------------------------------------------------
# Create output directory structure
# ---------------------------------------------------------------------------
mkdir -p "$OUTPUT_DIR/harvested/by_domain"
mkdir -p "$OUTPUT_DIR/golden_suite/portable_tests"
mkdir -p "$OUTPUT_DIR/golden_suite/by_domain"
mkdir -p "$OUTPUT_DIR/green/test_results"
mkdir -p "$OUTPUT_DIR/verify"
mkdir -p "$OUTPUT_DIR/state/meetings"
mkdir -p "$OUTPUT_DIR/figures"

# ---------------------------------------------------------------------------
# Initialize SQLite database
# ---------------------------------------------------------------------------
if [[ ! -f "$OUTPUT_DIR/golden.db" ]]; then
  python3 "$PLUGIN_ROOT/scripts/golden_database.py" --db-path "$OUTPUT_DIR/golden.db" init > /dev/null
fi

# ---------------------------------------------------------------------------
# Create state file
# ---------------------------------------------------------------------------
mkdir -p .claude

cat > .claude/golden-loop.local.md <<EOF
---
active: true
reference: "$REFERENCE_PATH"
target: "$TARGET_PATH"
current_phase: 1
phase_name: "read"
phase_iteration: 1
global_iteration: 1
max_global_iterations: $MAX_ITERATIONS
completion_promise: "$COMPLETION_PROMISE"
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
output_dir: "$OUTPUT_DIR"
mode: "$MODE"
source_tests_extracted: 0
golden_tests_created: 0
contracts_mapped: 0
tests_passing: 0
tests_failing: 0
differential_matches: 0
differential_mismatches: 0
---

$GOLDEN_PROMPT
EOF

# ---------------------------------------------------------------------------
# Output setup message
# ---------------------------------------------------------------------------
MODE_LABEL=""
case "$MODE" in
  full)          MODE_LABEL="Full (complete 5-phase pipeline)" ;;
  read-only)     MODE_LABEL="Read-only (extract tests only: phases 1, 5)" ;;
  golden-only)   MODE_LABEL="Golden-only (extract + normalize: phases 1, 2, 5)" ;;
  verify-only)   MODE_LABEL="Verify-only (green + verify: phases 3, 4, 5)" ;;
esac

cat <<EOF
Golden Harvest Loop activated!

Mode: $MODE_LABEL
Reference: $REFERENCE_PATH
Target: ${TARGET_PATH:-"(none — read/golden only)"}
Output: $OUTPUT_DIR/
Max iterations: $MAX_ITERATIONS
Completion promise: $COMPLETION_PROMISE

Pipeline phases:
  1. READ      -- Extract tests, fixtures, contracts from reference
  2. GOLDEN    -- Normalize into portable golden suite by domain
  3. GREEN     -- Drive implementation to pass golden tests
  4. VERIFY    -- Differential testing, fuzz, benchmarks, regression
  5. REPORT    -- Consolidation: compatibility matrix, coverage, figures

State: .claude/golden-loop.local.md
Monitor: grep 'current_phase\|global_iteration\|source_tests\|golden_tests\|tests_passing' .claude/golden-loop.local.md

EOF

echo "==============================================================="
echo "CRITICAL -- Completion Promise"
echo "==============================================================="
echo ""
echo "To complete the harvest, output this EXACT text:"
echo "  <promise>$COMPLETION_PROMISE</promise>"
echo ""
echo "ONLY output this when the golden harvest is GENUINELY complete."
echo "Do NOT output false promises to exit the loop."
echo "==============================================================="
echo ""
echo "Starting Phase 1: READ..."
echo ""
echo "$GOLDEN_PROMPT"
