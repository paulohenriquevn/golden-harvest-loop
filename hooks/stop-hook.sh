#!/bin/bash

# Golden Harvest Loop - Phase-Aware Stop Hook
# Extends Ralph Wiggum's stop hook with a 5-phase golden master testing pipeline.
# Phases: READ → GOLDEN → GREEN → VERIFY → REPORT
# Key feature: LOOP-BACK mechanism from VERIFY → GOLDEN for re-normalization cycles.

set -euo pipefail

HOOK_INPUT=$(cat)

STATE_FILE=".claude/golden-loop.local.md"

if [[ ! -f "$STATE_FILE" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Helper: safe SQLite query via Python with parameterized path
# ---------------------------------------------------------------------------
safe_db_count() {
  local db_file="$1"
  local sql_query="$2"
  if [[ ! -f "$db_file" ]]; then
    echo "0"
    return
  fi
  local result
  result=$(python3 -c "
import sqlite3, sys
try:
    db = sqlite3.connect(sys.argv[1])
    print(db.execute(sys.argv[2]).fetchone()[0])
    db.close()
except Exception as e:
    print('DB_ERROR:' + str(e), file=sys.stderr)
    print('-1')
" "$db_file" "$sql_query" 2>&1)

  if [[ "$result" == "-1" ]] || [[ -z "$result" ]]; then
    echo "-1"
  else
    echo "$result"
  fi
}

# ---------------------------------------------------------------------------
# Parse state file frontmatter
# ---------------------------------------------------------------------------
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE")

parse_field() {
  local field="$1"
  echo "$FRONTMATTER" | grep "^${field}:" | sed "s/${field}: *//" | sed 's/^"\(.*\)"$/\1/'
}

CURRENT_PHASE=$(parse_field "current_phase")
PHASE_NAME=$(parse_field "phase_name")
PHASE_ITERATION=$(parse_field "phase_iteration")
GLOBAL_ITERATION=$(parse_field "global_iteration")
MAX_GLOBAL_ITERATIONS=$(parse_field "max_global_iterations")
COMPLETION_PROMISE=$(parse_field "completion_promise")
REFERENCE=$(parse_field "reference")
TARGET=$(parse_field "target")
OUTPUT_DIR=$(parse_field "output_dir")
MODE=$(parse_field "mode")
SOURCE_TESTS_EXTRACTED=$(parse_field "source_tests_extracted")
GOLDEN_TESTS_CREATED=$(parse_field "golden_tests_created")
CONTRACTS_MAPPED=$(parse_field "contracts_mapped")
TESTS_PASSING=$(parse_field "tests_passing")
TESTS_FAILING=$(parse_field "tests_failing")
DIFFERENTIAL_MATCHES=$(parse_field "differential_matches")
DIFFERENTIAL_MISMATCHES=$(parse_field "differential_mismatches")

# Phase max iterations
declare -A PHASE_MAX_ITER
PHASE_MAX_ITER[1]=4   # read
PHASE_MAX_ITER[2]=3   # golden
PHASE_MAX_ITER[3]=5   # green
PHASE_MAX_ITER[4]=4   # verify
PHASE_MAX_ITER[5]=2   # report

# Phase names lookup
declare -A PHASE_NAMES
PHASE_NAMES[1]="read"
PHASE_NAMES[2]="golden"
PHASE_NAMES[3]="green"
PHASE_NAMES[4]="verify"
PHASE_NAMES[5]="report"

# Quality gate: phases that require quality evaluation before advancing
declare -A PHASE_QUALITY_GATE
PHASE_QUALITY_GATE[1]=1   # read — quality matters
PHASE_QUALITY_GATE[2]=1   # golden — quality matters
PHASE_QUALITY_GATE[3]=1   # green — quality matters
PHASE_QUALITY_GATE[4]=1   # verify — quality matters
PHASE_QUALITY_GATE[5]=0   # report — final pass, no gate

# Mode-specific phase skipping
# read-only: skip phases 2 (golden), 3 (green), 4 (verify)
# golden-only: skip phases 3 (green), 4 (verify)
# verify-only: skip phases 1 (read), 2 (golden)
declare -A SKIP_PHASES
if [[ "$MODE" == "read-only" ]]; then
  SKIP_PHASES[2]=1
  SKIP_PHASES[3]=1
  SKIP_PHASES[4]=1
elif [[ "$MODE" == "golden-only" ]]; then
  SKIP_PHASES[3]=1
  SKIP_PHASES[4]=1
elif [[ "$MODE" == "verify-only" ]]; then
  SKIP_PHASES[1]=1
  SKIP_PHASES[2]=1
fi

# ---------------------------------------------------------------------------
# Validate numeric fields
# ---------------------------------------------------------------------------
validate_numeric() {
  local field_name="$1"
  local field_value="$2"
  if [[ ! "$field_value" =~ ^[0-9]+$ ]]; then
    echo "⚠️  Golden loop: State file corrupted" >&2
    echo "   File: $STATE_FILE" >&2
    echo "   Problem: '$field_name' is not a valid number (got: '$field_value')" >&2
    echo "   Golden loop is stopping. Run /golden-loop again to start fresh." >&2
    rm "$STATE_FILE"
    exit 0
  fi
}

validate_numeric "current_phase" "$CURRENT_PHASE"
validate_numeric "phase_iteration" "$PHASE_ITERATION"
validate_numeric "global_iteration" "$GLOBAL_ITERATION"
validate_numeric "max_global_iterations" "$MAX_GLOBAL_ITERATIONS"

# Validate bounds — current_phase must be 1-5
if [[ $CURRENT_PHASE -lt 1 ]] || [[ $CURRENT_PHASE -gt 5 ]]; then
  echo "⚠️  Golden loop: State file corrupted — current_phase=$CURRENT_PHASE (must be 1-5)" >&2
  rm "$STATE_FILE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Check global iteration limit
# ---------------------------------------------------------------------------
if [[ $MAX_GLOBAL_ITERATIONS -gt 0 ]] && [[ $GLOBAL_ITERATION -ge $MAX_GLOBAL_ITERATIONS ]]; then
  echo "🛑 Golden loop: Max global iterations ($MAX_GLOBAL_ITERATIONS) reached."
  echo "   Reference: $REFERENCE"
  echo "   Target: ${TARGET:-'(none)'}"
  echo "   Final phase: $CURRENT_PHASE ($PHASE_NAME)"
  echo "   Source tests: $SOURCE_TESTS_EXTRACTED | Golden tests: $GOLDEN_TESTS_CREATED"
  echo "   Contracts: $CONTRACTS_MAPPED"
  echo "   Tests: passing=$TESTS_PASSING failing=$TESTS_FAILING"
  echo "   Differential: matches=$DIFFERENTIAL_MATCHES mismatches=$DIFFERENTIAL_MISMATCHES"
  rm "$STATE_FILE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Read transcript and extract last assistant output
# ---------------------------------------------------------------------------
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')

if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "⚠️  Golden loop: Transcript file not found at $TRANSCRIPT_PATH" >&2
  rm "$STATE_FILE"
  exit 0
fi

if ! grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  echo "⚠️  Golden loop: No assistant messages found in transcript" >&2
  rm "$STATE_FILE"
  exit 0
fi

LAST_LINE=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -1)
if [[ -z "$LAST_LINE" ]]; then
  echo "⚠️  Golden loop: Failed to extract last assistant message" >&2
  rm "$STATE_FILE"
  exit 0
fi

LAST_OUTPUT=$(echo "$LAST_LINE" | jq -r '
  .message.content |
  map(select(.type == "text")) |
  map(.text) |
  join("\n")
' 2>&1)

if [[ $? -ne 0 ]] || [[ -z "$LAST_OUTPUT" ]]; then
  echo "⚠️  Golden loop: Failed to parse assistant message" >&2
  rm "$STATE_FILE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Check for completion promise
# ---------------------------------------------------------------------------
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")

  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
    echo "✅ Golden loop complete: <promise>$COMPLETION_PROMISE</promise>"
    echo "   Reference: $REFERENCE"
    echo "   Target: ${TARGET:-'(none)'}"
    echo "   Total iterations: $GLOBAL_ITERATION"
    echo "   Final phase: $CURRENT_PHASE ($PHASE_NAME)"
    echo "   Source tests: $SOURCE_TESTS_EXTRACTED | Golden tests: $GOLDEN_TESTS_CREATED"
    echo "   Contracts: $CONTRACTS_MAPPED"
    echo "   Tests: passing=$TESTS_PASSING failing=$TESTS_FAILING"
    echo "   Differential: matches=$DIFFERENTIAL_MATCHES mismatches=$DIFFERENTIAL_MISMATCHES"
    echo "   Output: $OUTPUT_DIR/"
    rm "$STATE_FILE"
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Detect phase completion markers and update counters from output
# ---------------------------------------------------------------------------
PHASE_ADVANCED=false
FORCED_ADVANCE=false

# Check for explicit phase completion marker: <!-- PHASE_N_COMPLETE -->
if echo "$LAST_OUTPUT" | grep -qE "<!--\s*PHASE_${CURRENT_PHASE}_COMPLETE\s*-->"; then
  PHASE_ADVANCED=true
fi

# Update counters from output markers (if present)
NEW_SOURCE_TESTS=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*SOURCE_TESTS_EXTRACTED:(\d+)\s*-->' | grep -oP '\d+' | tail -1 || echo "")
NEW_GOLDEN_TESTS=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*GOLDEN_TESTS_CREATED:(\d+)\s*-->' | grep -oP '\d+' | tail -1 || echo "")
NEW_CONTRACTS=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*CONTRACTS_MAPPED:(\d+)\s*-->' | grep -oP '\d+' | tail -1 || echo "")
NEW_PASSING=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*TESTS_PASSING:(\d+)\s*-->' | grep -oP '\d+' | tail -1 || echo "")
NEW_FAILING=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*TESTS_FAILING:(\d+)\s*-->' | grep -oP '\d+' | tail -1 || echo "")
NEW_DIFF_MATCH=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*DIFFERENTIAL_MATCHES:(\d+)\s*-->' | grep -oP '\d+' | tail -1 || echo "")
NEW_DIFF_MISMATCH=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*DIFFERENTIAL_MISMATCHES:(\d+)\s*-->' | grep -oP '\d+' | tail -1 || echo "")

[[ -n "$NEW_SOURCE_TESTS" ]] && SOURCE_TESTS_EXTRACTED="$NEW_SOURCE_TESTS"
[[ -n "$NEW_GOLDEN_TESTS" ]] && GOLDEN_TESTS_CREATED="$NEW_GOLDEN_TESTS"
[[ -n "$NEW_CONTRACTS" ]] && CONTRACTS_MAPPED="$NEW_CONTRACTS"
[[ -n "$NEW_PASSING" ]] && TESTS_PASSING="$NEW_PASSING"
[[ -n "$NEW_FAILING" ]] && TESTS_FAILING="$NEW_FAILING"
[[ -n "$NEW_DIFF_MATCH" ]] && DIFFERENTIAL_MATCHES="$NEW_DIFF_MATCH"
[[ -n "$NEW_DIFF_MISMATCH" ]] && DIFFERENTIAL_MISMATCHES="$NEW_DIFF_MISMATCH"

# ---------------------------------------------------------------------------
# Quality gate: check if phase completion passed quality evaluation
# ---------------------------------------------------------------------------
QUALITY_FAILED=false

if [[ "$PHASE_ADVANCED" == "true" ]]; then
  HAS_GATE=${PHASE_QUALITY_GATE[$CURRENT_PHASE]:-0}

  if [[ "$HAS_GATE" == "1" ]]; then
    QUALITY_SCORE=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*QUALITY_SCORE:([\d.]+)\s*-->' | grep -oP '[\d.]+' | tail -1 || echo "")
    QUALITY_PASSED=$(echo "$LAST_OUTPUT" | grep -oP '<!--\s*QUALITY_PASSED:(\d)\s*-->' | grep -oP '\d' | tail -1 || echo "")

    if [[ -z "$QUALITY_PASSED" ]]; then
      PHASE_ADVANCED=false
      QUALITY_FAILED=true
    elif [[ "$QUALITY_PASSED" == "0" ]]; then
      PHASE_ADVANCED=false
      QUALITY_FAILED=true
    fi
  fi
fi

# Check for phase timeout (forced advancement)
CURRENT_PHASE_MAX=${PHASE_MAX_ITER[$CURRENT_PHASE]:-3}
if [[ "$PHASE_ADVANCED" != "true" ]] && [[ "$QUALITY_FAILED" != "true" ]] && [[ $PHASE_ITERATION -ge $CURRENT_PHASE_MAX ]]; then
  PHASE_ADVANCED=true
  FORCED_ADVANCE=true
fi

# ---------------------------------------------------------------------------
# HARD BLOCKS — verify mandatory work BEFORE allowing phase advancement
# ---------------------------------------------------------------------------
HARD_BLOCK=false
HARD_BLOCK_MSG=""

if [[ "$PHASE_ADVANCED" == "true" ]]; then
  if [[ "$OUTPUT_DIR" == ./* ]] || [[ "$OUTPUT_DIR" != /* ]]; then
    ABS_OUTPUT_DIR="$(pwd)/$OUTPUT_DIR"
  else
    ABS_OUTPUT_DIR="$OUTPUT_DIR"
  fi
  DB_PATH="$ABS_OUTPUT_DIR/golden.db"

  # HARD BLOCK 1: Phase 1→2 — source_tests must have entries
  if [[ $CURRENT_PHASE -eq 1 ]] && [[ "$HARD_BLOCK" != "true" ]]; then
    TEST_COUNT=$(safe_db_count "$DB_PATH" "SELECT COUNT(*) FROM source_tests")
    if [[ "$TEST_COUNT" == "-1" ]]; then
      echo "⚠️  Golden loop: Database error checking hard block for phase 1 (DB: $DB_PATH)" >&2
      TEST_COUNT=0
    fi
    if [[ "$TEST_COUNT" -eq 0 ]]; then
      HARD_BLOCK=true
      HARD_BLOCK_MSG="🚫 HARD BLOCK: Phase 1 (READ) cannot advance — 0 source tests extracted (DB: $DB_PATH). You MUST extract tests from the reference codebase before advancing."
    fi
  fi

  # HARD BLOCK 2: Phase 2→3 — golden_tests must have entries
  if [[ $CURRENT_PHASE -eq 2 ]] && [[ "$HARD_BLOCK" != "true" ]]; then
    GOLDEN_COUNT=$(safe_db_count "$DB_PATH" "SELECT COUNT(*) FROM golden_tests")
    CONTRACT_COUNT=$(safe_db_count "$DB_PATH" "SELECT COUNT(*) FROM contracts")
    if [[ "$GOLDEN_COUNT" == "-1" ]]; then
      echo "⚠️  Golden loop: Database error checking hard block for phase 2 (DB: $DB_PATH)" >&2
      GOLDEN_COUNT=0
    fi
    if [[ "$GOLDEN_COUNT" -eq 0 ]]; then
      HARD_BLOCK=true
      HARD_BLOCK_MSG="🚫 HARD BLOCK: Phase 2 (GOLDEN) cannot advance — 0 golden tests created (DB: $DB_PATH). You MUST normalize source tests into golden tests before advancing."
    fi
  fi

  # HARD BLOCK 3: Phase 3→4 — test_runs must have entries
  if [[ $CURRENT_PHASE -eq 3 ]] && [[ "$HARD_BLOCK" != "true" ]]; then
    RUN_COUNT=$(safe_db_count "$DB_PATH" "SELECT COUNT(*) FROM test_runs WHERE phase='green'")
    if [[ "$RUN_COUNT" == "-1" ]]; then
      echo "⚠️  Golden loop: Database error checking hard block for phase 3 (DB: $DB_PATH)" >&2
      RUN_COUNT=0
    fi
    if [[ "$RUN_COUNT" -eq 0 ]]; then
      HARD_BLOCK=true
      HARD_BLOCK_MSG="🚫 HARD BLOCK: Phase 3 (GREEN) cannot advance — 0 test runs recorded (DB: $DB_PATH). You MUST run golden tests against the target and record results before advancing."
    fi
  fi

  # HARD BLOCK 4: Phase 4→5 — differential_results must have entries
  if [[ $CURRENT_PHASE -eq 4 ]] && [[ "$HARD_BLOCK" != "true" ]]; then
    DIFF_COUNT=$(safe_db_count "$DB_PATH" "SELECT COUNT(*) FROM differential_results")
    if [[ "$DIFF_COUNT" == "-1" ]]; then
      echo "⚠️  Golden loop: Database error checking hard block for phase 4 (DB: $DB_PATH)" >&2
      DIFF_COUNT=0
    fi
    if [[ "$DIFF_COUNT" -eq 0 ]]; then
      HARD_BLOCK=true
      HARD_BLOCK_MSG="🚫 HARD BLOCK: Phase 4 (VERIFY) cannot advance — 0 differential results recorded (DB: $DB_PATH). You MUST run differential testing and record comparison results before advancing."
    fi
  fi

  if [[ "$HARD_BLOCK" == "true" ]]; then
    PHASE_ADVANCED=false
    FORCED_ADVANCE=false
    QUALITY_FAILED=false
    echo "🚫 HARD BLOCK ACTIVATED — Phase $CURRENT_PHASE cannot advance. DB: $DB_PATH" >&2
  fi
fi

# ---------------------------------------------------------------------------
# LOOP-BACK MECHANISM — verify → golden for re-normalization cycles
# When Phase 4 (verify) outputs <!-- LOOP_BACK_TO_GOLDEN -->, loop back
# to Phase 2 (golden) if budget allows.
# ---------------------------------------------------------------------------
LOOP_BACK=false

if [[ "$PHASE_ADVANCED" == "true" ]] && [[ $CURRENT_PHASE -eq 4 ]]; then
  if echo "$LAST_OUTPUT" | grep -qE "<!--\s*LOOP_BACK_TO_GOLDEN\s*-->"; then
    REMAINING=$((MAX_GLOBAL_ITERATIONS - GLOBAL_ITERATION))
    if [[ $REMAINING -gt 5 ]]; then
      LOOP_BACK=true
      CURRENT_PHASE=2
      PHASE_NAME="golden"
      PHASE_ITERATION=0
      PHASE_ADVANCED=false
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Advance phase if needed
# ---------------------------------------------------------------------------
MAX_PHASE=5

if [[ "$PHASE_ADVANCED" == "true" ]]; then
  if [[ $CURRENT_PHASE -ge $MAX_PHASE ]]; then
    echo "🛑 Golden loop: All $MAX_PHASE phases complete but no completion promise detected."
    echo "   Reference: $REFERENCE"
    echo "   Target: ${TARGET:-'(none)'}"
    echo "   Source tests: $SOURCE_TESTS_EXTRACTED | Golden tests: $GOLDEN_TESTS_CREATED"
    echo "   Tests: passing=$TESTS_PASSING failing=$TESTS_FAILING"
    echo "   Differential: matches=$DIFFERENTIAL_MATCHES mismatches=$DIFFERENTIAL_MISMATCHES"
    echo "   Output should be in: $OUTPUT_DIR/"
    rm "$STATE_FILE"
    exit 0
  fi

  CURRENT_PHASE=$((CURRENT_PHASE + 1))
  PHASE_NAME="${PHASE_NAMES[$CURRENT_PHASE]}"
  PHASE_ITERATION=0

  # Skip phases based on mode
  while [[ ${SKIP_PHASES[$CURRENT_PHASE]:-0} -eq 1 ]] && [[ $CURRENT_PHASE -lt $MAX_PHASE ]]; do
    CURRENT_PHASE=$((CURRENT_PHASE + 1))
    PHASE_NAME="${PHASE_NAMES[$CURRENT_PHASE]}"
  done
fi

# ---------------------------------------------------------------------------
# Increment counters
# ---------------------------------------------------------------------------
NEXT_GLOBAL=$((GLOBAL_ITERATION + 1))
NEXT_PHASE_ITER=$((PHASE_ITERATION + 1))

# ---------------------------------------------------------------------------
# Extract prompt text (everything after second ---)
# ---------------------------------------------------------------------------
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$STATE_FILE")

if [[ -z "$PROMPT_TEXT" ]]; then
  echo "⚠️  Golden loop: No prompt text found in state file" >&2
  rm "$STATE_FILE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Update state file atomically
# ---------------------------------------------------------------------------
TEMP_FILE=$(mktemp "${STATE_FILE}.tmp.XXXXXX")
cat > "$TEMP_FILE" <<EOF
---
active: true
reference: "$REFERENCE"
target: "$TARGET"
current_phase: $CURRENT_PHASE
phase_name: "$PHASE_NAME"
phase_iteration: $NEXT_PHASE_ITER
global_iteration: $NEXT_GLOBAL
max_global_iterations: $MAX_GLOBAL_ITERATIONS
completion_promise: "$(echo "$COMPLETION_PROMISE" | sed 's/"/\\"/g')"
started_at: "$(parse_field "started_at")"
output_dir: "$OUTPUT_DIR"
mode: "$MODE"
source_tests_extracted: $SOURCE_TESTS_EXTRACTED
golden_tests_created: $GOLDEN_TESTS_CREATED
contracts_mapped: $CONTRACTS_MAPPED
tests_passing: $TESTS_PASSING
tests_failing: $TESTS_FAILING
differential_matches: $DIFFERENTIAL_MATCHES
differential_mismatches: $DIFFERENTIAL_MISMATCHES
---

$PROMPT_TEXT
EOF
mv "$TEMP_FILE" "$STATE_FILE"

# ---------------------------------------------------------------------------
# Build system message with phase context
# ---------------------------------------------------------------------------
PHASE_MAX_FOR_CURRENT=${PHASE_MAX_ITER[$CURRENT_PHASE]:-3}

SYSTEM_MSG="🧬 Golden Loop | Phase $CURRENT_PHASE/5: $PHASE_NAME | Phase iter $NEXT_PHASE_ITER/$PHASE_MAX_FOR_CURRENT | Global iter $NEXT_GLOBAL"
SYSTEM_MSG="$SYSTEM_MSG | Mode: $MODE"
SYSTEM_MSG="$SYSTEM_MSG | Source: $SOURCE_TESTS_EXTRACTED | Golden: $GOLDEN_TESTS_CREATED | Contracts: $CONTRACTS_MAPPED"
SYSTEM_MSG="$SYSTEM_MSG | Tests: pass=$TESTS_PASSING fail=$TESTS_FAILING"
SYSTEM_MSG="$SYSTEM_MSG | Diff: match=$DIFFERENTIAL_MATCHES mismatch=$DIFFERENTIAL_MISMATCHES"

if [[ "$FORCED_ADVANCE" == "true" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | ⚠️ Previous phase timed out — forced advancement to $PHASE_NAME"
fi

if [[ "$QUALITY_FAILED" == "true" ]]; then
  if [[ -n "${QUALITY_SCORE:-}" ]]; then
    SYSTEM_MSG="$SYSTEM_MSG | ❌ Quality gate FAILED (score: $QUALITY_SCORE) — repeating phase. Review evaluator feedback and improve output."
  else
    SYSTEM_MSG="$SYSTEM_MSG | ❌ Quality gate REQUIRED but no quality evaluation found — you MUST run the quality-evaluator agent and emit <!-- QUALITY_SCORE:X.XX --> <!-- QUALITY_PASSED:1 --> markers before this phase can advance."
  fi
fi

if [[ "$HARD_BLOCK" == "true" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | $HARD_BLOCK_MSG"
fi

if [[ "$LOOP_BACK" == "true" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | 🔄 LOOP-BACK: Returning to GOLDEN phase for re-normalization based on VERIFY findings"
fi

if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  SYSTEM_MSG="$SYSTEM_MSG | To finish: <promise>$COMPLETION_PROMISE</promise> (ONLY when TRUE)"
fi

# ---------------------------------------------------------------------------
# Block exit and re-inject prompt
# ---------------------------------------------------------------------------
jq -n \
  --arg prompt "$PROMPT_TEXT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
