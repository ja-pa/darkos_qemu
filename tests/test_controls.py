"""Host legend: process safety, optional GUI failure and real Tk profile rendering."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/controls-window.py'
spec = importlib.util.spec_from_file_location('controls', SCRIPT)
controls = importlib.util.module_from_spec(spec)
spec.loader.exec_module(controls)


class ControlsTests(unittest.TestCase):
    def test_stale_pid_cannot_target_current_process(self):
        with tempfile.TemporaryDirectory() as folder:
            work = Path(folder)
            state = work / 'controls.json'
            state.write_text(json.dumps({'pid': os.getpid(), 'started': 'wrong'}))
            self.assertIsNone(controls.window_pid(state, work))
            started = Path(f'/proc/{os.getpid()}/stat').read_text().rsplit(')', 1)[1].split()[19]
            state.write_text(json.dumps({'pid': os.getpid(), 'started': started}))
            self.assertIsNone(controls.window_pid(state, work))

    def test_unavailable_display_is_optional(self):
        with tempfile.TemporaryDirectory() as folder:
            env = dict(os.environ, DISPLAY=':9876', WAYLAND_DISPLAY='missing')
            result = subprocess.run([sys.executable, str(SCRIPT), 'start', folder],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0)
            self.assertIn('controls window unavailable', result.stderr)
            self.assertFalse((Path(folder) / 'state/controls.json').exists())

    @unittest.skipUnless(os.environ.get('DISPLAY'), 'Requires WSLg or X11')
    def test_real_tk_profiles_resize_and_cleanup(self):
        import tkinter as tk
        from tkinter import ttk
        original = tk.Tk
        errors = []

        def factory():
            root = original()

            def verify():
                try:
                    frame = root.winfo_children()[0]
                    picker = next(w for w in frame.winfo_children() if isinstance(w, ttk.Combobox))
                    rows = next(w for w in frame.winfo_children() if isinstance(w, ttk.Frame))
                    self.assertIn('F4', [w.cget('text') for w in rows.winfo_children()])
                    picker.current(1)
                    picker.event_generate('<<ComboboxSelected>>')
                    root.update_idletasks()
                    text = [w.cget('text') for w in rows.winfo_children()]
                    self.assertIn('Game Boy A', text)
                    self.assertIn('Z', text)
                    self.assertNotIn('F4', text)
                    root.geometry('600x500')
                    root.update_idletasks()
                    self.assertGreaterEqual(root.winfo_width(), 590)
                except Exception as error:
                    errors.append(error)
                finally:
                    root.destroy()
            root.after(150, verify)
            return root

        with tempfile.TemporaryDirectory() as folder:
            work = Path(folder)
            (work / 'state').mkdir()
            state = work / 'state/controls.json'
            with patch.object(tk, 'Tk', factory):
                controls.show(work, state)
            self.assertFalse(state.exists())
        if errors:
            raise errors[0]


if __name__ == '__main__':
    unittest.main()
