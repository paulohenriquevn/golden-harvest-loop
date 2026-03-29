# Changelog

## [Unreleased]

### Added
- Initial plugin structure with 5-phase pipeline (READ, GOLDEN, GREEN, VERIFY, REPORT)
- 16 specialist agents for autonomous test harvesting and compatibility validation
- SQLite database manager (`golden_database.py`) with tables for source tests, golden tests, contracts, fixtures, test runs, differential results, and coverage maps
- Phase-aware stop hook with hard blocks, quality gates, and loop-back mechanism
- 4 pipeline modes: full, read-only, golden-only, verify-only
- Quality gate system with phase-specific rubrics (Autoresearch keep/discard pattern)
- Loop-back mechanism from VERIFY to GOLDEN for re-normalization cycles
- Report template with compatibility matrix, coverage analysis, and differential summary
- Commands: `/golden-loop`, `/golden-status`, `/golden-cancel`, `/golden-help`
