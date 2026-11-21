#!/usr/bin/env python3
import csv
import json
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CACHE = Path(os.environ.get("RUDDER_PRIOR_ART_CACHE", Path.home() / ".cache/rudder-prior-art"))
EVIDENCE = ROOT / "evidence"

DATASETS = [
    ("uhi-hook-directory", "https://github.com/AtriumAcademy/UHI-Hook-Data.git"),
    ("uniswap-hooklist", "https://github.com/Uniswap/hooklist.git"),
]

QUERIES = [
    ("curator", r"\bcurator(?:s|ial)?\b"),
    ("delegation_management", r"\b(delegat(?:e|ed|es|ion|ing)|manager|vault|strategist)\b"),
    ("range_rebalance", r"\b(range|rebalanc(?:e|es|ed|ing))\b"),
    ("mandate_bounds", r"\b(mandate|envelope|guardrail|bounded|limits?)\b"),
    ("performance_fee_hwm", r"performance\s+fee|high[- ]?water[- ]?mark"),
    ("timelock", r"\btimelock(?:s|ed)?\b|\btime[- ]lock(?:s|ed)?\b"),
    (
        "gated_liquidity_adds",
        r"\b(?:gated|whitelist(?:ed)?)\b[\s\S]{0,200}\b(?:liquidity|addLiquidity|beforeAddLiquidity)\b|\bbeforeAddLiquidity\b[\s\S]{0,200}\b(?:revert|only)\b",
    ),
    ("twap_tick_oracle", r"\bTWAP\b|tick[- ]cumulative|tickCumulative"),
    ("hold_benchmark", r"\bhold\b[\s\S]{0,80}\bbenchmark\b|\bbenchmark\b[\s\S]{0,80}\bhold\b"),
]


def run(cmd):
    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return result.stdout.strip()


def sync_repo(name, url):
    path = CACHE / name
    if (path / ".git").exists():
        run(["git", "-C", str(path), "fetch", "--depth", "1", "origin", "HEAD"])
        run(["git", "-C", str(path), "reset", "--hard", "FETCH_HEAD"])
    else:
        CACHE.mkdir(parents=True, exist_ok=True)
        run(["git", "clone", "--depth", "1", url, str(path)])
    return path, run(["git", "-C", str(path), "rev-parse", "HEAD"])


def markdown_entries(path):
    entries = {}
    for chunk in path.read_text(encoding="utf-8").split("\n---\n"):
        stripped = chunk.lstrip()
        if not stripped.startswith("# "):
            continue
        lines = stripped.splitlines()
        name = lines[0][2:].strip()
        if name == "UHI Hook Directory":
            continue
        entries.setdefault(name, "\n".join(lines[1:]))
    return entries


def first_line(value):
    value = " ".join((value or "").split())
    return value[:240]


