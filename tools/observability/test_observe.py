#!/usr/bin/env python3
import argparse
import json
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer
from pathlib import Path
from urllib.request import urlopen
from unittest.mock import patch
sys.path.insert(0, str(Path(__file__).resolve().parent))
import observe
import dashboard


class ObserveTests(unittest.TestCase):
    def test_dashboard_serves_only_observer_data(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / 'state.json').write_text('{"running": true}')
            (root / 'events.jsonl').write_text('{"event":"start"}\n')
            server = ThreadingHTTPServer(('127.0.0.1', 0), dashboard.handler_for(root))
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                url = f'http://127.0.0.1:{server.server_port}'
                self.assertTrue(json.load(urlopen(url + '/state'))['running'])
                self.assertEqual(json.load(urlopen(url + '/events'))[0]['event'], 'start')
                self.assertIn(b'CASbench campaign observer', urlopen(url + '/').read())
            finally:
                server.shutdown()
                server.server_close()
                thread.join()

    def test_counts_ignore_partial_records_and_load(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'r.tsv'
            p.write_text('idx\tcase\tstatus\n0\t_load\tverified\n1\ta\tverified\n2\tb\ttimeout\n3\tc\twrong')
            self.assertEqual(observe.read_counts(p), ({'timeout': 1, 'verified': 1}, 2))
            p.write_text('idx\tcase\tstatus\tresult\n1\ta\tverified\t' + 'x' * 200000 + '\n')
            self.assertEqual(observe.read_counts(p), ({'verified': 1}, 1))

    def test_progress_and_case_budget(self):
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            p = root / 'progress'
            p.write_text('34\tcyclic9\tnumeric')
            progress = observe.read_progress(p)
            self.assertEqual(progress['phase'], 'numeric')
            (root / '123').mkdir()
            (root / '123' / 'environ').write_bytes(b'BENCH_NUMERIC_VERIFY_TIMEOUT=42\0BENCH_CASE_BUDGETS=34:3600\0')
            sup = {'pid': 123, 'default_budget_s': 600}
            self.assertEqual(observe.phase_budget(sup, progress, root), 42)
            progress['phase'] = 'answer'
            self.assertEqual(observe.phase_budget(sup, progress, root), 3600)
            p.write_text('34\t')
            self.assertIsNone(observe.read_progress(p))

    def test_watch_records_transitions_without_mutating_results(self):
        with tempfile.TemporaryDirectory() as d:
            base = Path(d)
            results = base / 'results'
            results.mkdir()
            out = results / 'E_system.tsv'
            original = 'idx\tcase\tstatus\n1\tx\tverified\n'
            out.write_text(original)
            (results / 'E_system.tsv.progress').write_text('2\ty\tanswer')
            log = base / 'run.log'
            log.write_text('[supervise] worker crashed; restarting\n')
            exit_file = base / 'exit-code'
            exit_file.write_text('0\n')
            root = {'ppid': 1, 'start': 9, 'cmd': ['julia', 'run_all.jl'], 'rss': 10, 'state': 'S'}
            sup = {'ppid': 99, 'start': 10, 'cmd': ['julia', '/x/supervise.jl', 'env', 'worker', 'E', 'system', str(out), '60'], 'rss': 20, 'state': 'S'}
            snapshots = [{99: root}, {99: root, 100: sup}, {}]
            args = argparse.Namespace(pid=99, results=results, output=base / 'observe', log=log, exit_file=exit_file, interval=1)
            with patch.object(observe, 'process_info', side_effect=snapshots), patch.object(observe.time, 'sleep'), patch.object(observe.os, 'nice'):
                observe.watch(args)
            state = json.loads((args.output / 'state.json').read_text())
            events = [json.loads(line) for line in (args.output / 'events.jsonl').read_text().splitlines()]
            self.assertEqual(state['exit_code'], 0)
            self.assertEqual(state['files'][0]['statuses'], {'verified': 1})
            self.assertTrue(any(e['event'] == 'active_changed' and e['active'] and e['active'][0]['case']['index'] == 2 for e in events))
            self.assertTrue(any(e['event'] == 'supervisor_log' and 'crashed' in e['line'] for e in events))
            self.assertEqual(out.read_text(), original)


if __name__ == '__main__':
    unittest.main()
