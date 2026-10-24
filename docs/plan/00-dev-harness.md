# Phase 0: Dev harness

**Why first:** every later phase changes the UI. Today the only way to see a change is to install it, restart plasmashell (your whole desktop) and read the journal, and that only shows startup errors. In 1.4.0 the chat popup failed to load completely and neither CI nor tests noticed. The harness lets Claude launch, click, type, screenshot and read warnings on its own, without touching your desktop.

## What exists today

| Tool | Installed | Status |
|---|---|---|
| `plasmawindowed` | yes | Runs the widget in its own window with its own config (`~/.config/plasmawindowed-appletsrc`), so your keys and chats aren't touched. Only shows the panel icon, because `main.qml:4320` forces `preferredRepresentation: compactRepresentation`. |
| `spectacle -b -n -a -o file.png` | yes | Background screenshot of the active window. Verified working; Claude can read the PNG. |
| `qmltestrunner` + `-platform offscreen` | yes | Qt Quick Test with no window. Can click (`mouseClick`), type (`keyClick`) and save screenshots (`grabToImage`). |
| `xdotool` / `ydotool` | xdotool only | Simulated clicks into Wayland windows didn't work. Not needed if we use qmltestrunner. |

## Steps

1. **Open the chat view when windowed.** Use the full representation when the form factor is planar and the widget isn't on a panel or desktop (the plasmawindowed case). Users' panels keep today's behaviour.
2. **`scripts/dev-run.sh`**
   - Build the package from the working tree and install it under a separate test ID (`org.kde.plasma.kdeaichat.dev`) so it never replaces your real install.
   - Launch it with `plasmawindowed`, wait, screenshot to `build/screens/`, then close it.
   - Print every QML warning from the run, and exit non-zero if there are any.
3. **`tests/qml/`: offscreen component tests**
   - A small fake `plasmoid.configuration` and a fake backend that emits canned streaming events, so components load without Plasma.
   - Tests: chat view loads, send a message, streaming text appears, scroll stays put when the user scrolled up, the settings pages load.
   - `grabToImage` saves screenshots for visual review.
   - Every test fails on any QML warning.
4. **CI:** run the offscreen tests in GitHub Actions. Install the Kirigami/Plasma QML packages so `qmllint` can resolve imports again, then make it blocking.
5. **Developer docs:** add the commands to `CLAUDE.md`.

## Done when

- `scripts/dev-run.sh` produces a screenshot of the chat view and lists warnings, without restarting plasmashell.
- Reintroducing the `TextArea.maximumLength` bug makes CI fail.
