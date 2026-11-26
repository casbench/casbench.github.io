#!/usr/bin/env python3
"""Minimal line protocol for the supervised interface test."""
import re
import os
import sys
import time

# a version query is not an interface session: Maxima's `--version`, FriCAS's `-eval ")version"` (VERSIONS(), which
# the first worker of a supervised run calls for its machine block, also when the run starts at BENCH_START_INDEX)
if '--version' in sys.argv or ')version' in sys.argv:
    print('fake CAS 1')
    raise SystemExit(0)

if os.environ.get('FAKE_INTERFACE_STARTS'):
    with open(os.environ['FAKE_INTERFACE_STARTS'], 'a', encoding='utf-8') as f:
        f.write(str(os.getpid()) + '\n')

for line in sys.stdin:
    m = re.search(r'concat\("(CASBENCH)","([0-9]+END)"[),]', line)
    if m:
        if os.environ.get('FAKE_INTERFACE_HANG'):
            time.sleep(30)
        print(m.group(1) + m.group(2) + ' x^2+2*x*y+y^2', flush=True)
