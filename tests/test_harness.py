#!/usr/bin/env python3
import fcntl
import os
import pty
import select
import signal
import struct
import sys
import termios
import time

READY           = b"Tip"
QUIT_CMD        = b"/exit\r"
STARTUP_TIMEOUT = 45
QUIT_TIMEOUT    = 30
INPUT_DELAY     = 0
CHAR_DELAY      = 0.005  # seconds between keystrokes to simulate real typing


def test_harness(binary: str, debug: bool = False) -> None:
    master, slave = pty.openpty()

    # Set a real terminal size so TUI apps render correctly
    winsize = struct.pack("HHHH", 24, 80, 0, 0)
    fcntl.ioctl(master, termios.TIOCSWINSZ, winsize)
    fcntl.ioctl(slave,  termios.TIOCSWINSZ, winsize)

    pid = os.fork()

    if pid == 0:
        os.setsid()
        os.dup2(slave, 0)
        os.dup2(slave, 1)
        os.dup2(slave, 2)
        if slave > 2:
            os.close(slave)
        os.close(master)
        os.execvp(binary, [binary])
        os._exit(1)

    os.close(slave)

    buf      = b""
    deadline = time.monotonic() + STARTUP_TIMEOUT
    ready    = False

    while time.monotonic() < deadline:
        remaining = max(0.0, deadline - time.monotonic())
        r, _, _ = select.select([master], [], [], min(remaining, 0.5))
        if r:
            try:
                chunk = os.read(master, 4096)
                buf += chunk
                if debug:
                    print(repr(chunk), file=sys.stderr, flush=True)
            except OSError:
                break
            if READY in buf:
                ready = True
                break

    if not ready:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
        os.close(master)
        print(f"FAIL: {binary} — timed out waiting for ready state")
        sys.exit(1)

    # Drain PTY continuously so the child never blocks on output; send the quit
    # command one byte at a time (bulk writes can trigger paste-mode in TUI apps).
    status   = None
    char_idx = 0
    send_at  = time.monotonic() + INPUT_DELAY
    deadline = time.monotonic() + INPUT_DELAY + QUIT_TIMEOUT

    while time.monotonic() < deadline:
        now = time.monotonic()
        if char_idx < len(QUIT_CMD) and now >= send_at:
            byte = QUIT_CMD[char_idx:char_idx + 1]
            if debug:
                print(f"[sending {byte!r}]", file=sys.stderr, flush=True)
            try:
                os.write(master, byte)
            except OSError:
                pass
            char_idx += 1
            send_at = now + CHAR_DELAY

        r, _, _ = select.select([master], [], [], 0.1)
        if r:
            try:
                chunk = os.read(master, 4096)
                if debug:
                    print(repr(chunk), file=sys.stderr, flush=True)
            except OSError:
                try:
                    _, status = os.waitpid(pid, 0)
                except ChildProcessError:
                    status = 0
                break

        try:
            wpid, wstatus = os.waitpid(pid, os.WNOHANG)
            if wpid:
                status = wstatus
                break
        except ChildProcessError:
            status = 0
            break

    os.close(master)

    if status is None:
        os.kill(pid, signal.SIGKILL)
        os.waitpid(pid, 0)
        print(f"FAIL: {binary} — did not exit after quit")
        sys.exit(1)

    if os.WIFSIGNALED(status):
        print(f"FAIL: {binary} — killed by signal {os.WTERMSIG(status)}")
        sys.exit(1)

    if not os.WIFEXITED(status) or os.WEXITSTATUS(status) != 0:
        print(f"FAIL: {binary} — exited with code {os.WEXITSTATUS(status)}")
        sys.exit(1)

    print(f"PASS: {binary} — started and exited cleanly")


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    debug = "--debug" in sys.argv
    if len(args) != 1:
        print(f"Usage: {sys.argv[0]} [--debug] <binary>", file=sys.stderr)
        sys.exit(1)
    test_harness(args[0], debug=debug)
