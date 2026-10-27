# Pictures

Pictures work in **Direct** chats. There are two parts: pictures that models send back, and pictures you ask for with `/image`.

## Pictures in replies

Some models send a picture back. The widget saves it as a file in the chat's own folder and shows it in the message. Click a picture to enlarge it. Each picture has **Copy image**, **Download** and, for pictures the widget made for you, **Regenerate** (same prompt, a new picture). Copying needs `wl-copy` (Wayland) or `xclip` (X11); if neither is installed, the widget says so. Only PNG, JPEG, WebP and GIF files up to 12 MB are accepted.

A link to a picture in a reply (Markdown `![...](https://...)`) is **never loaded by itself**. The text shows `[image: ...]` and a button, "Show image from <site>". The picture is fetched only when you click it, and only from public secure (https) addresses.

## Making pictures with `/image`

Type `/image` and what you want, for example `/image a sun hugging the moon`. While it works, the reply shows the queue place and waiting time, with a **Stop** button. The chat is named after your prompt.

Pictures are made by an **image service**. Set one up in **Settings → Connection**, **Add provider**, then choose an image service. Each service starts **switched off**. Its form says in plain words where your prompt goes, links its terms, and has a box you tick before it can be used. The service marked **Use for /image** is the one `/image` uses.

Only your prompt is sent to an image service, never the rest of the chat. Don't put personal details or secrets in a prompt.

![Settings, Connection page](media/settings-connection-light.png)
*Image services are in the same list as your providers.*

### AI Horde

A community-run service. Your prompt is made into a picture on a **volunteer's computer**, so the volunteer can see it. Pictures made without an account are shared with LAION, a research dataset.

- It works **without an account**. An own key is optional and is kept in KWallet.
- Without an account, limits apply: **one picture at a time, up to 576 pixels wide or high and 30 steps**. The widget starts at 512 x 512 and 22 steps. More needs an account with kudos.
- Anonymous requests wait behind others, so a picture can take a minute or more.
- Models meant for adult content are left out of the list.

### Pollinations

- **Pollinations.ai (images, your key)**: use your own Pollinations key (kept in KWallet). The settings page has a link to get one.
- **Pollinations.ai (older free service)**: no key, but it may stop working, makes one picture every 45 seconds (the widget shows a countdown) and adds a Pollinations logo to the picture.

### Settings of an image service

**Model** (press Refresh to ask the service), **Picture size**, **Steps**, **Pictures per message** and **Seed** (the same prompt and seed give the same picture again; empty means a new one each time). Each is kept within the service's limits.

## Where pictures are kept

In `~/.local/share/kdeaichat/chats/`, in a private folder next to the chat they belong to. Deleting a chat deletes its pictures. **Settings → Storage** shows how much space they use. See [Privacy](privacy.md).
