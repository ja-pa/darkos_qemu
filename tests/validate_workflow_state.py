"""Integration rejection checks; run with the prepared WORK_DIR VM active."""
import os
from pathlib import Path
import subprocess

work = Path(os.environ['WORK_DIR'])
logs = work / 'logs/workflow'

def rejected(name, args, env=None):
    result = subprocess.run(args, env=env, capture_output=True, text=True)
    (logs / name).write_text(result.stdout + result.stderr)
    assert result.returncode != 0, f'Unexpected success: {args}'

env = dict(os.environ, DISK_IMAGE=str(work / 'images/other.qcow2'))
rejected('rejected-foreign-vm.log', ['bash', 'vm.sh', 'status'], env)
rejected('rejected-active-check.log', ['bash', 'vm.sh', 'check'])
path = work / 'state/runtime-id'
original = path.read_bytes()
try:
    path.write_text('0' * 64 + '\n')
    rejected('rejected-sdk-mismatch.log', ['bash', 'sdk.sh', 'check'])
finally:
    path.write_bytes(original)
print('Foreign VM, active image check and SDK mismatch rejected; original state restored')
