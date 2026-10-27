"""Headless scheduled runs in direct mode: chat files, KWallet, the provider call,
run state, notifications (fake HTTP server, fake busctl/notify-send, temp folders)."""
import datetime as dt
import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

from kdeaichat import qsettings_ini, schedule_chat, schedule_exec, schedule_job, schedule_runs, schedule_store
from kdeaichat.schedule_model import iso

KEY = "sk-test-not-a-real-key"
NOW = dt.datetime(2026, 10, 27, 9, 0)


class FakeProvider:
    """An OpenAI-compatible / Anthropic endpoint that records requests."""

    def __init__(self, status=200, reply="Here are today's headlines.", kind="openai"):
        self.requests = []
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                outer.requests.append({"path": self.path, "headers": {k.lower(): v for k, v in self.headers.items()}, "body": body})
                if status != 200:
                    data = json.dumps({"error": {"message": "invalid key"}}).encode()
                elif kind == "anthropic":
                    data = json.dumps({"content": [{"type": "text", "text": reply}],
                                       "usage": {"input_tokens": 12, "output_tokens": 5}}).encode()
                else:
                    data = json.dumps({"choices": [{"message": {"role": "assistant", "content": "<think>hmm</think>" + reply}}],
                                       "usage": {"prompt_tokens": 12, "completion_tokens": 5}}).encode()
                self.send_response(status)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        # 127.0.0.2: still loopback, but not a "local provider" URL (those may run without a key)
        self.server = ThreadingHTTPServer(("127.0.0.2", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.2:{self.server.server_address[1]}/v1"

    def close(self):
        self.server.shutdown()


@pytest.fixture
def provider():
    servers = []

    def make(**kw):
        servers.append(FakeProvider(**kw))
        return servers[-1]
    yield make
    for s in servers:
        s.close()


SCHEDULE = {"id": "news-1", "name": "Daily news", "chatId": "s-1", "message": "News for {{weekday}} {{date}} since {{last_run}}",
            "notify": True}


def setup_direct(chat_env, server, provider_id="nvidia", **config):
    chat_env.config(provider=provider_id, contextMessageLimit=2, systemPrompt="Be brief.", userName="Ana",
                    providersJson=[{"id": provider_id, "name": "Test", "type": "openai-compat",
                                    "baseUrl": server.url, "model": "test/model-1"}], **config)
    chat_env.wallet("open", {"KDEAIChat": {provider_id: KEY}})
    old = [{"role": "user", "content": "first"}, {"role": "assistant", "content": "one"},
           {"role": "user", "content": "second"}, {"role": "assistant", "content": "two"}]
    chat_env.add_chat("s-1", old, chatSystemPrompt="Answer in English.")


def test_direct_run_appends_to_the_chat_and_notifies(chat_env, provider):
    server = provider()
    setup_direct(chat_env, server)
    status = schedule_exec.run_prompt(dict(SCHEDULE), "2026-10-26T09:00:05", NOW)
    assert status == "ok"
    req = server.requests[0]
    assert req["path"] == "/v1/chat/completions" and req["headers"]["authorization"] == "Bearer " + KEY
    body = req["body"]
    assert body["model"] == "test/model-1" and body["stream"] is False and body["max_tokens"] == 4096
    system = body["messages"][0]
    assert system["role"] == "system" and system["content"].startswith("## About the user\nName: Ana")
    assert "Be brief." in system["content"] and "Answer in English." in system["content"]
    # contextMessageLimit 2: the last two old messages plus the scheduled prompt
    assert [m["content"] for m in body["messages"][1:]] == ["second", "two", "News for Tuesday 2026-10-27 since 2026-10-26 09:00"]
    messages = chat_env.messages("s-1")
    assert len(messages) == 6
    user, reply = messages[-2:]
    assert user["role"] == "user" and user["scheduled"] is True and user["scheduleName"] == "Daily news"
    assert user["content"] == "News for Tuesday 2026-10-27 since 2026-10-26 09:00"
    assert reply["role"] == "assistant" and reply["content"] == "Here are today's headlines."
    assert reply["reasoning"] == "hmm" and reply["tokens"] == {"input": 12, "output": 5} and reply["model"] == "test/model-1"
    assert user["scheduleRunId"] == reply["scheduleRunId"]
    # the same run is also in the inbox for an open widget; it was notified here (no Plasma)
    (name,) = chat_env.inbox()
    entry = chat_env.inbox_entry(name)
    assert entry["chatId"] == "s-1" and entry["notified"] is True and entry["messages"] == [user, reply]
    notes = chat_env.sched.recorded("fake-notify-send")
    assert notes and notes[-1][-2:] == ["Daily news is ready", "A new reply is ready"]
    assert not any("headlines" in " ".join(call) for call in chat_env.sched.recorded("fake-notify-send"))
    # the key never reaches a command line
    assert all(KEY not in " ".join(call) for call in chat_env.sched.recorded())


def test_open_widget_gets_the_notification_instead(chat_env, provider, monkeypatch):
    server = provider()
    setup_direct(chat_env, server)
    monkeypatch.setenv("KDEAICHAT_WIDGET_RUNNING", "1")
    assert schedule_exec.run_prompt(dict(SCHEDULE), None, NOW) == "ok"
    entry = chat_env.inbox_entry(chat_env.inbox()[0])
    assert entry["notify"] is True and entry["notified"] is False
    assert chat_env.sched.recorded("fake-notify-send") == []
    assert "since never" in entry["messages"][0]["content"]


def test_wallet_locked_skips_and_notifies(chat_env, provider):
    server = provider()
    setup_direct(chat_env, server)
    chat_env.wallet("closed")
    before = chat_env.messages("s-1")
    assert schedule_exec.run_prompt(dict(SCHEDULE), None, NOW) == "skipped: wallet locked"
    assert server.requests == [] and chat_env.messages("s-1") == before and chat_env.inbox() == []
    title, body = chat_env.sched.recorded("fake-notify-send")[-1][-2:]
    assert title == "Daily news: skipped" and "KWallet is locked" in body
    # it never asked to open the wallet
    assert not any("open" in call and "sxs" in call for call in chat_env.sched.recorded("fake-busctl-wallet"))


def test_local_provider_runs_without_a_key_even_when_locked(chat_env, provider):
    server = provider()
    setup_direct(chat_env, server, provider_id="ollama")
    chat_env.wallet("down")
    assert schedule_exec.run_prompt(dict(SCHEDULE), None, NOW) == "ok"
    assert "authorization" not in server.requests[0]["headers"]


def test_dev_wallet_folder_override(chat_env, provider, monkeypatch):
    server = provider()
    setup_direct(chat_env, server)
    chat_env.wallet("open", {"KDEAIChat-dev": {"nvidia": KEY}})
    monkeypatch.setenv("KDEAICHAT_WALLET_FOLDER", "KDEAIChat-dev")
    assert schedule_exec.run_prompt(dict(SCHEDULE), None, NOW) == "ok"


def test_rejected_key_is_an_error_and_the_chat_is_untouched(chat_env, provider):
    server = provider(status=401)
    setup_direct(chat_env, server)
    before = chat_env.messages("s-1")
    status = schedule_exec.run_prompt(dict(SCHEDULE), None, NOW)
    assert status.startswith("error: The provider rejected the API key (HTTP 401)") and "invalid key" in status
    assert chat_env.messages("s-1") == before
    assert chat_env.sched.recorded("fake-notify-send")[-1][-2] == "Daily news: failed"


def test_missing_key_and_missing_chat(chat_env, provider):
    server = provider()
    setup_direct(chat_env, server)
    chat_env.wallet("open", {"KDEAIChat": {}})
    assert schedule_exec.run_prompt(dict(SCHEDULE), None, NOW).startswith("error: there is no API key")
    assert schedule_exec.run_prompt(dict(SCHEDULE, chatId="gone"), None, NOW) == "skipped: chat not found"


def test_anthropic_request_shape(chat_env, provider):
    server = provider(kind="anthropic", reply="Bonjour")
    chat_env.config(provider="claude", providersJson=[{"id": "claude", "name": "A", "type": "anthropic",
                                                       "baseUrl": server.url, "model": "claude-x"}])
    chat_env.wallet("open", {"KDEAIChat": {"claude": KEY}})
    chat_env.add_chat("s-1", [], responseLength=1, personalityOff=True)
    assert schedule_exec.run_prompt(dict(SCHEDULE, message="Hi"), None, NOW) == "ok"
    req = server.requests[0]
    assert req["path"] == "/v1/messages" and req["headers"]["x-api-key"] == KEY
    assert req["body"]["max_tokens"] == 512 and req["body"]["messages"] == [{"role": "user", "content": "Hi"}]
    assert "Response length preference" in req["body"]["system"]
    assert chat_env.messages("s-1")[-1]["content"] == "Bonjour"


def test_the_chat_keeps_its_own_mode(chat_env):
    """Main settings say OpenCode, the chat is direct: the run is direct (and the other way round)."""
    chat_env.config(useOpenCode=True)
    chat_env.add_chat("s-1", [], source="provider")
    chat_env.add_chat("s-2", [], source="pi")
    used = []
    runners = {mode: (lambda m: lambda *a: used.append(m) or {"content": "ok"})(mode) for mode in ("provider", "opencode", "pi")}
    assert schedule_exec.run_prompt(dict(SCHEDULE), None, NOW, runners=runners) == "ok"
    assert schedule_exec.run_prompt(dict(SCHEDULE, chatId="s-2"), None, NOW, runners=runners) == "ok"
    assert used == ["provider", "pi"]


def test_deliver_twice_adds_once_and_keeps_newer_messages(chat_env):
    chat_env.add_chat("s-1", [{"role": "user", "content": "a"}])
    ref = schedule_chat.find_chat("s-1")
    msgs = [{"role": "user", "content": "p", "scheduleRunId": "r1"}, {"role": "assistant", "content": "x", "scheduleRunId": "r1"}]
    schedule_chat.deliver(ref, "r1", msgs, {"scheduleId": "news-1"})
    # the widget saved a newer message meanwhile; a second delivery of r1 must not duplicate nor drop it
    path = os.path.join(chat_env.dir, schedule_chat.file_name_for_id("s-1"))
    qsettings_ini.write_values(path, {"messages": json.dumps(chat_env.messages("s-1") + [{"role": "user", "content": "b"}])})
    schedule_chat.deliver(ref, "r1", msgs, {"scheduleId": "news-1"})
    assert [m["content"] for m in chat_env.messages("s-1")] == ["a", "p", "x", "b"]
    assert len(chat_env.inbox()) == 2


def test_inbox_done_removes_only_inbox_files(chat_env, capsys):
    chat_env.add_chat("s-1")
    path = schedule_chat.write_inbox(chat_env.dir, "run", "news-1", {"messages": []})
    name = os.path.basename(path)
    schedule_chat.cmd_schedule_inbox_done({"directory": chat_env.dir, "files": [name]})
    assert json.loads(capsys.readouterr().out)["removed"] == [name] and chat_env.inbox() == []
    for bad in ("../index.ini", "index.ini", "run-1-x.ini/../../a"):
        with pytest.raises(ValueError):
            schedule_chat.cmd_schedule_inbox_done({"directory": chat_env.dir, "files": [bad]})


def test_run_schedule_records_the_outcome(chat_env, provider, capsys):
    server = provider()
    setup_direct(chat_env, server)
    created = dt.datetime(2026, 10, 20, 8, 0)
    store = schedule_store.empty_store()
    store["schedules"] = [dict(SCHEDULE, enabled=True, rules=[{"kind": "daily", "times": ["09:00"]}],
                               createdAt=iso(created), editedAt=iso(created))]
    os.makedirs(chat_env.sched.data, exist_ok=True)
    with open(schedule_store.store_path(), "w") as f:
        json.dump(store, f)
    decision = schedule_job.run_schedule("news-1", now=NOW + dt.timedelta(seconds=30))
    assert decision["action"] == "run" and decision["status"] == "ok"
    state = schedule_runs.load_run_state("news-1")
    assert state["runCount"] == 1 and state["lastStatus"] == "ok" and state["history"][-1]["status"] == "ok"
    assert state["history"][-1]["scheduledFor"] == iso(NOW)
    # the next day the prompt says since when
    chat_env.wallet("closed")
    decision = schedule_job.run_schedule("news-1", now=NOW + dt.timedelta(days=1, seconds=30))
    state = schedule_runs.load_run_state("news-1")
    assert decision["status"] == "skipped: wallet locked" and state["runCount"] == 1
    assert [h["status"] for h in state["history"]] == ["ok", "skipped: wallet locked"]
    assert len(server.requests) == 1
