"""Optional host-side control legend; no guest connections or input injection."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

SCRIPT = Path(__file__).resolve()
CONFIG = SCRIPT.parents[1] / 'config/controls.json'


def window_pid(state, work):
    """Never signal an unrelated process when a PID file outlives its window."""
    try:
        saved = json.loads(state.read_text())
        proc = Path('/proc') / str(saved['pid'])
        args = (proc / 'cmdline').read_bytes().split(b'\0')
        started = (proc / 'stat').read_text().rsplit(')', 1)[1].split()[19]
        if (started == saved['started'] and str(SCRIPT).encode() in args
                and b'show' in args and str(work).encode() in args):
            return saved['pid']
    except (OSError, ValueError, KeyError, IndexError):
        pass
    return None


def show(work, state):
    # The window itself holds the lock, including during Tk initialization.
    with (work / 'state/controls.lock').open('w') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        import tkinter as tk
        from tkinter import ttk
        profiles = json.loads(CONFIG.read_text())['profiles']
        root = tk.Tk()
        root.title('dArkOS — Controls')
        root.geometry('430x410+860+100')
        root.minsize(390, 380)
        # A WM hint, not a positioning/focus guarantee under WSLg.
        try:
            root.attributes('-type', 'utility')
        except tk.TclError:
            pass
        outer = ttk.Frame(root, padding=16)
        outer.pack(fill='both', expand=True)
        ttk.Label(outer, text='Keyboard controls', font=('sans', 16, 'bold')).pack(anchor='w')
        profile = ttk.Combobox(outer, values=[p['name'] for p in profiles], state='readonly')
        profile.pack(fill='x', pady=(12, 10))
        rows = ttk.Frame(outer)
        rows.pack(fill='both', expand=True)
        note = ttk.Label(outer, wraplength=390, justify='left')
        note.pack(fill='x', pady=(12, 0))

        def select(_event=None):
            for child in rows.winfo_children():
                child.destroy()
            current = profiles[profile.current()]
            for row, (action, key) in enumerate(current['controls']):
                ttk.Label(rows, text=action).grid(row=row, column=0, sticky='w', pady=6)
                ttk.Label(rows, text=key, font=('sans', 11, 'bold')).grid(
                    row=row, column=1, sticky='e', padx=(12, 0), pady=6)
            rows.columnconfigure(0, weight=1)
            note.configure(text=current['note'])

        profile.bind('<<ComboboxSelected>>', select)
        root.bind('<Configure>', lambda e: note.configure(wraplength=max(100, root.winfo_width() - 40)))
        profile.current(0)
        select()
        signal.signal(signal.SIGTERM, lambda *_: root.destroy())

        def tick():
            root.after(200, tick)  # Allow Python to deliver SIGTERM while idle in Tk.

        tick()
        pid = os.getpid()
        started = Path(f'/proc/{pid}/stat').read_text().rsplit(')', 1)[1].split()[19]
        state.write_text(json.dumps({'pid': pid, 'started': started}))
        try:
            root.mainloop()
        finally:
            state.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['start', 'stop', 'show'])
    parser.add_argument('work', type=Path)
    args = parser.parse_args()
    work = args.work.resolve()
    (work / 'state').mkdir(parents=True, exist_ok=True)
    state = work / 'state/controls.json'
    if args.action == 'show':
        show(work, state)
    elif args.action == 'stop':
        pid = window_pid(state, work)
        if pid:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            for _ in range(20):
                if not window_pid(state, work):
                    break
                time.sleep(0.1)
    else:
        if window_pid(state, work):
            return
        log = work / 'logs/workflow/controls.log'
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open('ab') as output:
            child = subprocess.Popen([sys.executable, str(SCRIPT), 'show', str(work)],
                                     stdin=subprocess.DEVNULL, stdout=output, stderr=output,
                                     start_new_session=True)
        for _ in range(30):
            if window_pid(state, work):
                return
            if child.poll() is not None:
                break
            time.sleep(0.1)
        print(f'Warning: controls window unavailable; install python3-tk and check WSLg. Log: {log}',
              file=sys.stderr)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        # Optional help must never prevent QEMU from starting.
        print(f'Warning: controls window: {error}', file=sys.stderr)
