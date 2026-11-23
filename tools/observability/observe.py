#!/usr/bin/env python3
"""Read-only sidecar for a running Linux benchmark campaign.

Example: python3 tools/observability/observe.py watch --pid 1234 --results results/host \
  --output /tmp/casbench-observe --log /tmp/run.log --exit-file /tmp/exit-code
View: python3 tools/observability/observe.py show /tmp/casbench-observe/state.json
The observer writes only to --output, never to results or the worker's progress files.
"""
import argparse
import collections
import datetime
import json
import os
from pathlib import Path
import time


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def process_info(proc_root=Path('/proc')):
    """Snapshot process IDs, parents, start ticks, command arguments, and resident bytes."""
    processes = {}
    for entry in proc_root.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            fields = (entry / 'stat').read_text().rsplit(')', 1)[1].split()
            cmd = (entry / 'cmdline').read_bytes().split(b'\0')
            cmd = [x.decode('utf-8', errors='replace') for x in cmd if x]
            rss = int((entry / 'statm').read_text().split()[1]) * os.sysconf('SC_PAGE_SIZE')
            processes[int(entry.name)] = {'ppid': int(fields[1]), 'start': int(fields[19]),
                                           'cmd': cmd, 'rss': rss, 'state': fields[0]}
        except (OSError, ValueError, IndexError):
            continue
    return processes


def descendants(processes, root):
    selected = {root}
    while True:
        added = {pid for pid, info in processes.items() if info['ppid'] in selected} - selected
        if not added:
            return selected
        selected.update(added)


def read_counts(path):
    """Count complete TSV records only, excluding the harness load record."""
    counts = collections.Counter()
    try:
        with path.open('rb') as f:
            columns = f.readline().rstrip(b'\r\n').split(b'\t')
            idx, case, status = (columns.index(name) for name in (b'idx', b'case', b'status'))
            last = max(idx, case, status)
            for line in f:
                if not line.endswith(b'\n'):
                    continue
                fields = line.split(b'\t', last + 1)
                if len(fields) <= last or not fields[idx].isdigit() or fields[case] == b'_load':
                    continue
                value = fields[status].strip().decode('utf-8', errors='replace')
                if value:
                    counts[value] += 1
    except (OSError, ValueError):
        return {}, 0
    return dict(sorted(counts.items())), sum(counts.values())


def read_progress(path):
    try:
        parts = path.read_text(encoding='utf-8').split('\t', 2)
        if len(parts) < 2 or not parts[0].isdigit() or not parts[1].strip():
            return None
        phase = parts[2].strip() if len(parts) == 3 else 'answer'
        if phase not in ('answer', 'numeric', 'verify'):
            return None
        return {'index': int(parts[0]), 'case': parts[1].strip(), 'phase': phase}
    except (OSError, UnicodeError):
        return None


def supervisors(processes, campaign_pid):
    found = []
    for pid in sorted(descendants(processes, campaign_pid)):
        info = processes.get(pid)
        if not info:
            continue
        args = info['cmd']
        for i, arg in enumerate(args):
            if Path(arg).name == 'supervise.jl' and len(args) >= i + 7:
                found.append({'pid': pid, 'bench': args[i + 3], 'system': args[i + 4],
                              'output': args[i + 5], 'default_budget_s': float(args[i + 6])})
                break
    return found


def phase_budget(sup, progress, proc_root=Path('/proc')):
    if not progress:
        return None
    try:
        raw = (proc_root / str(sup['pid']) / 'environ').read_bytes().split(b'\0')
        env = dict(x.decode('utf-8', errors='replace').split('=', 1) for x in raw if b'=' in x)
        if progress['phase'] == 'numeric':
            return float(env.get('BENCH_NUMERIC_VERIFY_TIMEOUT', '60'))
        if progress['phase'] == 'verify':
            return float(env.get('BENCH_VERIFY_TIMEOUT', '60'))
        budgets = dict(item.split(':', 1) for item in env.get('BENCH_CASE_BUDGETS', '').split(',') if ':' in item)
        return float(budgets.get(str(progress['index']), sup['default_budget_s']))
    except (OSError, ValueError):
        return None


def atomic_json(path, value):
    tmp = path.with_name(path.name + '.tmp')
    tmp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    os.replace(tmp, path)


def result_summary(results, cache=None):
    result = []
    for path in sorted(results.glob('*.tsv')):
        try:
            stat = path.stat()
        except OSError:
            continue
        signature = (stat.st_size, stat.st_mtime_ns)
        cached = cache.get(path) if cache is not None else None
        if cached and cached[0] == signature:
            counts, total = cached[1]
        else:
            counts, total = read_counts(path)
            if cache is not None:
                cache[path] = (signature, (counts, total))
        result.append({'file': path.name, 'recorded_cases': total, 'statuses': counts})
    return result


def tail_new(path, offset):
    if not path:
        return offset, []
    try:
        with path.open('rb') as f:
            if f.seek(0, os.SEEK_END) < offset:
                offset = 0
            f.seek(offset)
            data = f.read()
            last = data.rfind(b'\n')
            if last < 0:
                return offset, []
            return offset + last + 1, data[:last].decode('utf-8', errors='replace').splitlines()
    except OSError:
        return offset, []


