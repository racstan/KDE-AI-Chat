"""A tiny loopback HTTP server for QML tests that must prove nothing is fetched.

python3 -I count_server.py PORT: listens on 127.0.0.1:PORT and remembers the path of every
request. /ping answers "ok", /requests answers the remembered paths as JSON, /quit stops the
server. Other paths are remembered and get a 1x1 PNG. It stops by itself after two minutes.
"""
import base64
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

SEEN = []
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR4nGNgAAIAAAUAAXpeqz8AAAAASUVORK5CYII=")


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802 (http.server's name)
        if self.path == "/ping":
            self._answer(200, b"ok")
        elif self.path == "/requests":
            self._answer(200, json.dumps(SEEN).encode())
        elif self.path == "/quit":
            self._answer(200, b"bye")
            threading.Thread(target=self.server.shutdown, daemon=True).start()
        else:
            SEEN.append(self.path)
            self._answer(200, PNG, "image/png")

    def _answer(self, code, body, kind="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def main():
    server = ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler)
    timer = threading.Timer(120, server.shutdown)
    timer.daemon = True
    timer.start()
    server.serve_forever()
    print("stopped")


if __name__ == "__main__":
    main()
