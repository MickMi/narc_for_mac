#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import os
import shlex
import time
import uuid
import tomllib
from unittest.mock import Mock, patch
from concurrent.futures import ThreadPoolExecutor

spec = importlib.util.spec_from_file_location("adapter", Path(__file__).parents[1] / "narc-codex-hook.py")
adapter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adapter)
THREAD = "00000000-0000-0000-0000-000000000001"
TURN = "00000000-0000-0000-0000-000000000002"


class CodexHookTests(unittest.TestCase):
    def payload(self, **extra):
        return dict(session_id=THREAD, turn_id=TURN, hook_event_name="Stop", **extra)

    def test_only_metadata_survives(self):
        event = adapter.normalize(self.payload(last_assistant_message="PRIVATE", transcript_path="PRIVATE", prompt="PRIVATE"), THREAD, "Test", now=123)
        self.assertEqual(event["state"], "replyReady")
        self.assertNotIn("PRIVATE", json.dumps(event))
        self.assertEqual(set(event), {"schemaVersion", "threadID", "turnID", "state", "title", "timestamp", "isPreview"})

    def test_other_thread_is_ignored(self):
        self.assertIsNone(adapter.normalize(self.payload(), TURN, "Test"))

    def test_subagent_is_ignored(self):
        self.assertIsNone(adapter.normalize(self.payload(agent_id="subagent"), THREAD, "Test"))

    def test_unknown_and_non_object_are_ignored(self):
        for data in [[], None, {**self.payload(), "hook_event_name": "SessionEnd"}]:
            self.assertIsNone(adapter.normalize(data, THREAD, "Test"))

    def test_invalid_id_is_ignored(self):
        for value in [None, 1, "../anything"]:
            self.assertIsNone(adapter.normalize({**self.payload(), "turn_id": value}, THREAD, "Test"))

    def test_working_and_interrupt_are_not_completion(self):
        for event, expected in [("UserPromptSubmit", "running"), ("Interrupt", "interrupted")]:
            result = adapter.normalize({**self.payload(), "hook_event_name": event}, THREAD, "Test")
            self.assertEqual(result["state"], expected)

    def test_atomic_private_write_and_replace(self):
        with tempfile.TemporaryDirectory() as root:
            folder = Path(root).resolve() / "events"
            event = adapter.normalize(self.payload(), THREAD, "Test", now=123)
            adapter.write_event(folder, event)
            adapter.write_event(folder, event)
            self.assertEqual(json.loads((folder / "latest.json").read_text()), event)
            self.assertEqual((folder / "latest.json").stat().st_mode & 0o777, 0o600)
            self.assertEqual(folder.stat().st_mode & 0o777, 0o700)
            self.assertEqual(len(list(folder.iterdir())), 1)

    def test_symlink_folder_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            link = Path(root).resolve() / "link"
            link.symlink_to(Path(root) / "missing")
            with self.assertRaises(ValueError):
                adapter.write_event(link, {})

    def test_symlink_file_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            (Path(root) / "latest.json").symlink_to(Path(root) / "missing")
            with self.assertRaises(ValueError):
                adapter.write_event(Path(root).resolve(), {})

    def test_global_concurrent_threads_do_not_overwrite(self):
        with tempfile.TemporaryDirectory() as root:
            folder = Path(root).resolve()
            events = [adapter.normalize({**self.payload(), "session_id": str(uuid.uuid4())}) for _ in range(24)]
            with ThreadPoolExecutor(max_workers=8) as pool:
                list(pool.map(lambda e: adapter.write_multi_event(folder, e), events))
            saved = [json.loads(p.read_text()) for p in (folder / "events").glob("*.json")]
            self.assertEqual({e["threadID"] for e in saved}, {e["threadID"] for e in events})
            self.assertTrue(all(e["startedAt"] == e["timestamp"] for e in saved))

    def test_start_time_preserved_and_interrupt_is_terminal(self):
        with tempfile.TemporaryDirectory() as root:
            folder = Path(root).resolve()
            start = adapter.normalize({**self.payload(), "hook_event_name": "UserPromptSubmit"}, now=100)
            adapter.write_multi_event(folder, start)
            adapter.write_multi_event(folder, adapter.normalize(self.payload(), now=110))
            target = next((folder / "events").glob("*.json"))
            self.assertEqual(json.loads(target.read_text())["startedAt"], 100)
            adapter.write_multi_event(folder, adapter.normalize({**self.payload(), "hook_event_name": "Interrupt"}, now=120))
            adapter.write_multi_event(folder, adapter.normalize(self.payload(), now=130))
            self.assertEqual(json.loads(target.read_text())["state"], "interrupted")

    def test_retention_does_not_remove_unrelated_files(self):
        with tempfile.TemporaryDirectory() as root:
            folder = Path(root).resolve()
            adapter.write_multi_event(folder, adapter.normalize(self.payload()))
            target = next((folder / "events").glob("*.json"))
            unrelated = folder / "events/notes.json"
            unrelated.write_text("KEEP")
            for path in (target, unrelated):
                os.utime(path, (time.time() - 90000,) * 2)
            adapter.write_multi_event(folder, adapter.normalize({**self.payload(), "turn_id": str(uuid.uuid4())}))
            self.assertFalse(target.exists())
            self.assertEqual(unrelated.read_text(), "KEEP")

    def test_title_index_metadata_only_and_last_title_wins(self):
        with tempfile.TemporaryDirectory() as root:
            home = Path(root).resolve()
            (home / ".codex").mkdir()
            (home / ".codex/session_index.jsonl").write_text("\n".join([
                json.dumps(dict(id=THREAD, thread_name="old")), "invalid",
                json.dumps(dict(id=THREAD, thread_name="new")),
            ]))
            self.assertEqual(adapter.indexed_title(home, THREAD), "new")
            self.assertIsNone(adapter.indexed_title(home, TURN))

    def test_install_merges_idempotently_preserves_trust_and_notify(self):
        with tempfile.TemporaryDirectory(prefix="narc user's test ") as root:
            home = Path(root).resolve()
            codex = home / ".codex"
            codex.mkdir(mode=0o755)
            original_mode = codex.stat().st_mode
            other = dict(hooks=[dict(type="command", command="harness-observer", timeout=3)])
            legacy = dict(hooks=[dict(type="command", command="python3 /old/narc-codex-hook.py --thread " + THREAD)])
            config = dict(extra="preserve", hooks={"Stop": [other, legacy], "SessionStart": [other]})
            (codex / "hooks.json").write_text(json.dumps(config))
            (codex / "config.toml").write_text('notify = ["unchanged"]\ntrust_hash = "unchanged"\n')
            self.assertTrue(adapter.install_hooks(home, spec.origin)["changed"])
            merged = json.loads((codex / "hooks.json").read_text())
            self.assertEqual(merged["hooks"]["Stop"][0], other)
            self.assertEqual(merged["hooks"]["SessionStart"], [other])
            self.assertEqual(merged["extra"], "preserve")
            command = merged["hooks"]["Stop"][1]["hooks"][0]["command"]
            args = shlex.split(command)
            self.assertEqual(args[2], "--all")
            self.assertTrue(Path(args[1]).is_file())
            self.assertEqual(Path(args[1]).read_bytes(), Path(spec.origin).read_bytes())
            self.assertFalse(adapter.install_hooks(home, spec.origin)["changed"])
            self.assertEqual(len(list(Path(args[1]).parent.glob("hooks-backup-*.json"))), 1)
            self.assertEqual((codex / "config.toml").read_text(), 'notify = ["unchanged"]\ntrust_hash = "unchanged"\n')
            self.assertEqual(codex.stat().st_mode, original_mode)

    def test_install_rejects_malformed_config_without_overwrite(self):
        with tempfile.TemporaryDirectory() as root:
            home = Path(root).resolve()
            (home / ".codex").mkdir()
            target = home / ".codex/hooks.json"
            for content in ['[]', '{"hooks":{"Stop":[1]}}', 'not json']:
                target.write_text(content)
                with self.assertRaises(ValueError):
                    adapter.install_hooks(home, spec.origin)
                self.assertEqual(target.read_text(), content)

    def test_global_symlink_event_and_config_are_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            folder = Path(root).resolve()
            (folder / "events").mkdir()
            (folder / "events" / (THREAD + "_" + TURN + ".json")).symlink_to(folder / "missing")
            with self.assertRaises(ValueError):
                adapter.write_multi_event(folder, adapter.normalize(self.payload()))
            (folder / ".codex").mkdir()
            (folder / ".codex/hooks.json").symlink_to(folder / "missing")
            with self.assertRaises(ValueError):
                adapter.install_hooks(folder, spec.origin)


class NotifyTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="narc notify user's ")
        self.home = Path(self.tmp.name).resolve()
        self.config = self.home / ".codex/config.toml"
        self.config.parent.mkdir()
        self.previous = ["/old application/notify", "turn-ended", "quoted ' argument"]
        self.config.write_text('notify = ' + json.dumps(self.previous) + '\n# KEEP\n[features]\nhooks = true\n')
        self.payload = json.dumps({"type": "agent-turn-complete", "thread-id": THREAD, "turn-id": TURN,
                                   "input-messages": ["PRIVATE_BODY"], "last-assistant-message": "PRIVATE_BODY"})

    def tearDown(self):
        self.tmp.cleanup()

    def connect(self):
        result = adapter.install_notify(self.home, spec.origin)
        command = tomllib.loads(self.config.read_text())["notify"]
        return result, command[3]

    def test_idempotent_preserves_other_settings_and_original_notification(self):
        hooks = self.config.parent / "hooks.json"
        hooks.write_text('{"unchanged":true}')
        self.assertEqual(adapter.notify_status(self.home)["status"], "notConfigured")
        result, connection = self.connect()
        self.assertEqual(result["status"], "waiting")
        original = self.config.read_bytes()
        self.assertEqual(self.connect()[1], connection)
        self.assertEqual(self.config.read_bytes(), original)
        record = adapter.connection_record(self.home, connection)
        self.assertEqual(record["previous"], self.previous)
        self.assertIn("# KEEP", self.config.read_text())
        self.assertEqual(tomllib.loads(self.config.read_text())["features"], {"hooks": True})
        self.assertEqual(hooks.read_text(), '{"unchanged":true}')
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)

    def test_forwards_exact_payload_but_narc_persists_metadata_only(self):
        _, connection = self.connect()
        callback = Mock()
        adapter.receive_notify(self.home, connection, self.payload, launch=callback)
        self.assertEqual(callback.call_args.args[0], self.previous + [self.payload])
        self.assertNotIn("shell", callback.call_args.kwargs)
        self.assertEqual(adapter.notify_status(self.home)["status"], "connected")
        folder = adapter.notify_folder(self.home)
        for path in folder.rglob("*.json"):
            self.assertNotIn("PRIVATE_BODY", path.read_text())
        event = json.loads(next((folder / "events").glob("*.json")).read_text())
        self.assertEqual(event["source"], "notify")
        self.assertEqual(event["threadID"], THREAD)
        adapter.receive_notify(self.home, connection, self.payload, launch=callback)
        self.assertEqual(len(list((folder / "events").glob("*.json"))), 1)

    def wrap_connection(self, command):
        helper = self.home / ".codex/computer-use/Codex Computer Use.app/Contents/SharedSupport/SkyComputerUseClient.app/Contents/MacOS/SkyComputerUseClient"
        return [str(helper), "turn-ended", "--previous-notify", json.dumps(command)]

    def test_client_wrapper_preserves_waiting_then_real_receipt(self):
        _, connection = self.connect()
        command = tomllib.loads(self.config.read_text())["notify"]
        wrapped = self.wrap_connection(command)
        self.config.write_text("notify=" + json.dumps(wrapped))
        before = self.config.read_bytes()
        self.assertEqual(adapter.notify_status(self.home)["status"], "waiting")
        adapter.receive_notify(self.home, connection, self.payload, launch=Mock())
        self.assertEqual(adapter.notify_status(self.home)["status"], "connected")
        self.assertEqual(self.config.read_bytes(), before)

    def test_wrapped_reconnect_and_upgrade_do_not_rewrite_client_chain(self):
        _, connection = self.connect()
        command = tomllib.loads(self.config.read_text())["notify"]
        self.config.write_text("notify=" + json.dumps(self.wrap_connection(command)))
        before = self.config.read_bytes()
        script = self.home / "new.py"
        script.write_bytes(Path(spec.origin).read_bytes() + b"\n# upgrade\n")
        for source in [spec.origin, script]:
            self.assertEqual(adapter.install_notify(self.home, source)["status"], "waiting")
            self.assertEqual(self.config.read_bytes(), before)

    def test_unknown_wrapper_is_not_a_connection(self):
        self.connect()
        wrapped = self.wrap_connection(tomllib.loads(self.config.read_text())["notify"])
        wrapped[0] = "/unknown/SkyComputerUseClient"
        self.assertIsNone(adapter.current_connection(self.home, wrapped))

    def test_broken_or_overdeep_wrapper_fails_closed(self):
        self.connect()
        command = tomllib.loads(self.config.read_text())["notify"]
        broken = self.wrap_connection(command)
        broken[3] = "not JSON"
        with self.assertRaises(ValueError):
            adapter.current_connection(self.home, broken)
        for _ in range(9):
            command = self.wrap_connection(command)
        with self.assertRaises(ValueError):
            adapter.current_connection(self.home, command)

    def test_hook_and_preview_do_not_confirm_connection(self):
        _, connection = self.connect()
        adapter.write_multi_event(adapter.notify_folder(self.home), adapter.normalize({
            "session_id": THREAD, "turn_id": TURN, "hook_event_name": "Stop"}))
        self.assertEqual(adapter.notify_status(self.home)["status"], "waiting")
        callback = Mock()
        for payload in ["{}", json.dumps({"type": "interrupted"}), json.dumps({
                "type": "agent-turn-complete", "thread-id": THREAD, "turn-id": "invalid"}),
                json.dumps({**json.loads(self.payload), "agent_id": "child"})]:
            adapter.receive_notify(self.home, connection, payload, launch=callback)
        self.assertEqual(adapter.notify_status(self.home)["status"], "waiting")
        self.assertEqual(callback.call_count, 4)

    def test_callback_failure_does_not_drop_narc_event(self):
        _, connection = self.connect()
        adapter.receive_notify(self.home, connection, self.payload, launch=Mock(side_effect=OSError()))
        self.assertEqual(adapter.notify_status(self.home)["status"], "connected")

    def test_invalid_payload_still_reaches_original_callback(self):
        _, connection = self.connect()
        callback = Mock()
        with self.assertRaises(ValueError):
            adapter.receive_notify(self.home, connection, "not json", launch=callback)
        callback.assert_called_once()
        self.assertEqual(adapter.notify_status(self.home)["status"], "waiting")

    def test_multiline_notify_and_absent_notify_are_preserved(self):
        for text in ['# keep\nnotify = [\n "x", # preserve behavior\n "y",\n]\n[a]\nb = 1\n', '[a]\nb = 1\n', 'notify = []\n']:
            data = tomllib.loads(text)
            new = adapter.notification_text(text.encode(), data, ["new"])
            self.assertEqual(tomllib.loads(new.decode()), {**data, "notify": ["new"]})

    def test_unsafe_or_complex_config_fails_closed(self):
        for text in ['notify = "wrong"', 'notify = ["x"]\n[profiles.p]\nnotify=["y"]', 'not toml']:
            self.config.write_text(text)
            with self.assertRaises(ValueError):
                self.connect()
            self.assertEqual(self.config.read_text(), text)
        self.config.unlink()
        self.config.symlink_to(self.home / "missing")
        with self.assertRaises(ValueError):
            self.connect()

    def test_other_notification_change_does_not_claim_connected(self):
        _, connection = self.connect()
        adapter.receive_notify(self.home, connection, self.payload, launch=Mock())
        self.config.write_text('notify=["another"]\n')
        self.assertEqual(adapter.notify_status(self.home)["status"], "notConfigured")

    def test_concurrent_install_keeps_one_generation(self):
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda _: self.connect()[1], range(8)))
        self.assertEqual(len(set(results)), 1)
        self.assertEqual(adapter.connection_record(self.home, results[0])["previous"], self.previous)

    def test_script_upgrade_does_not_nest_and_old_generation_is_safe(self):
        _, old = self.connect()
        script = self.home / "new.py"
        script.write_bytes(Path(spec.origin).read_bytes() + b'\n# new version\n')
        adapter.install_notify(self.home, script)
        new = tomllib.loads(self.config.read_text())["notify"][3]
        self.assertNotEqual(old, new)
        self.assertEqual(adapter.connection_record(self.home, new)["previous"], self.previous)
        adapter.receive_notify(self.home, old, self.payload, launch=Mock())
        self.assertEqual(adapter.notify_status(self.home)["status"], "waiting")

    def test_config_race_preserves_external_writer(self):
        original_atomic = adapter.atomic_bytes
        def concurrent_write(path, raw):
            original_atomic(path, raw)
            if path.suffix == ".py":
                self.config.write_text('notify=["external change"]\n')
        with patch.object(adapter, "atomic_bytes", side_effect=concurrent_write):
            with self.assertRaisesRegex(ValueError, "同时更新"):
                self.connect()
        self.assertEqual(self.config.read_text(), 'notify=["external change"]\n')

    def test_similar_directory_name_is_not_a_recursive_callback(self):
        previous = ["/tmp/narc-notify-fixture/normal.py"]
        self.config.write_text("notify=" + json.dumps(previous))
        _, connection = self.connect()
        self.assertEqual(adapter.connection_record(self.home, connection)["previous"], previous)
        wrapped = ["/wrapper", json.dumps(["python3", "/path/narc-notify-0123456789abcdef.py"])]
        self.config.write_text("notify=" + json.dumps(wrapped))
        with self.assertRaisesRegex(ValueError, "调整通知链路"):
            self.connect()


if __name__ == "__main__":
    unittest.main()
