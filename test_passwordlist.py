import re

with open("org.kde.plasma.kdeaichat/contents/ui/main.qml", "r") as f:
    content = f.read()

old_code = """                    var targets = ["openai", "anthropic", "groq", "deepseek", "minimax", "fireworks", "google", "openrouter", "mistral", "cloudflare", "nvidia", "huggingface", "xai", "litellm"];
                    
                    var idx = 0;
                    function readNext() {
                        if (idx >= targets.length) {
                            walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "org.kde.plasma.kdeaichat"]);
                            return;
                        }
                        var targetId = targets[idx++];
                        var key = "kai-chat-" + targetId + "-api-key";
                        walletCall("hasEntry", [new DBus.int32(handle), "KaiChat", key, "org.kde.plasma.kdeaichat"], function(hasEntry) {
                            if (hasEntry) {
                                walletCall("readPassword", [new DBus.int32(handle), "KaiChat", key, "org.kde.plasma.kdeaichat"], function(secret) {
                                    applyKWalletKeyToMemory(targetId, secret);
                                    readNext();
                                });
                            } else {
                                readNext();
                            }
                        });
                    }
                    readNext();"""

new_code = """                    walletCall("passwordList", [new DBus.int32(handle), "KaiChat", "org.kde.plasma.kdeaichat"], function(passwordsMap) {
                        if (passwordsMap) {
                            var targets = ["openai", "anthropic", "groq", "deepseek", "minimax", "fireworks", "google", "openrouter", "mistral", "cloudflare", "nvidia", "huggingface", "xai", "litellm"];
                            for (var i = 0; i < targets.length; i++) {
                                var targetId = targets[i];
                                var key = "kai-chat-" + targetId + "-api-key";
                                if (passwordsMap[key]) {
                                    applyKWalletKeyToMemory(targetId, passwordsMap[key]);
                                }
                            }
                        }
                        walletCall("close", [new DBus.int32(handle), new DBus.bool(false), "org.kde.plasma.kdeaichat"]);
                    });"""

content = content.replace(old_code, new_code)
with open("org.kde.plasma.kdeaichat/contents/ui/main.qml", "w") as f:
    f.write(content)
