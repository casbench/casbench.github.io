# Observing a campaign

The optional observer is a separate, low-priority Linux process. It reads the
supervisor's progress files, results and campaign log; it never writes to them.
The observer's JSON state and event log belong outside `results/`, and are not
benchmark results. Start it with the PID of `run_all.jl`:

```sh
python3 -I tools/observability/observe.py watch \
  --pid RUN_ALL_PID --results results/HOST --output /tmp/casbench-observer \
  --log /tmp/campaign.log --exit-file /tmp/campaign.exit
```

The log and exit file are optional. A shell wrapper can write its exit status
after the campaign finishes, for example `command; echo $? > /tmp/campaign.exit`.
The observer distinguishes a known exit code from a stopped process whose exit
status is unknown. It protects against PID reuse and writes snapshots atomically.
It can attach after a run starts; events before attachment are only available if
the supplied campaign log contains them. It ignores incomplete TSV rows.

Inspect the latest snapshot with:

```sh
python3 -I tools/observability/observe.py show /tmp/casbench-observer/state.json
python3 -I tools/observability/dashboard.py /tmp/casbench-observer --port 8765
```

The dashboard listens only on `127.0.0.1`. For a VM, forward the port with
`ssh -L 8765:127.0.0.1:8765 VM` and open <http://127.0.0.1:8765/> locally.
The dashboard shows active case and phase, observed duration and configured
budget, process-tree resident memory, per-file status counts and recent events.
The full journal is `events.jsonl` in the observer directory. It contains the
supervisor's log messages and should be treated as local operational data.

The observer samples every three seconds by default. The observed duration
starts when it first sees a phase, and the observed memory peak may miss a
short-lived peak. Process-tree RSS can double-count shared pages. Neither is a
replacement for the harness's recorded timings or a certified memory measure.
The default answer budget is reported separately from the per-case or phase
budget. Changes to observation files never alter the committed benchmark data.
