#!/usr/bin/env python3
"""Opt-in Codex metadata adapter. Never reads transcripts or saves message content."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import time
import uuid
import shlex
import re
import hashlib
import subprocess

LIMIT = 1024 * 1024
EVENT_FILE = re.compile(r"[0-9a-fA-F-]{36}_[0-9a-fA-F-]{36}(?:_preview)?\.json\Z")
NOTIFY_SCRIPT = re.compile(r"narc-notify-[0-9a-f]{16}\.py")


def normalize(data, thread=None, title=None, now=None, preview=False):
    if not isinstance(data, dict) or (thread is not None and data.get("session_id") != thread):
        return None
    thread = data.get("session_id")
    if data.get("agent_id") or data.get("subagent_id"):
        return None
    states = {"Stop": "replyReady", "UserPromptSubmit": "running", "Interrupt": "interrupted"}
    state = states.get(data.get("hook_event_name"))
    if state is None:
        return None
    turn = data.get("turn_id")
    try:
        uuid.UUID(thread)
        uuid.UUID(turn)
    except (ValueError, TypeError, AttributeError):
        return None
    # Allowlist only: last_assistant_message, prompt, cwd and transcript_path are discarded.
    return dict(schemaVersion=1, threadID=thread, turnID=turn, state=state,
                title=(title or ("对话 " + thread[-8:]))[:100], timestamp=time.time() if now is None else now,
                isPreview=preview)


def secure_folder(folder, private=True):
    folder = Path(folder)
    # Reject existing symlinks in the entire path, including dangling links.
    for part in [*reversed(folder.parents), folder]:
        if part.is_symlink():
            raise ValueError("symlink path rejected")
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    info = folder.stat()
    if info.st_uid != os.getuid() or not stat.S_ISDIR(info.st_mode):
        raise ValueError("invalid event directory")
    if private:
        os.chmod(folder, 0o700)
    return folder


def atomic_json(target, event):
    target = Path(target)
    if target.is_symlink():
        raise ValueError("symlink file rejected")
    fd, temp = tempfile.mkstemp(prefix=".event-", dir=target.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(event, stream, ensure_ascii=False)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temp, target)
    finally:
        if os.path.exists(temp):
            os.unlink(temp)


def write_event(folder, event):
    atomic_json(secure_folder(folder) / "latest.json", event)


def write_multi_event(folder, event):
    folder = secure_folder(Path(folder) / "events")
    # One file per turn prevents two conversations from overwriting each other.
    # Lock read-modify-write so a late Stop retains the original start time.
    lock = os.open(folder / ".lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX)
        target = folder / (event["threadID"] + "_" + event["turnID"] + ("_preview" if event["isPreview"] else "") + ".json")
        if target.is_symlink():
            raise ValueError("symlink event rejected")
        prior = {}
        if target.exists() and target.stat().st_size <= 8192:
            try:
                prior = json.loads(target.read_text())
                if not isinstance(prior, dict):
                    prior = {}
            except ValueError:
                prior = {}
        event = dict(event)
        event["startedAt"] = prior.get("startedAt", event["timestamp"])
        # Interrupted is terminal; a late Stop must not resurrect this turn.
        if prior.get("state") == "interrupted" or prior.get("timestamp", 0) > event["timestamp"]:
            return
        atomic_json(target, event)
        # Keep at most 512 turn envelopes; never follow or remove a symlink.
        files = sorted((p for p in folder.glob("*.json") if EVENT_FILE.fullmatch(p.name)
                        and not p.is_symlink() and p.is_file()),
                       key=lambda p: p.stat().st_mtime, reverse=True)
        for index, path in enumerate(files):
            if index >= 512 or path.stat().st_mtime < time.time() - 86400:
                path.unlink()
    finally:
        os.close(lock)


def indexed_title(home, thread):
    """Read only the bounded title index, never a conversation transcript."""
    path = Path(home) / ".codex/session_index.jsonl"
    if path.is_symlink() or not path.is_file():
        return None
    with path.open("rb") as stream:
        stream.seek(0, 2)
        start = max(0, stream.tell() - 262144)
        stream.seek(start)
        if start:
            stream.readline()
        for line in reversed(stream.read(262144).splitlines()):
            try:
                row = json.loads(line)
                if row.get("id") == thread and isinstance(row.get("thread_name"), str):
                    return row["thread_name"][:100] or None
            except (ValueError, AttributeError):
                continue
    return None


def is_narc_handler(handler):
    if not isinstance(handler, dict) or handler.get("type") != "command":
        return False
    try:
        args = shlex.split(handler.get("command", ""))
    except ValueError:
        return False
    return (len(args) >= 3 and Path(args[0]).name.startswith("python3")
            and Path(args[1]).name in ("narc-codex-hook.py", "narc-codex-hook-v2.py")
            and args[2] in ("--thread", "--all"))


def merged_hooks(config, command):
    # Preserve unrelated fields, groups, handlers and their trust-sensitive indices.
    if not isinstance(config, dict):
        raise ValueError("invalid hook config")
    result = json.loads(json.dumps(config))
    hooks = result.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise ValueError("invalid hooks object")
    for event in ("UserPromptSubmit", "Stop", "Interrupt"):
        groups = hooks.setdefault(event, [])
        if not isinstance(groups, list):
            raise ValueError("invalid hook groups")
        found = False
        for group in groups:
            if not isinstance(group, dict):
                raise ValueError("invalid hook group")
            handlers = group.get("hooks", [])
            if not isinstance(handlers, list):
                raise ValueError("invalid handlers")
            for i, handler in enumerate(handlers):
                if is_narc_handler(handler):
                    handlers[i] = dict(type="command", command=command, timeout=3)
                    found = True
        if not found:
            groups.append({"hooks": [dict(type="command", command=command, timeout=3)]})
    return result


def install_hooks(home, script):
    home = Path(home)
    destination = secure_folder(home / "Library/Application Support/NARC/codex-completion")
    codex = secure_folder(home / ".codex", private=False)
    target = codex / "hooks.json"
    if target.is_symlink() or (target.exists() and (not target.is_file() or target.stat().st_size > LIMIT)):
        raise ValueError("unsafe hook config")
    original = target.read_bytes() if target.exists() else None
    config = json.loads(original) if original is not None else {}
    installed = destination / "narc-codex-hook-v2.py"
    if installed.is_symlink():
        raise ValueError("unsafe adapter path")
    command = shlex.join([sys.executable, str(installed), "--all"])
    merged = merged_hooks(config, command)
    # Backup is private, unique and contains only hook definitions (never config.toml).
    backup = destination / ("hooks-backup-" + str(uuid.uuid4()) + ".json")
    if original is not None and merged != config:
        atomic_json(backup, config)
    fd, temporary = tempfile.mkstemp(prefix=".adapter-", dir=destination)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(Path(script).read_bytes())
        os.replace(temporary, installed)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    if (target.read_bytes() if target.exists() else None) != original:
        raise ValueError("hook config changed concurrently; retry")
    if merged != config:
        atomic_json(target, merged)
    return {"configured": True, "changed": merged != config, "requiresReview": True}


def notify_folder(home):
    return Path(home) / "Library/Application Support/NARC/codex-completion"


def checked_bytes(path):
    for part in [*path.parents, path]:
        if part.is_symlink():
            raise ValueError("不支持符号链接配置，请保持原连接并联系维护者。")
    if not path.exists():
        return None
    info = path.stat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_size > LIMIT:
        raise ValueError("配置文件无法安全读取，原设置保持不变。")
    return path.read_bytes()


def notification_config(home):
    import tomllib
    target = Path(home) / ".codex/config.toml"
    raw = checked_bytes(target)
    data = tomllib.loads(raw.decode() if raw else "")
    previous = data.get("notify")
    if previous is not None and (not isinstance(previous, list) or
                                not all(isinstance(x, str) and "\0" not in x for x in previous)):
        raise ValueError("现有通知设置格式不兼容，未覆盖原设置。")
    if data.get("profile") or any("notify" in v for v in data.get("profiles", {}).values() if isinstance(v, dict)):
        raise ValueError("当前使用独立配置方案，暂不支持自动接入；原提醒仍保留。")
    return target, raw, data


def notification_text(raw, data, command):
    import tomllib
    lines = (raw.decode() if raw else "").splitlines(keepends=True)
    if "notify" in data:
        candidates = [i for i, line in enumerate(lines) if re.match(r"^\s*notify\s*=", line)]
        found = False
        for start in candidates:
            for end in range(start + 1, min(len(lines), start + 100) + 1):
                try:
                    entry = tomllib.loads("".join(lines[start:end]))
                except ValueError:
                    continue
                if entry == {"notify": data["notify"]}:
                    remaining = "".join(lines[:start] + lines[end:])
                    expected = {k: v for k, v in data.items() if k != "notify"}
                    if tomllib.loads(remaining) == expected:
                        lines[start:end] = []
                        found = True
                    break
            if found:
                break
        if not found:
            raise ValueError("现有通知设置写法暂不兼容，未覆盖原设置。")
    prefix = "notify = " + json.dumps(command, ensure_ascii=False) + "\n" if command is not None else ""
    candidate = prefix + "".join(lines)
    expected = {k: v for k, v in data.items() if k != "notify"}
    if command is not None:
        expected["notify"] = command
    if tomllib.loads(candidate) != expected:
        raise ValueError("配置保护检查未通过，原设置保持不变。")
    return candidate.encode()


def atomic_bytes(path, raw):
    checked_bytes(path)
    fd, temporary = tempfile.mkstemp(prefix=".narc-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def connection_record(home, connection):
    if str(uuid.UUID(connection)) != connection:
        raise ValueError("invalid connection")
    raw = checked_bytes(notify_folder(home) / ("notify-" + connection + ".json"))
    if raw is None:
        raise ValueError("连接备份缺失，未覆盖现有通知。")
    record = json.loads(raw)
    previous = record.get("previous")
    if previous is not None and (not isinstance(previous, list) or
                                not all(isinstance(x, str) and "\0" not in x for x in previous)):
        raise ValueError("原通知备份格式错误。")
    if previous and any(NOTIFY_SCRIPT.search(x) for x in previous):
        raise ValueError("发现循环通知配置，已停止接入。")
    return record


def current_connection(home, command):
    # The desktop client may retain our argv under its own notification callback.
    # Recognize only the observed local helper and never execute during inspection.
    helper = str(Path(home) / ".codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient")
    for _ in range(8):
        if not isinstance(command, list) or len(command) != 4 or command[:3] != [helper, "turn-ended", "--previous-notify"]:
            break
        command = json.loads(command[3])
        if not isinstance(command, list) or not all(isinstance(x, str) and "\0" not in x for x in command):
            raise ValueError("连接信息无法识别，请展开详情联系维护者；无需重复连接。")
    else:
        raise ValueError("连接信息层级异常；请联系维护者，无需重复连接。")
    if not isinstance(command, list) or len(command) != 4 or command[2] != "--notify":
        return None
    if not NOTIFY_SCRIPT.fullmatch(Path(command[1]).name):
        return None
    record = connection_record(home, command[3])
    if record.get("command") != command:
        raise ValueError("通知配置与备份不匹配。")
    path = Path(command[1])
    if path.parent != notify_folder(home) or not path.name.startswith("narc-notify-"):
        raise ValueError("通知程序位置不匹配。")
    source = checked_bytes(path)
    if source is None or hashlib.sha256(source).hexdigest() != record.get("scriptHash"):
        raise ValueError("提醒组件缺失或已改变，请重新安装 NARC。")
    return record


def notify_status(home):
    _, _, data = notification_config(home)
    record = current_connection(home, data.get("notify"))
    if record is None:
        return {"status": "notConfigured"}
    receipt = checked_bytes(notify_folder(home) / ("receipt-" + record["id"] + ".json"))
    seen = json.loads(receipt).get("receivedAt", 0) if receipt else 0
    connected = isinstance(seen, (int, float)) and record["configuredAt"] <= seen <= time.time() + 30
    return {"status": "connected" if connected else "waiting", "receivedAt": seen if connected else None}


def install_notify(home, script):
    folder = secure_folder(notify_folder(home))
    lock = os.open(folder / ".notify-lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX)
        target, raw, data = notification_config(home)
        previous = data.get("notify")
        source = Path(script).read_bytes()
        digest = hashlib.sha256(source).hexdigest()
        existing = current_connection(home, previous)
        if existing:
            if previous != existing["command"]:
                # Keep the client's wrapper and the validated immutable adapter.
                # Replacing the outer callback can create a recursive chain.
                return notify_status(home)
            if existing["scriptHash"] == digest:
                return notify_status(home)
            previous = existing["previous"]
        elif previous and any(NOTIFY_SCRIPT.search(x) for x in previous):
            raise ValueError("其他程序已调整通知链路，未覆盖，请联系维护者。")
        connection = str(uuid.uuid4())
        installed = folder / ("narc-notify-" + digest[:16] + ".py")
        command = [sys.executable, str(installed), "--notify", connection]
        candidate = notification_text(raw, data, command)
        record = dict(id=connection, command=command, previous=previous,
                      configuredAt=time.time(), scriptHash=digest)
        # Immutable generations keep callbacks from an older running client safe.
        atomic_bytes(installed, source)
        atomic_json(folder / ("notify-" + connection + ".json"), record)
        secure_folder(target.parent, private=False)
        if checked_bytes(target) != raw:
            raise ValueError("客户端同时更新了配置，请再点一次连接。")
        atomic_bytes(target, candidate)
        return notify_status(home)
    finally:
        os.close(lock)


def receive_notify(home, connection, raw, launch=subprocess.Popen):
    record = connection_record(home, connection)
    previous = record["previous"]
    # The user explicitly opts into forwarding the unchanged payload to their
    # already-configured callback. Never use a shell or log this payload.
    if previous:
        try:
            launch(previous + [raw], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, start_new_session=True)
        except OSError:
            pass
    if len(raw.encode()) > LIMIT:
        return
    data = json.loads(raw)
    if not isinstance(data, dict) or data.get("type") != "agent-turn-complete":
        return
    event = normalize(dict(session_id=data.get("thread-id"), turn_id=data.get("turn-id"),
                           hook_event_name="Stop", agent_id=data.get("agent_id"),
                           subagent_id=data.get("subagent_id")))
    if event:
        event["source"] = "notify"
        try:
            event["title"] = indexed_title(home, event["threadID"]) or event["title"]
        except OSError:
            pass
        write_multi_event(notify_folder(home), event)
        atomic_json(notify_folder(home) / ("receipt-" + connection + ".json"), {"receivedAt": event["timestamp"]})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--thread")
    mode.add_argument("--all", action="store_true")
    mode.add_argument("--install", action="store_true")
    mode.add_argument("--install-notify", action="store_true")
    mode.add_argument("--notify-status", action="store_true")
    mode.add_argument("--notify", nargs=2, metavar=("CONNECTION", "EVENT"))
    parser.add_argument("--title")
    parser.add_argument("--preview", action="store_true")
    args = parser.parse_args()
    try:
        if args.install_notify or args.notify_status:
            if os.environ.get("CODEX_HOME") and Path(os.environ["CODEX_HOME"]) != Path.home() / ".codex":
                raise ValueError("自定义客户端配置位置暂不支持自动连接，原设置保持不变。")
            result = install_notify(Path.home(), __file__) if args.install_notify else notify_status(Path.home())
            print(json.dumps(result))
            return 0
        if args.notify:
            receive_notify(Path.home(), *args.notify)
            return 0
        if args.install:
            print(json.dumps(install_hooks(Path.home(), __file__)))
            return 0
        raw = sys.stdin.buffer.read(LIMIT + 1)
        if len(raw) > LIMIT:
            return 0
        event = normalize(json.loads(raw), args.thread, args.title, preview=args.preview)
        if event:
            folder = Path.home() / "Library/Application Support/NARC/codex-completion"
            if args.all:
                try:
                    event["title"] = indexed_title(Path.home(), event["threadID"]) or event["title"]
                except OSError:
                    pass  # A missing/unreadable title must not drop the completion.
                write_multi_event(folder, event)
            else:
                write_event(folder, event)
    except (ValueError, OSError, TypeError, KeyError, ImportError) as error:
        if args.install_notify or args.notify_status:
            message = (str(error) if isinstance(error, ValueError) and not isinstance(error, json.JSONDecodeError)
                       else "连接检查未完成。请确认 Python 3.11 或更新版本可用，并重新安装 NARC 后重试。")
            # Only our localized messages may reach UI; parser errors can contain config text.
            if not message or not ('\u4e00' <= message[0] <= '\u9fff'):
                message = "无法安全读取客户端配置；原有提醒和权限保持不变。"
            print(json.dumps({"status": "error", "message": message}))
            return 1
        # Notification failure must not block the user's actual task. No payload in logs.
        print("NARC completion adapter: event not recorded", file=sys.stderr)
        if args.install:
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
