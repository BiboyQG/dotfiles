#!/usr/bin/env python3

import os
import re
import subprocess
import sys
from contextlib import contextmanager
from typing import List, Dict, Optional, Tuple


LOCK_NAME = "dotfiles-session-manager"


def run_tmux(args: List[str], check: bool = True, capture: bool = False) -> str:
    kwargs = {
        "check": check,
    }
    if capture:
        kwargs["stdout"] = subprocess.PIPE
        kwargs["text"] = True
    result = subprocess.run(["tmux", *args], **kwargs)
    if capture:
        return result.stdout.rstrip("\n")
    return ""


def list_sessions() -> List[Dict[str, object]]:
    output = run_tmux([
        "list-sessions",
        "-F",
        "#{session_id}\t#{session_name}\t#{session_created}"
    ], capture=True)
    if not output:
        return []

    sessions = []
    for line in output.splitlines():
        session_id, name, created_str = line.split("\t")
        created = int(created_str)
        match = re.match(r"^(\d+)-(.*)$", name)
        if match:
            index = int(match.group(1))
            label = match.group(2)
        else:
            index = None
            label = name
        sessions.append({
            "id": session_id,
            "name": name,
            "created": created,
            "index": index,
            "label": label,
        })

    def sort_key(entry: Dict[str, object]):
        index = entry["index"]
        return (0, index) if index is not None else (1, entry["created"])

    sessions.sort(key=sort_key)
    return sessions


def sanitize_label(label: str) -> str:
    stripped = label.strip()
    return stripped or "session"


def apply_order(ordered_sessions: List[Dict[str, object]]) -> None:
    planned_names = []
    for position, session in enumerate(ordered_sessions, start=1):
        label = sanitize_label(str(session["label"]))
        planned_names.append((session, f"{position}-{label}"))

    if all(session["name"] == new_name for session, new_name in planned_names):
        return

    prefix = f"__dotfiles_{os.getpid()}_"
    for session, _ in planned_names:
        session_id = str(session["id"]).lstrip("$")
        run_tmux(["rename-session", "-t", session["id"], f"{prefix}{session_id}"])
    for session, new_name in planned_names:
        run_tmux(["rename-session", "-t", session["id"], new_name])


@contextmanager
def mutation_lock():
    run_tmux(["wait-for", "-L", LOCK_NAME])
    try:
        yield
    finally:
        run_tmux(["wait-for", "-U", LOCK_NAME], check=False)


def current_session_id() -> str:
    return run_tmux(["display-message", "-p", "#{session_id}"], capture=True)


def current_window_id() -> str:
    return run_tmux(["display-message", "-p", "#{window_id}"], capture=True)


def parse_optional_client(args: List[str]) -> Tuple[Optional[str], List[str]]:
    client: Optional[str] = None
    remaining: List[str] = []
    it = iter(args)
    for arg in it:
        if arg == "--client":
            client = next(it, None)
        else:
            remaining.append(arg)
    return client, remaining


def command_switch(index_str: str, client: Optional[str] = None) -> None:
    try:
        index = int(index_str)
    except ValueError:
        return
    if index < 1:
        return
    sessions = list_sessions()
    if index > len(sessions):
        return
    target_session_id = str(sessions[index - 1]["id"])
    if client:
        run_tmux(["switch-client", "-c", client, "-t", target_session_id], check=False)
        run_tmux(["refresh-client", "-S", "-t", client], check=False)
    else:
        run_tmux(["switch-client", "-t", target_session_id], check=False)
        run_tmux(["refresh-client", "-S"], check=False)


def command_rename(label: str) -> None:
    label = sanitize_label(label)
    current_id = current_session_id()
    sessions = list_sessions()
    for session in sessions:
        if session["id"] == current_id:
            session["label"] = label
            break
    else:
        return
    apply_order(sessions)


def command_ensure() -> None:
    sessions = list_sessions()
    if sessions:
        apply_order(sessions)


def command_created() -> None:
    # Called after a session is created; ensure numbering stays contiguous.
    command_ensure()


def command_move_window_to_session(index_str: str, client: Optional[str] = None) -> None:
    try:
        index = int(index_str)
    except ValueError:
        return
    if index < 1:
        return
    sessions = list_sessions()
    if index > len(sessions):
        return
    target_session_id = sessions[index - 1]["id"]
    source_window_id = current_window_id()
    if not source_window_id:
        return
    current_id = current_session_id()
    if target_session_id != current_id:
        run_tmux(["move-window", "-s", source_window_id, "-t", f"{target_session_id}:"], check=False)
    if client:
        run_tmux(["switch-client", "-c", client, "-t", target_session_id], check=False)
        run_tmux(["refresh-client", "-S", "-t", client], check=False)
    else:
        run_tmux(["switch-client", "-t", target_session_id], check=False)
        run_tmux(["refresh-client", "-S"], check=False)


def main(argv: List[str]) -> None:
    if len(argv) < 2:
        return
    command = argv[1]
    if command == "switch" and len(argv) >= 3:
        client, _ = parse_optional_client(argv[3:])
        command_switch(argv[2], client)
    elif command == "rename" and len(argv) >= 3:
        with mutation_lock():
            command_rename(argv[2])
    elif command == "ensure":
        with mutation_lock():
            command_ensure()
    elif command == "created":
        with mutation_lock():
            command_created()
    elif command == "move-window-to" and len(argv) >= 3:
        client, _ = parse_optional_client(argv[3:])
        command_move_window_to_session(argv[2], client)


if __name__ == "__main__":
    main(sys.argv)
