// AI assistant tab: multi-session chat over the account's own data, inline charts/reports, and kept snippets
// that re-run their queries on fresh data. Talks to the JSON endpoints under /ai.
(() => {
  // Reference categorical palette (fixed order, never cycled). Text never wears series colours.
  const SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948"];
  const MAX_SLICES = 8;
  const SUGGESTIONS = [
    "สรุปเหตุการณ์และภัยพิบัติในพื้นที่ช่วง 3 เดือนล่าสุด แยกตามสถานะ พร้อมกราฟ",
    "เปรียบเทียบงบประมาณโครงการแต่ละปีงบประมาณ แยกตามกลุ่มโครงการ",
    "จัดทำรายงานสถานการณ์สิ่งแวดล้อม ฝุ่น PM2.5 และระดับน้ำล่าสุดในพื้นที่",
    "มีชุดข้อมูลอะไรบ้างที่นำเข้าไว้ และสรุปข้อมูลประชากรรายหมู่บ้าน"
  ];

  const escapeHtml = (value) => String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  const el = (tag, attrs = {}, children = []) => {
    const node = document.createElement(tag);
    Object.entries(attrs).forEach(([key, value]) => {
      if (value === null || value === undefined || value === false) return;
      if (key === "class") node.className = value;
      else if (key === "text") node.textContent = value;
      else if (key === "html") node.innerHTML = value;
      else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
      else node.setAttribute(key, value === true ? "" : value);
    });
    [].concat(children).forEach((child) => child && node.append(child));
    return node;
  };
  const icon = (name) => el("span", { class: "material-symbols-outlined", "aria-hidden": "true", text: name });
  const button = (label, iconName, onclick, extra = {}) => el("button", { type: "button", class: `button-link ${extra.class || ""}`, title: extra.title, onclick }, [iconName && icon(iconName), label]);
  const fmtNumber = (value) => (typeof value === "number" ? value.toLocaleString("th-TH", { maximumFractionDigits: 2 }) : value);
  const fmtTime = (value) => (value ? new Date(value).toLocaleString("th-TH", { dateStyle: "medium", timeStyle: "short" }) : "");
  // Years (fiscal_year, ปีงบ…) are identifiers, so they never get a thousands separator.
  const yearLike = (key, value) => Number.isInteger(value) && /year|ปี/i.test(String(key || "")) && value > 1900 && value < 2800;
  const fmtCell = (value, key) => {
    if (value === null || value === undefined || value === "") return "-";
    if (yearLike(key, value)) return String(value);
    if (typeof value === "number") return fmtNumber(value);
    if (/^\d{4}-\d{2}-\d{2}T/.test(value)) return fmtTime(value);
    return value;
  };

  // --- Markdown (escaped first, so model output can never inject HTML) -------------------------------------
  const inline = (text) => escapeHtml(text)
    .replace(/`([^`]+)`/g, "<code>$1</code>")
    .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
    .replace(/(^|[^*])\*([^*\s][^*]*)\*/g, "$1<em>$2</em>")
    .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, '<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>');

  const markdown = (source) => {
    const lines = String(source || "").replace(/\r/g, "").split("\n");
    const out = [];
    let list = null;
    let paragraph = [];
    const flushParagraph = () => { if (paragraph.length) { out.push(`<p>${paragraph.map(inline).join("<br>")}</p>`); paragraph = []; } };
    const flushList = () => { if (list) { out.push(`<${list.tag}>${list.items.map((item) => `<li>${inline(item)}</li>`).join("")}</${list.tag}>`); list = null; } };
    const flush = () => { flushParagraph(); flushList(); };

    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i];
      const trimmed = line.trim();
      const marker = trimmed.match(/^\[\[artifact:(\d+)\]\]$/);
      if (marker) { flush(); out.push(`<div data-artifact-slot="${marker[1]}"></div>`); continue; }
      if (!trimmed) { flush(); continue; }
      const heading = trimmed.match(/^(#{1,4})\s+(.*)$/);
      if (heading) { flush(); const level = Math.min(heading[1].length + 1, 5); out.push(`<h${level}>${inline(heading[2])}</h${level}>`); continue; }
      if (/^(-{3,}|\*{3,})$/.test(trimmed)) { flush(); out.push("<hr>"); continue; }
      if (trimmed.startsWith(">")) { flush(); out.push(`<blockquote>${inline(trimmed.replace(/^>\s?/, ""))}</blockquote>`); continue; }
      if (trimmed.startsWith("|") && lines[i + 1] && /^\s*\|?\s*:?-{2,}/.test(lines[i + 1])) {
        flush();
        const cells = (row) => row.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((cell) => cell.trim());
        const head = cells(trimmed);
        i += 1;
        const body = [];
        while (lines[i + 1] && lines[i + 1].trim().startsWith("|")) { i += 1; body.push(cells(lines[i])); }
        out.push(`<div class="ai-table-wrap"><table><thead><tr>${head.map((cell) => `<th>${inline(cell)}</th>`).join("")}</tr></thead><tbody>${body.map((row) => `<tr>${row.map((cell) => `<td>${inline(cell)}</td>`).join("")}</tr>`).join("")}</tbody></table></div>`);
        continue;
      }
      const bullet = trimmed.match(/^[-*•]\s+(.*)$/);
      const numbered = trimmed.match(/^\d+[.)]\s+(.*)$/);
      if (bullet || numbered) {
        flushParagraph();
        const tag = bullet ? "ul" : "ol";
        if (!list || list.tag !== tag) { flushList(); list = { tag, items: [] }; }
        list.items.push((bullet || numbered)[1]);
        continue;
      }
      flushList();
      paragraph.push(trimmed);
    }
    flush();
    // Inline markers inside paragraphs become their own blocks after the paragraph.
    return out.join("").replace(/\[\[artifact:(\d+)\]\]/g, '</p><div data-artifact-slot="$1"></div><p>').replace(/<p><\/p>/g, "");
  };

  // --- Charts --------------------------------------------------------------------------------------------
  const chartData = (artifact) => {
    const rows = artifact.rows || [];
    const x = artifact.x;
    const ys = (artifact.y || []).filter(Boolean);
    if (artifact.series_by) {
      const labels = [...new Set(rows.map((row) => String(row[x] ?? "(ไม่ระบุ)")))];
      const series = [...new Set(rows.map((row) => String(row[artifact.series_by] ?? "(ไม่ระบุ)")))];
      const shown = series.slice(0, MAX_SLICES - 1);
      const folded = series.length > MAX_SLICES ? [...shown, "อื่น ๆ"] : series;
      const datasets = folded.map((name) => ({
        label: name,
        data: labels.map((label) => rows
          .filter((row) => String(row[x] ?? "(ไม่ระบุ)") === label && (name === "อื่น ๆ" ? !shown.includes(String(row[artifact.series_by] ?? "(ไม่ระบุ)")) : String(row[artifact.series_by] ?? "(ไม่ระบุ)") === name))
          .reduce((sum, row) => sum + (Number(row[ys[0]]) || 0), 0))
      }));
      return { labels, datasets };
    }
    return { labels: rows.map((row) => String(fmtCell(row[x], x))), datasets: ys.map((key) => ({ label: key, data: rows.map((row) => (row[key] === null || row[key] === undefined ? null : Number(row[key]))) })) };
  };

  const foldSlices = ({ labels, datasets }) => {
    if (labels.length <= MAX_SLICES) return { labels, datasets };
    const data = datasets[0].data;
    const order = labels.map((label, index) => ({ label, value: data[index] || 0 })).sort((a, b) => b.value - a.value);
    const top = order.slice(0, MAX_SLICES - 1);
    const rest = order.slice(MAX_SLICES - 1).reduce((sum, item) => sum + item.value, 0);
    return { labels: [...top.map((item) => item.label), "อื่น ๆ"], datasets: [{ ...datasets[0], data: [...top.map((item) => item.value), rest] }] };
  };

  const drawChart = (canvas, artifact) => {
    if (!window.Chart) return null;
    const kind = artifact.kind;
    const round = kind === "pie" || kind === "doughnut";
    let data = chartData(artifact);
    if (round) data = foldSlices(data);
    const many = data.datasets.length > 1;
    data.datasets = data.datasets.map((dataset, index) => {
      const color = SERIES[index % SERIES.length];
      if (round) return { ...dataset, backgroundColor: data.labels.map((_, i) => SERIES[i % SERIES.length]), borderColor: "#ffffff", borderWidth: 2 };
      if (kind === "line" || kind === "area") {
        return { ...dataset, borderColor: color, backgroundColor: `${color}26`, fill: kind === "area", borderWidth: 2, pointRadius: data.labels.length > 40 ? 0 : 3, pointHoverRadius: 5, tension: 0.25, spanGaps: true };
      }
      return { ...dataset, backgroundColor: color, borderColor: "#ffffff", borderWidth: { top: 0, bottom: 0, left: 0, right: 0 }, borderRadius: 4, borderSkipped: "start", maxBarThickness: 36 };
    });
    const ink = "#52514e";
    const grid = "#eceee9";
    return new window.Chart(canvas, {
      type: round ? kind : (kind === "area" ? "line" : (kind === "horizontal_bar" ? "bar" : kind)),
      data,
      options: {
        responsive: true,
        maintainAspectRatio: false,
        indexAxis: kind === "horizontal_bar" ? "y" : "x",
        interaction: { mode: round ? "nearest" : "index", intersect: false },
        animation: { duration: 250 },
        plugins: {
          legend: { display: round || many, position: "bottom", labels: { color: ink, boxWidth: 12, boxHeight: 12, font: { family: "Google Sans, sans-serif" } } },
          tooltip: { callbacks: { label: (ctx) => `${ctx.dataset.label || ctx.label}: ${fmtNumber(ctx.parsed?.y ?? ctx.parsed?.x ?? ctx.parsed)}` } }
        },
        scales: round ? {} : {
          x: { stacked: false, grid: { color: kind === "horizontal_bar" ? grid : "transparent" }, ticks: { color: ink, maxRotation: 45, autoSkip: true } },
          y: { beginAtZero: true, grid: { color: kind === "horizontal_bar" ? "transparent" : grid }, ticks: { color: ink, callback(value) { return kind === "horizontal_bar" ? this.getLabelForValue(value) : fmtNumber(value); } } }
        }
      }
    });
  };

  const tableFor = (artifact) => {
    const columns = artifact.columns?.length ? artifact.columns : Object.keys((artifact.rows || [])[0] || {});
    return el("div", { class: "ai-table-wrap" }, el("table", {}, [
      el("thead", {}, el("tr", {}, columns.map((column) => el("th", { text: column })))),
      el("tbody", {}, (artifact.rows || []).map((row) => el("tr", {}, columns.map((column) => el("td", { class: typeof row[column] === "number" ? "numeric" : null, text: fmtCell(row[column], column) })))))
    ]));
  };

  const csvFor = (artifact) => {
    const columns = artifact.columns?.length ? artifact.columns : Object.keys((artifact.rows || [])[0] || {});
    const quote = (value) => `"${String(value ?? "").replace(/"/g, '""')}"`;
    return "﻿" + [columns.map(quote).join(","), ...(artifact.rows || []).map((row) => columns.map((column) => quote(row[column])).join(","))].join("\n");
  };

  const download = (name, content, type) => {
    const link = el("a", { href: URL.createObjectURL(new Blob([content], { type })), download: name });
    document.body.append(link);
    link.click();
    link.remove();
  };

  // An artifact card: chart (or table/KPI), with keep / table toggle / CSV actions.
  const artifactCard = (artifact, { onKeep } = {}) => {
    const card = el("figure", { class: `ai-artifact kind-${artifact.kind}` });
    const body = el("div", { class: "ai-artifact-body" });
    const header = el("figcaption", {}, [
      el("div", {}, [el("b", { text: artifact.title }), el("small", { text: artifact.error ? "" : `${(artifact.rows || []).length.toLocaleString("th-TH")} แถว · จากข้อมูลที่ตรงเงื่อนไข ${fmtNumber(artifact.total ?? 0)} รายการ` })]),
      el("div", { class: "ai-artifact-actions" }, [
        onKeep && button("", "bookmark_add", () => onKeep(artifact), { title: "เก็บกราฟนี้ไว้รันใหม่", class: "icon-only" }),
        artifact.kind !== "table" && artifact.kind !== "kpi" && button("", "table_view", () => toggleTable(), { title: "สลับกราฟ/ตาราง", class: "icon-only" }),
        button("", "download", () => download(`${artifact.title}.csv`, csvFor(artifact), "text/csv;charset=utf-8"), { title: "ดาวน์โหลด CSV", class: "icon-only" })
      ])
    ]);
    card.append(header, body);
    let chart = null;
    let showingTable = false;
    const render = () => {
      chart?.destroy();
      chart = null;
      body.replaceChildren();
      if (artifact.error) { body.append(el("p", { class: "ai-error", text: artifact.error })); return; }
      if (!(artifact.rows || []).length) { body.append(el("p", { class: "ai-muted", text: "ไม่พบข้อมูลตามเงื่อนไข" })); return; }
      if (artifact.kind === "kpi") {
        const row = artifact.rows[0];
        const keys = (artifact.y || []).length ? artifact.y : Object.keys(row);
        body.append(el("div", { class: "ai-kpis" }, keys.map((key) => el("div", { class: "ai-kpi" }, [el("strong", { text: fmtCell(row[key], key) }), el("span", { text: key })]))));
        return;
      }
      if (artifact.kind === "table" || showingTable || !window.Chart) { body.append(tableFor(artifact)); return; }
      const canvas = el("canvas", { role: "img", "aria-label": artifact.title });
      body.append(el("div", { class: "ai-chart-box" }, canvas));
      chart = drawChart(canvas, artifact);
    };
    const toggleTable = () => { showingTable = !showingTable; render(); };
    card.renderArtifact = render;
    requestAnimationFrame(render);
    return card;
  };

  // Markdown with artifacts placed at their [[artifact:N]] markers; unplaced artifacts follow the text.
  const reportView = (content, artifacts, options = {}) => {
    const wrap = el("div", { class: "ai-report", html: markdown(content) });
    const byKey = new Map((artifacts || []).map((artifact) => [String(artifact.key), artifact]));
    wrap.querySelectorAll("[data-artifact-slot]").forEach((slot) => {
      const artifact = byKey.get(slot.dataset.artifactSlot);
      if (artifact) { slot.replaceWith(artifactCard(artifact, options)); byKey.delete(slot.dataset.artifactSlot); } else slot.remove();
    });
    byKey.forEach((artifact) => wrap.append(artifactCard(artifact, options)));
    return wrap;
  };

  // Opens a print window with charts frozen as images; the browser's print dialog also saves as PDF.
  const printReport = (title, reportElement, meta) => {
    const clone = reportElement.cloneNode(true);
    const sourceCanvases = reportElement.querySelectorAll("canvas");
    clone.querySelectorAll("canvas").forEach((canvas, index) => {
      const image = el("img", { src: sourceCanvases[index].toDataURL("image/png"), alt: "" });
      canvas.replaceWith(image);
    });
    clone.querySelectorAll(".ai-artifact-actions").forEach((node) => node.remove());
    const popup = window.open("", "_blank");
    if (!popup) { alert("เบราว์เซอร์บล็อกหน้าต่างพิมพ์ กรุณาอนุญาต pop-up"); return; }
    popup.document.write(`<!doctype html><html lang="th"><head><meta charset="utf-8"><title>${escapeHtml(title)}</title>
      <style>body{font-family:"Google Sans","Sarabun",sans-serif;color:#1f2a22;margin:32px;line-height:1.6}h1{font-size:22px;margin:0 0 4px}
      .meta{color:#6b756f;font-size:12px;margin-bottom:20px;border-bottom:1px solid #e3e7e2;padding-bottom:10px}
      figure{margin:16px 0;break-inside:avoid;border:1px solid #e3e7e2;border-radius:10px;padding:12px}figcaption b{display:block}
      figcaption small{color:#6b756f}img{max-width:100%}table{border-collapse:collapse;width:100%;font-size:12px}
      th,td{border:1px solid #e3e7e2;padding:4px 8px;text-align:left}td.numeric{text-align:right}.ai-kpis{display:flex;gap:16px}
      .ai-kpi strong{font-size:24px;display:block}</style></head><body><h1>${escapeHtml(title)}</h1>
      <div class="meta">${escapeHtml(meta)}</div>${clone.innerHTML}</body></html>`);
    popup.document.close();
    setTimeout(() => popup.print(), 400);
  };

  // --- App ---------------------------------------------------------------------------------------------
  const init = () => {
    const root = document.querySelector("[data-ai-app]");
    if (!root) return;
    const providers = JSON.parse(root.dataset.providers || "[]");
    const main = root.querySelector("[data-ai-main]");
    const sessionList = root.querySelector("[data-ai-session-list]");
    const snippetList = root.querySelector("[data-ai-snippet-list]");
    const state = { sessions: [], snippets: [], current: null, sending: false };
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
    const configured = providers.length > 0;

    const api = async (method, url, body) => {
      const response = await fetch(url, {
        method, credentials: "same-origin",
        headers: { Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": csrf },
        body: body ? JSON.stringify(body) : undefined
      });
      if (response.status === 204) return null;
      const data = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(data.error || `เกิดข้อผิดพลาด (${response.status})`);
      return data;
    };
    const toast = (message, kind = "notice") => {
      const node = el("div", { class: `ai-toast ${kind}`, role: "status", text: message });
      document.body.append(node);
      setTimeout(() => node.remove(), 3500);
    };

    // Panel tabs
    root.querySelectorAll("[data-ai-tab]").forEach((tab) => tab.addEventListener("click", () => {
      root.querySelectorAll("[data-ai-tab]").forEach((other) => other.classList.toggle("active", other === tab));
      root.querySelectorAll("[data-ai-panel]").forEach((panel) => { panel.hidden = panel.dataset.aiPanel !== tab.dataset.aiTab; });
    }));
    const showPanel = (name) => root.querySelector(`[data-ai-tab="${name}"]`).click();

    const renderSessions = () => {
      sessionList.replaceChildren(...(state.sessions.length ? state.sessions.map((session) => el("li", { class: state.current?.type === "chat" && state.current.id === session.id ? "active" : "" }, [
        el("button", { type: "button", class: "ai-list-main", onclick: () => openChat(session.id) }, [el("b", { text: session.title }), el("small", { text: fmtTime(session.updated_at) })]),
        el("span", { class: "ai-list-tools" }, [
          button("", "edit", () => renameSession(session), { title: "เปลี่ยนชื่อ", class: "icon-only" }),
          button("", "delete", () => deleteSession(session), { title: "ลบแชต", class: "icon-only danger" })
        ])
      ])) : [el("li", { class: "ai-list-empty", text: "ยังไม่มีแชต" })]));
    };

    const renderSnippets = () => {
      snippetList.replaceChildren(...(state.snippets.length ? state.snippets.map((snippet) => el("li", { class: state.current?.type === "snippet" && state.current.id === snippet.id ? "active" : "" }, [
        el("button", { type: "button", class: "ai-list-main", onclick: () => openSnippet(snippet.id) }, [
          el("b", { text: snippet.title }),
          el("small", {}, [snippet.mine ? "ของฉัน" : `โดย ${snippet.owner_name}`, snippet.shared ? el("em", { class: "ai-badge", text: "แชร์ใน อบต." }) : null, ` · ${(snippet.artifacts || []).length} กราฟ`])
        ])
      ])) : [el("li", { class: "ai-list-empty", text: "ยังไม่มีผลลัพธ์ที่เก็บไว้" })]));
    };

    const loadLists = async () => {
      const [sessions, snippets] = await Promise.all([api("GET", "/ai/sessions"), api("GET", "/ai/snippets")]);
      state.sessions = sessions;
      state.snippets = snippets;
      renderSessions();
      renderSnippets();
    };

    const renameSession = async (session) => {
      const title = prompt("ชื่อแชต", session.title);
      if (!title || title === session.title) return;
      const updated = await api("PATCH", `/ai/sessions/${session.id}`, { title });
      Object.assign(session, updated);
      renderSessions();
      if (state.current?.type === "chat" && state.current.id === session.id) main.querySelector("[data-ai-title]").textContent = updated.title;
    };

    const deleteSession = async (session) => {
      if (!confirm(`ลบแชต “${session.title}”? ผลลัพธ์ที่เก็บไว้จะไม่ถูกลบ`)) return;
      await api("DELETE", `/ai/sessions/${session.id}`);
      state.sessions = state.sessions.filter((item) => item.id !== session.id);
      if (state.current?.id === session.id) showWelcome();
      renderSessions();
    };

    const providerSelect = (session) => {
      if (!providers.length) return null;
      const select = el("select", { class: "ai-provider-select", "aria-label": "เลือกโมเดล AI" }, providers.map((provider) => el("option", { value: provider.id, text: `${provider.name} (${provider.model})` })));
      select.value = session?.ai_provider_id || providers.find((provider) => provider.default)?.id || providers[0].id;
      select.addEventListener("change", async () => {
        if (session?.id) await api("PATCH", `/ai/sessions/${session.id}`, { ai_provider_id: select.value });
        else state.pendingProvider = select.value;
      });
      return select;
    };

    const composer = (session) => {
      const textarea = el("textarea", { rows: 2, placeholder: configured ? "ถามเกี่ยวกับข้อมูลในพื้นที่ เช่น “สรุปเหตุการณ์เดือนนี้เป็นกราฟ” (Enter ส่ง, Shift+Enter ขึ้นบรรทัดใหม่)" : "ยังไม่ได้ตั้งค่า AI", disabled: !configured || session?.full, maxlength: 4000 });
      const send = el("button", { type: "submit", class: "button-link primary", disabled: !configured || session?.full }, [icon("send"), "ส่ง"]);
      const form = el("form", { class: "ai-composer" }, [textarea, send]);
      form.addEventListener("submit", (event) => { event.preventDefault(); sendMessage(textarea.value); });
      textarea.addEventListener("keydown", (event) => {
        if (event.key === "Enter" && !event.shiftKey && !event.isComposing) { event.preventDefault(); sendMessage(textarea.value); }
      });
      if (session?.full) form.append(el("small", { class: "ai-muted", text: "แชตนี้ยาวถึงขีดจำกัดแล้ว กรุณาเริ่มแชตใหม่" }));
      return form;
    };

    const welcome = () => el("div", { class: "ai-empty" }, [
      icon("smart_toy"),
      el("h2", { text: "ผู้ช่วย AI ของ อบต." }),
      el("p", { text: `ถาม วิเคราะห์ และจัดทำรายงานจากข้อมูลในระบบของ ${root.dataset.area} — เหตุการณ์ ภัยพิบัติ กิจกรรม โครงการ งบประมาณ สิ่งแวดล้อม เซนเซอร์ และชุดข้อมูลที่นำเข้า` }),
      el("div", { class: "ai-suggestions" }, SUGGESTIONS.map((text) => el("button", { type: "button", disabled: !configured, onclick: () => sendMessage(text) }, [icon("auto_awesome"), text]))),
      el("p", { class: "ai-hint", text: "AI เห็นเฉพาะข้อมูลที่บัญชีนี้มีสิทธิ์ และไม่ได้รับชื่อหรือเบอร์ติดต่อของผู้แจ้งเหตุ ตรวจสอบตัวเลขสำคัญก่อนนำไปใช้อ้างอิง" })
    ]);

    const showWelcome = () => {
      state.current = { type: "chat", id: null };
      main.replaceChildren(
        el("header", { class: "ai-main-header" }, [el("div", {}, [el("h1", { "data-ai-title": true, text: "แชตใหม่" })]), providerSelect(null)]),
        el("div", { class: "ai-transcript", "data-ai-transcript": true }, welcome()),
        composer(null)
      );
      renderSessions();
      renderSnippets();
    };

    const queriesPanel = (queries) => {
      if (!queries?.length) return null;
      return el("details", { class: "ai-queries" }, [
        el("summary", { text: `อ้างอิงจากการค้นข้อมูล ${queries.length} ครั้ง` }),
        el("ol", {}, queries.map((query) => el("li", {}, [
          el("code", { text: JSON.stringify(query.spec) }),
          el("small", { text: query.error ? `ผิดพลาด: ${query.error}` : `ตรงเงื่อนไข ${fmtNumber(query.total ?? 0)} รายการ` })
        ])))
      ]);
    };

    const keepResult = async (session, message, artifact) => {
      try {
        const snippet = await api("POST", "/ai/snippets", { session_id: session.id, message_id: message.id, artifact_key: artifact?.key });
        state.snippets.unshift(snippet);
        renderSnippets();
        toast(`เก็บ “${snippet.title}” ไว้ในแท็บ “ที่เก็บไว้” แล้ว`);
      } catch (error) { toast(error.message, "alert"); }
    };

    const messageView = (session, message) => {
      if (message.role === "user") return el("div", { class: "ai-message user" }, el("div", { class: "ai-bubble", text: message.content }));
      const node = el("div", { class: "ai-message assistant" });
      node.append(el("span", { class: "ai-avatar" }, icon("smart_toy")));
      const body = el("div", { class: "ai-bubble" });
      node.append(body);
      if (message.error) { body.append(el("p", { class: "ai-error" }, [icon("error"), message.error])); return node; }
      const report = reportView(message.content, message.artifacts, { onKeep: (artifact) => keepResult(session, message, artifact) });
      body.append(report, queriesPanel(message.queries) || "");
      body.append(el("div", { class: "ai-message-actions" }, [
        button("เก็บผลลัพธ์", "bookmark_add", () => keepResult(session, message, null), { title: "เก็บคำตอบและกราฟทั้งหมดไว้รันใหม่ภายหลัง" }),
        button("พิมพ์ / PDF", "print", () => printReport(session.title, report, `${root.dataset.systemName} · ${root.dataset.area} · ${fmtTime(message.created_at)}`)),
        button("คัดลอก", "content_copy", () => navigator.clipboard?.writeText(message.content).then(() => toast("คัดลอกข้อความแล้ว"))),
        el("small", { class: "ai-muted", text: message.model || "" })
      ]));
      return node;
    };

    const renderChat = (session) => {
      state.current = { type: "chat", id: session.id };
      const transcript = el("div", { class: "ai-transcript", "data-ai-transcript": true });
      if (!session.messages.length) transcript.append(welcome());
      session.messages.forEach((message) => transcript.append(messageView(session, message)));
      main.replaceChildren(
        el("header", { class: "ai-main-header" }, [el("div", {}, [el("h1", { "data-ai-title": true, text: session.title })]), providerSelect(session)]),
        transcript,
        composer(session)
      );
      transcript.scrollTop = transcript.scrollHeight;
      renderSessions();
      renderSnippets();
    };

    const openChat = async (id) => {
      showPanel("chats");
      try { renderChat(await api("GET", `/ai/sessions/${id}`)); } catch (error) { toast(error.message, "alert"); }
    };

    const sendMessage = async (raw) => {
      const text = String(raw || "").trim();
      if (!text || state.sending || !configured) return;
      state.sending = true;
      try {
        let sessionId = state.current?.type === "chat" ? state.current.id : null;
        if (!sessionId) {
          const select = main.querySelector(".ai-provider-select");
          const created = await api("POST", "/ai/sessions", { ai_provider_id: select?.value || state.pendingProvider });
          sessionId = created.id;
          state.current = { type: "chat", id: sessionId };
        }
        const transcript = main.querySelector("[data-ai-transcript]");
        const input = main.querySelector(".ai-composer textarea");
        if (input) input.value = "";
        transcript.querySelector(".ai-empty")?.remove();
        transcript.append(el("div", { class: "ai-message user" }, el("div", { class: "ai-bubble", text })));
        transcript.append(el("div", { class: "ai-message assistant pending" }, [el("span", { class: "ai-avatar" }, icon("smart_toy")), el("div", { class: "ai-bubble" }, [el("span", { class: "ai-dots" }, [el("i"), el("i"), el("i")]), "กำลังค้นและวิเคราะห์ข้อมูล…"])]));
        transcript.scrollTop = transcript.scrollHeight;
        main.querySelectorAll(".ai-composer textarea, .ai-composer button").forEach((input) => { input.disabled = true; });
        const session = await api("POST", `/ai/sessions/${sessionId}/messages`, { content: text });
        if (state.current?.id === session.id) renderChat(session);
        const index = state.sessions.findIndex((item) => item.id === session.id);
        const summary = { id: session.id, title: session.title, message_count: session.message_count, ai_provider_id: session.ai_provider_id, updated_at: session.updated_at };
        if (index >= 0) state.sessions.splice(index, 1);
        state.sessions.unshift(summary);
        renderSessions();
      } catch (error) {
        toast(error.message, "alert");
        main.querySelector(".ai-message.pending")?.remove();
        main.querySelectorAll(".ai-composer textarea, .ai-composer button").forEach((input) => { input.disabled = false; });
      } finally {
        state.sending = false;
      }
    };

    // --- Snippets ---
    const openSnippet = async (id) => {
      const snippet = state.snippets.find((item) => item.id === id);
      if (!snippet) return;
      showPanel("snippets");
      state.current = { type: "snippet", id };
      renderSnippets();
      const from = el("input", { type: "date", "aria-label": "ตั้งแต่วันที่" });
      const to = el("input", { type: "date", "aria-label": "ถึงวันที่" });
      const status = el("small", { class: "ai-muted" });
      const content = el("div", { class: "ai-snippet-content" });
      let artifacts = snippet.artifacts;
      let reportNode = null;

      const draw = () => {
        reportNode = reportView(snippet.report, artifacts);
        content.replaceChildren(reportNode);
      };
      const period = () => ({ from: from.value || undefined, to: to.value || undefined });
      const run = async () => {
        status.textContent = "กำลังรันใหม่ด้วยข้อมูลล่าสุด…";
        try {
          const result = await api("POST", `/ai/snippets/${id}/run`, period());
          artifacts = result.artifacts;
          snippet.last_run_at = result.ran_at;
          status.textContent = `ข้อมูล ณ ${fmtTime(result.ran_at)}${from.value || to.value ? ` · ช่วง ${from.value || "…"} ถึง ${to.value || "…"}` : ""}`;
          draw();
        } catch (error) { status.textContent = error.message; }
      };
      const summarize = async () => {
        if (!configured) return toast("ยังไม่ได้ตั้งค่า AI", "alert");
        status.textContent = "AI กำลังเขียนสรุปใหม่จากข้อมูลล่าสุด…";
        try {
          const result = await api("POST", `/ai/snippets/${id}/summarize`, period());
          snippet.report = result.report;
          artifacts = result.artifacts;
          status.textContent = `สรุปใหม่เมื่อ ${fmtTime(new Date())}${snippet.mine ? " · บันทึกแล้ว" : ""}`;
          draw();
        } catch (error) { status.textContent = error.message; }
      };
      const share = el("label", { class: "settings-check" }, [el("input", { type: "checkbox", checked: snippet.shared, disabled: !snippet.mine }), "แชร์ให้เจ้าหน้าที่ใน อบต."]);
      share.querySelector("input").addEventListener("change", async (event) => {
        try {
          Object.assign(snippet, await api("PATCH", `/ai/snippets/${id}`, { shared: event.target.checked }));
          renderSnippets();
        } catch (error) { toast(error.message, "alert"); event.target.checked = !event.target.checked; }
      });

      const title = el("h1", { text: snippet.title });
      main.replaceChildren(
        el("header", { class: "ai-main-header" }, [
          el("div", {}, [title, el("small", { class: "ai-muted", text: `${snippet.mine ? "ของฉัน" : `โดย ${snippet.owner_name}`} · เก็บเมื่อ ${fmtTime(snippet.created_at)}${snippet.question ? ` · คำถาม: ${snippet.question}` : ""}` })]),
          snippet.mine ? share : null
        ]),
        el("div", { class: "ai-snippet-toolbar" }, [
          el("label", {}, ["ตั้งแต่", from]), el("label", {}, ["ถึง", to]),
          button("รันใหม่", "refresh", run, { class: "primary", title: "รัน query เดิมด้วยข้อมูลล่าสุด" }),
          button("ให้ AI สรุปใหม่", "auto_awesome", summarize, { title: "ให้ AI เขียนรายงานใหม่จากข้อมูลล่าสุด" }),
          button("พิมพ์ / PDF", "print", () => printReport(snippet.title, reportNode, `${root.dataset.systemName} · ${root.dataset.area} · ${status.textContent}`)),
          snippet.mine ? button("เปลี่ยนชื่อ", "edit", async () => {
            const value = prompt("ชื่อรายการ", snippet.title);
            if (!value) return;
            Object.assign(snippet, await api("PATCH", `/ai/snippets/${id}`, { title: value }));
            title.textContent = snippet.title;
            renderSnippets();
          }) : null,
          snippet.session_id && snippet.mine ? button("เปิดแชตต้นทาง", "forum", () => openChat(snippet.session_id)) : null,
          snippet.mine ? button("ลบ", "delete", async () => {
            if (!confirm(`ลบ “${snippet.title}”?`)) return;
            await api("DELETE", `/ai/snippets/${id}`);
            state.snippets = state.snippets.filter((item) => item.id !== id);
            showWelcome();
          }, { class: "danger" }) : null,
          status
        ]),
        el("div", { class: "ai-transcript ai-snippet-view" }, content)
      );
      draw();
      run();
    };

    root.querySelector("[data-ai-new-chat]").addEventListener("click", () => { showPanel("chats"); showWelcome(); });
    if (configured) showWelcome();
    loadLists().then(() => {
      const wanted = new URLSearchParams(window.location.search);
      if (wanted.get("snippet")) openSnippet(wanted.get("snippet"));
      else if (wanted.get("session")) openChat(wanted.get("session"));
    }).catch((error) => toast(error.message, "alert"));
  };

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
