#!/usr/bin/env python3
"""One GrobX call; input is the msolve-format instance file passed in argv."""
import resource
import sys
import time
import grobx

if sys.platform != 'linux':
    raise RuntimeError('GrobX benchmark process RSS is defined here only on Linux')
if grobx.__version__ != '0.73.3':
    raise RuntimeError('expected GrobX 0.73.3, got ' + grobx.__version__)
with open(sys.argv[1], encoding='utf-8') as f:
    instance = f.read()
t0 = time.perf_counter()
answer = grobx.groebner(instance, order='grevlex', threads=1, seed=0, checker=None)
elapsed = time.perf_counter() - t0
print('<<TIME>>', format(elapsed, '.17g'))
if answer.basis is None:
    print('<<STOP>>', answer.stopped or 'no basis')
else:
    basis = answer.basis.strip()
    if not basis.endswith(']:') or not basis.startswith('['):
        raise ValueError('unexpected GrobX basis format')
    for polynomial in basis[1:-2].split(','):
        if polynomial.strip():
            print('<<G>>', polynomial.strip())
print('<<RSS_KIB>>', resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
