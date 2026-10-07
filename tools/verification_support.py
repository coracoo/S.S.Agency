"""隔离验证入口共享的跨平台互斥与错误感知子进程等待。"""
from contextlib import contextmanager
import errno
import os
from pathlib import Path
import queue
import re
import signal
import subprocess
import threading
import time

ENGINE_ERROR = re.compile(r"(^|\n)(?:SCRIPT ERROR|ERROR):")


def _stop_process_tree(process):
    # Windows 官方 console 可再启动真实引擎；只杀包装进程会留下占用管道的子进程。
    if os.name == "nt":
        subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


@contextmanager
def exclusive_file_lock(path, timeout=600):
    """Windows 锁定首字节，POSIX 使用 flock；异常退出也释放共享锁。"""
    with Path(path).open("a+b") as stream:
        if os.name == "nt":
            import msvcrt
            if stream.seek(0, os.SEEK_END) == 0:
                stream.write(b"\0")
                stream.flush()
            deadline = time.monotonic() + timeout
            while True:
                stream.seek(0)
                try:
                    msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                    break
                except OSError as error:
                    if error.errno not in (errno.EACCES, errno.EAGAIN, errno.EDEADLK):
                        raise
                    if time.monotonic() >= deadline:
                        raise TimeoutError("等待共享文件锁超时：" + str(path)) from error
                    time.sleep(.05)
            try:
                yield stream
            finally:
                stream.seek(0)
                msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
        else:
            import fcntl
            deadline = time.monotonic() + timeout
            while True:
                try:
                    fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except OSError as error:
                    if error.errno not in (errno.EACCES, errno.EAGAIN):
                        raise
                    if time.monotonic() >= deadline:
                        raise TimeoutError("等待共享文件锁超时：" + str(path)) from error
                    time.sleep(.05)
            try:
                yield stream
            finally:
                fcntl.flock(stream, fcntl.LOCK_UN)


def run_captured(command, *, env=None, timeout=300):
    """后台逐块读取两平台管道；解析错误时停止空转并保留完整日志。"""
    deadline = time.monotonic() + timeout
    with subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=os.name != "nt") as process:
        messages = queue.Queue()
        chunks = []

        def read_pipe():
            try:
                while chunk := process.stdout.read1(65536):
                    messages.put(chunk)
            finally:
                messages.put(None)

        reader = threading.Thread(target=read_pipe, daemon=True)
        reader.start()
        timed_out = False
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                timed_out = True
                break
            try:
                chunk = messages.get(timeout=min(.1, remaining))
            except queue.Empty:
                continue
            if chunk is None:
                break
            chunks.append(chunk)
            if ENGINE_ERROR.search(b"".join(chunks).decode("utf-8", errors="replace")):
                _stop_process_tree(process)
                break
        if timed_out:
            _stop_process_tree(process)
        try:
            process.wait(timeout=max(.01, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            timed_out = True
            _stop_process_tree(process)
            process.wait()
        reader.join()
        while not messages.empty():
            chunk = messages.get_nowait()
            if chunk is not None:
                chunks.append(chunk)
        output = b"".join(chunks)
        if timed_out:
            raise subprocess.TimeoutExpired(command, timeout, output=output)
        return subprocess.CompletedProcess(command, process.returncode, output.decode("utf-8", errors="replace"))
