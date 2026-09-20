#!/usr/bin/env python3
"""Opt-in runtime probe. Local fake model only; no real model or user config edits.

Uses a short ephemeral exec, not the running desktop session. A pass therefore
proves bundled runtime delivery, not desktop onboarding or live connection.
"""
import argparse
from collections import deque
import hashlib
import importlib.util
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import queue
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import tomllib
import uuid


def capture(target, raw):
    data = json.loads(raw)
    # Do not store the notification body, even though this probe is synthetic.
    result = {key: data.get(key) for key in ("type", "thread-id", "turn-id", "client")}
    result["receivedKeys"] = sorted(data)
    Path(target).write_text(json.dumps(result))


class MockModel(BaseHTTPRequestHandler):
    requests_seen = 0

    def log_message(self, *args):
        pass

    def do_POST(self):
        # Discard request data; never persist prompts, instructions or auth headers.
        remaining = int(self.headers.get("Content-Length", 0))
        while remaining:
            chunk = self.rfile.read(min(remaining, 65536))
            if not chunk:
                break
            remaining -= len(chunk)
        type(self).requests_seen += 1
        message = {"id": "msg_probe", "type": "message", "role": "assistant",
                   "status": "completed", "content": [
                       {"type": "output_text", "text": "NARC_LOCAL_PROBE_OK", "annotations": []}]}
        response = {"id": "resp_probe", "object": "response", "status": "completed",
                    "output": [message], "usage": {"input_tokens": 1, "output_tokens": 1, "total_tokens": 2}}
        events = [
            {"type": "response.created", "response": {**response, "status": "in_progress", "output": []}},
            {"type": "response.output_item.added", "output_index": 0, "item": {**message, "status": "in_progress", "content": []}},
            {"type": "response.output_text.delta", "item_id": "msg_probe", "output_index": 0,
             "content_index": 0, "delta": "NARC_LOCAL_PROBE_OK"},
            {"type": "response.output_item.done", "output_index": 0, "item": message},
            {"type": "response.completed", "response": response},
        ]
        body = "".join("event: " + e["type"] + "\ndata: " + json.dumps(e) + "\n\n" for e in events).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def fingerprint(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def load_adapter():
    spec = importlib.util.spec_from_file_location("narc_adapter", Path(__file__).parents[1] / "narc-codex-hook.py")
    adapter = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(adapter)
    return adapter


def run_app_server(binary, overrides, root):
    # Use in-memory overrides; do not edit config or connect to the live daemon.
    config = Path.home() / ".codex/config.toml"
    existing = tomllib.loads(config.read_text()) if config.exists() else {}
    for name in existing.get("mcp_servers", {}):
        if not re.fullmatch(r"[A-Za-z0-9_-]+", name):
            raise ValueError("Probe cannot safely override this MCP name")
        overrides["mcp_servers." + name + ".enabled"] = False
    overrides["analytics.enabled"] = False
    command = [binary, "app-server", "--stdio"]
    for key, value in overrides.items():
        command.extend(["-c", key + "=" + json.dumps(value)])
    process = subprocess.Popen(command, cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    messages = queue.Queue()
    diagnostics = deque(maxlen=100)
    def read_diagnostics():
        for line in process.stderr:
            diagnostics.append(line.rstrip())
    threading.Thread(target=read_diagnostics, daemon=True).start()
    def read_messages():
        for line in process.stdout:
            messages.put(json.loads(line))
        messages.put({"probeProcessExited": True})
    threading.Thread(target=read_messages, daemon=True).start()
    def send(method, params, request_id=None):
        message = {"method": method, "params": params}
        if request_id is not None:
            message["id"] = request_id
        process.stdin.write(json.dumps(message) + "\n")
        process.stdin.flush()
    def wait_for(predicate):
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            try:
                message = messages.get(timeout=max(0.1, deadline - time.monotonic()))
            except queue.Empty:
                print("App-server exit status:", process.poll(), file=sys.stderr)
                print("\n".join(diagnostics), file=sys.stderr)
                raise TimeoutError("No app-server response within 30 seconds") from None
            if "error" in message:
                raise RuntimeError("App-server rejected probe: " + json.dumps(message["error"]))
            if message.get("probeProcessExited"):
                process.wait(timeout=2)
                print("\n".join(diagnostics), file=sys.stderr)
                raise RuntimeError("App-server exited before completing probe")
            if predicate(message):
                return message
        raise TimeoutError("App-server probe timed out")
    try:
        send("initialize", {"clientInfo": {"name": "narc_notify_probe", "version": "1"},
                            "capabilities": {"experimentalApi": True}}, 1)
        wait_for(lambda m: m.get("id") == 1)
        send("initialized", {})
        send("thread/start", {"ephemeral": True, "cwd": str(root),
                              "model": "narc-local-probe", "modelProvider": "narc_local_probe",
                              "approvalPolicy": "never", "sandbox": "read-only",
                              "baseInstructions": "Local notification plumbing test. Do not use tools.",
                              "developerInstructions": "", "experimentalRawEvents": False}, 2)
        thread = wait_for(lambda m: m.get("id") == 2)["result"]["thread"]["id"]
        send("turn/start", {"threadId": thread, "input": [{"type": "text", "text": "Local probe."}]}, 3)
        finished = wait_for(lambda m: m.get("method") == "turn/completed")
        assert finished["params"]["turn"]["status"] == "completed", "probe turn did not complete"
        # notify is asynchronous relative to the turn/completed event.
        time.sleep(1)
        return subprocess.CompletedProcess(command, 0, b"", b"")
    finally:
        process.stdin.close()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.terminate()
            process.wait(timeout=5)
        process.stdout.close()
        process.stderr.close()


def probe(binary, surface, integration=False):
    protected = [Path.home() / ".codex" / name for name in ("config.toml", "hooks.json")]
    before = [fingerprint(p) for p in protected]
    with tempfile.TemporaryDirectory(prefix="narc-notify-probe-") as temporary:
        root = Path(temporary).resolve()
        target = root / "receipt.json"
        callback = [sys.executable, str(Path(__file__).resolve()), "--capture", str(target)]
        if integration:
            adapter = load_adapter()
            isolated = root / "narc-fixture"
            (isolated / ".codex").mkdir(parents=True)
            (isolated / ".codex/config.toml").write_text("notify=" + json.dumps(callback))
            assert adapter.install_notify(isolated, Path(__file__).parents[1] / "narc-codex-hook.py")["status"] == "waiting"
            connection = tomllib.loads((isolated / ".codex/config.toml").read_text())["notify"][3]
            # Explicit fixture home argument; never changes HOME/CODEX_HOME.
            callback = [sys.executable, str(Path(__file__).resolve()), "--through-adapter", str(isolated), connection]
        server = ThreadingHTTPServer(("127.0.0.1", 0), MockModel)
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        command = [binary, "exec", "--ephemeral", "--ignore-user-config", "--ignore-rules",
                   "--skip-git-repo-check", "--json", "-C", str(root), "-s", "read-only"]
        overrides = {
            "features.hooks": False, "features.plugins": False, "features.remote_plugin": False,
            "model_provider": "narc_local_probe", "model": "narc-local-probe",
            "model_providers.narc_local_probe.name": "NARC local fake response",
            "model_providers.narc_local_probe.base_url": "http://127.0.0.1:" + str(server.server_port) + "/v1",
            "model_providers.narc_local_probe.wire_api": "responses",
            "model_providers.narc_local_probe.requires_openai_auth": False,
            "model_providers.narc_local_probe.supports_websockets": False,
            "notify": callback,
        }
        for key, value in overrides.items():
            command.extend(["-c", key + "=" + json.dumps(value)])
        command.append("Local notification plumbing test. Do not use tools.")
        try:
            run = (run_app_server(binary, overrides, root) if surface == "app-server" else
                   subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, timeout=40))
            deadline = time.monotonic() + 3
            while not target.exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            receipt = json.loads(target.read_text()) if target.exists() else None
            unchanged = before == [fingerprint(p) for p in protected]
            print(json.dumps({"surface": surface, "runtimeExit": run.returncode, "localRequests": MockModel.requests_seen,
                              "configAndHooksUnchanged": unchanged, "receipt": receipt}, indent=2))
            if run.returncode:
                # Error text only on failure; no model request or credential output.
                print(run.stderr.decode(errors="replace")[-4000:], file=sys.stderr)
            assert run.returncode == 0 and MockModel.requests_seen > 0, "runtime probe did not complete"
            assert unchanged, "protected config changed during probe"
            assert receipt and receipt["type"] == "agent-turn-complete", "notify receipt missing"
            uuid.UUID(receipt["thread-id"])
            uuid.UUID(receipt["turn-id"])
            if integration:
                assert adapter.notify_status(isolated)["status"] == "connected"
                event = json.loads(next((adapter.notify_folder(isolated) / "events").glob("*.json")).read_text())
                assert event["threadID"] == receipt["thread-id"] and event["turnID"] == receipt["turn-id"]
                assert "NARC_LOCAL_PROBE_OK" not in json.dumps(event)
                print("PASS: production adapter + previous callback both received completion; NARC metadata only")
            print("PASS: bundled runtime notify; desktop delivery remains unverified")
        finally:
            server.shutdown()
            server.server_close()
            assert before == [fingerprint(p) for p in protected], "protected config changed during probe"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", default="/Applications/ChatGPT.app/Contents/Resources/codex")
    parser.add_argument("--surface", choices=["exec", "app-server"], default="exec")
    parser.add_argument("--capture", nargs=2, metavar=("TARGET", "PAYLOAD"))
    parser.add_argument("--integration", action="store_true")
    parser.add_argument("--through-adapter", nargs=3)
    args = parser.parse_args()
    if args.capture:
        capture(*args.capture)
    elif args.through_adapter:
        load_adapter().receive_notify(Path(args.through_adapter[0]), *args.through_adapter[1:])
    else:
        probe(args.binary, args.surface, args.integration)
