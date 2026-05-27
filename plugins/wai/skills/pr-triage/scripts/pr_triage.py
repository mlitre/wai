#!/usr/bin/env python3
"""PR triage helper.

Queries GitHub for:
- PRs the current user authored (open)
- PRs where the current user is BOTH a requested reviewer AND an assignee

Prints a single markdown table with an `Action on me?` column.

Requires `gh` CLI authenticated as the user whose PRs should be triaged.

Usage:
    python3 pr_triage.py [--login LOGIN] [--include-drafts] [--json]

If --login is omitted, the login of the currently authenticated gh user is used.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from typing import Any


def gh(*args: str) -> str:
    """Run gh and return stdout. Raise on non-zero exit."""
    result = subprocess.run(
        ["gh", *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        sys.stderr.write(f"gh {' '.join(args)} failed: {result.stderr}\n")
        sys.exit(1)
    return result.stdout


def current_login() -> str:
    return gh("api", "user", "--jq", ".login").strip()


def search_prs(query: str) -> list[dict[str, Any]]:
    raw = gh(
        "search", "prs",
        *query.split(),
        "--state", "open",
        "--limit", "100",
        "--json", "number,title,url,repository,isDraft",
    )
    return json.loads(raw)


def pr_details(repo: str, number: int) -> dict[str, Any]:
    raw = gh(
        "pr", "view", str(number),
        "-R", repo,
        "--json",
        "number,title,url,reviewDecision,mergeable,mergeStateStatus,isDraft,statusCheckRollup",
    )
    return json.loads(raw)


@dataclass
class PRRow:
    repo: str
    number: int
    title: str
    url: str
    role: str  # "author" or "reviewer+assignee"
    is_draft: bool
    review_decision: str  # APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED, NONE
    mergeable: str  # MERGEABLE, CONFLICTING, UNKNOWN
    merge_state: str  # CLEAN, BLOCKED, UNSTABLE, DIRTY, BEHIND, HAS_HOOKS, UNKNOWN
    ci_ok: int
    ci_fail: int
    ci_pending: int

    @property
    def ci_summary(self) -> str:
        if self.ci_ok == 0 and self.ci_fail == 0 and self.ci_pending == 0:
            return "no CI"
        if self.ci_fail:
            return f"{self.ci_fail} fail"
        if self.ci_pending:
            return f"{self.ci_ok} ok / {self.ci_pending} pending"
        return f"{self.ci_ok}/0/0"

    def action_on_me(self) -> tuple[bool, str]:
        """Return (action_required, reason)."""
        if self.role == "reviewer+assignee":
            if self.review_decision == "CHANGES_REQUESTED":
                return True, "re-review or ping"
            return True, "review"

        # author role
        if self.review_decision == "CHANGES_REQUESTED":
            extras = []
            if self.ci_fail:
                extras.append("CI")
            if self.merge_state == "DIRTY":
                extras.append("rebase")
            tail = " + " + " + ".join(extras) if extras else ""
            return True, f"address feedback{tail}"
        if self.ci_fail:
            tail = " + rebase" if self.merge_state == "DIRTY" else ""
            return True, f"fix CI{tail}" + (", undraft" if self.is_draft else "")
        if self.merge_state == "DIRTY":
            return True, "rebase" + (", undraft" if self.is_draft else "")
        if self.mergeable == "UNKNOWN" and self.merge_state == "UNKNOWN":
            return True, "rebase"
        if self.merge_state == "CLEAN":
            return True, "ready, merge or ping"
        # REVIEW_REQUIRED or BLOCKED with green/pending CI: waiting on reviewer
        return False, "waiting reviewer"


def classify_checks(checks: list[dict[str, Any]]) -> tuple[int, int, int]:
    ok = fail = pending = 0
    for c in checks or []:
        status = (
            c.get("conclusion")
            or c.get("state")
            or c.get("status")
            or ""
        )
        if status in ("SUCCESS", "NEUTRAL", "SKIPPED"):
            ok += 1
        elif status in (
            "FAILURE", "CANCELLED", "TIMED_OUT", "ERROR", "ACTION_REQUIRED",
        ):
            fail += 1
        else:
            pending += 1
    return ok, fail, pending


def build_row(item: dict[str, Any], role: str) -> PRRow:
    repo = item["repository"]["nameWithOwner"]
    number = item["number"]
    detail = pr_details(repo, number)
    ok, fail, pending = classify_checks(detail.get("statusCheckRollup") or [])
    return PRRow(
        repo=repo,
        number=number,
        title=detail.get("title", item.get("title", "")),
        url=detail.get("url", item.get("url", "")),
        role=role,
        is_draft=bool(detail.get("isDraft")),
        review_decision=detail.get("reviewDecision") or "NONE",
        mergeable=detail.get("mergeable") or "UNKNOWN",
        merge_state=detail.get("mergeStateStatus") or "UNKNOWN",
        ci_ok=ok,
        ci_fail=fail,
        ci_pending=pending,
    )


def render_table(rows: list[PRRow], include_drafts: bool) -> str:
    visible = [r for r in rows if include_drafts or not r.is_draft]
    # Order: action-required first, then waiting
    keyed: list[tuple[int, PRRow, bool, str]] = []
    for r in visible:
        action, reason = r.action_on_me()
        # priority: author CHANGES_REQUESTED + CI fail high, then CI fail, then changes, then CLEAN ready, then reviewer reviews, then waiting
        priority = 5
        if r.role == "author":
            if r.review_decision == "CHANGES_REQUESTED":
                priority = 1
            elif r.ci_fail:
                priority = 2
            elif r.merge_state == "DIRTY":
                priority = 2
            elif r.merge_state == "CLEAN":
                priority = 3
            elif not action:
                priority = 6
        else:
            priority = 4 if action else 6
        keyed.append((priority, r, action, reason))
    keyed.sort(key=lambda t: (t[0], t[1].repo, t[1].number))

    lines = [
        "| PR | Role | State | Review | Merge | CI | Action on me? |",
        "|---|---|---|---|---|---|---|",
    ]
    on_me = 0
    waiting = 0
    for _, r, action, reason in keyed:
        state = "DRAFT" if r.is_draft else "OPEN"
        review = r.review_decision if r.review_decision != "NONE" else (
            "pending" if r.role == "reviewer+assignee" else "none"
        )
        merge = (
            f"{r.merge_state}" if r.mergeable == "MERGEABLE"
            else f"{r.mergeable}/{r.merge_state}"
        )
        action_cell = f"**YES**, {reason}" if action else f"no, {reason}"
        title = r.title.replace("|", "\\|")
        lines.append(
            f"| [{r.repo.split('/')[-1]}#{r.number}]({r.url}) {title} "
            f"| {r.role} | {state} | {review} | {merge} | {r.ci_summary} | {action_cell} |"
        )
        if action:
            on_me += 1
        else:
            waiting += 1
    lines.append("")
    lines.append(f"**Tally:** {on_me} on you, {waiting} waiting on others.")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Triage your GitHub PRs.")
    parser.add_argument("--login", help="GitHub login (default: current gh user)")
    parser.add_argument(
        "--include-drafts",
        action="store_true",
        help="Include draft PRs in the table (default: include).",
        default=True,
    )
    parser.add_argument(
        "--no-drafts",
        dest="include_drafts",
        action="store_false",
        help="Exclude draft PRs.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit raw JSON instead of a markdown table.",
    )
    args = parser.parse_args()

    login = args.login or current_login()

    authored = search_prs(f"--author {login}")
    review_assigned = search_prs(f"--review-requested {login} --assignee {login}")

    rows: list[PRRow] = []
    for item in authored:
        rows.append(build_row(item, "author"))
    for item in review_assigned:
        rows.append(build_row(item, "reviewer+assignee"))

    if args.json:
        print(json.dumps([row.__dict__ for row in rows], indent=2))
    else:
        print(render_table(rows, args.include_drafts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
