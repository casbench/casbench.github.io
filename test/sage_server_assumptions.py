#!/usr/bin/env python3
"""Exercise assumption isolation in the persistent Sage server (requires Sage)."""
import pathlib
import subprocess
import tempfile

server = pathlib.Path(__file__).resolve().parents[1] / "lib/adapters/sage_server.py"
with tempfile.TemporaryDirectory() as tmp:
    root = pathlib.Path(tmp)
    scripts = [
        "x = var('x')\nassume(x > 0)\nprint('positive')\n",
        "x = var('x')\nassume(x < 0)\nprint('negative')\n",
        "x = var('x')\nassume(x > 0)\nraise ValueError('expected failure')\n",
        "x = var('x')\nassume(x < 0)\nprint('after failure')\n",
    ]
    paths = []
    for i, script in enumerate(scripts):
        path = root / f"case{i}.sage"
        path.write_text(script, encoding="utf-8")
        paths.append(str(path))
    run = subprocess.run(
        ["sage", "-python", str(server)],
        input="\n".join(paths + ["<<QUIT>>", ""]),
        text=True, capture_output=True, timeout=120, check=True,
    )
    assert run.stdout.count("<<END>>") == 4, run.stdout
    for marker in ("positive", "negative", "sage_error: expected failure", "after failure"):
        assert marker in run.stdout, run.stdout
    assert "Assumption is inconsistent" not in run.stdout, run.stdout
print("Sage assumptions isolated across scripts and exceptions")
