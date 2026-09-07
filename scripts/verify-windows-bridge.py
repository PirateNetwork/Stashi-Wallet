#!/usr/bin/env python3
"""Check the managed-transport handshake without connecting to a Tor bridge."""

import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time


def verify(executable: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="stashi-pt-check-") as state:
        environment = os.environ.copy()
        environment.update({
            "TOR_PT_MANAGED_TRANSPORT_VER": "1",
            "TOR_PT_CLIENT_TRANSPORTS": "obfs4,snowflake",
            "TOR_PT_STATE_LOCATION": state,
            "TOR_PT_EXIT_ON_STDIN_CLOSE": "1",
        })
        process = subprocess.Popen(
            [str(executable.resolve())], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, env=environment, text=True,
            creationflags=subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0,
        )
        lines = queue.Queue()

        def read_lines():
            for line in process.stdout:
                lines.put(line.strip())
            lines.put(None)

        reader = threading.Thread(target=read_lines, daemon=True)
        reader.start()
        try:
            deadline = time.monotonic() + 15
            protocols = set()
            version = None
            while True:
                line = lines.get(timeout=max(0.01, deadline - time.monotonic()))
                if line is None:
                    raise RuntimeError("Bridge helper exited before completing its handshake")
                fields = line.split()
                if fields[:1] == ["VERSION"]:
                    version = fields[1:]
                if fields[:1] == ["CMETHOD"] and len(fields) >= 4 and fields[2] == "socks5":
                    protocols.add(fields[1])
                if line == "CMETHODS DONE":
                    break
                if time.monotonic() >= deadline:
                    raise TimeoutError("Bridge helper handshake timed out")
            if version != ["1"] or protocols != {"obfs4", "snowflake"}:
                raise RuntimeError(f"Unexpected bridge capabilities: {version}, {protocols}")
        finally:
            process.stdin.close()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            reader.join(timeout=1)
            process.stdout.close()
    print("Lyrebird managed-transport handshake passed: obfs4 and snowflake")


if __name__ == "__main__":
    verify(Path(sys.argv[1]))
