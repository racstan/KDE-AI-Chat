# Plasma Widget Configuration Pages

> **Source**: [develop.kde.org/docs/plasma/widget/configuration/](https://develop.kde.org/docs/plasma/widget/configuration/)

## Architecture

A Plasma widget's settings are defined by three files:

### 1. `contents/config/main.xml` — KConfigXT Schema
Declares all configuration keys, their types, and default values.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<kcfg ...>
  <kcfgfile name=""/>
  <group name="General">
    <entry name="provider" type="String">
      <default>openai</default>
    </entry>
  </group>
</kcfg>
```

### 2. `contents/config/config.qml` — Tab Registration
Maps config page names to QML files:

```qml
import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "ConfigGeneral.qml"
    }
}
```

### 3. `contents/ui/ConfigGeneral.qml` — The Settings UI

```qml
import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    id: page
    
    property alias cfg_myProperty: myTextField.text
    
    Kirigami.FormLayout {
        anchors.fill: parent
        
        QQC2.TextField {
            id: myTextField
            Kirigami.FormData.label: "My Setting:"
        }
    }
}
```

## Property Alias Convention

For each entry in `main.xml`, the QML file needs a `property alias` with the prefix `cfg_`:

```
main.xml: <entry name="provider" type="String">
QML:      property alias cfg_provider: providerCombo.currentValue
```

**If an alias is missing**, Plasma logs a warning:
```
Setting initial properties failed: ConfigGeneral does not have a property called cfg_propertyName
```
This is a **non-fatal warning** — the page still loads but that property won't be saved.

## KCM.SimpleKCM

`SimpleKCM` inherits from `Kirigami.ScrollablePage` → `Kirigami.Page` → `QQC2.Page` → `QQC2.Control`.

Key behavior:
- Content is automatically placed in a **ScrollView**
- Scrolling is vertical by default
- `anchors.fill: parent` on the FormLayout fills the ScrollView's viewport
- **Do NOT set hardcoded width/height** — the host window manages sizing

## Best Practices for Settings Pages

### DO:
- Use `Kirigami.FormLayout` with `Kirigami.FormData.label` for all controls
- Use `Layout.fillWidth: true` on text labels and text areas
- Use `Layout.preferredWidth: 0` on any element with `wrapMode: Text.Wrap` to prevent width inflation
- Use `Kirigami.Separator` with `Kirigami.FormData.isSection: true` for visual grouping
- Use `Kirigami.Units.gridUnit` for spacing/sizing (DPI-aware)
- Let the KCM host manage window dimensions

### DON'T:
- ❌ Set `implicitWidth` on `QQC2.Label` or `QQC2.Control` (it's **read-only**)
- ❌ Hardcode pixel widths — breaks on different monitors/DPI
- ❌ Use `anchors` on items inside a Layout (conflicts with layout engine)
- ❌ Bind `width`/`height` of layout children (causes binding loops)
- ❌ Rely on `implicitWidth` for text labels — it equals the unwrapped text width

## Debugging Settings Pages

### Check Plasma Logs
```bash
journalctl --user -u plasma-plasmashell.service --since "5 min ago" | grep -i "error\|qml\|kdeaichat"
```

### Common Errors

| Error | Cause | Fix |
|---|---|---|
| `"implicitWidth" is a read-only property` | Assigning `implicitWidth` on QQC2 controls | Use `Layout.preferredWidth` instead |
| `Setting initial properties failed: cfg_X` | Missing `property alias cfg_X` in QML | Add the alias or remove from main.xml |
| Blank page | Fatal QML error preventing page load | Check logs for the actual error |
| Text not wrapping | Label's `implicitWidth` inflates the layout | Add `Layout.preferredWidth: 0` |

### Testing Without Restart
```bash
# Reinstall widget
kpackagetool6 --type Plasma/Applet --remove org.kde.plasma.kdeaichat
kpackagetool6 --type Plasma/Applet --install org.kde.plasma.kdeaichat

# Restart plasmashell to load changes
systemctl --user restart plasma-plasmashell.service
```
