#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from typing import Any


QUERY = """\
query(
  $owner: String!,
  $repo: String!,
  $number: Int!,
  $commentsCursor: String,
  $reviewsCursor: String,
  $threadsCursor: String
) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      number
      url
      title
      state
      headRefName
      baseRefName
      headRefOid

      comments(first: 100, after: $commentsCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          body
          createdAt
          updatedAt
          author { login }
        }
      }

      reviews(first: 100, after: $reviewsCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          state
          body
          submittedAt
          author { login }
          commit { oid }
        }
      }

      reviewThreads(first: 100, after: $threadsCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          diffSide
          startLine
          startDiffSide
          originalLine
          originalStartLine
          resolvedBy { login }
          comments(first: 100) {
            nodes {
              id
              body
              createdAt
              updatedAt
              author { login }
            }
          }
        }
      }
    }
  }
}
"""


def _run(cmd: list[str], stdin: str | None = None) -> str:
    proc = subprocess.run(cmd, input=stdin, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"command failed: {' '.join(cmd)}\n{proc.stderr}")
    return proc.stdout


def _run_json(cmd: list[str], stdin: str | None = None) -> dict[str, Any]:
    out = _run(cmd, stdin=stdin)
    return json.loads(out)


def _current_pr() -> tuple[str, str, int]:
    data = _run_json(["gh", "pr", "view", "--json", "number,headRepositoryOwner,headRepository"])
    return data["headRepositoryOwner"]["login"], data["headRepository"]["name"], int(data["number"])


def _repo_parts(repo: str) -> tuple[str, str]:
    if "/" not in repo:
        raise ValueError("--repo must be OWNER/REPO")
    owner, name = repo.split("/", 1)
    if not owner or not name:
        raise ValueError("--repo must be OWNER/REPO")
    return owner, name


def _graphql(
    owner: str,
    repo: str,
    number: int,
    comments_cursor: str | None,
    reviews_cursor: str | None,
    threads_cursor: str | None,
) -> dict[str, Any]:
    cmd = [
        "gh",
        "api",
        "graphql",
        "-F",
        "query=@-",
        "-F",
        f"owner={owner}",
        "-F",
        f"repo={repo}",
        "-F",
        f"number={number}",
    ]
    if comments_cursor:
        cmd += ["-F", f"commentsCursor={comments_cursor}"]
    if reviews_cursor:
        cmd += ["-F", f"reviewsCursor={reviews_cursor}"]
    if threads_cursor:
        cmd += ["-F", f"threadsCursor={threads_cursor}"]
    return _run_json(cmd, stdin=QUERY)


def fetch_all(owner: str, repo: str, number: int) -> dict[str, Any]:
    comments: list[dict[str, Any]] = []
    reviews: list[dict[str, Any]] = []
    threads: list[dict[str, Any]] = []
    comments_cursor = reviews_cursor = threads_cursor = None
    pr_meta: dict[str, Any] | None = None

    while True:
        payload = _graphql(owner, repo, number, comments_cursor, reviews_cursor, threads_cursor)
        if payload.get("errors"):
            raise RuntimeError(json.dumps(payload["errors"], indent=2))
        pr = payload["data"]["repository"]["pullRequest"]
        if pr_meta is None:
            pr_meta = {
                "number": pr["number"],
                "url": pr["url"],
                "title": pr["title"],
                "state": pr["state"],
                "owner": owner,
                "repo": repo,
                "headRefName": pr["headRefName"],
                "baseRefName": pr["baseRefName"],
                "headRefOid": pr["headRefOid"],
            }

        c = pr["comments"]
        r = pr["reviews"]
        t = pr["reviewThreads"]
        comments.extend(c.get("nodes") or [])
        reviews.extend(r.get("nodes") or [])
        threads.extend(t.get("nodes") or [])

        comments_cursor = c["pageInfo"]["endCursor"] if c["pageInfo"]["hasNextPage"] else None
        reviews_cursor = r["pageInfo"]["endCursor"] if r["pageInfo"]["hasNextPage"] else None
        threads_cursor = t["pageInfo"]["endCursor"] if t["pageInfo"]["hasNextPage"] else None
        if not (comments_cursor or reviews_cursor or threads_cursor):
            break

    return {
        "pull_request": pr_meta,
        "conversation_comments": comments,
        "reviews": reviews,
        "review_threads": threads,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Fetch GitHub PR review context with thread state.")
    parser.add_argument("--repo", help="Repository as OWNER/REPO. Defaults to current branch PR.")
    parser.add_argument("--pr", type=int, help="Pull request number. Defaults to current branch PR.")
    args = parser.parse_args()

    try:
        if args.repo or args.pr:
            if not (args.repo and args.pr):
                raise ValueError("--repo and --pr must be provided together")
            owner, repo = _repo_parts(args.repo)
            number = args.pr
        else:
            owner, repo, number = _current_pr()
        print(json.dumps(fetch_all(owner, repo, number), indent=2))
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
