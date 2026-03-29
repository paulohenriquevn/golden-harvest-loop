# Golden Harvest Report — [PROJECT_NAME]

**Date:** [DATE]
**Reference:** [REFERENCE_PATH]
**Target:** [TARGET_PATH]
**Mode:** [MODE]
**Total Iterations:** [N]

---

## 1. Executive Summary

### Compatibility Score
- **Overall:** X% (N/M golden tests passing)
- **Critical tests:** X% passing
- **High tests:** X% passing

### Key Metrics
| Metric | Value |
|--------|-------|
| Source tests extracted | N |
| Golden tests created | N |
| Contracts mapped | N |
| Tests passing | N |
| Tests failing | N |
| Differential matches | N |
| Differential mismatches | N |

### Verdict
[One paragraph summary: is the target compatible? What are the major gaps?]

---

## 2. Reference System Profile

### Architecture
[Brief description of reference system architecture]

### Technology Stack
[Languages, frameworks, databases, etc.]

### Test Landscape
| Category | Count |
|----------|-------|
| Unit tests | N |
| Integration tests | N |
| E2E tests | N |
| Benchmarks | N |
| Total | N |

---

## 3. Harvest Summary (Phase 1: READ)

### Tests Extracted by Domain
| Domain | Count | Types |
|--------|-------|-------|
| [domain] | N | unit, integration |
| ... | ... | ... |

### Contracts Identified
| Contract | Domain | Type |
|----------|--------|------|
| [name] | [domain] | function/api/protocol |
| ... | ... | ... |

### Fixtures Collected
| Fixture | Domain | Portable? |
|---------|--------|-----------|
| [name] | [domain] | Yes/No |
| ... | ... | ... |

---

## 4. Golden Suite Overview (Phase 2: GOLDEN)

### Suite Composition
| Domain | Critical | High | Medium | Low | Total |
|--------|----------|------|--------|-----|-------|
| [domain] | N | N | N | N | N |
| ... | ... | ... | ... | ... | ... |
| **Total** | N | N | N | N | N |

### Portability Audit
- Tests audited: N
- Passed: N
- Warnings: N
- Blocked: N

---

## 5. Compatibility Results (Phase 3: GREEN)

### Pass/Fail by Domain
| Domain | Pass | Fail | Error | Skip | Rate |
|--------|------|------|-------|------|------|
| [domain] | N | N | N | N | X% |
| ... | ... | ... | ... | ... | ... |
| **Total** | N | N | N | N | X% |

### Progress Over Iterations
[Chart or table showing pass rate improvement per iteration]

### Notable Failures
| Golden Test | Status | Root Cause |
|-------------|--------|------------|
| [test_id] | fail | [reason] |
| ... | ... | ... |

---

## 6. Differential Analysis (Phase 4: VERIFY)

### Match Summary
| Status | Count | Percentage |
|--------|-------|------------|
| Exact match | N | X% |
| Within tolerance | N | X% |
| Mismatch | N | X% |
| Error | N | X% |

### Mismatch Analysis
| Golden Test | Category | Root Cause |
|-------------|----------|------------|
| [test_id] | real_divergence/tolerance_issue/bug | [details] |
| ... | ... | ... |

---

## 7. Coverage Analysis

### By Domain
| Domain | Behaviors | Covered | Coverage |
|--------|-----------|---------|----------|
| [domain] | N | N | X% |
| ... | ... | ... | ... |

### Identified Gaps
| Domain | Gap | Severity |
|--------|-----|----------|
| [domain] | [description] | high/medium/low |
| ... | ... | ... |

---

## 8. Performance Comparison

### Execution Time (ms)
| Test Category | Reference p50 | Target p50 | Ratio |
|---------------|---------------|------------|-------|
| [category] | N | N | X.Xx |
| ... | ... | ... | ... |

---

## 9. Edge Cases & Robustness

### Fuzz Testing Results
[Summary of fuzz testing findings]

### Boundary Behavior
[Notable boundary behavior differences]

---

## 10. Risk Assessment

### High Risk Areas
| Area | Risk | Evidence |
|------|------|----------|
| [area] | [description] | [evidence] |
| ... | ... | ... |

### Unverified Behaviors
[Behaviors in reference not captured by golden suite]

---

## 11. Recommendations

### P1 — Critical (fix before production)
1. [recommendation with evidence]

### P2 — High (fix soon)
1. [recommendation with evidence]

### P3 — Medium (address in next iteration)
1. [recommendation with evidence]

### P4 — Low (backlog)
1. [recommendation with evidence]

---

## 12. Compatibility Matrix

| Domain | Behavior | Status | Notes |
|--------|----------|--------|-------|
| [domain] | [behavior] | pass/fail/partial | [notes] |
| ... | ... | ... | ... |

---

## Appendix A: Quality Gate Scores

| Phase | Score | Decision |
|-------|-------|----------|
| READ | 0.XX | PASS/FAIL |
| GOLDEN | 0.XX | PASS/FAIL |
| GREEN | 0.XX | PASS/FAIL |
| VERIFY | 0.XX | PASS/FAIL |

## Appendix B: Iteration Timeline

| Iteration | Phase | Key Action | Outcome |
|-----------|-------|------------|---------|
| 1 | READ | Initial scan | N tests found |
| ... | ... | ... | ... |
