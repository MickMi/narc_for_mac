#!/usr/bin/env python3
"""NARC Hook for Claude Code — sends events to /tmp/narc-claude.sock
v3: reliable terminal window identification (TTY + PID + CWD)"""
import json, os, socket, subprocess, sys

SOCKET_PATH = "/tmp/narc-claude.sock"

def get_tty():
    """Get the TTY device path for this Claude session's terminal tab.
    Strategy: walk up the process tree to find the TTY."""
    methods = []

    # Method 1: check parent's TTY (ppid = Claude Code node process)
    try:
        ppid = os.getppid()
        result = subprocess.run(
            ['ps', '-p', str(ppid), '-o', 'tty='],
            capture_output=True, text=True, timeout=2
        )
        tty = result.stdout.strip()
        if tty and tty != '??' and tty != '?':
            full_path = f"/dev/{tty}" if not tty.startswith('/') else tty
            methods.append(('ppid', full_path))
    except Exception:
        pass

    # Method 2: walk further up (grandparent — the shell)
    try:
        ppid = os.getppid()
        # Get grandparent PID
        result = subprocess.run(
            ['ps', '-p', str(ppid), '-o', 'ppid='],
            capture_output=True, text=True, timeout=2
        )
        gppid = result.stdout.strip()
        if gppid:
            result2 = subprocess.run(
                ['ps', '-p', gppid, '-o', 'tty='],
                capture_output=True, text=True, timeout=2
            )
            tty2 = result2.stdout.strip()
            if tty2 and tty2 != '??' and tty2 != '?':
                full_path = f"/dev/{tty2}" if not tty2.startswith('/') else tty2
                methods.append(('gppid', full_path))
    except Exception:
        pass

    # Method 3: try /dev/tty directly (works if we have a controlling terminal)
    try:
        tty3 = os.ttyname(2)  # stderr might still be connected to terminal
        if tty3:
            methods.append(('fd2', tty3))
    except Exception:
        pass

    # Return first successful result
    if methods:
        return methods[0][1]
    return None

def send_to_narc(payload, wait_response=False):
    if not os.path.exists(SOCKET_PATH):
        return None
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(300 if wait_response else 2)
        sock.connect(SOCKET_PATH)
        sock.sendall(json.dumps(payload).encode())
        if wait_response:
            resp = sock.recv(4096)
            sock.close()
            return json.loads(resp.decode()) if resp else None
        sock.close()
    except (socket.error, OSError, json.JSONDecodeError):
        pass
    return None

def main():
    try:
        data = json.load(sys.stdin)
    except json.JSONDecodeError:
        sys.exit(0)

    event = data.get("hook_event_name", "")
    tty = get_tty()
    cwd = data.get("cwd") or os.getcwd()

    payload = {
        "session_id": data.get("session_id", ""),
        "event": event,
        "cwd": cwd,
        "tty": tty,
        "pid": os.getppid(),  # Claude Code's PID — NARC can trace to terminal window
        "narc_session_id": os.environ.get("NARC_SESSION_ID"),  # set by NARC workspace pane; nil for external terminals
    }

    if event == "PermissionRequest":
        payload["status"] = "waiting_for_approval"
        payload["tool"] = data.get("tool_name", "")
        payload["tool_input"] = data.get("tool_input", {})
        response = send_to_narc(payload, wait_response=True)
        if response:
            decision = response.get("decision", "ask")
            if decision == "allow":
                print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow"}}}))
                sys.exit(0)
            elif decision == "deny":
                print(json.dumps({"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "deny", "message": response.get("reason", "Denied via NARC")}}}))
                sys.exit(0)
        sys.exit(0)
    elif event in ("Stop", "SubagentStop"):
        payload["status"] = "waiting_for_input"
    elif event == "StopFailure":
        payload["status"] = "error"
        payload["message"] = data.get("error", "Unknown error")
    elif event == "SessionStart":
        payload["status"] = "waiting_for_input"
    elif event == "SessionEnd":
        payload["status"] = "ended"
    else:
        sys.exit(0)

    send_to_narc(payload)
    sys.exit(0)

if __name__ == "__main__":
    main()
