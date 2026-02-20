#!/usr/bin/env python3
"""
Minimal WebSocket handshake probe for codex app-server.

Default behavior compares two requests:
1) Without Sec-WebSocket-Extensions
2) With Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits
"""

from __future__ import annotations

import argparse
import base64
import os
import socket
import sys
from dataclasses import dataclass


@dataclass
class ProbeResult:
    label: str
    status_line: str
    header_block: str
    ok: bool


def run_probe(
    *,
    host: str,
    port: int,
    path: str,
    timeout: float,
    include_extensions: bool,
    label: str,
) -> ProbeResult:
    key = base64.b64encode(os.urandom(16)).decode("ascii")
    headers = [
        f"GET {path} HTTP/1.1",
        f"Host: {host}:{port}",
        "Upgrade: websocket",
        "Connection: Upgrade",
        f"Sec-WebSocket-Key: {key}",
        "Sec-WebSocket-Version: 13",
    ]
    if include_extensions:
        headers.append("Sec-WebSocket-Extensions: permessage-deflate; client_max_window_bits")
    request = "\r\n".join(headers) + "\r\n\r\n"

    sock = socket.create_connection((host, port), timeout=timeout)
    try:
        sock.sendall(request.encode("ascii"))
        response = sock.recv(8192)
    finally:
        sock.close()

    if not response:
        return ProbeResult(
            label=label,
            status_line="<no response>",
            header_block="",
            ok=False,
        )

    text = response.decode("latin1", errors="replace")
    header_block = text.split("\r\n\r\n", 1)[0]
    status_line = header_block.split("\r\n", 1)[0]
    return ProbeResult(
        label=label,
        status_line=status_line,
        header_block=header_block,
        ok=status_line.startswith("HTTP/1.1 101"),
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Probe codex app-server WebSocket handshake behavior.")
    parser.add_argument("--host", default="127.0.0.1", help="Target host (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8080, help="Target port (default: 8080)")
    parser.add_argument("--path", default="/", help="WebSocket request path (default: /)")
    parser.add_argument("--timeout", type=float, default=5.0, help="Socket timeout seconds (default: 5)")
    parser.add_argument(
        "--single",
        action="store_true",
        help="Run a single probe. Without this flag, script compares without/with extensions.",
    )
    parser.add_argument(
        "--extensions",
        action="store_true",
        help="When --single is set, include Sec-WebSocket-Extensions header.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print full response header block.",
    )
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("--port must be in range 1..65535")
    return args


def print_result(result: ProbeResult, verbose: bool) -> None:
    print(f"[{result.label}] {result.status_line}")
    if verbose and result.header_block:
        print(result.header_block)
        print("---")


def main() -> int:
    args = parse_args()

    try:
        if args.single:
            result = run_probe(
                host=args.host,
                port=args.port,
                path=args.path,
                timeout=args.timeout,
                include_extensions=args.extensions,
                label="with-ext" if args.extensions else "no-ext",
            )
            print_result(result, args.verbose)
            return 0 if result.ok else 1

        without_ext = run_probe(
            host=args.host,
            port=args.port,
            path=args.path,
            timeout=args.timeout,
            include_extensions=False,
            label="no-ext",
        )
        with_ext = run_probe(
            host=args.host,
            port=args.port,
            path=args.path,
            timeout=args.timeout,
            include_extensions=True,
            label="with-ext",
        )
    except OSError as error:
        print(f"probe failed: {error}", file=sys.stderr)
        return 2

    print_result(without_ext, args.verbose)
    print_result(with_ext, args.verbose)

    if without_ext.ok and with_ext.ok:
        return 0
    if without_ext.ok and not with_ext.ok:
        return 3
    if not without_ext.ok and with_ext.ok:
        return 4
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
