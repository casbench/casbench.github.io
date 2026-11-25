#!/usr/bin/env python3
"""A subprocess memory peak must not inherit its launching worker's peak."""
import os
import pathlib
import subprocess
import sys
import tempfile

runner = pathlib.Path(__file__).resolve().parents[1] / 'lib/adapters/grobx_runner.py'
with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    (root / 'grobx.py').write_text(
        "__version__ = '0.73.3'\n"
        "class Answer:\n    basis = '[x]:'\n"
        "def groebner(*args, **kwargs): return Answer()\n", encoding='utf-8')
    instance = root / 'input.txt'
    instance.write_text('x\n0\nx\n', encoding='utf-8')
    allocation = bytearray(192 * 1024 * 1024)
    del allocation
    env = dict(os.environ, PYTHONPATH=str(root))
    result = subprocess.run([sys.executable, str(runner), str(instance)], env=env,
                            capture_output=True, text=True, check=True)
    rss = next(int(line.split()[1]) for line in result.stdout.splitlines()
               if line.startswith('<<RSS_KIB>>'))
    assert 0 < rss < 128 * 1024, f'child RSS inherited parent peak: {rss} KiB'
print('GrobX process RSS excludes the launcher peak')
