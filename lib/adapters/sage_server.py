#!/usr/bin/env sage -python
"""A Sage process that stays alive for a whole worker (lib/adapters/sage.jl).

Reads one line at a time from stdin: the path of a Sage script. The script is
preparsed (Sage syntax: ^ is a power, integer literals are Sage Integers) and
executed in a fresh namespace over `sage.all`. Sage assumptions are global,
so clear them before and after each script, including after an exception.
Whatever the script prints goes to
stdout, then the line <<END>> marks the end of the answer. An exception is
printed as "<<ANS>> sage_error: ..." so that the caller sees it as an answer.
Starting Sage once per worker instead of once per case saves several seconds
per case; the giac pexpect interface stays open across cases as well.
"""
import sys
import traceback

from sage.all import *                      # noqa: F401,F403
from sage.repl.preparse import preparse

sys.stdout.reconfigure(line_buffering=True)
print("<<READY>>", flush=True)
for line in sys.stdin:
    path = line.strip()
    if not path:
        continue
    if path == "<<QUIT>>":
        break
    try:
        forget()
        with open(path, encoding="utf-8") as f:
            code = preparse(f.read())
        ns = {}
        exec("from sage.all import *", ns)
        exec(code, ns)
    except SystemExit:
        pass
    except Exception as ex:                 # noqa: BLE001
        print("<<ANS>> sage_error: " + str(ex).replace("\n", " ")[:300])
        print("<<TIME>> nan")
    finally:
        forget()
        print("<<END>>", flush=True)
