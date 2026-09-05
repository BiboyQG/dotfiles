#!/usr/bin/env python3

import argparse
import os
import re
import subprocess
import sys
import time
from contextlib import contextmanager
from typing import List, Dict, Optional


LOCK_NAME = "dotfiles-session-manager"
STARTUP_OPTION = "@dotfiles-session-startup"
RESTORING_OPTION = "@dotfiles-session-restoring"


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
    for line in output.split("\n"):
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
    if re.search(r"[\x00-\x1f\x7f]", label):
        raise ValueError("session labels cannot contain ASCII control characters")
    label.encode("utf-8")
    stripped = label.strip()
    return stripped or "session"


def get_option(name: str) -> str:
    return run_tmux(["show-option", "-gqv", name], check=False, capture=True)


def set_option(name: str, value: str) -> None:
    run_tmux(["set-option", "-gq", name, value])


def numbering_suspended() -> bool:
    return (
        get_option(STARTUP_OPTION) in ("pending", "restoring")
        or get_option(RESTORING_OPTION) == "on"
    )


def rename_session(session_id: object, name: str) -> bool:
    # The session may have been killed between listing and renaming.
    try:
        # tmux expands this argument as a format, even when passed without a shell.
        run_tmux(["rename-session", "-t", str(session_id), name.replace("#", "##")])
    except subprocess.CalledProcessError:
        live_ids = run_tmux(["list-sessions", "-F", "#{session_id}"], capture=True)
        if str(session_id) in live_ids.split("\n"):
            raise
        return False
    return True


def apply_order(ordered_sessions: List[Dict[str, object]]) -> None:
    planned_names = []
    for position, session in enumerate(ordered_sessions, start=1):
        label = sanitize_label(str(session["label"]))
        planned_names.append((session, f"{position}-{label}"))

    if all(session["name"] == new_name for session, new_name in planned_names):
        return

    prefix = f"__dotfiles_{os.getpid()}_"
    changed_sessions = []
    try:
        for session, _ in planned_names:
            session_id = str(session["id"]).lstrip("$")
            temporary_name = f"{prefix}{session_id}"
            if rename_session(session["id"], temporary_name):
                changed_sessions.append((session, temporary_name))
        for session, new_name in planned_names:
            rename_session(session["id"], new_name)
    except subprocess.CalledProcessError:
        # Vacate final names before restoring originals, which may overlap them.
        for restore_originals in (False, True):
            for session, temporary_name in changed_sessions:
                name = str(session["name"]) if restore_originals else temporary_name
                try:
                    rename_session(session["id"], name)
                except subprocess.CalledProcessError as error:
                    print(f"Unable to restore session {session['id']}: {error}", file=sys.stderr)
        raise


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
    if numbering_suspended():
        return
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
    if numbering_suspended():
        return
    sessions = list_sessions()
    if sessions:
        apply_order(sessions)
    refresh_clients()


def command_created() -> None:
    # Called after a session is created; ensure numbering stays contiguous.
    command_ensure()


def command_startup_prepare() -> None:
    # Set before loading plugins or installing session-created hooks. In
    # particular, resurrect must still see the initial session named "0".
    if not get_option(STARTUP_OPTION):
        started = int(run_tmux(["display-message", "-p", "#{start_time}"], capture=True))
        max_delay = int(get_option("@continuum-restore-max-delay") or "10")
        state = "pending" if started > time.time() - max_delay else "complete"
        set_option(STARTUP_OPTION, state)


def command_startup_claim() -> None:
    if get_option(STARTUP_OPTION) == "pending":
        set_option(STARTUP_OPTION, "restoring")
        print("claimed")


def command_startup_finish() -> None:
    set_option(STARTUP_OPTION, "complete")
    set_option(RESTORING_OPTION, "off")
    command_ensure()


def command_restore_begin() -> None:
    set_option(RESTORING_OPTION, "on")


def command_restore_end() -> None:
    set_option(RESTORING_OPTION, "off")
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
    for command in (
        "ensure", "created", "list", "startup-prepare", "startup-claim",
        "startup-finish", "restore-begin", "restore-end",
    ):
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
        elif args.command == "startup-prepare":
            command_startup_prepare()
        elif args.command == "startup-claim":
            command_startup_claim()
        elif args.command == "startup-finish":
            command_startup_finish()
        elif args.command == "restore-begin":
            command_restore_begin()
        elif args.command == "restore-end":
            command_restore_end()
        elif args.command == "move-window-to":
            command_move_window_to_session(args.index, args.session, args.window, args.client)
        elif args.command == "list":
            for session in list_sessions():
                print(f"{session['id']}::{session['name']}")


if __name__ == "__main__":
    try:
        main(sys.argv)
    except (ValueError, subprocess.CalledProcessError) as error:
        print(f"session_manager: {error}", file=sys.stderr)
        sys.exit(1)
