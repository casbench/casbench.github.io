// Filter and sort the tables inside <div class="filterable">.
// In the spirit of s-celles/julia-findings (MIT), docs/src/assets/interactive-tables.js.
document.addEventListener("DOMContentLoaded", () => {
  const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });
  document.querySelectorAll(".filterable table").forEach((table, tableIndex) => {
    const body = table.tBodies[0];
    const headerRow = table.tHead?.rows[0] ?? table.rows[0];
    const headers = Array.from(headerRow?.cells ?? []);
    if (!body || !headerRow || headers.length === 0 || table.rows.length < 3) return;
    const rows = Array.from(body.rows);
    table.id ||= `interactive-table-${tableIndex + 1}`;

    const tools = document.createElement("div");
    tools.className = "table-tools";
    const input = document.createElement("input");
    input.className = "table-filter";
    input.type = "search";
    input.placeholder = "Filter this table…";
    input.setAttribute("aria-controls", table.id);
    const count = document.createElement("span");
    count.className = "table-count";
    tools.append(input, count);
    table.parentNode.insertBefore(tools, table);

    const render = () => {
      const needle = input.value.trim().toLowerCase();
      let shown = 0;
      rows.forEach((row) => {
        const hit = !needle || row.textContent.toLowerCase().includes(needle);
        row.hidden = !hit;
        if (hit) shown += 1;
      });
      count.textContent = `${shown} of ${rows.length} rows`;
    };
    input.addEventListener("input", render);

    let sortCol = -1, asc = true;
    headers.forEach((th, col) => {
      th.style.cursor = "pointer";
      th.title = "Sort";
      th.addEventListener("click", () => {
        asc = sortCol === col ? !asc : true;
        sortCol = col;
        const sorted = rows.slice().sort((a, b) => {
          const x = a.cells[col]?.textContent.trim() ?? "", y = b.cells[col]?.textContent.trim() ?? "";
          return asc ? collator.compare(x, y) : collator.compare(y, x);
        });
        sorted.forEach((r) => body.appendChild(r));
        headers.forEach((h) => h.removeAttribute("aria-sort"));
        th.setAttribute("aria-sort", asc ? "ascending" : "descending");
      });
    });
    render();
  });
});
