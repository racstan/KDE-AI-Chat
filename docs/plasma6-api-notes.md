# KDE Plasma 6 QML API Notes

Source: https://develop.kde.org/docs/plasma/widget/porting_kf6  
Source: https://develop.kde.org/docs/plasma/widget/properties

---

## PlasmoidItem — Direct Properties (no `Plasmoid.` prefix)

These are **direct properties** on the `PlasmoidItem {}` root item in Plasma 6.  
Do NOT use `Plasmoid.xyz:` for these — that will cause "Cannot assign to non-existent property" errors.

| Property | Type | Notes |
|---|---|---|
| `fullRepresentation` | Component | Replaces `Plasmoid.fullRepresentation` |
| `compactRepresentation` | Component | Replaces `Plasmoid.compactRepresentation` |
| `preferredRepresentation` | Component | Replaces `Plasmoid.preferredRepresentation` |
| `hideOnWindowDeactivate` | bool | Replaces `Plasmoid.hideOnWindowDeactivate` |
| `toolTipMainText` | string | Replaces `Plasmoid.toolTipMainText` |
| `toolTipSubText` | string | Replaces `Plasmoid.toolTipSubText` |
| `toolTipTextFormat` | int | Replaces `Plasmoid.toolTipTextFormat` |
| `toolTipItem` | Item | Replaces `Plasmoid.toolTipItem` |
| `switchWidth` | int | Min width to switch to fullRepresentation |
| `switchHeight` | int | Min height to switch to fullRepresentation |

---

## Plasmoid Attached Property (keep `Plasmoid.` prefix)

These are **still accessed via the `Plasmoid` attached object**:

| Property | Notes |
|---|---|
| `Plasmoid.icon` | Set widget icon name |
| `Plasmoid.title` | Widget title (read-only) |
| `Plasmoid.configuration` | Config object |
| `Plasmoid.expanded` | bool, get/set popup open state |
| `Plasmoid.screen` | int, screen index |
| `Plasmoid.status` | Plasma::Types::ItemStatus |
| `Plasmoid.contextualActions` | List of PlasmaCore.Action |
| `Plasmoid.backgroundHints` | Background hint |
| `Plasmoid.userBackgroundHints` | User-specified background hint |
| `Plasmoid.userConfiguring` | bool, is config dialog open |

---

## Removed Types

| Removed | Plasma 6 Replacement |
|---|---|
| `PlasmaCore.FrameSvgItem` | `Rectangle` with `Kirigami.Theme.backgroundColor` |
| `PlasmaCore.IconItem` | `Kirigami.Icon` |
| `PlasmaCore.ColorScope` | `Kirigami.Theme` color properties |
| `PlasmaCore.DataModel` | Use `P5Support.DataSource` from `org.kde.plasma.plasma5support` |
| `PlasmaCore.SvgItem` | `Kirigami.Icon` or plain `Image` |

---

## Imports — Plasma 6

```qml
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid          // Required for PlasmoidItem
import org.kde.kirigami as Kirigami     // Theming, icons, units
import org.kde.plasma.components as PC3 // Buttons, labels, menus, etc.
import org.kde.plasma.plasma5support as P5Support // DataSource (legacy engines)
// Note: 'org.kde.plasma.core as PlasmaCore' is mostly empty in Plasma 6
// Only needed for PlasmaCore.Action (contextual actions)
```

---

## Porting Pattern (Plasma 5 → 6)

```qml
// PLASMA 5
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.plasmoid 2.0

Item {
    id: root
    Plasmoid.fullRepresentation: Item { ... }
    Plasmoid.compactRepresentation: Item { ... }
    Plasmoid.hideOnWindowDeactivate: true
    Plasmoid.toolTipMainText: "Hello"
}

// PLASMA 6
import org.kde.plasma.plasmoid

PlasmoidItem {
    id: root
    fullRepresentation: Item { ... }
    compactRepresentation: Item { ... }
    hideOnWindowDeactivate: true
    toolTipMainText: "Hello"
    Plasmoid.icon: "dialog-messages"  // still uses Plasmoid. prefix
}
```

---

## PlasmaComponents 3 Available Types

Import: `import org.kde.plasma.components as PC3`

```
AbstractButton, BusyIndicator, Button, CheckBox, CheckDelegate,
ComboBox, Dialog, DialogButtonBox, Frame, GroupBox, ItemDelegate,
Label, Menu, MenuItem, MenuSeparator, Page, Popup, ProgressBar,
RadioButton, RoundButton, ScrollBar, ScrollView, Slider, SpinBox,
StackView, Switch, SwitchDelegate, TabBar, TabButton, TextArea,
TextField, ToolBar, ToolButton, ToolTip
```

---

## metadata.json Requirements for Plasma 6

```json
{
    "KPlugin": { ... },
    "X-Plasma-API-Minimum-Version": "6.0",
    "KPackageStructure": "Plasma/Applet"
}
```
