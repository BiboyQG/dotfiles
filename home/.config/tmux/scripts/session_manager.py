#!/usr/bin/env python3

import argparse
import os
import re
import subprocess
import sys
from contextlib import contextmanager
from typing import List, Dict, Optional


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


def refresh_clients() -> None:
    output = run_tmux(
        ["list-clients", "-F", "#{client_name}"], check=False, capture=True
    )
    for client in output.splitlines():
        if client:
            run_tmux(["refresh-client", "-S", "-t", client], check=False)


def sanitize_label(label: str) -> str:
    stripped = label.strip()
    return stripped or "session"


def rename_session(session_id: object, name: str) -> None:
    # The session may have been killed between listing and renaming.
    try:
        run_tmux(["rename-session", "-t", str(session_id), name])
    except subprocess.CalledProcessError:
        pass


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
        rename_session(session["id"], f"{prefix}{session_id}")
    for session, new_name in planned_names:
        rename_session(session["id"], new_name)


@contextmanager
def mutation_lock():
    run_tmux(["wait-for", "-L", LOCK_NAME])
    try:
        yield
    finally:
        run_tmux(["wait-for", "-U", LOCK_NAME], check=False)


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


def command_rename(label: str, session_id: str) -> None:
    label = sanitize_label(label)
    sessions = list_sessions()
    for session in sessions:
        if session["id"] == session_id:
            session["label"] = label
            break
    else:
        return
    apply_order(sessions)
    refresh_clients()


def command_ensure() -> None:
    sessions = list_sessions()
    if sessions:
        apply_order(sessions)
    refresh_clients()


def command_created() -> None:
    # Called after a session is created; ensure numbering stays contiguous.
    command_ensure()


def command_move_window_to_session(
    index_str: str, session_id: str, window_id: str, client: Optional[str] = None
) -> None:
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
    if target_session_id != session_id:
        # A vanished window must fail here instead of falling back to another one.
        run_tmux(["move-window", "-s", window_id, "-t", f"{target_session_id}:"])
    if client:
        run_tmux(["switch-client", "-c", client, "-t", target_session_id], check=False)
        run_tmux(["refresh-client", "-S", "-t", client], check=False)
    else:
        run_tmux(["switch-client", "-t", target_session_id], check=False)
        run_tmux(["refresh-client", "-S"], check=False)


def main(argv: List[str]) -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    switch = commands.add_parser("switch")
    switch.add_argument("index")
    switch.add_argument("--client")
    rename = commands.add_parser("rename")
    rename.add_argument("label")
    rename.add_argument("--session", required=True)
    move = commands.add_parser("move-window-to")
    move.add_argument("index")
    move.add_argument("--session", required=True)
    move.add_argument("--window", required=True)
    move.add_argument("--client")
    for command in ("ensure", "created", "list"):
        commands.add_parser(command)
    args = parser.parse_args(argv[1:])
    for option, pattern in (("session", r"\$\d+"), ("window", r"@\d+")):
        value = getattr(args, option, None)
        if value is not None and not re.fullmatch(pattern, value):
            parser.error(f"--{option} requires a tmux {option} ID")

    with mutation_lock():
        if args.command == "switch":
            command_switch(args.index, args.client)
        elif args.command == "rename":
            command_rename(args.label, args.session)
        elif args.command == "ensure":
            command_ensure()
        elif args.command == "created":
            command_created()
        elif args.command == "move-window-to":
            command_move_window_to_session(args.index, args.session, args.window, args.client)
        elif args.command == "list":
            for session in list_sessions():
                print(f"{session['id']}::{session['name']}")


if __name__ == "__main__":
    main(sys.argv)
