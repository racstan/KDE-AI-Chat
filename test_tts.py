import sys, os, time, json
sys.path.append("/home/home/Programming/rachitkdeaichat/org.kde.plasma.kdeaichat/contents/ui/voice")
import urllib.request
import urllib.error

text = "Elephants are fascinating creatures with many unique traits! Here are some amazing facts about them: African elephants are the largest land animals on Earth."

payload = {
    "cmd": "tts",
    "text": text,
    "voice": "af_bella",
    "gpu_requested": True,
    "model": "kokoro-82m",
    "model_path": "/home/home/.local/share/kdeaichat/models/kokoro"
}

req = urllib.request.Request("http://127.0.0.1:9016/command", data=json.dumps(payload).encode('utf-8'), headers={'Content-Type': 'application/json'})

start = time.time()
try:
    with urllib.request.urlopen(req) as response:
        res = response.read()
        print(f"Time taken: {time.time() - start:.2f}s")
        print("Response:", res.decode('utf-8'))
except urllib.error.URLError as e:
    print(e)
