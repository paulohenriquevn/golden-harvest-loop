#!/usr/bin/env python3
"""Golden Harvest Loop — SQLite database manager.

Manages source tests, golden tests, contracts, fixtures, test runs,
differential results, coverage maps, quality scores, and agent messages.
"""

import argparse
import json
import sqlite3
import sys
from datetime import datetime, timezone

SCHEMA = """
CREATE TABLE IF NOT EXISTS source_tests (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    source_project TEXT NOT NULL,
    file_path TEXT NOT NULL,
    test_type TEXT NOT NULL,
    domain TEXT,
    language TEXT,
    framework TEXT,
    code TEXT NOT NULL,
    fixtures_used TEXT DEFAULT '[]',
    mocks_used TEXT DEFAULT '[]',
    dependencies TEXT DEFAULT '[]',
    behavioral_contract TEXT,
    extraction_status TEXT DEFAULT 'raw',
    rejection_reason TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS golden_tests (
    id TEXT PRIMARY KEY,
    source_test_id TEXT REFERENCES source_tests(id),
    name TEXT NOT NULL,
    domain TEXT NOT NULL,
    test_type TEXT NOT NULL,
    description TEXT,
    input_spec TEXT NOT NULL,
    expected_output TEXT NOT NULL,
    tolerance TEXT,
    preconditions TEXT DEFAULT '[]',
    postconditions TEXT DEFAULT '[]',
    portable_code TEXT,
    priority TEXT DEFAULT 'medium',
    status TEXT DEFAULT 'draft',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS contracts (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    domain TEXT NOT NULL,
    description TEXT,
    contract_type TEXT NOT NULL,
    signature TEXT,
    preconditions TEXT DEFAULT '[]',
    postconditions TEXT DEFAULT '[]',
    invariants TEXT DEFAULT '[]',
    source_evidence TEXT DEFAULT '[]',
    golden_test_ids TEXT DEFAULT '[]',
    status TEXT DEFAULT 'draft',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS fixtures (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    source_project TEXT,
    fixture_type TEXT NOT NULL,
    domain TEXT,
    content TEXT NOT NULL,
    format TEXT,
    used_by TEXT DEFAULT '[]',
    portable INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS test_runs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phase TEXT NOT NULL,
    iteration INTEGER NOT NULL,
    golden_test_id TEXT REFERENCES golden_tests(id),
    target_system TEXT NOT NULL,
    status TEXT NOT NULL,
    actual_output TEXT,
    error_message TEXT,
    execution_time_ms REAL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS differential_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    golden_test_id TEXT REFERENCES golden_tests(id),
    reference_output TEXT,
    target_output TEXT,
    match_status TEXT NOT NULL,
    diff_details TEXT,
    tolerance_used TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS coverage_map (
    id TEXT PRIMARY KEY,
    domain TEXT NOT NULL,
    area TEXT NOT NULL,
    total_behaviors INTEGER DEFAULT 0,
    covered_behaviors INTEGER DEFAULT 0,
    golden_test_count INTEGER DEFAULT 0,
    passing_count INTEGER DEFAULT 0,
    failing_count INTEGER DEFAULT 0,
    coverage_pct REAL DEFAULT 0.0,
    gaps TEXT DEFAULT '[]',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS quality_scores (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    phase INTEGER NOT NULL,
    score REAL NOT NULL,
    details TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS agent_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_agent TEXT NOT NULL,
    phase INTEGER NOT NULL,
    iteration INTEGER DEFAULT 0,
    message_type TEXT NOT NULL,
    content TEXT NOT NULL,
    metadata TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
"""


def get_db(db_path: str) -> sqlite3.Connection:
    conn = sqlite3.connect(db_path)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.row_factory = sqlite3.Row
    return conn


# ── init ──────────────────────────────────────────────────────────────────

def cmd_init(args):
    db = get_db(args.db_path)
    db.executescript(SCHEMA)
    db.commit()
    db.close()
    print(f"Database initialized at {args.db_path}")


# ── source tests ──────────────────────────────────────────────────────────

