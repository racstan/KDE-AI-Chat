# KDE AI Chat Publishing Runbook (For You)

This is the exact order to publish a new KDE AI Chat release.

## 0) Preconditions

- You are in repo root: `rachitkdeaichat`
- Plasma 6 tooling is installed (`kpackagetool6`, `qmllint`, `zip`)
- You are logged in to GitHub and KDE Store in your browser

## 1) Update Version + Release Notes

1. Edit `org.kde.plasma.kaichat/metadata.json` and bump:
   - `KPlugin.Version`
2. Update release notes in:
   - `README.md`

## 2) Validate Before Packaging

Run these from repo root:

```bash
qmllint org.kde.plasma.kaichat/contents/ui/main.qml
qmllint org.kde.plasma.kaichat/contents/ui/ConfigGeneral.qml
./install.sh
systemctl --user restart plasma-plasmashell.service
plasmawindowed org.kde.plasma.kaichat
```

Manual checks:

- Open/close popup works
- Follow system / Light / Dark all readable
- Send button and message text visible
- Provider settings open and save correctly

## 3) Build Release Artifact (.plasmoid)

```bash
rm -rf dist
mkdir -p dist
VERSION="$(jq -r '.KPlugin.Version' org.kde.plasma.kaichat/metadata.json)"
cd org.kde.plasma.kaichat
zip -r "../dist/org.kde.plasma.kaichat-v${VERSION}.plasmoid" * \
  -x "*.git*" "*__pycache__*" "*.DS_Store"
cd ..
```

Optional checksum:

```bash
kpackagetool6 --hash "dist/org.kde.plasma.kaichat-v${VERSION}.plasmoid"
```

## 4) Verify Artifact Installs Cleanly

```bash
kpackagetool6 --type Plasma/Applet --upgrade "dist/org.kde.plasma.kaichat-v${VERSION}.plasmoid"
systemctl --user restart plasma-plasmashell.service
```

Then re-open widget once to confirm no regressions.

## 5) Commit + Tag

*(Note: The codebase folder and install script are ignored via `.gitignore`, so only documentation markdown files will be committed to GitHub).*

```bash
git add README.md SETUP.md FORUSER.md audit.md .gitignore
git commit -m "Prepare KDE AI Chat v${VERSION} release documentation"
git tag "v${VERSION}"
git push
git push --tags
```

## 6) GitHub Release

1. Open GitHub repo releases page.
2. Create release from tag `v<version>`.
3. Title: `KDE AI Chat v<version>`.
4. Paste release notes.
5. Upload file:
   - `dist/org.kde.plasma.kaichat-v<version>.plasmoid`
6. Publish release.

## 7) KDE Store Publish / Update

KDE Store UI changes over time, but flow is typically:

1. Open store.kde.org and sign in.
2. Create product (first publish) or open existing product (update).
3. Category: Plasma widget/applet category.
4. Update description/changelog/screenshots.
5. Upload the same `.plasmoid` artifact from `dist/`.
6. Save/submit.

## 8) Post-Publish Checks

- Confirm new version appears in GitHub release page.
- Confirm KDE Store page shows new version/file.
- Fresh install test from artifact on one machine.

## KDE Docs References Used

- Setup: <https://develop.kde.org/docs/plasma/widget/setup/>
- Testing: <https://develop.kde.org/docs/plasma/widget/testing/>
- Widget properties: <https://develop.kde.org/docs/plasma/widget/properties/>

