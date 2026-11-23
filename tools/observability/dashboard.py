#!/usr/bin/env python3
"""Serve one observer's local state on loopback; no benchmark files are modified."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PAGE = r'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>CASbench campaign observer</title><style>
body{font:16px system-ui,sans-serif;max-width:1100px;margin:2rem auto;padding:0 1rem;color:#172b3a;background:#f6f9fb}
h1,h2{color:#173f66} table{border-collapse:collapse;width:100%;background:white}th,td{text-align:left;border-bottom:1px solid #dce5eb;padding:.55rem;vertical-align:top}th{background:#eaf0f5}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#172b3a;color:#f3f7fa;padding:1rem;max-height:28rem;overflow:auto}.scroll{overflow-x:auto}.note{color:#455b6a}
</style></head><body><h1>CASbench campaign observer</h1><p id="status">Loading…</p>
<p class="note">Observations are sampled, not benchmark timings. Phase durations begin when first observed; memory peaks are lower bounds. Results may still change.</p>
<h2>Active work</h2><div class="scroll"><table><thead><tr><th>Bench / system</th><th>Case / phase</th><th>Observed duration / budget</th><th>Process tree RSS / sampled peak</th><th>Recorded cases</th></tr></thead><tbody id="active"></tbody></table></div>
<h2>Recorded cases</h2><div class="scroll"><table><thead><tr><th>Result file</th><th>Cases</th><th>Statuses</th></tr></thead><tbody id="files"></tbody></table></div>
<h2>Recent events</h2><pre id="events">Loading…</pre><script>
function rows(id, data){const body=document.getElementById(id); body.replaceChildren(); for(const row of data){const tr=document.createElement('tr'); for(const value of row){const td=document.createElement('td');td.textContent=value;tr.append(td)}body.append(tr)}}
async function refresh(){try {const [sr,er]=await Promise.all([fetch('/state',{cache:'no-store'}),fetch('/events',{cache:'no-store'})]);if(!sr.ok||!er.ok) throw Error('Observer state unavailable');const s=await sr.json();const events=await er.json();document.getElementById('status').textContent=`PID ${s.campaign_pid}: ${s.running?'running':'stopped'}; updated ${s.updated_at}`+(s.exit_code===null?'':`; exit code ${s.exit_code}`)+`; load ${s.load_average.map(x=>x.toFixed(2)).join(', ')}`;
rows('active',s.active.map(a=>[`${a.bench} / ${a.system}`,a.case?`${a.case.index} ${a.case.case} (${a.case.phase})`:'worker starting',`${a.observed_phase_s} s / ${a.phase_budget_s===null?'unknown':a.phase_budget_s+' s'}`,`${(a.observed_tree_rss_bytes/1073741824).toFixed(2)} / ${(a.observed_peak_tree_rss_bytes/1073741824).toFixed(2)} GiB`,a.recorded_cases]));
rows('files',s.files.map(f=>[f.file,f.recorded_cases,Object.entries(f.statuses).map(([k,v])=>`${k}: ${v}`).join(', ')]));document.getElementById('events').textContent=events.map(x=>`${x.timestamp} ${x.event} ${x.line||JSON.stringify(x.active||x.statuses||'')}`).join('\n');}catch(e){document.getElementById('status').textContent=`Unable to refresh: ${e.message}`}}
refresh();setInterval(refresh,3000);
</script></body></html>'''


def handler_for(directory):
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == '/':
                body, content_type = PAGE.encode(), 'text/html; charset=utf-8'
            elif self.path == '/state':
                try:
                    body = (directory / 'state.json').read_bytes()
                except OSError:
                    self.send_error(503, 'State unavailable')
                    return
                content_type = 'application/json; charset=utf-8'
            elif self.path == '/events':
                try:
                    # Bound the read even when the campaign has a long event history.
                    with (directory / 'events.jsonl').open('rb') as f:
                        f.seek(0, 2)
                        size = f.tell()
                        f.seek(max(0, size - 262144))
                        data = f.read().splitlines()
                        if size > 262144:
                            data = data[1:]
                    import json
                    entries = []
                    for line in data[-50:]:
                        try:
                            entries.append(json.loads(line))
                        except (ValueError, UnicodeError):
                            pass
                    body = json.dumps(entries, ensure_ascii=False).encode()
                except OSError:
                    body = b'[]'
                content_type = 'application/json; charset=utf-8'
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', content_type)
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
    return Handler


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('directory', type=Path, help='observer output directory')
    p.add_argument('--port', type=int, default=8765)
    args = p.parse_args()
    server = ThreadingHTTPServer(('127.0.0.1', args.port), handler_for(args.directory.resolve()))
    print(f'Observer dashboard: http://127.0.0.1:{server.server_port}/', flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