def watch(args):
    results, output = args.results.resolve(), args.output.resolve()
    if output == results or results in output.parents:
        raise ValueError('observer output must be outside the results directory')
    output.mkdir(parents=True, exist_ok=True)
    try:
        os.nice(10)
    except OSError:
        pass
    initial = process_info().get(args.pid)
    if not initial or initial['state'] == 'Z':
        raise ValueError('campaign process is not running')
    start_ticks = initial['start']
    log_offset = 0
    previous = {}
    previous_counts = {}
    result_cache = {}
    seen_since = {}
    peak_rss = {}
    with (output / 'events.jsonl').open('a', encoding='utf-8', buffering=1) as events:
        def emit(kind, **fields):
            events.write(json.dumps({'timestamp': utc_now(), 'event': kind, **fields}, ensure_ascii=False) + '\n')
        emit('observer_started', campaign_pid=args.pid, results=str(results))
        while True:
            now = time.time()
            processes = process_info()
            root = processes.get(args.pid)
            running = bool(root and root['start'] == start_ticks and root['state'] != 'Z')
            files = result_summary(results, result_cache)
            by_file = {f['file']: f for f in files}
            current = []
            if running:
                for sup in supervisors(processes, args.pid):
                    progress = read_progress(Path(sup['output'] + '.progress'))
                    key = (sup['pid'], progress['index'], progress['phase']) if progress else (sup['pid'], None, 'startup')
                    seen_since.setdefault(key, now)
                    tree = descendants(processes, sup['pid'])
                    rss = sum(processes[p]['rss'] for p in tree if p in processes)
                    peak_rss[sup['pid']] = max(peak_rss.get(sup['pid'], 0), rss)
                    summary = by_file.get(Path(sup['output']).name, {'statuses': {}, 'recorded_cases': 0})
                    current.append({**sup, 'case': progress, 'observed_phase_s': round(now - seen_since[key], 1),
                                    'phase_budget_s': phase_budget(sup, progress),
                                    'observed_tree_rss_bytes': rss, 'observed_peak_tree_rss_bytes': peak_rss[sup['pid']],
                                    'recorded_cases': summary['recorded_cases'], 'statuses': summary['statuses']})
            current_keys = {str(x['pid']): {'bench': x['bench'], 'system': x['system'], 'case': x['case']} for x in current}
            if current_keys != previous:
                emit('active_changed', active=list(current_keys.values()))
                previous = current_keys
            log_offset, lines = tail_new(args.log, log_offset)
            for line in lines:
                if '[supervise]' in line:
                    emit('supervisor_log', line=line)
            exit_code = None
            if not running and args.exit_file:
                # The shell writes the exit file immediately after wait(2);
                # allow that write to finish before the final snapshot.
                if not args.exit_file.exists():
                    time.sleep(1)
                try:
                    exit_code = int(args.exit_file.read_text().strip())
                except (OSError, ValueError):
                    pass
            for item in files:
                if previous_counts.get(item['file']) != item['statuses']:
                    emit('counts_changed', **item)
                    previous_counts[item['file']] = item['statuses']
            state = {'updated_at': utc_now(), 'campaign_pid': args.pid, 'running': running,
                     'exit_code': exit_code, 'results': str(results), 'active': current,
                     'load_average': list(os.getloadavg()), 'files': files,
                     'note': 'Samples are observational; phase durations start when first observed and RSS peaks are sampled.'}
            atomic_json(output / 'state.json', state)
            if not running:
                emit('campaign_stopped', exit_code=exit_code)
                break
            time.sleep(args.interval)


def show(path):
    state = json.loads(path.read_text(encoding='utf-8'))
    print(f"Campaign PID {state['campaign_pid']}: {'running' if state['running'] else 'stopped'}; updated {state['updated_at']}")
    if state['exit_code'] is not None:
        print(f"Exit code: {state['exit_code']}")
    for a in state['active']:
        case = a['case']
        detail = f"{case['index']} {case['case']} ({case['phase']})" if case else 'worker starting'
        budget = f" / {a['phase_budget_s']} s budget" if a.get('phase_budget_s') is not None else ''
        print(f"{a['bench']}/{a['system']}: {detail}; observed {a['observed_phase_s']} s; "
              f"{a['recorded_cases']} recorded; tree RSS {a['observed_tree_rss_bytes'] / 2**30:.2f} GiB{budget}")
    for f in state['files']:
        print(f"  {f['file']}: {f['recorded_cases']} cases {f['statuses']}")
    print(state['note'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest='command', required=True)
    w = subs.add_parser('watch')
    w.add_argument('--pid', type=int, required=True)
    w.add_argument('--results', type=Path, required=True)
    w.add_argument('--output', type=Path, required=True)
    w.add_argument('--log', type=Path)
    w.add_argument('--exit-file', type=Path)
    w.add_argument('--interval', type=float, default=3.0)
    s = subs.add_parser('show')
    s.add_argument('state', type=Path)
    args = parser.parse_args()
    if args.command == 'watch':
        if args.interval < 1:
            parser.error('--interval must be at least 1 second')
        watch(args)
    else:
        show(args.state)


if __name__ == '__main__':
    main()
