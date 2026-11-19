"""Sample aggregate RAM/CPU for the engine and all child processes.

Linux uses /proc. On macOS and Windows, psutil is needed.
"""
from __future__ import annotations

import os
from pathlib import Path
import signal
import subprocess

try:
    import psutil  # type: ignore[import-not-found]
except ImportError:
    psutil = None


def _linux_usage(root: int) -> tuple[float | None, float | None, int]:
    pending = [root]
    visited: set[int] = set()
    rss_bytes = 0
    cpu_ticks = 0
    count = 0
    while pending:
        pid = pending.pop()
        if pid in visited:
            continue
        visited.add(pid)
        try:
            raw = Path(f"/proc/{pid}/task/{pid}/children").read_text()
            pending.extend(int(x) for x in raw.split() if x.isdecimal())
        except OSError:
            pass
        try:
            fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
            pages = Path(f"/proc/{pid}/statm").read_text().split()
            rss_bytes += int(pages[1]) * os.sysconf("SC_PAGE_SIZE")
            cpu_ticks += int(fields[11]) + int(fields[12])
            count += 1
        except (OSError, ValueError, IndexError):
            pass
    if count == 0:
        return None, None, 0
    return rss_bytes / 1048576.0, cpu_ticks / os.sysconf("SC_CLK_TCK"), count


def sample(pid: int) -> tuple[float | None, float | None, int]:
    """Return sampled process-tree RSS (MiB), CPU seconds and process count."""
    if psutil is not None:
        try:
            parent = psutil.Process(pid)
            rss = 0
            cpu = 0.0
            count = 0
            for proc in [parent] + parent.children(recursive=True):
                try:
                    rss += proc.memory_info().rss
                    times = proc.cpu_times()
                    cpu += times.user + times.system
                    count += 1
                except (psutil.NoSuchProcess, psutil.ZombieProcess, psutil.AccessDenied):
                    pass
            if count:
                return rss / 1048576.0, cpu, count
        except (psutil.NoSuchProcess, psutil.ZombieProcess, psutil.AccessDenied):
            pass
    if os.name == "posix" and Path("/proc").is_dir():
        return _linux_usage(pid)
    return None, None, 0


def isolation_options() -> dict[str, object]:
    if os.name == "nt":
        return {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP}
    return {"start_new_session": True}


def kill_group(process: subprocess.Popen[object]) -> None:
    """Stop isolated workload workers and their children on resource violation."""
    if os.name == "posix":
        try:
            os.killpg(process.pid, signal.SIGKILL)
            return
        except ProcessLookupError:
            return
        except OSError:
            pass
    elif os.name == "nt":
        try:
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           timeout=5, check=False)
            return
        except (OSError, subprocess.TimeoutExpired):
            pass
    try:
        process.kill()
    except ProcessLookupError:
        pass
