import urllib.request
import threading
import time

def start_tts():
    req = urllib.request.Request("http://127.0.0.1:9016/command", data=b'{"cmd": "tts", "text": "This is a very very very very very very long text to test if stop works during playback.", "voice": "af_bella"}', headers={'Content-Type': 'application/json'})
    try:
        urllib.request.urlopen(req)
    except:
        pass

threading.Thread(target=start_tts).start()

time.sleep(1)

req2 = urllib.request.Request("http://127.0.0.1:9016/command", data=b'{"cmd": "stop_tts"}', headers={'Content-Type': 'application/json'})
start = time.time()
urllib.request.urlopen(req2)
print("Stop returned in", time.time() - start)
