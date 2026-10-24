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

| Check | Command | Rule |
|---|---|---|
| Tests | `pytest -q` | Must pass on Python 3.11–3.13. |
| QML tests | `REQUIRE_QML_TESTS=1 pytest -q tests/test_qml.py` | Run in an Arch Linux container with Plasma 6, because Ubuntu runners only have Plasma 5. |
| qmllint ratchet | `scripts/qmllint_ratchet.py` | Each QML file's warning count may only go down. After fixing warnings, run with `--update` **inside the CI container** (counts depend on Qt and module versions). |
| File sizes | `scripts/check_file_sizes.py` | Source files are limited to 400 lines; the big files listed in `scripts/file_size_allowlist.json` may only shrink. Use `--update` after splitting a file. |
| Package | (inline in `ci.yml`) | The built `.plasmoid` contains the required files. |

To reproduce the CI QML job locally:

```bash
podman run --rm -v "$PWD":/src:Z -w /src -e REQUIRE_QML_TESTS=1 docker.io/archlinux:latest bash -c '
  pacman -Syu --noconfirm --needed qt6-declarative kirigami libplasma plasma5support \
    plasma-workspace kcmutils qqc2-desktop-style python python-pytest >/dev/null
  pytest -q tests/test_qml.py && python scripts/qmllint_ratchet.py --qmllint /usr/lib/qt6/bin/qmllint'
```

## Plans

The rebuild plan, with per-area audits, is in [docs/plan/](plan/README.md).
