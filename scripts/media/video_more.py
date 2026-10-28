"""The video's middle chapters (youtube.py): personality and avatars, memory, the three modes, schedules, voice and
small touches. Recorded by scripts/media/VideoMore*.qml.

PARTS: (kind, name, title, line, ...), see youtube.py."""

PARTS = [
    # Personality and avatars (VideoMorePersona.qml)
    ('flow', 'personality', 'Make it yours', 'Tell the AI your name and a little about you, and pick the tone you like.',
     'Give the AI a name and a personality of its own.'),
    ('flow', 'avatar-picker', 'A face for the AI', 'Pick any picture as the AI\'s avatar, even an animated GIF.'),
    ('flow', 'panel-icon', 'A panel icon to match', 'The same picture can be the widget\'s icon in your panel.'),
    ('flow', 'avatar-chat', 'It shows in the chat', 'The avatar and names appear above the messages.'),
    # Memory (VideoMoreMemory.qml)
    ('flow', 'memory-page', 'Memories you control', 'Add a note the AI should keep, pin the important ones,',
     'and edit or delete any of them in Settings, Memory.'),
    ('flow', 'memory-chat', 'Memory per chat', 'Memories are sent only when they fit what you ask.',
     'Switch memory off for a single chat in its Chat info.'),
    # The three modes (VideoMoreModes.qml)
    ('flow', 'modes-settings', 'Three ways to talk to an AI', 'Directly to a provider, through OpenCode, or through Pi.',
     'Choose in Settings, Connection.'),
    ('flow', 'mode-banner', 'A chat keeps its mode', 'Changing the mode never changes a chat you already have.',
     'The banner offers a new chat in the new mode.'),
    ('flow', 'mode-opencode', 'OpenCode: an agent in your project', 'It reads the real files of the folder the chat works in.',
     'Pick one of OpenCode\'s agents for the chat, like plan or build.',
     'Before it changes a file, it asks you, and you allow it.'),
    ('flow', 'mode-pi-settings', 'Pi, a small coding agent', 'Choose Pi in Settings, Connection.'),
    ('flow', 'mode-pi', 'What Pi does, step by step', 'Its thinking and every tool it runs sit in one box above the reply.',
     'Open the box to see each step.'),
    # Schedules (VideoMoreSchedule.qml)
    ('flow', 'schedule-create', 'Let it work on a schedule', 'From a chat\'s More menu, schedule a message.',
     'Describe when in plain words and the AI fills in the times. Check them, then save.'),
    ('flow', 'schedule-run', 'The answer arrives by itself', 'At the set time the message is sent, even when the chat is closed,',
     'and the answer appears in the chat.'),
    ('flow', 'schedule-list', 'All schedules in Settings', 'See when each one runs next, and look back at its history.'),
    # Voice (VideoMoreVoice.qml)
    ('flow', 'voice-settings', 'Voice, when you want it', 'Read aloud and dictation are off until you switch them on.',
     'Speech is handled on your computer by the Speech Note app.'),
    ('flow', 'voice-read', 'Listen to a reply', 'Press the speaker under a reply.',
     'The sentence being read is highlighted and follows along.'),
    ('flow', 'voice-dictate', 'Talk instead of typing', 'Press the microphone, speak, and press it again.',
     'Your words are written for you and sent.'),
    # Small touches (VideoMoreTouches.qml)
    ('flow', 'touch-more-menu', 'Everything else, one click away', 'The More menu opens as soon as you point at it:',
     'rename, move to a project, jump around, schedule, export or clear.'),
    ('flow', 'touch-undo', 'Nothing is lost by accident', 'Deleted a chat by mistake?',
     'Undo brings it back.'),
]
