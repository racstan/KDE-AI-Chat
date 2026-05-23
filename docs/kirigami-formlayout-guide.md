# Kirigami FormLayout Guide

> **Sources**: [develop.kde.org](https://develop.kde.org/docs/getting-started/kirigami/components-formlayouts/), [Qt Layout docs](https://doc.qt.io/qt-6/qml-qtquick-layouts-layout.html)

## What is FormLayout?

`Kirigami.FormLayout` is a layout component that creates form-style UIs with label-value pairs. It internally uses a **GridLayout** with two columns:
- **Column 1**: Form labels (set via `Kirigami.FormData.label`)
- **Column 2**: The controls/content

## Wide Mode vs Narrow Mode

```qml
Kirigami.FormLayout {
    wideMode: true   // Two-column layout (labels left, controls right)
    // wideMode: false  // Single-column (labels above controls, capped width ~576px)
}
```

- `wideMode: true` (default on desktop): Two-column grid. **No built-in width cap** — the layout grows to fit the widest child's `implicitWidth`.
- `wideMode: false`: Single-column, centered, capped at ~576px.

### The Width Inflation Problem

When `wideMode: true`, the GridLayout column width is determined by the widest child's preferred/implicit width. Long text labels inflate the grid:

```
Window grows → FormLayout grows → Label implicitWidth = 800px → Column = 800px → Window = 800+px → No wrapping needed
```

**Solution**: Break the cycle by setting `Layout.preferredWidth: 0` on text labels.

## Sections and Separators

```qml
Kirigami.Separator {
    Kirigami.FormData.isSection: true
    Kirigami.FormData.label: "Section Title"
}
```

## Label Alignment

```qml
QQC2.TextField {
    Kirigami.FormData.label: "Name:"
    Kirigami.FormData.labelAlignment: Qt.AlignTop  // For multi-line controls
}
```

## Twin Form Layouts

To align label columns across multiple FormLayouts on the same page:

```qml
Kirigami.FormLayout {
    id: form1
}
Kirigami.FormLayout {
    twinFormLayouts: form1  // Columns align with form1
}
```

## Dynamic Width Pattern for KCM Settings Pages

### Root Sizing

```qml
KCM.SimpleKCM {
    // NO hardcoded sizes — remove implicitWidth/implicitHeight
    // The KCM host (System Settings / kcmshell6) controls the window size
    
    Kirigami.FormLayout {
        anchors.fill: parent
        wideMode: true
        
        QQC2.Label {
            Kirigami.FormData.label: "Info:"
            Layout.fillWidth: true
            Layout.preferredWidth: 0   // ← KEY: prevents width inflation
            wrapMode: Text.Wrap
            text: "Long description text..."
        }
    }
}
```

### Why NOT to Hardcode Root Size

- `implicitWidth: Kirigami.Units.gridUnit * 38` sets a **default** window size
- But it doesn't adapt to monitor resolution, DPI scaling, or user resizing
- The KCM host (System Settings window) manages its own size — let it

### Why `Layout.preferredWidth: 0` is Dynamic

- It tells the FormLayout: "don't use my text width for column sizing"
- The FormLayout sizes its column based on OTHER children (text fields, dropdowns)
- The label then fills whatever width the column ends up at
- Works at ANY window size because it's relative, not absolute
