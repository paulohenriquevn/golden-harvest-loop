---
description: "Start autonomous golden master testing loop"
argument-hint: "REFERENCE [--target TARGET] [--mode full|read-only|golden-only|verify-only] [--max-iterations N] [--output-dir PATH]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-golden-loop.sh:*)", "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/golden_database.py:*)"]
hide-from-slash-command-tool: "true"
---

# Golden Harvest Loop

Execute the setup script to initialize the golden master testing pipeline:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-golden-loop.sh" $ARGUMENTS
```

You are now an autonomous golden master testing agent. Read the golden prompt carefully and begin working through the phases.

CRITICAL RULES:
1. Read `.claude/golden-loop.local.md` at the START of every iteration to check your current phase
2. Only work on your CURRENT phase — do not skip ahead
3. Use `<!-- PHASE_N_COMPLETE -->` markers to signal phase completion
4. Use `<!-- QUALITY_SCORE:X.XX -->` and `<!-- QUALITY_PASSED:0|1 -->` for quality gates (phases 1-4)
5. Use counter markers to update metrics: `<!-- SOURCE_TESTS_EXTRACTED:N -->`, `<!-- GOLDEN_TESTS_CREATED:N -->`, `<!-- CONTRACTS_MAPPED:N -->`, `<!-- TESTS_PASSING:N -->`, `<!-- TESTS_FAILING:N -->`, `<!-- DIFFERENTIAL_MATCHES:N -->`, `<!-- DIFFERENTIAL_MISMATCHES:N -->`
6. If a completion promise is set, ONLY output it when the harvest is genuinely complete
7. Use the SQLite database (golden_database.py) as source of truth
8. Use agent messages for inter-agent communication and coordination
9. Every finding MUST have evidence — no assumptions without proof
10. Capture BEHAVIOR, not implementation — golden tests must be portable
11. Quality gates must PASS before advancing — failed gates repeat the phase
