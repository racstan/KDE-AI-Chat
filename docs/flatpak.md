# Flatpak Packaging

KDE AI Chat ships a Flatpak manifest at
`org.kde.plasma.kdeaichat.flatpak.json` for users who prefer
sandboxed distribution.

## Building

```sh
# Install flatpak-builder and the KDE runtime first
flatpak install --user flathub org.kde.Platform//6.8 org.kde.Sdk//6.8

# Build the .plasmoid artifact
flatpak-builder --user --install build-dir org.kde.plasma.kdeaichat.flatpak.json
```

The build produces `org.kde.plasma.kdeaichat.plasmoid` (a
gzipped tarball of the widget) inside the build directory.

## Installing the resulting widget

Because the widget itself is a Plasma applet that has to integrate
with the host's running Plasma session, the typical install path is:

```sh
tar -xzf org.kde.plasma.kdeaichat.plasmoid -C ~/.local/share/plasma/packages/
# Or use the build script:
install.sh
```

The Flatpak manifest is mostly useful for reproducible CI builds
that produce a distributable artifact without polluting the
developer's local Plasma install.

## Why not a fully-sandboxed widget?

KDE Plasma widgets are loaded as QML plugins inside the running
`plasmashell` process. They cannot run in a separate Flatpak
sandbox without significant Plasma engineering work that KDE has
not yet shipped. The Flatpak manifest here therefore builds the
plasmoid artifact inside a clean environment and is intended to be
unpacked and installed in the user's host session.

## See also

- [KDE Plasma packaging guide](https://develop.kde.org/docs/packaging/plasma/)
- [`install.sh`](../install.sh) — the recommended user install path
- [`docs/SETUP.md`](SETUP.md) — full setup instructions
