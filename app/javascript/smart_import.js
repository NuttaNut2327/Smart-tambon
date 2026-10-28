// AI smart import: the upload form (renders scanned PDF pages to images with pdf.js before sending) and the
// editable table that lets the user fix columns, cells and coordinates before importing.
(() => {
  const csrf = () => document.querySelector("meta[name=csrf-token]")?.content;
  const escapeHtml = value => String(value ?? "").replace(/[&<>"']/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[char]);
  const PDF_WORKER = "https://cdnjs.cloudflare.com/ajax/libs/pdf.js/3.11.174/pdf.worker.min.js";
  const MAX_PAGES = 10;
  const MODEL_KEY = "smartImportModelName";

  async function postJson(url, body) {
    const response = await fetch(url, { method: "POST", headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrf() }, body: JSON.stringify(body) });
    const data = await response.json().catch(() => ({ error: `เซิร์ฟเวอร์ตอบกลับผิดพลาด (HTTP ${response.status})` }));
    if (!response.ok) throw new Error(data.error || `HTTP ${response.status}`);
    return data;
  }

  // ---------- Upload form ----------
  function setupUpload(form) {
    const fileInput = form.querySelector("[data-file]");
    const fileLabel = form.querySelector("[data-file-label]");
    const provider = form.querySelector("[data-provider]");
    const model = form.querySelector("[data-model-input]");
    const error = form.querySelector("[data-error]");
    const progress = form.querySelector("[data-progress]");
    const progressText = form.querySelector("[data-progress-text]");
    const submit = form.querySelector("[data-submit]");
    const drop = form.querySelector("[data-drop]");

    // Default to a vision-capable model so scanned files work; remember the user's last choice.
    const providerModel = () => provider?.selectedOptions[0]?.dataset.model || "";
    let saved = null;
    try { saved = localStorage.getItem(MODEL_KEY); } catch (_) {}
    model.value = saved || (/claude|gpt|vl|gemini|omni/i.test(providerModel()) ? providerModel() : "claude-sonnet-5-5");
    provider?.addEventListener("change", () => { if (/claude|gpt|vl|gemini|omni/i.test(providerModel())) model.value = providerModel(); });

    const showFile = () => { fileLabel.textContent = fileInput.files[0] ? `${fileInput.files[0].name} (${(fileInput.files[0].size / 1024).toFixed(0)} KB)` : "ลากไฟล์มาวาง หรือคลิกเพื่อเลือก"; };
    fileInput.addEventListener("change", showFile);
    ["dragover", "dragenter"].forEach(name => drop.addEventListener(name, event => { event.preventDefault(); drop.classList.add("dragging"); }));
    ["dragleave", "drop"].forEach(name => drop.addEventListener(name, () => drop.classList.remove("dragging")));
    drop.addEventListener("drop", event => { event.preventDefault(); if (event.dataTransfer.files.length) { fileInput.files = event.dataTransfer.files; showFile(); } });

    form.addEventListener("submit", async event => {
      event.preventDefault();
      const file = fileInput.files[0];
      if (!file) return;
      error.hidden = true;
      submit.disabled = true;
      progress.hidden = false;
      try { localStorage.setItem(MODEL_KEY, model.value); } catch (_) {}
      try {
        const body = new FormData(form);
        if (/\.pdf$/i.test(file.name)) {
          progressText.textContent = "กำลังตรวจหน้า PDF…";
          const pages = await scannedPdfPages(file, (page, total) => { progressText.textContent = `กำลังแปลงหน้า PDF เป็นภาพ ${page}/${total}…`; });
          pages.forEach((blob, index) => body.append("page_images[]", blob, `page-${index + 1}.jpg`));
        }
        progressText.textContent = "AI กำลังอ่านตารางและแยกคอลัมน์ แล้วหาพิกัดในพื้นที่…";
        const response = await fetch(form.action, { method: "POST", headers: { Accept: "application/json", "X-CSRF-Token": csrf() }, body });
        const data = await response.json().catch(() => ({ error: `เซิร์ฟเวอร์ตอบกลับผิดพลาด (HTTP ${response.status})` }));
        if (!response.ok) throw new Error(data.error || `HTTP ${response.status}`);
        progressText.textContent = "อ่านไฟล์เรียบร้อย กำลังเปิดตาราง…";
        window.location.href = data.url;
      } catch (failure) {
        error.textContent = failure.message;
        error.hidden = false;
        progress.hidden = true;
        submit.disabled = false;
      }
    });
  }

  // Returns page images only for PDFs without a text layer; text PDFs are read on the server.
  async function scannedPdfPages(file, onPage) {
    if (!window.pdfjsLib) return [];
    window.pdfjsLib.GlobalWorkerOptions.workerSrc = PDF_WORKER;
    const pdf = await window.pdfjsLib.getDocument({ data: await file.arrayBuffer() }).promise;
    const total = Math.min(pdf.numPages, MAX_PAGES);
    let textLength = 0;
    for (let number = 1; number <= total; number += 1) {
      const content = await (await pdf.getPage(number)).getTextContent();
      textLength += content.items.map(item => item.str).join("").replace(/\s+/g, "").length;
    }
    if (textLength >= 40) return [];

    const blobs = [];
    for (let number = 1; number <= total; number += 1) {
      onPage(number, total);
      const page = await pdf.getPage(number);
      const base = page.getViewport({ scale: 1 });
      const viewport = page.getViewport({ scale: Math.min(2.5, 2000 / Math.max(base.width, base.height)) });
      const canvas = document.createElement("canvas");
      canvas.width = Math.round(viewport.width);
      canvas.height = Math.round(viewport.height);
      const context = canvas.getContext("2d");
      context.fillStyle = "#fff";
      context.fillRect(0, 0, canvas.width, canvas.height);
      await page.render({ canvasContext: context, viewport }).promise;
      blobs.push(await new Promise(resolve => canvas.toBlob(resolve, "image/jpeg", 0.88)));
    }
    return blobs;
  }

  // ---------- Editor ----------
  function setupEditor(root) {
    const state = JSON.parse(document.querySelector("[data-smart-import-json]").textContent);
    const boundary = JSON.parse(document.querySelector("[data-smart-import-boundary]").textContent || "{}");
    const table = root.querySelector("[data-table]");
    const nameInput = root.querySelector("[data-name]");
    const summary = root.querySelector("[data-geo-summary]");
    const error = root.querySelector("[data-error]");
    const saveState = root.querySelector("[data-save-state]");
    const resultPanel = root.querySelector("[data-result-panel]");
    const editorPanel = root.querySelector("[data-editor-panel]");
    const geoRoles = ["coordinates", "latitude", "longitude"];
    let dirty = false;
    let pickRow = null;
    let map = null;
    let pointSource = null;

    nameInput.value = state.name || "";
    nameInput.addEventListener("input", () => { state.name = nameInput.value; markDirty(); });

    const payload = () => ({ name: state.name, columns: state.columns, rows: state.rows });
    const markDirty = () => { dirty = true; saveState.textContent = "มีการแก้ไขที่ยังไม่บันทึก"; };
    const showError = message => { error.textContent = message; error.hidden = !message; };
    const nextKey = () => `c${Math.max(0, ...state.columns.map(column => parseInt(column.key.slice(1), 10) || 0)) + 1}`;

    function geoChip(row) {
      const status = row._geo || "none";
      const label = state.geo_statuses[status] || status;
      return `<span class="smart-geo ${status}" title="${escapeHtml(row._geo_note || label)}">${escapeHtml(label)}</span>`;
    }

    function render() {
      const options = (map, selected) => Object.entries(map).map(([value, label]) => `<option value="${value}" ${value === selected ? "selected" : ""}>${escapeHtml(label)}</option>`).join("");
      const head = `<thead><tr><th class="smart-index">#</th><th class="smart-location-head">ตำแหน่งบนแผนที่</th>${state.columns.map((column, index) => `
        <th class="${geoRoles.includes(column.role) ? "geo-column" : ""} ${column.role === "location" ? "location-column" : ""}">
          <div class="smart-column-head">
            <input value="${escapeHtml(column.label)}" data-column-label="${index}" aria-label="ชื่อคอลัมน์">
            <button type="button" data-remove-column="${index}" title="ลบคอลัมน์">×</button>
          </div>
          <select data-column-type="${index}" aria-label="ชนิดข้อมูล">${options(state.field_types, column.type)}</select>
          <select data-column-role="${index}" aria-label="บทบาท">${options(state.roles, column.role)}</select>
        </th>`).join("")}<th></th></tr></thead>`;
      const body = `<tbody>${state.rows.map((row, rowIndex) => `<tr data-row="${rowIndex}" class="${pickRow === rowIndex ? "picking" : ""}">
        <td class="smart-index">${rowIndex + 1}</td>
        <td class="smart-location-cell">
          <div class="smart-row-geo-actions">
            ${geoChip(row)}
            <button type="button" data-geocode-row="${rowIndex}" title="หาพิกัดจากข้อมูลในแถว"><span class="material-symbols-outlined">travel_explore</span></button>
            <button type="button" data-pick-row="${rowIndex}" title="คลิกบนแผนที่เพื่อปักตำแหน่ง"><span class="material-symbols-outlined">location_on</span></button>
          </div>
          <div class="smart-latlon">
            <input value="${row.latitude ?? ""}" placeholder="ละติจูด" data-lat="${rowIndex}" inputmode="decimal">
            <input value="${row.longitude ?? ""}" placeholder="ลองจิจูด" data-lon="${rowIndex}" inputmode="decimal">
          </div>
          ${row._geo_note ? `<small title="${escapeHtml(row._geo_note)}">${escapeHtml(row._geo_note)}</small>` : ""}
        </td>
        ${state.columns.map(column => `<td><input value="${escapeHtml(row[column.key])}" data-cell="${rowIndex}" data-key="${column.key}"></td>`).join("")}
        <td><button type="button" class="smart-remove-row" data-remove-row="${rowIndex}" title="ลบแถว">×</button></td>
      </tr>`).join("")}</tbody>`;
      table.innerHTML = head + body;
      renderSummary();
      renderPoints();
    }

    function renderSummary() {
      const counts = {};
      state.rows.forEach(row => { const status = row._geo || "none"; counts[status] = (counts[status] || 0) + 1; });
      const located = state.rows.filter(row => row.latitude != null && row.latitude !== "" && row._geo !== "outside").length;
      summary.innerHTML = `<b>${state.rows.length} แถว · ${state.columns.length} คอลัมน์ · มีพิกัด ${located}</b>` +
        Object.entries(counts).map(([status, count]) => `<span class="smart-geo ${status}">${escapeHtml(state.geo_statuses[status] || status)} ${count}</span>`).join("");
    }

    // Small OpenLayers preview: the subdistrict boundary plus one point per located row.
    function setupMap() {
      const element = root.querySelector("[data-map]");
      if (!window.ol || !element) return;
      pointSource = new ol.source.Vector();
      const boundarySource = new ol.source.Vector();
      if (boundary.geometry) boundarySource.addFeatures(new ol.format.GeoJSON().readFeatures(boundary, { featureProjection: "EPSG:3857" }));
      const colors = { file: "#16a34a", manual: "#16a34a", geocoded: "#2563eb", outside: "#dc2626" };
      map = new ol.Map({
        target: element,
        layers: [
          new ol.layer.Tile({ source: new ol.source.OSM() }),
          new ol.layer.Vector({ source: boundarySource, style: new ol.style.Style({ stroke: new ol.style.Stroke({ color: "#0f766e", width: 2 }), fill: new ol.style.Fill({ color: "rgba(15,118,110,.08)" }) }) }),
          new ol.layer.Vector({ source: pointSource, style: feature => new ol.style.Style({
            image: new ol.style.Circle({ radius: 7, fill: new ol.style.Fill({ color: colors[feature.get("geo")] || "#64748b" }), stroke: new ol.style.Stroke({ color: "#fff", width: 2 }) }),
            text: new ol.style.Text({ text: String(feature.get("index") + 1), offsetY: -14, font: "600 11px sans-serif", fill: new ol.style.Fill({ color: "#0f172a" }), stroke: new ol.style.Stroke({ color: "#fff", width: 3 }) })
          }) })
        ],
        view: new ol.View({ center: ol.proj.fromLonLat([100.5, 13.7]), zoom: 6 })
      });
      if (boundarySource.getFeatures().length) map.getView().fit(boundarySource.getExtent(), { padding: [20, 20, 20, 20] });
      map.on("singleclick", event => {
        if (pickRow == null) return;
        const [lon, lat] = ol.proj.toLonLat(event.coordinate);
        const index = pickRow;
        pickRow = null;
        root.querySelector("[data-map-hint]").classList.remove("picking");
        Object.assign(state.rows[index], { latitude: +lat.toFixed(7), longitude: +lon.toFixed(7) });
        checkManual(index);
      });
    }

    function renderPoints() {
      if (!pointSource) return;
      pointSource.clear();
      state.rows.forEach((row, index) => {
        const lat = parseFloat(row.latitude), lon = parseFloat(row.longitude);
        if (Number.isFinite(lat) && Number.isFinite(lon)) pointSource.addFeature(new ol.Feature({ geometry: new ol.geom.Point(ol.proj.fromLonLat([lon, lat])), index, geo: row._geo }));
      });
    }

    async function geocode(indices, manual = false) {
      showError("");
      saveState.textContent = manual ? "กำลังตรวจพิกัด…" : "กำลังหาพิกัด…";
      try {
        const data = await postJson(root.dataset.geocodeUrl, { ...payload(), indices, manual });
        Object.entries(data.rows).forEach(([index, row]) => { state.rows[index] = row; });
        dirty = false;
        saveState.textContent = "บันทึกแล้ว";
        render();
      } catch (failure) {
        showError(failure.message);
        saveState.textContent = "";
      }
    }
    const checkManual = index => geocode([index], true);

    async function save() {
      showError("");
      saveState.textContent = "กำลังบันทึก…";
      try {
        const response = await fetch(root.dataset.updateUrl, { method: "PATCH", headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrf() }, body: JSON.stringify(payload()) });
        if (!response.ok) throw new Error((await response.json().catch(() => ({}))).error || `HTTP ${response.status}`);
        dirty = false;
        saveState.textContent = "บันทึกแล้ว";
      } catch (failure) {
        showError(failure.message);
        saveState.textContent = "";
      }
    }

    table.addEventListener("input", event => {
      const target = event.target;
      if (target.dataset.cell !== undefined) { state.rows[+target.dataset.cell][target.dataset.key] = target.value; markDirty(); }
      if (target.dataset.columnLabel !== undefined) { state.columns[+target.dataset.columnLabel].label = target.value; markDirty(); }
    });
    table.addEventListener("change", event => {
      const target = event.target;
      if (target.dataset.columnType !== undefined) { state.columns[+target.dataset.columnType].type = target.value; markDirty(); }
      if (target.dataset.columnRole !== undefined) {
        state.columns[+target.dataset.columnRole].role = target.value;
        render();
        geocode([]);
      }
      if (target.dataset.lat !== undefined || target.dataset.lon !== undefined) {
        const index = +(target.dataset.lat ?? target.dataset.lon);
        const field = target.dataset.lat !== undefined ? "latitude" : "longitude";
        state.rows[index][field] = target.value.trim() === "" ? null : target.value.trim();
        checkManual(index);
      }
      // A changed coordinate or location cell is re-read straight away.
      if (target.dataset.cell !== undefined) {
        const column = state.columns.find(item => item.key === target.dataset.key);
        if (column && (geoRoles.includes(column.role) || column.role === "location")) geocode([+target.dataset.cell]);
      }
    });
    table.addEventListener("click", event => {
      const button = event.target.closest("button");
      if (!button) return;
      if (button.dataset.removeColumn !== undefined) {
        const column = state.columns[+button.dataset.removeColumn];
        if (!window.confirm(`ลบคอลัมน์ "${column.label}" ใช่หรือไม่?`)) return;
        state.columns.splice(+button.dataset.removeColumn, 1);
        state.rows.forEach(row => delete row[column.key]);
        markDirty();
        render();
      }
      if (button.dataset.removeRow !== undefined) { state.rows.splice(+button.dataset.removeRow, 1); markDirty(); render(); }
      if (button.dataset.geocodeRow !== undefined) geocode([+button.dataset.geocodeRow]);
      if (button.dataset.pickRow !== undefined) {
        pickRow = +button.dataset.pickRow;
        root.querySelector("[data-map-hint]").classList.add("picking");
        root.querySelector("[data-map-hint]").textContent = `คลิกบนแผนที่เพื่อปักตำแหน่งแถวที่ ${pickRow + 1}`;
        render();
        root.querySelector("[data-map]").scrollIntoView({ behavior: "smooth", block: "nearest" });
      }
    });

    root.querySelector("[data-add-column]").addEventListener("click", () => {
      const key = nextKey();
      state.columns.push({ key, label: `คอลัมน์ ${state.columns.length + 1}`, type: "text", role: "none" });
      markDirty();
      render();
    });
    root.querySelector("[data-add-row]").addEventListener("click", () => {
      state.rows.push(Object.fromEntries(state.columns.map(column => [column.key, ""])));
      markDirty();
      render();
      table.querySelector("tbody tr:last-child input")?.focus();
    });
    root.querySelector("[data-regeocode]").addEventListener("click", () => geocode([]));
    root.querySelector("[data-save]").addEventListener("click", save);
    window.addEventListener("beforeunload", event => { if (dirty) event.preventDefault(); });

    root.querySelector("[data-finalize]").addEventListener("click", async event => {
      const button = event.currentTarget;
      const dataColumns = state.columns.filter(column => !geoRoles.includes(column.role));
      if (!dataColumns.length) return showError("ต้องมีอย่างน้อย 1 คอลัมน์ที่ไม่ใช่พิกัด");
      if (!window.confirm(`นำเข้า ${state.rows.length} แถว เป็นชุดข้อมูล "${state.name || "ไม่มีชื่อ"}" ใช่หรือไม่?`)) return;
      button.disabled = true;
      showError("");
      saveState.textContent = "กำลังนำเข้า…";
      try {
        const { result } = await postJson(root.dataset.finalizeUrl, payload());
        dirty = false;
        showResult(result);
      } catch (failure) {
        showError(failure.message);
        saveState.textContent = "";
        button.disabled = false;
      }
    });

    function showResult(result) {
      editorPanel.hidden = true;
      root.querySelector("[data-step-edit]").className = "done";
      root.querySelector("[data-step-result]").className = "active";
      const stat = (label, value, tone = "") => `<div class="smart-stat ${tone}"><b>${value ?? 0}</b><span>${label}</span></div>`;
      resultPanel.innerHTML = `
        <div class="smart-result-head"><span class="material-symbols-outlined">task_alt</span><div><h2>นำเข้าเรียบร้อย</h2><p>สร้างชุดข้อมูล <b>${escapeHtml(result.dataset_name)}</b> (Version 1)</p></div></div>
        <div class="smart-stats">
          ${stat("รายการที่นำเข้า", result.records)}
          ${stat("มีพิกัดบนแผนที่", result.located, "good")}
          ${stat("พิกัดจากไฟล์/แก้ไขเอง", result.from_file)}
          ${stat("หาพิกัดจากชื่อสถานที่", result.geocoded, "info")}
          ${stat("หาพิกัดไม่พบ", result.not_found, result.not_found ? "warn" : "")}
          ${stat("อยู่นอกพื้นที่ (ไม่ใส่พิกัด)", result.outside, result.outside ? "bad" : "")}
        </div>
        ${result.not_found || result.outside ? `<p class="smart-hint">รายการที่ไม่มีพิกัดถูกนำเข้าแล้วแต่ยังไม่แสดงบนแผนที่ — แก้ไขพิกัดเพิ่มได้ในหน้าชุดข้อมูล</p>` : ""}
        <footer>
          <a class="button-link" href="${root.dataset.newUrl || "/smart_imports/new"}">นำเข้าไฟล์อื่น</a>
          ${result.located ? `<a class="button-link" href="${result.map_url}">ดูบนแผนที่</a>` : ""}
          <a class="data-layer-add" href="${result.dataset_url}">เปิดชุดข้อมูล</a>
        </footer>`;
      resultPanel.hidden = false;
      resultPanel.scrollIntoView({ behavior: "smooth", block: "start" });
    }

    if (state.status === "imported" && state.result && state.result.dataset_id) {
      showResult(state.result);
      return;
    }
    setupMap();
    render();
  }

  document.addEventListener("DOMContentLoaded", () => {
    const form = document.querySelector("[data-smart-import-form]");
    if (form) setupUpload(form);
    const editor = document.querySelector("[data-smart-editor]");
    if (editor) setupEditor(editor);
  });
})();
