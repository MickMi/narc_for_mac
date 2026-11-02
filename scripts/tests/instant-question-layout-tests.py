"""Run live long-answer window tests with a watchdog outside the UI process.

A SwiftUI layout loop blocks MainActor timers, including an in-test timeout.
This runner only kills its own isolated test process tree on timeout. It never
launches or quits the installed NARC, reads API keys, or makes model requests.
"""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile


def run_bounded(command, project, timeout, log):
    with log.open("w") as output:
        process = subprocess.Popen(command, cwd=project, stdout=output,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        try:
            return process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            output.write("\nEXTERNAL_TIMEOUT: isolated test process stopped making progress.\n")
            output.flush()
            # SwiftPM's testing helper creates a separate process group. Capture
            # only descendants of this invocation before terminating the parent.
            listing = subprocess.check_output(["ps", "-axo", "pid=,ppid="], text=True)
            descendants = [process.pid]
            pairs = [tuple(map(int, line.split())) for line in listing.splitlines()]
            for parent in descendants:
                descendants.extend(pid for pid, ppid in pairs if ppid == parent)
            for pid in reversed(descendants):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
            process.wait()
            return 124


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    project = args.project.resolve()
    if not (project / "Package.swift").is_file():
        parser.error("project must be a NARC checkout")
    directory = Path(tempfile.mkdtemp(prefix="narc-layout-watchdog-"))
    # Keep compilation outside the shorter UI responsiveness deadline.
    build_log = directory / "build.log"
    code = run_bounded(["swift", "build", "--build-tests", "--scratch-path", ".build",
                        "--disable-sandbox"], project, 300, build_log)
    print(f"build exit={code}; log={build_log}", flush=True)
    if code:
        return code
    test_log = directory / "test.log"
    code = run_bounded(["swift", "test", "--skip-build", "--scratch-path", ".build",
                        "--disable-sandbox", "--no-parallel", "--filter",
                        "instantQuestionLiveLongAnswerKeepsWindowResponsive|"
                        "instantQuestionMultipleLongRoundsKeepLayoutResponsive"],
                       project, 90, test_log)
    print(f"live layout exit={code}; log={test_log}", flush=True)
    expected = ["instantQuestionLiveLongAnswerKeepsWindowResponsive",
                "instantQuestionMultipleLongRoundsKeepLayoutResponsive"]
    if code == 0 and not all("✔ Test " + name in test_log.read_text() for name in expected):
        print("FAIL: expected live-window tests did not report success; zero tests is not a pass.")
        return 1
    print("This checks local fixture rendering; the installed app and online responses are not tested.")
    return code


if __name__ == "__main__":
    sys.exit(main())