def cmd_add_source_test(args):
    data = json.loads(args.test_json)
    db = get_db(args.db_path)
    db.execute(
        """INSERT OR REPLACE INTO source_tests
           (id, name, source_project, file_path, test_type, domain, language,
            framework, code, fixtures_used, mocks_used, dependencies,
            behavioral_contract, extraction_status, rejection_reason)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (
            data["id"], data["name"], data["source_project"], data["file_path"],
            data["test_type"], data.get("domain"), data.get("language"),
            data.get("framework"), data["code"],
            json.dumps(data.get("fixtures_used", [])),
            json.dumps(data.get("mocks_used", [])),
            json.dumps(data.get("dependencies", [])),
            data.get("behavioral_contract"),
            data.get("extraction_status", "raw"),
            data.get("rejection_reason"),
        ),
    )
    db.commit()
    db.close()
    print(f"Source test added: {data['id']}")


def cmd_query_source_tests(args):
    db = get_db(args.db_path)
    clauses, params = [], []
    if args.source_project:
        clauses.append("source_project = ?")
        params.append(args.source_project)
    if args.domain:
        clauses.append("domain = ?")
        params.append(args.domain)
    if args.test_type:
        clauses.append("test_type = ?")
        params.append(args.test_type)
    if args.status:
        clauses.append("extraction_status = ?")
        params.append(args.status)
    where = " WHERE " + " AND ".join(clauses) if clauses else ""
    rows = db.execute(f"SELECT * FROM source_tests{where} ORDER BY created_at", params).fetchall()
    db.close()
    for r in rows:
        d = dict(r)
        for k in ("fixtures_used", "mocks_used", "dependencies"):
            if d.get(k):
                try:
                    d[k] = json.loads(d[k])
                except (json.JSONDecodeError, TypeError):
                    pass
        print(json.dumps(d, indent=2, default=str))
        print("---")
    print(f"Total: {len(rows)}")


# ── golden tests ──────────────────────────────────────────────────────────

def cmd_add_golden_test(args):
    data = json.loads(args.test_json)
    db = get_db(args.db_path)
    db.execute(
        """INSERT OR REPLACE INTO golden_tests
           (id, source_test_id, name, domain, test_type, description,
            input_spec, expected_output, tolerance, preconditions,
            postconditions, portable_code, priority, status)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
        (
            data["id"], data.get("source_test_id"), data["name"], data["domain"],
            data["test_type"], data.get("description"),
            json.dumps(data["input_spec"]) if isinstance(data["input_spec"], dict) else data["input_spec"],
            json.dumps(data["expected_output"]) if isinstance(data["expected_output"], dict) else data["expected_output"],
            json.dumps(data.get("tolerance")) if data.get("tolerance") else None,
            json.dumps(data.get("preconditions", [])),
            json.dumps(data.get("postconditions", [])),
            data.get("portable_code"),
            data.get("priority", "medium"),
            data.get("status", "draft"),
        ),
    )
    db.commit()
    db.close()
    print(f"Golden test added: {data['id']}")


def cmd_update_golden_test(args):
    updates = json.loads(args.updates_json)
    db = get_db(args.db_path)
    set_parts, params = [], []
    for k, v in updates.items():
        set_parts.append(f"{k} = ?")
        params.append(json.dumps(v) if isinstance(v, (dict, list)) else v)
    params.append(args.test_id)
    db.execute(f"UPDATE golden_tests SET {', '.join(set_parts)} WHERE id = ?", params)
    db.commit()
    db.close()
    print(f"Golden test updated: {args.test_id}")


def cmd_query_golden_tests(args):
    db = get_db(args.db_path)
    clauses, params = [], []
    if args.domain:
        clauses.append("domain = ?")
        params.append(args.domain)
    if args.status:
        clauses.append("status = ?")
        params.append(args.status)
    if args.priority:
        clauses.append("priority = ?")
        params.append(args.priority)
    where = " WHERE " + " AND ".join(clauses) if clauses else ""
    rows = db.execute(f"SELECT * FROM golden_tests{where} ORDER BY priority, created_at", params).fetchall()
    db.close()
    for r in rows:
        d = dict(r)
        for k in ("input_spec", "expected_output", "tolerance", "preconditions", "postconditions"):
            if d.get(k):
                try:
                    d[k] = json.loads(d[k])
                except (json.JSONDecodeError, TypeError):
                    pass
        print(json.dumps(d, indent=2, default=str))
        print("---")
    print(f"Total: {len(rows)}")


