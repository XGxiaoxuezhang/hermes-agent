"""PTY bridge for the dashboard Chat tab.

The browser Chat page talks to ``/api/pty`` over WebSocket.  This module
wraps the real ``hermes --tui`` child process behind a platform PTY and
exposes a small byte-oriented interface used by that endpoint.

POSIX hosts use ``ptyprocess``.  Native Windows uses ``pywinpty`` / ConPTY.
Both paths intentionally share the same public methods so Windows dashboard
installs can use Chat without requiring WSL.
"""

from __future__ import annotations

import errno
import os
import signal
import struct
import sys
import time
from typing import Optional, Sequence

_IS_WINDOWS = sys.platform.startswith("win")

if _IS_WINDOWS:
    try:
        import winpty  # type: ignore
    except ImportError:  # pragma: no cover - Windows env without pywinpty
        winpty = None  # type: ignore
    ptyprocess = None  # type: ignore
    fcntl = None  # type: ignore
    select = None  # type: ignore
    termios = None  # type: ignore
else:
    try:
        import fcntl
        import select
        import termios
        import ptyprocess  # type: ignore
    except ImportError:  # pragma: no cover - dev env without ptyprocess
        fcntl = None  # type: ignore
        select = None  # type: ignore
        termios = None  # type: ignore
        ptyprocess = None  # type: ignore
    winpty = None  # type: ignore

_PTY_AVAILABLE = bool(winpty if _IS_WINDOWS else ptyprocess)

__all__ = ["PtyBridge", "PtyUnavailableError"]


# ``struct winsize`` packs rows/cols as unsigned short (0..65535).  Clamp
# well below that ceiling: real terminals never exceed a couple thousand
# columns, and values above this are usually broken probes.
_MIN_DIMENSION = 1
_MAX_COLS = 2000
_MAX_ROWS = 1000


def _clamp_dimension(value: int, maximum: int) -> int:
    try:
        n = int(value)
    except (TypeError, ValueError, OverflowError):
        return _MIN_DIMENSION
    if n < _MIN_DIMENSION:
        return _MIN_DIMENSION
    if n > maximum:
        return maximum
    return n


class PtyUnavailableError(RuntimeError):
    """Raised when the platform-specific PTY backend is unavailable."""


class PtyBridge:
    """Thin wrapper around a platform PTY process for byte streaming."""

    def __init__(self, proc):  # type: ignore[no-untyped-def]
        self._proc = proc
        self._fd: int = int(getattr(proc, "fd", -1))
        self._closed = False

    @classmethod
    def is_available(cls) -> bool:
        return bool(_PTY_AVAILABLE)

    @classmethod
    def spawn(
        cls,
        argv: Sequence[str],
        *,
        cwd: Optional[str] = None,
        env: Optional[dict] = None,
        cols: int = 80,
        rows: int = 24,
    ) -> "PtyBridge":
        if not _PTY_AVAILABLE:
            if _IS_WINDOWS:
                raise PtyUnavailableError(
                    "The `pywinpty` package is missing, so native Windows "
                    "embedded chat cannot start. Re-run the Hermes Windows "
                    "installer or install with: pip install pywinpty"
                )
            raise PtyUnavailableError(
                "The `ptyprocess` package is missing. Install with: "
                "pip install ptyprocess (or pip install -e '.[pty]')."
            )

        spawn_env = (os.environ.copy() if env is None else env.copy())
        if not spawn_env.get("TERM"):
            spawn_env["TERM"] = "xterm-256color"

        rows = _clamp_dimension(rows, _MAX_ROWS)
        cols = _clamp_dimension(cols, _MAX_COLS)

        if _IS_WINDOWS:
            # pywinpty defaults to blocking reads. The websocket pump expects
            # read() to periodically return b"" when no data is ready.
            old_block = os.environ.get("PYWINPTY_BLOCK")
            os.environ["PYWINPTY_BLOCK"] = "0"
            try:
                proc = winpty.PtyProcess.spawn(  # type: ignore[union-attr]
                    list(argv),
                    cwd=cwd,
                    env=spawn_env,
                    dimensions=(rows, cols),
                )
            finally:
                if old_block is None:
                    os.environ.pop("PYWINPTY_BLOCK", None)
                else:
                    os.environ["PYWINPTY_BLOCK"] = old_block
        else:
            proc = ptyprocess.PtyProcess.spawn(  # type: ignore[union-attr]
                list(argv),
                cwd=cwd,
                env=spawn_env,
                dimensions=(rows, cols),
            )
        return cls(proc)

    @property
    def pid(self) -> int:
        return int(self._proc.pid)

    def is_alive(self) -> bool:
        if self._closed:
            return False
        try:
            return bool(self._proc.isalive())
        except Exception:
            return False

    def read(self, timeout: float = 0.2) -> Optional[bytes]:
        """Read raw bytes, b"" when idle, or None when the child exits."""
        if self._closed:
            return None

        if _IS_WINDOWS:
            try:
                data = self._proc.read(65536)
            except EOFError:
                return None
            except OSError:
                return None
            if not data:
                return b""
            if isinstance(data, bytes):
                data = data.decode("utf-8", "replace")
            # pywinpty's non-blocking reader uses this private sentinel to
            # wake its socket bridge when no console output is ready.
            data = str(data).replace("0011Ignore", "")
            if not data:
                return b""
            return data.encode("utf-8", "replace")

        try:
            readable, _, _ = select.select([self._fd], [], [], timeout)
        except (OSError, ValueError):
            return None
        if not readable:
            return b""
        try:
            data = os.read(self._fd, 65536)
        except OSError as exc:
            if exc.errno in {errno.EIO, errno.EBADF}:
                return None
            raise
        if not data:
            return None
        return data

    def write(self, data: bytes) -> None:
        if self._closed or not data:
            return

        if _IS_WINDOWS:
            try:
                self._proc.write(data.decode("utf-8", "ignore"))
            except (EOFError, OSError):
                return
            return

        view = memoryview(data)
        while view:
            try:
                n = os.write(self._fd, view)
            except OSError as exc:
                if exc.errno in {errno.EIO, errno.EBADF, errno.EPIPE}:
                    return
                raise
            if n <= 0:
                return
            view = view[n:]

    def resize(self, cols: int, rows: int) -> None:
        if self._closed:
            return
        cols = _clamp_dimension(cols, _MAX_COLS)
        rows = _clamp_dimension(rows, _MAX_ROWS)

        if _IS_WINDOWS:
            try:
                self._proc.setwinsize(rows, cols)
            except Exception:
                pass
            return

        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        try:
            fcntl.ioctl(self._fd, termios.TIOCSWINSZ, winsize)
        except OSError:
            pass

    def close(self) -> None:
        if self._closed:
            return
        self._closed = True

        if _IS_WINDOWS:
            try:
                self._proc.close(force=True)
            except Exception:
                try:
                    self._proc.terminate(force=True)
                except Exception:
                    pass
            return

        for sig in (signal.SIGHUP, signal.SIGTERM, signal.SIGKILL):
            if not self._proc.isalive():
                break
            try:
                self._proc.kill(sig)
            except Exception:
                pass
            deadline = time.monotonic() + 0.5
            while self._proc.isalive() and time.monotonic() < deadline:
                time.sleep(0.02)

        try:
            self._proc.close(force=True)
        except Exception:
            pass

    def __enter__(self) -> "PtyBridge":
        return self

    def __exit__(self, *_exc) -> None:
        self.close()
