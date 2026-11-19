// Filter and sort the tables of the site, in the browser, without any dependency.
//   - a text filter for the whole table and one filter box per column (all must match, case-insensitive);
//   - click a heading to sort by it (again to reverse); shift+click adds it as a further key, so that
//     several columns sort together, in the order shown by the small numbers next to the arrows;
//   - values with a unit (2 µs, 15.3 ms, 1.20 s) and plain numbers sort numerically, the rest as text.
// Tables stay complete and readable without JavaScript.
document.addEventListener("DOMContentLoaded", () => {
  const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });
  const UNITS = { "µs": 1e-6, "us": 1e-6, "ms": 1e-3, "s": 1 };
  const numeric = (text) => {
    const t = text.trim().replace(/,/g, "");
    let m = t.match(/^([+-]?\d+(?:\.\d+)?(?:e[+-]?\d+)?)\s*(µs|us|ms|s)$/i);
    if (m) return parseFloat(m[1]) * UNITS[m[2].toLowerCase()];
    m = t.match(/^×?\s*([+-]?\d+(?:\.\d+)?(?:e[+-]?\d+)?)(?:\s*(?:of|\/)\s*\d+)?/);
    return m ? parseFloat(m[1]) : null;
  };
  const compare = (a, b) => {
    const na = numeric(a), nb = numeric(b);
    if (na !== null && nb !== null && na !== nb) return na - nb;
    if (na !== null && nb === null) return -1;
    if (na === null && nb !== null) return 1;
    return collator.compare(a, b);
  };

  document.querySelectorAll("table").forEach((table, tableIndex) => {
    const body = table.tBodies[0];
    const headerRow = table.tHead?.rows[0] ?? table.rows[0];
    const headers = Array.from(headerRow?.cells ?? []);
    if (!body || !headerRow || headers.length === 0 || table.rows.length < 4) return;
    const rows = Array.from(body.rows);
    table.id ||= `interactive-table-${tableIndex + 1}`;
    table.classList.add("interactive-table");

    // tools above the table: a global filter and a row count
    const tools = document.createElement("div");
    tools.className = "table-tools";
    const input = document.createElement("input");
    input.className = "table-filter";
    input.type = "search";
    input.placeholder = "Filter this table…";
    input.setAttribute("aria-controls", table.id);
    const count = document.createElement("span");
    count.className = "table-count";
    const hint = document.createElement("span");
    hint.className = "table-hint";
    hint.textContent = "click a heading to sort, shift+click to add a sort key";
    tools.append(input, count, hint);
    table.parentNode.insertBefore(tools, table);

    // one filter box per column, in a second header row
    const filterRow = document.createElement("tr");
    filterRow.className = "table-filters";
    const colFilters = headers.map(() => {
      const td = document.createElement("th");
      const f = document.createElement("input");
      f.type = "search";
      f.className = "table-col-filter";
      f.placeholder = "…";
      f.setAttribute("aria-label", "filter column");
      td.appendChild(f);
      filterRow.appendChild(td);
      return f;
    });
    (table.tHead ?? headerRow.parentNode).appendChild(filterRow);

    const keys = [];   // [{col, asc}] in order of priority
    const render = () => {
      const needle = input.value.trim().toLowerCase();
      const cols = colFilters.map((f) => f.value.trim().toLowerCase());
      let shown = 0;
      rows.forEach((row) => {
        const cells = Array.from(row.cells).map((c) => c.textContent.toLowerCase());
        const hit = (!needle || cells.join(" ").includes(needle)) && cols.every((v, i) => !v || (cells[i] ?? "").includes(v));
        row.hidden = !hit;
        if (hit) shown += 1;
      });
      count.textContent = `${shown} of ${rows.length} rows`;
    };
    const resort = () => {
      const sorted = rows.slice().sort((a, b) => {
        for (const k of keys) {
          const c = compare(a.cells[k.col]?.textContent ?? "", b.cells[k.col]?.textContent ?? "");
          if (c !== 0) return k.asc ? c : -c;
        }
        return 0;
      });
      sorted.forEach((r) => body.appendChild(r));
      headers.forEach((h, i) => {
        const k = keys.findIndex((x) => x.col === i);
        h.querySelector(".sort-mark")?.remove();
        h.removeAttribute("aria-sort");
        if (k >= 0) {
          const mark = document.createElement("span");
          mark.className = "sort-mark";
          mark.textContent = (keys[k].asc ? " ▲" : " ▼") + (keys.length > 1 ? String(k + 1) : "");
          h.appendChild(mark);
          h.setAttribute("aria-sort", keys[k].asc ? "ascending" : "descending");
        }
      });
    };
    headers.forEach((th, col) => {
      th.style.cursor = "pointer";
      th.title = "Sort (shift+click: add as a further key)";
      th.addEventListener("click", (ev) => {
        const i = keys.findIndex((k) => k.col === col);
        if (ev.shiftKey) {
          if (i >= 0) keys[i].asc = !keys[i].asc; else keys.push({ col, asc: true });
        } else {
          const asc = i === 0 ? !keys[0].asc : true;
          keys.length = 0;
          keys.push({ col, asc });
        }
        resort();
      });
    });
    input.addEventListener("input", render);
    colFilters.forEach((f) => f.addEventListener("input", render));
    render();
  });
});
