#!/usr/bin/env python3
# Copyright (c) 2026 PDC
# Distributed under the MIT/X11 software license, see the accompanying
# file COPYING or http://www.opensource.org/licenses/mit-license.php.
"""Stand-in for pdcd's RPC server used by gateway/test/run.sh.

Logs one JSON line per request to stdout (so the test can tell whether the gateway forwarded it) and
answers with canned data. /getblocks.bin returns a fixed binary blob containing NUL and 0xFF bytes so
the test can verify the gateway does not corrupt binary bodies.
"""
import hashlib
import json
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BINARY_BLOB = bytes(range(256)) * 8  # 2 KiB, every byte value present


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _handle(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length else b""
        print(json.dumps({
            "method": self.command,
            "path": self.path,
            "body_sha256": hashlib.sha256(body).hexdigest(),
            "body_len": len(body),
            "xff": self.headers.get("X-Forwarded-For", ""),
            "real_ip": self.headers.get("X-Real-IP", ""),
        }), flush=True)

        if self.path.endswith(".bin"):
            payload, ctype = BINARY_BLOB, "application/octet-stream"
        else:
            payload, ctype = json.dumps({"mock": True, "path": self.path}).encode(), "application/json"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = do_POST = _handle

    def log_message(self, *args):  # silence the default access log
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 19211
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
