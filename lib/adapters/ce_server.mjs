// A Node.js process that stays alive for a whole worker (lib/adapters/computeengine.jl):
// the Compute Engine (@cortex-js/compute-engine, MathJSON) driven line by line.
//
// Each request is one JSON line on stdin: {"op": ..., "expr": <MathJSON>, ...}; the answer is a
// sequence of marker lines on stdout, ending with <<END>>:
//   <<ANS>> <LaTeX of the result, or "ce_error: ..." >
//   <<TIME>> <seconds of the call inside the engine>
//   <<V1>> ... <<V6>> numeric values of the result at the requested points (op expand_diff, subs, ...)
//   <<N>> the numeric value (op eval)
//   <<C1>> ... values of the compiled function at the requested points (op codegen) and <<CTIME>> their time
// The package directory comes from the COMPUTE_ENGINE_DIR environment variable.
import { createInterface } from "node:readline";
import { performance } from "node:perf_hooks";

const dir = process.env.COMPUTE_ENGINE_DIR;
const { ComputeEngine } = await import(`${dir}/dist/esm-min/compute-engine.js`);
const { compile } = await import(`${dir}/dist/esm-min/compile.js`);
const ce = new ComputeEngine();
ce.timeLimit = 1e9;      // the harness enforces the limit
ce.iterationLimit = 1e9;

const out = (s) => process.stdout.write(s + "\n");
const num = (v) => {
  // a numeric value of a boxed expression as "re,im", or null when it is not a number
  const b = v.N();
  const re = b.re, im = b.im;
  if (typeof re === "number" && Number.isFinite(re)) return `${re},${typeof im === "number" ? im : 0}`;
  return null;
};

console.log("<<READY>>");
const rl = createInterface({ input: process.stdin });
for await (const line of rl) {
  if (!line.trim()) continue;
  if (line.trim() === "<<QUIT>>") break;
  try {
    const req = JSON.parse(line);
    const expr = ce.box(req.expr);
    let result;
    const t0 = performance.now();
    switch (req.op) {
      case "expand": result = ce.box(["Expand", expr]).evaluate(); break;
      case "expand_diff": result = ce.box(["D", ce.box(["Expand", expr]).evaluate(), req.var]).evaluate(); break;
      case "diff": result = ce.box(["D", expr, req.var]).evaluate(); break;
      case "simplify": result = expr.simplify(); break;
      case "subs": result = expr.subs(Object.fromEntries(Object.entries(req.rules).map(([k, v]) => [k, ce.box(v)]))); break;
      case "factor": result = ce.box(["Factor", expr]).evaluate(); break;
      case "eval": result = (req.rules ? expr.subs(Object.fromEntries(Object.entries(req.rules).map(([k, v]) => [k, ce.box(v)]))) : expr).N(); break;
      case "integrate": result = ce.box(["Integrate", expr, req.var]).evaluate(); break;
      case "verify_integral": {
        const antiderivative = ce.parse(req.answer);
        const derivative = ce.box(["D", antiderivative, req.var]).evaluate();
        result = ce.box(["Subtract", derivative, expr]).simplify();
        break;
      }
      case "codegen": {
        const fn = compile(expr, { to: "javascript" });
        if (!fn || !fn.success) throw new Error("compile failed: " + (fn && fn.unsupported ? JSON.stringify(fn.unsupported) : "?"));
        const t1 = performance.now();
        const vals = [];
        for (const p of req.points) vals.push(fn.run(p));
        out(`<<CTIME>> ${((performance.now() - t1) / 1000).toFixed(6)}`);
        vals.forEach((v, i) => out(`<<C${i + 1}>> ${v}`));
        result = expr;
        break;
      }
      default: throw new Error(`unknown op ${req.op}`);
    }
    const t = (performance.now() - t0) / 1000;
    out(`<<ANS>> ${result.latex}`);
    out(`<<TIME>> ${t.toFixed(6)}`);
    if (req.op === "eval") out(`<<N>> ${num(result) ?? "fail"}`);
    if (req.points_eval) {
      req.points_eval.forEach((pt, i) => {
        try { out(`<<V${i + 1}>> ${num(result.subs(pt)) ?? "fail"}`); } catch (err) { out(`<<V${i + 1}>> fail`); }
      });
    }
  } catch (err) {
    out(`<<ANS>> ce_error: ${String(err && err.message ? err.message : err).replace(/\n/g, " ").slice(0, 300)}`);
    out("<<TIME>> nan");
  }
  out("<<END>>");
}
