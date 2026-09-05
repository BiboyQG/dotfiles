"""Exercise resize hotkeys without moving any real AeroSpace windows."""
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest


ROOT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "home/.config/aerospace/scripts/resize-edge"
MOCK = r'''#!/usr/bin/env python3
import fcntl
import json
import os
from pathlib import Path
import sys
import time

root = Path(os.environ["RESIZE_FIXTURE"])
label = os.environ.get("RESIZE_LABEL", "single")
args = sys.argv[1:]
code = 0
with (root / "state.json").open("r+") as handle:
    fcntl.flock(handle, fcntl.LOCK_EX)
    state = json.load(handle)
    state["calls"].append({"label": label, "args": args, "focused": state["focused"]})
    if args[0] == "list-windows":
        if state["focused"] is not None:
            print(state["focused"])
    elif args[0] == "focus" and "--window-id" not in args:
        if os.environ.get("RESIZE_BOUNDARY"):
            code = 1
        else:
            state["focused"] = str(int(state["focused"]) + 1)
    elif args[0] == "focus":
        if os.environ.get("RESIZE_RESTORE_FAILURE"):
            code = 7
        else:
            state["focused"] = args[-1]
    elif args[0] == "resize":
        code = 9 if os.environ.get("RESIZE_FAILURE") else 0
    else:
        raise AssertionError(args)
    handle.seek(0)
    json.dump(state, handle)
    handle.truncate()

pause = None
if args[0] == "focus" and "--window-id" not in args and os.environ.get("RESIZE_PAUSE"):
    pause = "probe"
elif args[0] == "resize" and os.environ.get("RESIZE_PAUSE_RESIZE"):
    pause = "resize"
if pause:
    (root / (pause + "-ready")).touch()
    deadline = time.monotonic() + 10
    while not (root / ("release-" + pause)).exists():
        if time.monotonic() > deadline:
            raise TimeoutError("fixture command was not released")
        time.sleep(0.005)
sys.exit(code)
'''


class ResizeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dotfiles-resize-spec-")
        self.root = Path(self.temp.name)
        self.mock = self.root / "aerospace"
        self.mock.write_text(MOCK)
        self.mock.chmod(0o755)
        self.set_state("1")
        self.processes = []

    def tearDown(self):
        for process in self.processes:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.communicate(timeout=5)
        self.temp.cleanup()

    def set_state(self, focused):
        (self.root / "state.json").write_text(json.dumps({"focused": focused, "calls": []}))

    def state(self):
        return json.loads((self.root / "state.json").read_text())

    def start(self, direction="left", amount="50", trace=False, **options):
        env = dict(os.environ, AEROSPACE=str(self.mock), TMPDIR=str(self.root),
                   RESIZE_FIXTURE=str(self.root), **options)
        command = ["/bin/zsh"] + (["-x"] if trace else []) + [str(SCRIPT), direction, amount]
        process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
        self.processes.append(process)
        return process

    def finish(self, process, expected=0):
        stdout, stderr = process.communicate(timeout=5)
        self.assertEqual(process.returncode, expected, (stdout, stderr))

    def wait_for_command(self, command="probe"):
        deadline = time.monotonic() + 5
        while not (self.root / (command + "-ready")).exists():
            self.assertLess(time.monotonic(), deadline, command + " did not start")
            time.sleep(0.005)

    def wait_for_contender(self, process):
        # Observe acquisition with xtrace so the test does not race the second
        # process's startup. Reading focus before acquisition is itself a bug.
        deadline = time.monotonic() + 5
        trace = ""
        while "zsystem flock" not in trace:
            remaining = deadline - time.monotonic()
            self.assertGreater(remaining, 0, trace)
            ready, _, _ = select.select([process.stderr], [], [], remaining)
            self.assertTrue(ready, trace)
            chunk = os.read(process.stderr.fileno(), 4096).decode()
            self.assertTrue(chunk, trace)
            trace += chunk
            self.assertNotIn("list-windows", trace, "contender read the temporary probe focus")

    def test_dimensions_and_boundary(self):
        for direction, dimension in (("left", "width"), ("right", "width"),
                                     ("up", "height"), ("down", "height")):
            for boundary in (False, True):
                with self.subTest(direction=direction, boundary=boundary):
                    self.set_state("1")
                    options = {"RESIZE_BOUNDARY": "1"} if boundary else {}
                    self.finish(self.start(direction, "35", **options))
                    state = self.state()
                    self.assertEqual(state["focused"], "1")
                    self.assertEqual(state["calls"][-1]["args"],
                                     ["resize", "--window-id", "1", dimension,
                                      "-35" if boundary else "+35"])

    def test_empty_workspace_and_invalid_direction(self):
        self.set_state(None)
        self.finish(self.start())
        self.assertEqual(len(self.state()["calls"]), 1)
        self.set_state("1")
        self.finish(self.start("invalid"), expected=2)
        self.assertEqual(self.state()["calls"], [])

    def test_repeated_hotkey_waits_for_original_focus(self):
        first = self.start(RESIZE_LABEL="first", RESIZE_PAUSE="1")
        self.wait_for_command()
        self.assertEqual(self.state()["focused"], "2")
        second = self.start(trace=True, RESIZE_LABEL="second")
        self.wait_for_contender(second)
        self.assertFalse(any(call["label"] == "second" for call in self.state()["calls"]))
        (self.root / "release-probe").touch()
        self.finish(first)
        self.finish(second)
        state = self.state()
        resizes = [call["args"] for call in state["calls"] if call["args"][0] == "resize"]
        self.assertEqual(resizes, [["resize", "--window-id", "1", "width", "+50"]] * 2)
        self.assertEqual(state["focused"], "1")

    def test_lock_is_held_until_resize_finishes(self):
        first = self.start(RESIZE_LABEL="first", RESIZE_PAUSE_RESIZE="1")
        self.wait_for_command("resize")
        second = self.start(trace=True, RESIZE_LABEL="second")
        self.wait_for_contender(second)
        self.assertFalse(any(call["label"] == "second" for call in self.state()["calls"]))
        (self.root / "release-resize").touch()
        self.finish(first)
        self.finish(second)

    def test_restore_failure_aborts_resize_and_releases_lock(self):
        self.finish(self.start(RESIZE_RESTORE_FAILURE="1"), expected=7)
        self.assertFalse(any(call["args"][0] == "resize" for call in self.state()["calls"]))
        self.set_state("1")
        self.finish(self.start())

    def test_resize_failure_preserves_status_and_releases_lock(self):
        self.finish(self.start(RESIZE_FAILURE="1"), expected=9)
        self.assertEqual(self.state()["focused"], "1")
        self.finish(self.start())

    def test_termination_restores_focus_and_releases_lock(self):
        process = self.start(RESIZE_PAUSE="1")
        self.wait_for_command()
        os.killpg(process.pid, signal.SIGTERM)
        self.finish(process, expected=143)
        self.assertEqual(self.state()["focused"], "1")
        self.assertFalse(any(call["args"][0] == "resize" for call in self.state()["calls"]))
        self.finish(self.start())

    def test_sigkill_does_not_leave_a_stale_lock(self):
        process = self.start(RESIZE_PAUSE="1")
        self.wait_for_command()
        os.killpg(process.pid, signal.SIGKILL)
        self.finish(process, expected=-signal.SIGKILL)
        self.set_state("1")
        self.finish(self.start())


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]])
