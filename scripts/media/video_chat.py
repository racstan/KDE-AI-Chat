"""The video's chat chapters (youtube.py): everything inside a chat.

PARTS: (kind, name, title, line, ...), see youtube.py. Each "flow" is recorded by scripts/media/VideoChat*.qml
(VideoChatA: chapters 1-4, VideoChatB: 5-6, VideoChatC: 7-10)."""

PARTS = [
    # 1. Chatting
    ('flow', 'chat-stop', 'Ask anything', 'Type a question and press Enter.', 'The answer is written word by word. Press Esc or the Stop button to cut it off.'),
    ('flow', 'chat-queue', 'Keep typing while it answers', 'Write your next message right away.', 'It waits in line and is sent as soon as the answer is finished.'),
    ('flow', 'chat-formatted', 'Answers that are easy to read', 'Tables, lists and code are formatted for you.', 'Every code block has its own copy button.'),
    # 2. Working with messages
    ('flow', 'chat-messages', 'Work with your messages', 'Copy an answer, or regenerate it to get a new one.', 'Edit your own message in place and save it: it is sent again. Delete a message you do not need.'),
    # 3. Quoting
    ('flow', 'chat-quote-jump', 'Quote a reply', 'Press Quote under a message and it waits above the box.', 'Click the quote in your sent message to jump back to the original.'),
    # 4. Remembering
    ('flow', 'chat-remember-flow', 'Let it remember', 'Remember, under a message, saves it as a memory for your later chats.', 'Or type /remember followed by what to keep.'),
    # 5. Organising chats
    ('flow', 'chat-pin', 'Keep it open', 'Pin the widget and it stays open when you click somewhere else.', 'Click the pin again to let it close as usual.'),
    ('flow', 'chat-rename', 'All your chats in one place', 'Open the history to see your chats.', 'Click the pencil on a chat to rename it.'),
    ('flow', 'chat-projects', 'Group chats in projects', 'Make a project with its own instructions and move a chat into it.', 'Every chat in the project follows its instructions.'),
    ('flow', 'chat-search-jump', 'Search every chat', 'Type a few words to find a message in any chat.', 'Click a result to jump straight to that message.'),
    # 6. Keyboard
    ('flow', 'keys-new', 'Ctrl+N starts a new chat', 'Press Ctrl+N and a fresh chat opens, ready for your question.'),
    ('flow', 'keys-incognito', 'Ctrl+Shift+N starts an incognito chat', 'An incognito chat is never saved.'),
    ('flow', 'keys-pick', 'Up and Down pick a message', 'Press Up to pick the latest message, again for the one before.', 'Press Down to go forward, and Esc to let go.'),
    ('flow', 'keys-edit', 'Ctrl+E edits your last message', 'Change what you wrote and send it again.', 'Esc cancels the edit.'),
    ('flow', 'keys-quote', 'Ctrl+Q quotes the picked message', 'Pick a message with Up, then press Ctrl+Q.', 'The quote appears above the box.'),
    ('flow', 'keys-page', 'PageUp and PageDown jump around', 'PageUp goes to the first message, PageDown to the latest.'),
    ('flow', 'keys-list', 'Every shortcut in one list', 'Settings, Appearance lists all the keys.', 'They work while the chat is open.'),
    # 7. Commands
    ('flow', 'chat-commands-list', 'Type / for commands', 'A list of commands and your own saved prompts opens.', 'Keep typing to narrow it down.'),
    ('flow', 'chat-template', 'Use a saved prompt', 'Pick /summarize with Tab, then add your text.', 'The saved prompt and your text are sent together.'),
    ('flow', 'chat-model-cmd', '/model picks the model', 'Type /model to see the models this chat can use.', 'Choose one and only this chat changes.'),
    ('flow', 'chat-image-cmd', '/image makes a picture', 'Type /image and describe what you want.', 'The picture appears in the chat, with buttons to enlarge, copy or save it.'),
    # 8. Attachments
    ('flow', 'chat-attach', 'Attach files', 'Attach a document or a picture: they show above the box.', 'Send them with your question, and the AI reads both.'),
    # 9. Incognito
    ('flow', 'chat-incognito-flow', 'Incognito chats', 'Start an incognito chat and talk as usual.', 'When you leave it, its messages are gone for good.'),
    # 10. The AI asks you
    ('flow', 'chat-ask-flow', 'The AI can ask you', 'When it needs a choice, it asks you in the chat with buttons.', 'Click an answer and it carries on with it.'),
]
