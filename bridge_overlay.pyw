# -*- coding: utf-8 -*-
"""Transparent fullscreen Bridge OS threads overlay on the Windows desktop."""
import atexit
import ctypes
import os
import subprocess
import sys
import time
import urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
PID_FILE = os.path.join(ROOT, '.overlay.pid')
PORT = 8787
URL = f'http://127.0.0.1:{PORT}/?overlay=1'


def _pid_alive(pid):
    handle = ctypes.windll.kernel32.OpenProcess(0x1000, False, pid)
    if handle:
        ctypes.windll.kernel32.CloseHandle(handle)
        return True
    return False


def acquire_lock():
    if os.path.isfile(PID_FILE):
        try:
            old = int(open(PID_FILE, encoding='utf-8').read().strip())
            if old != os.getpid() and _pid_alive(old):
                return False
        except (ValueError, OSError):
            pass
    with open(PID_FILE, 'w', encoding='utf-8') as f:
        f.write(str(os.getpid()))
    return True


def release_lock():
    if not os.path.isfile(PID_FILE):
        return
    try:
        if int(open(PID_FILE, encoding='utf-8').read().strip()) == os.getpid():
            os.remove(PID_FILE)
    except (ValueError, OSError):
        pass


def server_up():
    try:
        urllib.request.urlopen(f'http://127.0.0.1:{PORT}/api/info', timeout=2)
        return True
    except Exception:
        return False


def ensure_server():
    if server_up():
        return True
    ps1 = os.path.join(ROOT, 'bridge.ps1')
    subprocess.Popen(
        ['powershell', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass',
         '-File', ps1, '-Action', 'serve'],
        cwd=ROOT,
        creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0),
    )
    for _ in range(20):
        if server_up():
            return True
        time.sleep(0.4)
    return False


class OverlayApi:
    def close_overlay(self):
        for win in webview.windows:
            win.destroy()


def main():
    if not acquire_lock():
        ctypes.windll.user32.MessageBoxW(
            0, 'שכבת החוטים כבר פתוחה.\nEsc או Alt+F4 לסגירה', 'Bridge Overlay', 0x40)
        sys.exit(0)
    atexit.register(release_lock)

    if not ensure_server():
        ctypes.windll.user32.MessageBoxW(
            0, 'שרת Bridge OS לא עלה.\nהפעל קודם: שולחן עבודה.bat', 'Bridge Overlay', 0x10)
        sys.exit(1)

    import webview

    w = ctypes.windll.user32.GetSystemMetrics(0)
    h = ctypes.windll.user32.GetSystemMetrics(1)
    webview.create_window(
        'Bridge OS',
        URL,
        width=w,
        height=h,
        x=0,
        y=0,
        frameless=True,
        transparent=True,
        easy_drag=False,
        on_top=False,
        resizable=False,
        js_api=OverlayApi(),
    )
    webview.start(gui='edgechromium')


if __name__ == '__main__':
    main()