# Development

## Run the widget without touching your desktop

```bash
scripts/dev-run.sh [seconds] [screenshot.png]
```

- Installs the working tree as `org.kde.plasma.kdeaichat.dev` into a sandbox under `build/dev-run/sandbox/` (its own config, data and cache folders).
- Opens it in a window with `plasmawindowed`, with the chat view open.
- Saves a screenshot to `build/dev-run/screenshot.png`, then closes it.
- Prints any QML warnings from the widget's files, and exits 1 if there are any.

Your real widget, its settings and your chats are never read or changed. KWallet is the real session wallet, because it's a system service. The sandbox resets every run; use `DEV_KEEP=1` to keep chats between runs.

To send one **real message** through the widget's own send path (in the sandbox):

```bash
scripts/dev-send.sh openrouter openrouter/auto ["message"]
```

It copies that provider's key from your KWallet folder `KDEAIChat` into the dev folder `KDEAIChat-dev` inside D-Bus (never printed), delivers the message as a scheduler trigger, prints the conversation, and deletes the dev folder afterwards.

The agent modes have their own end-to-end runs, which need no model credit:

```bash
scripts/dev-opencode-e2e.sh            # OpenCode mode against scripts/dev-opencode-mock.py
scripts/dev-pi-e2e.sh ["message"]      # Pi mode; `pi` is scripts/dev-pi-mock.py replaying a real capture
PI_E2E_REAL=1 PI_E2E_SECONDS=150 PI_CODING_AGENT_DIR=/path/to/test-config \
    scripts/dev-pi-e2e.sh "message" ollama qwen3:8b   # the real `pi`, e.g. on a local Ollama model
```

Each prints what the agent was asked and the saved chat. For the real-Pi run, a test config folder with a `models.json` pointing at Ollama keeps your own `~/.pi/agent` out of it (see Pi's `docs/models.md`).

To try the widget on your real panel instead:

```bash
./install.sh && systemctl --user restart plasma-plasmashell.service
journalctl --user -u plasma-plasmashell -b --no-pager | grep kdeaichat
```

## Tests

```bash
pytest -q                                   # everything (Python, JS via node, QML)
pytest tests/test_security.py -q            # one file
pytest tests/test_security.py::test_name -q # one test
pytest -q tests/test_qml.py                 # only the QML suite
```

- **Python and JS:** JS modules are tested by loading the `.js` source into `node` (see `tests/test_provider_service.py`), so `.js` files must stay plain JavaScript with no QML `.import` lines.
- **QML:** `tests/qml/` runs offscreen with Qt 6's test runner.
  - `tst_components_load.qml` compiles every shipped QML file, so a component that would fail to load in Plasma fails here.
  - New component tests extend `HarnessTestCase` to get `screenshot(item, name)`, which saves to `build/qml-screens/`, and a fake `plasmoid.configuration`.
  - Requires `qmltestrunner6` (openSUSE/Fedora) or `/usr/lib/qt6/bin/qmltestrunner` (Arch/Debian). The plain `qmltestrunner` on some distros is the Qt 5 one.

## Checks CI runs

CI runs on a **local Gitea** (http://localhost:3000, repo `rachit/KDE-AI-Chat`) with its `act_runner`, not on GitHub Actions. The workflow is `.gitea/workflows/ci.yml` and runs on every push to Gitea:

```bash
git -c http.extraHeader="Authorization: token $(cat ~/.config/gitea-local/api-token)" push gitea <branch>
```

The runner's labels map to local podman images:
- `ubuntu-latest` → `localhost/act-ubuntu`
- `arch-plasma` → `localhost/act-arch-plasma`, built from `ci/arch-plasma/Containerfile` with `podman build -t localhost/act-arch-plasma:latest ci/arch-plasma`. Rebuild it to pick up newer Plasma or Qt.


| Check | Command | Rule |
|---|---|---|
| Tests | `pytest -q` | Must pass on Python 3.11–3.13. |
| QML tests | `REQUIRE_QML_TESTS=1 pytest -q tests/test_qml.py` | Run on the `arch-plasma` image (Plasma 6), because Ubuntu only has Plasma 5. |
| qmllint ratchet | `scripts/qmllint_ratchet.py` | Each QML file's warning count may only go down. After fixing warnings, run with `--update` **inside the CI container** (counts depend on Qt and module versions). |
| File sizes | `scripts/check_file_sizes.py` | Source files are limited to 400 lines; the big files listed in `scripts/file_size_allowlist.json` may only shrink. Use `--update` after splitting a file. |
| Package | (inline in `ci.yml`) | The built `.plasmoid` contains the required files. |

To reproduce the CI QML job without pushing:

```bash
podman run --rm -v "$PWD":/src:Z -w /src -e REQUIRE_QML_TESTS=1 localhost/act-arch-plasma:latest bash -c '
  pytest -q tests/test_qml.py && python scripts/qmllint_ratchet.py --qmllint /usr/lib/qt6/bin/qmllint'
```

## Plans

The rebuild plan, with per-area audits, is in [docs/plan/](plan/README.md).
