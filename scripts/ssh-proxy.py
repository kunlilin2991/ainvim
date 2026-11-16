#!/usr/bin/env python3
"""SSH ProxyCommand: tunnel SSH through the HTTPS proxy's CONNECT method.

Usage:
  ssh -o ProxyCommand='python3 ssh-proxy.py %h %p' ...

Reads proxy URL (with optional credentials) from https_proxy/HTTPS_PROXY,
http_proxy/HTTP_PROXY. No credentials are printed.
"""
import base64
import os
import select
import socket
import sys
import urllib.parse

def main():
    if len(sys.argv) < 3:
        sys.exit(2)
    host = sys.argv[1]
    try:
        port = int(sys.argv[2])
    except ValueError:
        sys.exit(2)

    proxy = (
        os.environ.get("https_proxy")
        or os.environ.get("HTTPS_PROXY")
        or os.environ.get("http_proxy")
        or os.environ.get("HTTP_PROXY")
    )
    if not proxy:
        sys.exit(1)
    u = urllib.parse.urlparse(proxy)
    if not u.hostname:
        sys.exit(1)
    phost = u.hostname
    pport = u.port or 8080

    try:
        s = socket.create_connection((phost, pport), timeout=20)
    except OSError:
        sys.exit(1)

    auth = ""
    if u.username is not None:
        cred = "%s:%s" % (
            urllib.parse.unquote(u.username),
            urllib.parse.unquote(u.password or ""),
        )
        auth = "Proxy-Authorization: Basic %s\r\n" % base64.b64encode(
            cred.encode("utf-8")
        ).decode("ascii")

    req = "CONNECT %s:%d HTTP/1.1\r\nHost: %s:%d\r\n%s\r\n" % (
        host, port, host, port, auth
    )
    try:
        s.sendall(req.encode("ascii"))
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = s.recv(4096)
            if not chunk:
                sys.exit(1)
            buf += chunk
        status = buf.split(b"\r\n", 1)[0]
        if b" 200 " not in status:
            sys.stderr.write(status.decode("utf-8", "ignore") + "\n")
            sys.exit(1)
    except OSError:
        sys.exit(1)

    # Bidirectional relay between stdin/stdout and the tunnel.
    s.setblocking(False)
    try:
        while True:
            r, _, _ = select.select([sys.stdin.buffer, s], [], [], 60)
            if sys.stdin.buffer in r:
                data = os.read(sys.stdin.fileno(), 8192)
                if not data:
                    break
                s.sendall(data)
            if s in r:
                data = s.recv(8192)
                if not data:
                    break
                os.write(sys.stdout.fileno(), data)
    except (OSError, BrokenPipeError):
        pass
    finally:
        try:
            s.close()
        except OSError:
            pass

if __name__ == "__main__":
    main()
