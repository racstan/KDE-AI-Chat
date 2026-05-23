# Qt Quick Layout Attached Properties

> **Source**: [Qt 6 Documentation](https://doc.qt.io/qt-6/qml-qtquick-layouts-layout.html)

## Overview

The `Layout` attached properties control how items behave within `GridLayout`, `RowLayout`, or `ColumnLayout`. **Kirigami.FormLayout** internally uses a GridLayout, so all these properties apply to children of FormLayout.

## Key Properties for Width Management

### `Layout.fillWidth : bool`
- If `true`, the item will be as wide as possible while respecting constraints
- If `false`, the item will have a fixed width set to preferred width
- Default depends on the item's built-in size policy

### `Layout.preferredWidth : real`
- The preferred width of the item in a layout
- If set to `-1` (default), the layout uses `implicitWidth` instead
- **Critical**: When `Layout.preferredWidth` is set to any non-negative value, it OVERRIDES `implicitWidth` for layout calculations
- Setting `Layout.preferredWidth: 0` with `Layout.fillWidth: true` means: "I prefer 0 width, but fill whatever space is available"

### `Layout.minimumWidth : real`
- Minimum width the item can shrink to. Default: `0`
- The layout will never make the item smaller than this

### `Layout.maximumWidth : real`
- Maximum width the item can grow to. Default: `Number.POSITIVE_INFINITY`
- The layout will never make the item larger than this

## Width Calculation Priority

1. Layout reads `Layout.preferredWidth` (or falls back to `implicitWidth` if preferredWidth is -1)
2. When distributing space, items with `fillWidth: true` grow/shrink between their min and max
3. Items are distributed proportionally to their preferred widths when multiple have `fillWidth: true`

## Read-Only vs Writable Properties

| Property | Writable? | Notes |
|---|---|---|
| `Item.implicitWidth` | ✅ Yes on `Item` | Base QML Item allows writing |
| `Control.implicitWidth` | ❌ **READ-ONLY** | `QQC2.Label`, `QQC2.TextField`, etc. compute this internally |
| `Layout.preferredWidth` | ✅ Yes | Attached property, always writable |
| `Layout.fillWidth` | ✅ Yes | Attached property, always writable |

### ⚠️ CRITICAL BUG PATTERN
```qml
// ❌ WILL CRASH — implicitWidth is read-only on QQC2.Label
QQC2.Label {
    implicitWidth: 100  // Runtime error: "implicitWidth is a read-only property"
    text: "Some text"
}

// ✅ CORRECT — use Layout.preferredWidth instead
QQC2.Label {
    Layout.preferredWidth: 0
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    text: "Some text"
}
```

## Dynamic Text Wrapping Pattern

For text that must wrap dynamically at any window size:

```qml
QQC2.Label {
    Layout.fillWidth: true       // Expand to fill available space
    Layout.preferredWidth: 0     // Don't inflate the layout's width calculation
    wrapMode: Text.WordWrap      // Wrap at word boundaries
    text: "Very long text that should wrap..."
}
```

**Why this works**: `Layout.preferredWidth: 0` tells the layout "this item prefers 0 width" so it doesn't push the parent wider. `Layout.fillWidth: true` then expands the item to whatever width IS available. `wrapMode` wraps within that allocated width.
