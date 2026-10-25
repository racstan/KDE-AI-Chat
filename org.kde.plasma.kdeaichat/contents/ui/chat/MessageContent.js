.pragma library
// A user message with attachments as request content: text files are put in
// front of the text; images become image parts in the API's format
// ("anthropic" or OpenAI-style). Without images the result is a string.

function build(text, attachments, apiType) {
    var docs = [];
    var imgs = [];
    var skippedImageCount = 0;
    var imageChars = 0;
    for (var i = 0; i < attachments.length; i++) {
        var att = attachments[i] || {};
        if (att.type === "image") {
            var imageSize = String(att.content || "").length;
            if (imageChars + imageSize <= 20000000) {
                imgs.push(att);
                imageChars += imageSize;
            } else {
                skippedImageCount++;
            }
        } else if (att.type === "text")
            docs.push(att);
    }
    var compiledPrompt = skippedImageCount > 0
        ? "[" + skippedImageCount + " image attachment(s) omitted because the request image limit was reached.]\n"
        : "";
    for (var d = 0; d < docs.length; d++) {
        if (compiledPrompt.length > 5000000)
            break;
        compiledPrompt += "[Attached File: " + String(docs[d].name || "file") + " (" + Math.round((docs[d].size || 0) / 1024) + " KB)]\n";
        compiledPrompt += "--- START OF FILE CONTENT ---\n";
        var remainingDocChars = Math.max(0, 5000000 - compiledPrompt.length - 40);
        var docContent = String(docs[d].content || "");
        if (docContent.length > remainingDocChars)
            docContent = docContent.substring(0, remainingDocChars) + "\n[file content truncated]";
        compiledPrompt += docContent + "\n";
        compiledPrompt += "--- END OF FILE CONTENT ---\n\n";
    }
    compiledPrompt += text;
    if (imgs.length === 0)
        return compiledPrompt;

    var contentList = [];
    if (compiledPrompt.trim() !== "")
        contentList.push({
            "type": "text",
            "text": compiledPrompt
        });

    for (var imgIdx = 0; imgIdx < imgs.length; imgIdx++) {
        var image = imgs[imgIdx];
        if (apiType === "anthropic")
            contentList.push({
                "type": "image",
                "source": {
                    "type": "base64",
                    "media_type": image.mimeType || "image/jpeg",
                    "data": image.content
                }
            });
        else
            contentList.push({
                "type": "image_url",
                "image_url": {
                    "url": "data:" + (image.mimeType || "image/jpeg") + ";base64," + image.content
                }
            });
    }
    return contentList;
}
