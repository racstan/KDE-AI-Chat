# Scrolling Regression Audit - 2026-06-14

## History Window

Relevant commits today:

- `863c6c3` at 14:23:31: eliminated scroll lag and reduced streaming/render overhead.
- `140d9bd` at 15:23:02: precomputed message blocks to stabilize delegate heights.
- `dd49dd3` at 15:47:27: made scrollbar handle size constant.
- `835e3ad` at 15:53:30: optimized message scrolling and fixed user bubble overlap.
- `c115fbc` at 17:29:15: stabilized chat scroll and hardened error paths.

The current worktree has uncommitted edits in `FullRepresentation.qml`.

## Implemented Resolution

The chat list has been restored to the final June 13 implementation:

- `model: root.messages`
- attached `QQC2.ScrollBar.vertical`
- no custom handle geometry or drag binding
- no `visibleMessages` slice
- direct message indices for search, jumps, edits, and actions

The cache buffer is intentionally `600`, lower than the June 13 value, because
message delegates contain rich content and creating many off-screen delegates
causes avoidable memory and UI-thread work.

`queueScrollToBottom()` now coalesces repeated streaming/appending requests into
one queued UI update. Message day labels and lowercase search text are also
precomputed outside the delegate hot path.

## Remaining Scroll Risk

The full message array is restored as explicitly requested, but very large
histories still depend on Qt ListView virtualization and delegate complexity.
The next structural step is extracting `ChatList.qml` and simplifying
`MessageContent.qml`; reintroducing a sliced model should only happen with a
real stable-ID model rather than array slicing and index arithmetic.