def load_directory(path):
    with (path / "hook_directory.csv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    entries = markdown_entries(path / "hook_directory.md")
    result = []
    for row in rows:
        name = row["Name"].strip()
        description = row.get("Description", "") or ""
        md_text = entries.get(name, "")
        if not description:
            match = re.search(r"^Description:\s*(.+)$", md_text, re.MULTILINE)
            description = match.group(1) if match else ""
        search_text = "\n".join(
            [
                description,
                row.get("Tags", "") or "",
                row.get("Integrations", "") or "",
                md_text,
            ]
        )
        result.append(
            {
                "name": name,
                "source": "uhi-hook-directory",
                "cohort": row.get("Cohort", "") or "unrecorded",
                "description": first_line(description),
                "address": "",
                "search_text": search_text,
            }
        )
    return result, len(entries)


def load_hooklist(path):
    with (path / "hooklist.json").open(encoding="utf-8") as handle:
        rows = json.load(handle)
    result = []
    for row in rows:
        hook = row["hook"]
        description = hook.get("description", "") or ""
        result.append(
            {
                "name": hook.get("name", "") or "unrecorded",
                "source": "uniswap-hooklist",
                "cohort": hook.get("chain", "") or "unrecorded",
                "description": first_line(description),
                "address": hook.get("address", "") or "",
                "search_text": description,
            }
        )
    return result


def main():
    EVIDENCE.mkdir(exist_ok=True)
    datasets = []
    all_entries = []
    for name, url in DATASETS:
        path, commit = sync_repo(name, url)
        datasets.append(
            {
                "name": name,
                "repo": url,
                "path": str(path),
                "commit": commit,
                "file": "hook_directory.csv" if name == "uhi-hook-directory" else "hooklist.json",
            }
        )
        if name == "uhi-hook-directory":
            entries, md_count = load_directory(path)
            datasets[-1]["entry_count"] = len(entries)
            datasets[-1]["markdown_entry_count"] = md_count
        else:
            entries = load_hooklist(path)
            datasets[-1]["entry_count"] = len(entries)
        all_entries.extend(entries)

    directory_entries = [entry for entry in all_entries if entry["source"] == "uhi-hook-directory"]
    queries = []
    for query_id, pattern in QUERIES:
        regex = re.compile(pattern, re.IGNORECASE)
        matches = []
        for entry in all_entries:
            if not regex.search(entry["search_text"]):
                continue
            matches.append(
                {
                    "name": entry["name"],
                    "source": entry["source"],
                    "cohort": entry["cohort"],
                    "address": entry["address"],
                }
            )
        queries.append(
            {
                "id": query_id,
                "regex": pattern,
                "scope": "description, tags, integrations, and entry text for directory; description for hooklist",
                "total_entries_searched": len(all_entries),
                "hit_count": len(matches),
                "directory_hit_count": sum(1 for match in matches if match["source"] == "uhi-hook-directory"),
                "hooklist_hit_count": sum(1 for match in matches if match["source"] == "uniswap-hooklist"),
                "matches": matches,
            }
        )

    by_id = {query["id"]: query for query in queries}
    curator_names = sorted({match["name"] for match in by_id["curator"]["matches"] if match["source"] == "uhi-hook-directory"})
    performance_query = by_id["performance_fee_hwm"]
    manual_findings = {
        "performance_fee_hwm": {
            "claim": "none of the directory entries searched mention a performance fee or high-water mark",
            "reproduced": performance_query["directory_hit_count"] == 0,
            "directory_hit_count": performance_query["directory_hit_count"],
            "namespace": f"none of the {len(directory_entries)} directory entries searched mention a performance fee or high-water mark",
        },
        "curator_entry_count": {
            "claim": "curator appears in two directory entries, Gainswap and PumpUp",
            "reproduced": curator_names == ["Gainswap: Impermanent Gain", "PumpUp"],
            "directory_hit_count": len(curator_names),
            "names": curator_names,
        },
    }

    report = {
        "run_date": datetime.now(timezone.utc).date().isoformat(),
        "cache_dir": str(CACHE),
        "datasets": datasets,
        "total_entries_searched": len(all_entries),
        "queries": queries,
        "manual_findings": manual_findings,
    }
    (EVIDENCE / "prior_art_search.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")

    lines = [
        "# Prior-art search",
        "",
        f"Run date: {report['run_date']}",
        "",
        "## Datasets",
        "",
        "| Dataset | Commit | Entries |",
        "| --- | --- | ---: |",
    ]
    for dataset in datasets:
        lines.append(f"| {dataset['name']} | `{dataset['commit']}` | {dataset['entry_count']} |")
    lines.extend(
        [
            "",
            f"Total entries searched: {report['total_entries_searched']}",
            "",
            "## Queries",
            "",
            "| Query | Regex | Hits | Directory | Hooklist |",
            "| --- | --- | ---: | ---: | ---: |",
        ]
    )
    for query in queries:
        lines.append(
            f"| {query['id']} | `{query['regex']}` | {query['hit_count']} | "
            f"{query['directory_hit_count']} | {query['hooklist_hit_count']} |"
        )
    lines.extend(["", "## Manual findings", ""])
    for key, finding in manual_findings.items():
        lines.append(f"- {key}: reproduced={str(finding['reproduced']).lower()}; {finding['claim']}.")
    lines.append("")
    (EVIDENCE / "prior_art_summary.md").write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()
