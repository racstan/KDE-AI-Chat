// The wording of the built-in starting points of an empty chat. Starters.js
// chooses ids; each has a short label and the text put in the message box
// (never sent by itself).
import QtQuick
// i18n() comes from Plasma (KLocalizedContext), which qmllint cannot see.
// qmllint disable unqualified

QtObject {
    id: texts

    // The label and prompt for an id from Starters.js.
    function forId(id) {
        return table[id] || {"name": id, "prompt": ""};
    }

    readonly property var table: ({
        // Direct chats.
        "explain": {"name": i18n("Explain something simply"), "prompt": i18n("Explain this in simple terms: ")},
        "write": {"name": i18n("Help me write"), "prompt": i18n("Help me write ")},
        "summarise": {"name": i18n("Summarise a text"), "prompt": i18n("Summarise the following in five bullet points:\n")},
        "translate": {"name": i18n("Translate"), "prompt": i18n("Translate this into English:\n")},
        "plan": {"name": i18n("Make a plan"), "prompt": i18n("Help me make a step-by-step plan for ")},
        "brainstorm": {"name": i18n("Brainstorm ideas"), "prompt": i18n("Give me ten ideas for ")},
        "email": {"name": i18n("Draft an email"), "prompt": i18n("Draft a polite email to ")},
        "recipe": {"name": i18n("Dinner ideas"), "prompt": i18n("Suggest a quick dinner I can make with ")},
        "compare": {"name": i18n("Compare options"), "prompt": i18n("Compare these options and tell me the pros and cons: ")},
        "learn": {"name": i18n("Learn a topic"), "prompt": i18n("Teach me the basics of ")},
        "proofread": {"name": i18n("Proofread"), "prompt": i18n("Fix the spelling and grammar in this text, keeping my wording:\n")},
        "decide": {"name": i18n("Help me decide"), "prompt": i18n("Help me decide between ")},
        "study": {"name": i18n("Quiz me"), "prompt": i18n("Quiz me with five questions about ")},
        "rewrite": {"name": i18n("Rewrite it nicer"), "prompt": i18n("Rewrite this so it sounds friendlier and clearer:\n")},
        "travel": {"name": i18n("Plan a trip"), "prompt": i18n("Plan a three-day trip to ")},
        "gift": {"name": i18n("Gift ideas"), "prompt": i18n("Suggest gift ideas for ")},
        "shorter": {"name": i18n("Make it shorter"), "prompt": i18n("Make this shorter without losing the point:\n")},
        "regex": {"name": i18n("Spreadsheet or regex help"), "prompt": i18n("Help me write a formula or regular expression that ")},
        // Time of day.
        "planday": {"name": i18n("Plan my day"), "prompt": i18n("Help me plan my day. Here is what I have to do: ")},
        "reflect": {"name": i18n("Reflect on today"), "prompt": i18n("Help me look back on today: what went well, and what to do tomorrow. Today I ")},
        // OpenCode and Pi.
        "project": {"name": i18n("Explain this project"), "prompt": i18n("Explain what this project does and how it is organised.")},
        "bugfix": {"name": i18n("Find and fix a bug"), "prompt": i18n("Find and fix the bug where ")},
        "tests": {"name": i18n("Write tests"), "prompt": i18n("Write tests for ")},
        "changes": {"name": i18n("Summarise recent changes"), "prompt": i18n("Summarise the most recent changes in this project.")},
        "review": {"name": i18n("Review my changes"), "prompt": i18n("Review my uncommitted changes and point out problems.")},
        "todo": {"name": i18n("Find the TODOs"), "prompt": i18n("List the TODO and FIXME comments in this project, most important first.")},
        "refactor": {"name": i18n("Refactor"), "prompt": i18n("Refactor this to be simpler without changing what it does: ")},
        "docs": {"name": i18n("Write documentation"), "prompt": i18n("Write or improve the documentation for ")},
        "deps": {"name": i18n("Check dependencies"), "prompt": i18n("List the dependencies of this project and tell me which look outdated.")},
        "run": {"name": i18n("How do I run it?"), "prompt": i18n("Show me how to build, run and test this project.")},
        "standup": {"name": i18n("What should I do first?"), "prompt": i18n("Look at the recent changes and open TODOs and suggest what to work on first today.")},
        "wrapup": {"name": i18n("Wrap up today's work"), "prompt": i18n("Summarise what changed in this project today and what is left to do.")}
    })
}