# ── contracts ─────────────────────────────────────────────────────────────

def cmd_add_contract(args):
    data = json.loads(args.contract_json)
    db = get_db(args.db_path)
    db.execute(
        """INSERT OR REPLACE INTO contracts
           (id, name, domain, description, contract_type, signature,
            preconditions, postconditions, invariants, source_evidence,
            golden_test_ids, status)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
        (
            data["id"], data["name"], data["domain"], data.get("description"),
            data["contract_type"], data.get("signature"),
            json.dumps(data.get("preconditions", [])),
            json.dumps(data.get("postconditions", [])),
            json.dumps(data.get("invariants", [])),
            json.dumps(data.get("source_evidence", [])),
            json.dumps(data.get("golden_test_ids", [])),
            data.get("status", "draft"),
        ),
    )
    db.commit()
    db.close()
    print(f"Contract added: {data['id']}")


def cmd_query_contracts(args):
    db = get_db(args.db_path)
    clauses, params = [], []
    if args.domain:
        clauses.append("domain = ?")
        params.append(args.domain)
    if args.contract_type:
        clauses.append("contract_type = ?")
        params.append(args.contract_type)
    where = " WHERE " + " AND ".join(clauses) if clauses else ""
    rows = db.execute(f"SELECT * FROM contracts{where} ORDER BY created_at", params).fetchall()
    db.close()
    for r in rows:
        d = dict(r)
        for k in ("preconditions", "postconditions", "invariants", "source_evidence", "golden_test_ids"):
            if d.get(k):
                try:
                    d[k] = json.loads(d[k])
                except (json.JSONDecodeError, TypeError):
                    pass
        print(json.dumps(d, indent=2, default=str))
        print("---")
    print(f"Total: {len(rows)}")


# ── fixtures ──────────────────────────────────────────────────────────────

def cmd_add_fixture(args):
    data = json.loads(args.fixture_json)
    db = get_db(args.db_path)
    db.execute(
        """INSERT OR REPLACE INTO fixtures
           (id, name, source_project, fixture_type, domain, content, format,
            used_by, portable)
           VALUES (?,?,?,?,?,?,?,?,?)""",
        (
            data["id"], data["name"], data.get("source_project"),
            data["fixture_type"], data.get("domain"), data["content"],
            data.get("format"),
            json.dumps(data.get("used_by", [])),
            data.get("portable", 0),
        ),
    )
    db.commit()
    db.close()
    print(f"Fixture added: {data['id']}")


def cmd_query_fixtures(args):
    db = get_db(args.db_path)
    clauses, params = [], []
    if args.domain:
        clauses.append("domain = ?")
        params.append(args.domain)
    if args.fixture_type:
        clauses.append("fixture_type = ?")
        params.append(args.fixture_type)
    where = " WHERE " + " AND ".join(clauses) if clauses else ""
    rows = db.execute(f"SELECT * FROM fixtures{where} ORDER BY created_at", params).fetchall()
    db.close()
    for r in rows:
        print(json.dumps(dict(r), indent=2, default=str))
        print("---")
    print(f"Total: {len(rows)}")


# ── test runs ─────────────────────────────────────────────────────────────

def cmd_add_test_run(args):
    data = json.loads(args.run_json)
    db = get_db(args.db_path)
    db.execute(
        """INSERT INTO test_runs
           (phase, iteration, golden_test_id, target_system, status,
            actual_output, error_message, execution_time_ms)
           VALUES (?,?,?,?,?,?,?,?)""",
        (
            data["phase"], data["iteration"], data["golden_test_id"],
            data["target_system"], data["status"],
            data.get("actual_output"), data.get("error_message"),
            data.get("execution_time_ms"),
        ),
    )
    db.commit()
    db.close()
    print(f"Test run added for: {data['golden_test_id']}")


def cmd_query_test_runs(args):
    db = get_db(args.db_path)
    clauses, params = [], []
    if args.phase:
        clauses.append("phase = ?")
        params.append(args.phase)
    if args.status:
        clauses.append("status = ?")
        params.append(args.status)
    if args.golden_test_id:
        clauses.append("golden_test_id = ?")
        params.append(args.golden_test_id)
    where = " WHERE " + " AND ".join(clauses) if clauses else ""
    rows = db.execute(f"SELECT * FROM test_runs{where} ORDER BY created_at DESC", params).fetchall()
    db.close()
    for r in rows:
        print(json.dumps(dict(r), indent=2, default=str))
        print("---")
    print(f"Total: {len(rows)}")


# ── differential results ──────────────────────────────────────────────────

def cmd_add_differential(args):
    data = json.loads(args.diff_json)
    db = get_db(args.db_path)
    db.execute(
        """INSERT INTO differential_results
           (golden_test_id, reference_output, target_output, match_status,
            diff_details, tolerance_used)
           VALUES (?,?,?,?,?,?)""",
        (
            data["golden_test_id"], data.get("reference_output"),
            data.get("target_output"), data["match_status"],
            json.dumps(data.get("diff_details")) if data.get("diff_details") else None,
            data.get("tolerance_used"),
        ),
    )
    db.commit()
    db.close()
    print(f"Differential result added for: {data['golden_test_id']}")


def cmd_query_differentials(args):
    db = get_db(args.db_path)
    clauses, params = [], []
    if args.match_status:
        clauses.append("match_status = ?")
        params.append(args.match_status)
    if args.golden_test_id:
        clauses.append("golden_test_id = ?")
        params.append(args.golden_test_id)
    where = " WHERE " + " AND ".join(clauses) if clauses else ""
    rows = db.execute(f"SELECT * FROM differential_results{where} ORDER BY created_at DESC", params).fetchall()
    db.close()
    for r in rows:
        d = dict(r)
        if d.get("diff_details"):
            try:
                d["diff_details"] = json.loads(d["diff_details"])
            except (json.JSONDecodeError, TypeError):
                pass
        print(json.dumps(d, indent=2, default=str))
        print("---")
    print(f"Total: {len(rows)}")


# ── coverage map ──────────────────────────────────────────────────────────

def cmd_add_coverage(args):
    data = json.loads(args.coverage_json)
    db = get_db(args.db_path)
    db.execute(
        """INSERT OR REPLACE INTO coverage_map
           (id, domain, area, total_behaviors, covered_behaviors,
            golden_test_count, passing_count, failing_count, coverage_pct, gaps)
           VALUES (?,?,?,?,?,?,?,?,?,?)""",
        (
            data["id"], data["domain"], data["area"],
            data.get("total_behaviors", 0), data.get("covered_behaviors", 0),
            data.get("golden_test_count", 0), data.get("passing_count", 0),
            data.get("failing_count", 0), data.get("coverage_pct", 0.0),
            json.dumps(data.get("gaps", [])),
        ),
    )
    db.commit()
    db.close()
    print(f"Coverage entry added: {data['id']}")


def cmd_query_coverage(args):
    db = get_db(args.db_path)
    clauses, params = [], []
    if args.domain:
        clauses.append("domain = ?")
        params.append(args.domain)
    where = " WHERE " + " AND ".join(clauses) if clauses else ""
    rows = db.execute(f"SELECT * FROM coverage_map{where} ORDER BY domain, area", params).fetchall()
    db.close()
    for r in rows:
        d = dict(r)
        if d.get("gaps"):
            try:
                d["gaps"] = json.loads(d["gaps"])
            except (json.JSONDecodeError, TypeError):
                pass
        print(json.dumps(d, indent=2, default=str))
        print("---")
    print(f"Total: {len(rows)}")


# ── quality scores ────────────────────────────────────────────────────────

def cmd_add_quality_score(args):
    db = get_db(args.db_path)
    db.execute(
        "INSERT INTO quality_scores (phase, score, details) VALUES (?,?,?)",
        (args.phase, args.score, args.details),
    )
    db.commit()
    db.close()
    print(f"Quality score added: phase={args.phase} score={args.score}")


# ── agent messages ────────────────────────────────────────────────────────

def cmd_add_message(args):
    db = get_db(args.db_path)
    db.execute(
        """INSERT INTO agent_messages
           (from_agent, phase, iteration, message_type, content, metadata)
           VALUES (?,?,?,?,?,?)""",
        (
            args.from_agent, args.phase, args.iteration or 0,
            args.message_type or "finding", args.content,
            args.metadata_json,
        ),
    )
    db.commit()
    db.close()
    print(f"Message added from {args.from_agent}")


def cmd_query_messages(args):
    db = get_db(args.db_path)
    clauses, params = [], []
    if args.phase is not None:
        clauses.append("phase = ?")
        params.append(args.phase)
    if args.from_agent:
        clauses.append("from_agent = ?")
        params.append(args.from_agent)
    if args.message_type:
        clauses.append("message_type = ?")
        params.append(args.message_type)
    where = " WHERE " + " AND ".join(clauses) if clauses else ""
    rows = db.execute(f"SELECT * FROM agent_messages{where} ORDER BY created_at", params).fetchall()
    db.close()
    for r in rows:
        d = dict(r)
        if d.get("metadata"):
            try:
                d["metadata"] = json.loads(d["metadata"])
            except (json.JSONDecodeError, TypeError):
                pass
        print(json.dumps(d, indent=2, default=str))
        print("---")
    print(f"Total: {len(rows)}")


# ── stats ─────────────────────────────────────────────────────────────────

def cmd_stats(args):
    db = get_db(args.db_path)

    source_total = db.execute("SELECT COUNT(*) FROM source_tests").fetchone()[0]
    source_by_status = db.execute(
        "SELECT extraction_status, COUNT(*) FROM source_tests GROUP BY extraction_status"
    ).fetchall()
    source_by_domain = db.execute(
        "SELECT domain, COUNT(*) FROM source_tests WHERE domain IS NOT NULL GROUP BY domain"
    ).fetchall()

    golden_total = db.execute("SELECT COUNT(*) FROM golden_tests").fetchone()[0]
    golden_by_status = db.execute(
        "SELECT status, COUNT(*) FROM golden_tests GROUP BY status"
    ).fetchall()
    golden_by_domain = db.execute(
        "SELECT domain, COUNT(*) FROM golden_tests GROUP BY domain"
    ).fetchall()
    golden_by_priority = db.execute(
        "SELECT priority, COUNT(*) FROM golden_tests GROUP BY priority"
    ).fetchall()

    contracts_total = db.execute("SELECT COUNT(*) FROM contracts").fetchone()[0]
    fixtures_total = db.execute("SELECT COUNT(*) FROM fixtures").fetchone()[0]

    runs_total = db.execute("SELECT COUNT(*) FROM test_runs").fetchone()[0]
    runs_by_status = db.execute(
        "SELECT status, COUNT(*) FROM test_runs GROUP BY status"
    ).fetchall()

    diff_total = db.execute("SELECT COUNT(*) FROM differential_results").fetchone()[0]
    diff_by_status = db.execute(
        "SELECT match_status, COUNT(*) FROM differential_results GROUP BY match_status"
    ).fetchall()

    coverage_entries = db.execute("SELECT COUNT(*) FROM coverage_map").fetchone()[0]
    avg_coverage = db.execute("SELECT AVG(coverage_pct) FROM coverage_map").fetchone()[0]

    messages_total = db.execute("SELECT COUNT(*) FROM agent_messages").fetchone()[0]
    quality_total = db.execute("SELECT COUNT(*) FROM quality_scores").fetchone()[0]

    db.close()

    print("=" * 60)
    print("GOLDEN HARVEST LOOP — Database Statistics")
    print("=" * 60)

    print(f"\nSource Tests: {source_total}")
    for r in source_by_status:
        print(f"  {r[0]}: {r[1]}")
    if source_by_domain:
        print("  By domain:")
        for r in source_by_domain:
            print(f"    {r[0]}: {r[1]}")

    print(f"\nGolden Tests: {golden_total}")
    for r in golden_by_status:
        print(f"  {r[0]}: {r[1]}")
    if golden_by_domain:
        print("  By domain:")
        for r in golden_by_domain:
            print(f"    {r[0]}: {r[1]}")
    if golden_by_priority:
        print("  By priority:")
        for r in golden_by_priority:
            print(f"    {r[0]}: {r[1]}")

    print(f"\nContracts: {contracts_total}")
    print(f"Fixtures: {fixtures_total}")

    print(f"\nTest Runs: {runs_total}")
    for r in runs_by_status:
        print(f"  {r[0]}: {r[1]}")

    print(f"\nDifferential Results: {diff_total}")
    for r in diff_by_status:
        print(f"  {r[0]}: {r[1]}")

    print(f"\nCoverage Entries: {coverage_entries}")
    if avg_coverage is not None:
        print(f"  Average coverage: {avg_coverage:.1f}%")

    print(f"\nAgent Messages: {messages_total}")
    print(f"Quality Scores: {quality_total}")
    print("=" * 60)


# ── CLI ───────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Golden Harvest Loop DB Manager")
    parser.add_argument("--db-path", required=True, help="Path to SQLite database")
    sub = parser.add_subparsers(dest="command")

    # init
    sub.add_parser("init")

    # source tests
    p = sub.add_parser("add-source-test")
    p.add_argument("--test-json", required=True)

    p = sub.add_parser("query-source-tests")
    p.add_argument("--source-project", default=None)
    p.add_argument("--domain", default=None)
    p.add_argument("--test-type", default=None)
    p.add_argument("--status", default=None)

    # golden tests
    p = sub.add_parser("add-golden-test")
    p.add_argument("--test-json", required=True)

    p = sub.add_parser("update-golden-test")
    p.add_argument("--test-id", required=True)
    p.add_argument("--updates-json", required=True)

    p = sub.add_parser("query-golden-tests")
    p.add_argument("--domain", default=None)
    p.add_argument("--status", default=None)
    p.add_argument("--priority", default=None)

    # contracts
    p = sub.add_parser("add-contract")
    p.add_argument("--contract-json", required=True)

    p = sub.add_parser("query-contracts")
    p.add_argument("--domain", default=None)
    p.add_argument("--contract-type", default=None)

    # fixtures
    p = sub.add_parser("add-fixture")
    p.add_argument("--fixture-json", required=True)

    p = sub.add_parser("query-fixtures")
    p.add_argument("--domain", default=None)
    p.add_argument("--fixture-type", default=None)

    # test runs
    p = sub.add_parser("add-test-run")
    p.add_argument("--run-json", required=True)

    p = sub.add_parser("query-test-runs")
    p.add_argument("--phase", default=None)
    p.add_argument("--status", default=None)
    p.add_argument("--golden-test-id", default=None)

    # differential results
    p = sub.add_parser("add-differential")
    p.add_argument("--diff-json", required=True)

    p = sub.add_parser("query-differentials")
    p.add_argument("--match-status", default=None)
    p.add_argument("--golden-test-id", default=None)

    # coverage
    p = sub.add_parser("add-coverage")
    p.add_argument("--coverage-json", required=True)

    p = sub.add_parser("query-coverage")
    p.add_argument("--domain", default=None)

    # quality scores
    p = sub.add_parser("add-quality-score")
    p.add_argument("--phase", type=int, required=True)
    p.add_argument("--score", type=float, required=True)
    p.add_argument("--details", default=None)

    # messages
    p = sub.add_parser("add-message")
    p.add_argument("--from-agent", required=True)
    p.add_argument("--phase", type=int, required=True)
    p.add_argument("--iteration", type=int, default=0)
    p.add_argument("--message-type", default="finding")
    p.add_argument("--content", required=True)
    p.add_argument("--metadata-json", default=None)

    p = sub.add_parser("query-messages")
    p.add_argument("--phase", type=int, default=None)
    p.add_argument("--from-agent", default=None)
    p.add_argument("--message-type", default=None)

    # stats
    sub.add_parser("stats")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    cmd_map = {
        "init": cmd_init,
        "add-source-test": cmd_add_source_test,
        "query-source-tests": cmd_query_source_tests,
        "add-golden-test": cmd_add_golden_test,
        "update-golden-test": cmd_update_golden_test,
        "query-golden-tests": cmd_query_golden_tests,
        "add-contract": cmd_add_contract,
        "query-contracts": cmd_query_contracts,
        "add-fixture": cmd_add_fixture,
        "query-fixtures": cmd_query_fixtures,
        "add-test-run": cmd_add_test_run,
        "query-test-runs": cmd_query_test_runs,
        "add-differential": cmd_add_differential,
        "query-differentials": cmd_query_differentials,
        "add-coverage": cmd_add_coverage,
        "query-coverage": cmd_query_coverage,
        "add-quality-score": cmd_add_quality_score,
        "add-message": cmd_add_message,
        "query-messages": cmd_query_messages,
        "stats": cmd_stats,
    }

    cmd_map[args.command](args)


if __name__ == "__main__":
    main()
