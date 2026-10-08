document.addEventListener("DOMContentLoaded", () => {
  const breadcrumb = document.querySelector(".data-layers-shell .breadcrumb");
  const areaName = document.querySelector(".data-layers-shell .scope-summary b")?.textContent.trim();
  if (breadcrumb && areaName) {
    const area = document.createElement("span"); area.id = "selection-label"; area.textContent = areaName;
    const separator = document.createElement("b"); separator.textContent = "›";
    const section = document.createElement("span"); section.textContent = "นำเข้าข้อมูล";
    breadcrumb.replaceChildren(area, separator, section);
  }
  const list = document.querySelector(".custom-dataset-list");
  if (!list || !list.querySelector("article")) return;
  const catalog = list.closest(".dataset-catalog");
  const catalogHero = catalog?.querySelector(".catalog-hero");
  const createDatasetButton = document.querySelector("[data-open-custom-dialog]");
  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content || "";
  const initialDetailUrl = list.dataset.initialDetailUrl;
  let activeDataset = null;

  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, character => ({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[character]));
  const formatThaiDateTime = value => {
    if (!value) return "—";
    return new Intl.DateTimeFormat("th-TH", { timeZone: "Asia/Bangkok", day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }).format(new Date(value)) + " น.";
  };
  const sourceLabels = { manual: "กรอกหรือแก้ไขข้อมูล", file: "นำเข้าจากไฟล์", restored: "สร้างจากรุ่นข้อมูลเดิม", checkpoint: "รุ่นข้อมูลที่บันทึกไว้ดูย้อนหลัง" };
  const versionCardMarkup = (version, editable) => `<article class="version-history-card ${version.current ? "current" : ""}"><div class="version-history-top"><span class="version-history-badge">v${version.version_number}</span>${version.current ? "<em>ใช้งานอยู่</em>" : ""}</div><b>${escapeHtml(version.display_name)}</b><p>${escapeHtml(version.change_note)}</p><small>${escapeHtml(sourceLabels[version.source_kind] || version.source_kind)} · ${Number(version.record_count || 0).toLocaleString()} รายการ · ${escapeHtml(formatThaiDateTime(version.created_at))}</small>${version.source_filename ? `<small>ไฟล์: ${escapeHtml(version.source_filename)}</small>` : ""}<div><button type="button" class="table-action" data-view-version="${escapeHtml(version.view_url)}">ดูข้อมูล</button>${version.downloadable ? `<a href="${escapeHtml(version.download_url)}" class="table-action">ดาวน์โหลดไฟล์</a>` : ""}${editable && !version.current ? `<button type="button" class="table-action" data-restore-version="${escapeHtml(version.restore_url)}">ใช้ข้อมูลรุ่นนี้</button>` : ""}</div></article>`;
  const auditActionLabels = { add: "เพิ่ม", update: "แก้ไข", delete: "ลบ", import: "นำเข้าไฟล์", restore: "กู้คืน", checkpoint: "บันทึกเป็นรุ่นข้อมูล" };
  const auditMarkup = (logs, schema, datasetName) => {
    if (!logs.length) return '<section class="data-tab-empty custom-tab-empty"><span class="material-symbols-outlined">manage_search</span><h2>ยังไม่มีประวัติการแก้ไข</h2><p>รายการเพิ่ม แก้ไข ลบ และนำเข้าข้อมูลจะแสดงที่นี่</p></section>';
    const labels = Object.fromEntries(schema.map(field => [field.key, field.label]));
    const rows = logs.map(log => {
      const changedFields = Array.isArray(log.changed_fields) ? log.changed_fields : [];
      const summary = log.action === "add" ? "เพิ่มข้อมูลใหม่ 1 รายการ" : log.action === "delete" ? "ลบข้อมูล 1 รายการ" : log.action === "update" ? `แก้ไข ${changedFields.length} ช่องข้อมูล` : (log.note || "ข้อมูลทั้งชุด");
      const details = changedFields.length ? changedFields.map(field => `<p><b>${escapeHtml(labels[field] || field)}</b><span><small>ข้อมูลเดิม</small><em>${escapeHtml(log.before_data?.[field] || "—")}</em></span><i class="material-symbols-outlined">arrow_forward</i><strong><small>ข้อมูลใหม่</small><em>${escapeHtml(log.after_data?.[field] || "—")}</em></strong></p>`).join("") : `<p><b>จำนวนข้อมูล</b><span><small>ข้อมูลเดิม</small><em>${Number(log.before_data?.record_count || 0).toLocaleString()} รายการ</em></span><i class="material-symbols-outlined">arrow_forward</i><strong><small>ข้อมูลใหม่</small><em>${Number(log.after_data?.record_count || 0).toLocaleString()} รายการ</em></strong></p>`;
      return `<tr><td class="audit-date">${escapeHtml(formatThaiDateTime(log.created_at))}</td><td><span class="audit-action ${escapeHtml(log.action)}">${escapeHtml(auditActionLabels[log.action] || log.action)}</span></td><td class="audit-record"><b>${escapeHtml(log.record_label || log.note || datasetName)}</b><small>${escapeHtml(summary)}</small></td><td class="audit-user"><span class="material-symbols-outlined">person</span>${escapeHtml(log.user_name)}</td><td><button type="button" class="dataset-audit-toggle" data-custom-audit-toggle="custom-audit-${escapeHtml(log.id)}" aria-expanded="false">ดูรายละเอียด <i class="material-symbols-outlined">expand_more</i></button></td></tr><tr id="custom-audit-${escapeHtml(log.id)}" class="dataset-audit-detail-row" hidden><td colspan="5"><div class="dataset-audit-detail">${details}${log.note ? `<small>หมายเหตุ: ${escapeHtml(log.note)}</small>` : ""}</div></td></tr>`;
    }).join("");
    return `<section class="dataset-audit-panel custom-audit-panel"><div class="section-card-heading"><div><h2>ประวัติการแก้ไข</h2><p>ตรวจสอบย้อนหลังว่าใครเพิ่ม แก้ไข ลบ หรือนำเข้าข้อมูล</p></div><span>${logs.length} รายการล่าสุด</span></div><div class="dataset-audit-table-wrap"><table class="dataset-audit-table"><thead><tr><th>วันและเวลา</th><th>การดำเนินการ</th><th>รายการข้อมูล</th><th>ผู้ดำเนินการ</th><th>การเปลี่ยนแปลง</th></tr></thead><tbody>${rows}</tbody></table></div></section>`;
  };
  const items = [...list.querySelectorAll("article")].map(article => ({
    name: article.querySelector("b")?.textContent.trim() || "ชุดข้อมูล",
    summary: article.querySelector("small")?.textContent.trim() || "",
    categoryLabel: article.dataset.categoryLabel || "ยังไม่ระบุประเภท",
    updatedLabel: article.dataset.updatedLabel || "—",
    url: article.querySelector("a")?.href
  }));
  list.classList.add("custom-dataset-table");
  const renderList = () => {
    const categories = [...new Set(items.map(item => item.categoryLabel))];
    const categoryOptions = categories.map(category => `<option value="${escapeHtml(category)}">${escapeHtml(category)}</option>`).join("");
    list.innerHTML = `<div class="custom-catalog-toolbar"><div class="custom-catalog-filters"><input type="search" placeholder="ค้นหาชื่อชุดข้อมูล" data-custom-search><select data-custom-category-filter aria-label="กรองตามประเภทข้อมูล"><option value="">ทุกประเภทข้อมูล</option>${categoryOptions}</select></div><span data-custom-result-count>${items.length} ชุดข้อมูล</span></div><div class="custom-table-scroll"><div class="custom-catalog-head"><span>ชื่อชุดข้อมูล</span><span>ประเภทข้อมูล</span><span>จำนวน</span><span>รูปแบบตำแหน่ง</span><span>อัปเดตล่าสุด</span><span></span></div><div data-custom-rows>${items.map(item => { const count = item.summary.match(/\d+/)?.[0] || "0"; const map = item.summary.includes("ไม่แสดง") ? "ไม่แสดงบนแผนที่" : "จุดตำแหน่ง"; return `<article data-custom-row data-category="${escapeHtml(item.categoryLabel)}" data-detail-url="${escapeHtml(item.url)}" data-search="${escapeHtml(`${item.name} ${item.categoryLabel}`.toLowerCase())}" role="link" tabindex="0" aria-label="ดูรายละเอียด ${escapeHtml(item.name)}"><div class="custom-name-cell"><i>▧</i><div><b>${escapeHtml(item.name)}</b><small>ดูข้อมูลและโครงสร้าง</small></div></div><span>${escapeHtml(item.categoryLabel)}</span><strong>${Number(count).toLocaleString()} รายการ</strong><span class="custom-geometry-cell">⌾ ${map}</span><time>${escapeHtml(item.updatedLabel)}</time><span class="custom-detail-arrow" aria-hidden="true">›</span></article>`; }).join("")}</div></div>`;
    const applyFilters = () => {
      const query = list.querySelector("[data-custom-search]").value.trim().toLowerCase();
      const category = list.querySelector("[data-custom-category-filter]").value;
      let visibleCount = 0;
      list.querySelectorAll("[data-custom-row]").forEach(row => {
        row.hidden = !row.dataset.search.includes(query) || Boolean(category && row.dataset.category !== category);
        if (!row.hidden) visibleCount += 1;
      });
      list.querySelector("[data-custom-result-count]").textContent = `${visibleCount} ชุดข้อมูล`;
    };
    list.querySelector("[data-custom-search]").addEventListener("input", applyFilters);
    list.querySelector("[data-custom-category-filter]").addEventListener("change", applyFilters);
  };
  const renderDetail = data => {
    activeDataset = data;
    const headers = data.schema.map(field => `<th>${escapeHtml(field.label)}</th>`).join("") + (data.editable ? '<th class="record-actions-heading">จัดการ</th>' : "");
    const rows = data.records.map((record, position) => `<tr>${data.schema.map(field => `<td>${escapeHtml(record[field.key] ?? "—")}</td>`).join("")}${data.editable ? `<td class="record-actions"><button type="button" class="record-icon-button edit" title="แก้ไขข้อมูล" aria-label="แก้ไขข้อมูล" data-custom-record-edit="${position}">✎</button><button type="button" class="record-icon-button delete" title="ลบข้อมูล" aria-label="ลบข้อมูล" data-custom-record-delete="${position}">♲</button></td>` : ""}</tr>`).join("") || `<tr><td colspan="${Math.max(data.schema.length + (data.editable ? 1 : 0), 1)}">ยังไม่มีข้อมูลในชุดนี้</td></tr>`;
    const versions = Array.isArray(data.versions) ? data.versions : [];
    const versionCards = versions.map(version => versionCardMarkup(version, data.editable)).join("");
    const versionPanel = versionCards ? `<section class="dataset-version-panel custom-version-panel"><div class="section-card-heading"><div><h2>ประวัติรุ่นข้อมูล</h2><p>รุ่นข้อมูลจากไฟล์และรุ่นข้อมูลที่บันทึกไว้ใช้เป็นจุดย้อนกลับสำหรับดูข้อมูลย้อนหลัง</p></div><div class="version-heading-actions"><span>${versions.length} รุ่นข้อมูล</span></div></div><div class="version-history-cards">${versionCards}</div></section>` : '<section class="data-tab-empty custom-tab-empty"><span class="material-symbols-outlined">history</span><h2>ยังไม่มีประวัติรุ่นข้อมูล</h2><p>เมื่อเพิ่มข้อมูลหรือนำเข้าไฟล์ ประวัติรุ่นข้อมูลจะแสดงที่นี่</p></section>';
    const auditPanel = auditMarkup(Array.isArray(data.change_logs) ? data.change_logs : [], data.schema, data.name);
    const geometry = { none: "ไม่แสดงบนแผนที่", point: "จุด", line: "เส้นทาง", polygon: "ขอบเขตพื้นที่" }[data.geometry_type] || "—";
    const summaryGeometry = data.map_enabled ? ({ point: "จุดตำแหน่ง", line: "เส้นทาง", polygon: "ขอบเขตพื้นที่" }[data.geometry_type] || "—") : "—";
    if (catalogHero) catalogHero.hidden = true;
    if (createDatasetButton) createDatasetButton.hidden = true;
    catalog?.classList.add("custom-detail-mode");
    list.classList.remove("custom-dataset-table");
    const typeLabel = { text: "ข้อความ", number: "ตัวเลข", integer: "จำนวนเต็ม", date: "วันที่", boolean: "ใช่/ไม่ใช่" };
    list.innerHTML = `<button type="button" class="custom-back-link" data-custom-back>‹ กลับไปรายการชุดข้อมูล</button><section class="custom-detail-card"><header class="custom-detail-header"><div><small>ชุดข้อมูลแบบกำหนดเอง</small><h2>${escapeHtml(data.name)}</h2><p>${escapeHtml(data.type)} · เจ้าของข้อมูล · อัปเดตล่าสุด</p></div><div class="custom-detail-actions">${data.editable ? '<button type="button" class="custom-delete-dataset" data-custom-delete-dataset>♲ ลบชุดข้อมูล</button>' : ""}<button type="button" class="button-link" data-custom-add-record>＋ เพิ่มข้อมูล</button><button type="button" class="data-layer-add" data-custom-upload-file>⇧ นำเข้าไฟล์</button></div></header><nav class="data-management-tabs custom-data-tabs" role="tablist" aria-label="ข้อมูลชุดที่กำหนดเอง"><button type="button" class="active" role="tab" aria-selected="true" data-custom-detail-tab="current"><span class="material-symbols-outlined">table_view</span>ข้อมูลปัจจุบัน</button><button type="button" role="tab" aria-selected="false" data-custom-detail-tab="versions"><span class="material-symbols-outlined">history</span>ประวัติรุ่นข้อมูล</button><button type="button" role="tab" aria-selected="false" data-custom-detail-tab="audit"><span class="material-symbols-outlined">manage_search</span>ประวัติการแก้ไข</button></nav><section class="custom-detail-stats"><div><small>รุ่นข้อมูลปัจจุบัน</small><b>${data.current_version_number ? `v${data.current_version_number}` : "ยังไม่มีรุ่นข้อมูล"}</b></div><div><small>จำนวนข้อมูล</small><b>${data.record_count} รายการ</b></div><div><small>สถานะแผนที่</small><b class="map-enabled-state">${data.map_enabled ? "เปิดแสดง" : "ไม่แสดง"}</b></div><div><small>รูปแบบตำแหน่ง</small><b>${geometry}</b></div><div><small>อัปเดตล่าสุด</small><b>${escapeHtml(formatThaiDateTime(data.updated_at))}</b></div></section><div class="data-management-tab-panel active" role="tabpanel" data-custom-detail-panel="current"><section class="map-layer-setting-panel custom-map-setting-panel"><div><span class="material-symbols-outlined">layers</span><div><b>การตั้งค่าชั้นข้อมูลบนแผนที่</b><p>${data.geometry_type === "none" ? "ชุดข้อมูลนี้ยังไม่มีข้อมูลตำแหน่ง จึงยังไม่สามารถแสดงบนแผนที่ได้" : "เมื่อปิด ชื่อชั้นข้อมูลและข้อมูลชุดนี้จะไม่ปรากฏในหน้าแผนที่เมือง"}</p></div></div>${data.editable ? `<label class="map-layer-switch custom-map-layer-switch"><input type="checkbox" data-custom-map-toggle ${data.map_enabled ? "checked" : ""} ${data.geometry_type === "none" ? "disabled" : ""}><span aria-hidden="true"></span><em>${data.map_enabled ? "แสดงในชั้นข้อมูล" : "ไม่แสดงในชั้นข้อมูล"}</em></label>` : `<strong class="map-setting-readonly">${data.map_enabled ? "เปิดใช้งาน" : "ปิดใช้งาน"}</strong>`}</section><section class="custom-detail-section schema-detail-card"><div class="detail-section-heading"><div><h3>โครงสร้างรายละเอียดข้อมูล</h3><p>กด “แก้ไขโครงสร้าง” ก่อนเปลี่ยนหัวข้อรายละเอียดข้อมูล</p></div><button type="button" class="button-link" data-custom-edit-schema>⚙ แก้ไขโครงสร้าง</button></div><div class="fixed-table-wrap"><table class="fixed-data-table"><thead><tr><th>ชื่อหัวข้อ</th><th>ประเภทข้อมูลที่เก็บ</th><th>การกรอกข้อมูล</th></tr></thead><tbody>${data.schema.map(field => `<tr><td>${escapeHtml(field.label)}</td><td>${typeLabel[field.type] || escapeHtml(field.type)}</td><td>${field.required ? "☑ จำเป็นต้องกรอก" : "☐ ไม่บังคับ"}</td></tr>`).join("")}</tbody></table></div></section><section class="custom-detail-section data-detail-card"><div class="detail-section-heading"><div><h3>ข้อมูลในชุดนี้</h3><p>แสดงรายละเอียดที่ถูกนำเข้าและบันทึกไว้ทั้งหมด</p></div><input type="search" placeholder="⌕ ค้นหาข้อมูลในตาราง" data-detail-search></div><div class="fixed-table-wrap"><table class="fixed-data-table"><thead><tr>${headers}</tr></thead><tbody>${rows}</tbody></table></div></section></div><div class="data-management-tab-panel" role="tabpanel" data-custom-detail-panel="versions" hidden>${versionPanel}</div><div class="data-management-tab-panel" role="tabpanel" data-custom-detail-panel="audit" hidden>${auditPanel}</div></section>`;
    const summaryCards = list.querySelector(".custom-detail-stats");
    summaryCards.className = "import-summary-grid dataset-summary-grid custom-detail-stats";
    summaryCards.setAttribute("aria-label", "สรุปชุดข้อมูลปัจจุบัน");
    summaryCards.innerHTML = `<article><span class="material-symbols-outlined versions">history</span><div><small>รุ่นข้อมูลที่ใช้อยู่</small><strong>${data.current_version_number ? `รุ่นที่ ${data.current_version_number}` : "—"}</strong></div></article><article><span class="material-symbols-outlined records">database</span><div><small>จำนวนข้อมูล</small><strong>${Number(data.record_count || 0).toLocaleString()}</strong></div></article><article><span class="material-symbols-outlined maps">map</span><div><small>การแสดงบนแผนที่</small><strong class="state ${data.map_enabled ? "enabled" : "disabled"}">${data.map_enabled ? "เปิดใช้งาน" : "ยังไม่เปิดใช้งาน"}</strong></div></article><article><span class="material-symbols-outlined geometry">category</span><div><small>รูปแบบข้อมูลแผนที่</small><strong class="date">${escapeHtml(summaryGeometry)}</strong></div></article><article><span class="material-symbols-outlined updated">update</span><div><small>อัปเดตล่าสุด</small><strong class="date">${escapeHtml(formatThaiDateTime(data.updated_at))}</strong></div></article>`;
    list.querySelector("[data-detail-search]").addEventListener("input", event => {
      const query = event.target.value.trim().toLowerCase();
      list.querySelectorAll(".data-detail-card tbody tr").forEach(row => row.hidden = Boolean(query) && !row.textContent.toLowerCase().includes(query));
    });
  };
  const loadDetail = async (url, updateHistory = true) => {
    list.setAttribute("aria-busy", "true");
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } });
      if (!response.ok) throw new Error("ไม่สามารถเปิดรายละเอียดชุดข้อมูลได้");
      const data = await response.json();
      renderDetail(data);
      if (updateHistory && window.location.pathname !== new URL(url, window.location.origin).pathname) history.pushState({ customDatasetUrl: url }, "", url);
    } finally {
      list.removeAttribute("aria-busy");
    }
  };
  const returnToList = (updateHistory = true) => {
    activeDataset = null;
    if (catalogHero) catalogHero.hidden = false;
    if (createDatasetButton) createDatasetButton.hidden = false;
    catalog?.classList.remove("custom-detail-mode");
    list.classList.add("custom-dataset-table");
    renderList();
    if (updateHistory && window.location.pathname !== "/imported_datasets") history.pushState({ customDatasetList: true }, "", "/imported_datasets");
  };
  const closeDialog = dialog => { dialog.close(); dialog.remove(); };
  const dialogShell = (title, content) => {
    const dialog = document.createElement("dialog");
    dialog.className = "dataset-modal custom-action-modal";
    dialog.innerHTML = `<header><div><small>ชุดข้อมูลแบบกำหนดเอง</small><h2>${escapeHtml(title)}</h2></div><button type="button" aria-label="ปิด">×</button></header>${content}`;
    dialog.querySelector("header button").addEventListener("click", () => closeDialog(dialog));
    document.body.append(dialog);
    dialog.showModal();
    return dialog;
  };
  const openAllVersions = () => {
    const versions = Array.isArray(activeDataset?.versions) ? activeDataset.versions : [];
    const cards = versions.map(version => versionCardMarkup(version, activeDataset.editable)).join("") || '<p class="custom-empty">ยังไม่มีประวัติรุ่นข้อมูล</p>';
    const dialog = dialogShell(`ประวัติรุ่นข้อมูลทั้งหมด (${versions.length})`, `<div class="custom-version-history version-history-modal"><div class="version-history-cards">${cards}</div></div>`);
    dialog.addEventListener("click", event => {
      const viewVersion = event.target.closest("[data-view-version]");
      if (viewVersion) { showVersionRecords(viewVersion.dataset.viewVersion); return; }
      const restore = event.target.closest("[data-restore-version]");
      if (restore) { restoreVersion(restore.dataset.restoreVersion); }
    });
  };
  const reloadActiveDataset = async () => {
    const response = await fetch(`/imported_datasets/${activeDataset.id}`, { headers: { Accept: "application/json" } });
    if (!response.ok) throw new Error("ไม่สามารถโหลดข้อมูลล่าสุดได้");
    renderDetail(await response.json());
  };
  const openCustomRecordEditor = position => {
    const record = activeDataset?.records?.[position];
    if (!record) return;
    const fields = activeDataset.schema.map(field => `<label>${escapeHtml(field.label)}${field.required ? " *" : ""}<input name="record[${escapeHtml(field.key)}]" value="${escapeHtml(record[field.key] ?? "")}" type="${field.type === "number" || field.type === "integer" ? "number" : field.type === "date" ? "date" : "text"}" ${field.required ? "required" : ""} step="any"></label>`).join("");
    const dialog = dialogShell("แก้ไขข้อมูล", `<form class="manual-record-form"><div class="modal-info">ระบบจะอัปเดตรุ่นข้อมูลที่กรอกเองล่าสุด หากข้อมูลปัจจุบันมาจากไฟล์ ระบบจะสร้างรุ่นข้อมูลสำหรับการแก้ไขขึ้นใหม่</div><div class="manual-fixed-grid">${fields}</div><label class="record-change-note">รายละเอียดการแก้ไข<input name="change_note" placeholder="ระบุรายละเอียดที่แก้ไข"></label><p class="modal-status" data-status></p><footer><button type="button" class="button-link" data-cancel>ยกเลิก</button><button class="data-layer-add" type="submit">บันทึกการแก้ไข</button></footer></form>`);
    const form = dialog.querySelector("form");
    form.querySelector("[data-cancel]").addEventListener("click", () => closeDialog(dialog));
    form.addEventListener("submit", async event => {
      event.preventDefault();
      const status = form.querySelector("[data-status]"), submit = form.querySelector('[type="submit"]');
      status.textContent = "กำลังบันทึกข้อมูล…"; submit.disabled = true;
      try {
        const response = await fetch(`/imported_datasets/${activeDataset.id}/records/${position}`, { method: "PATCH", headers: { Accept: "application/json", "X-CSRF-Token": csrfToken }, body: new FormData(form) });
        const payload = await response.json();
        if (!response.ok) throw new Error(payload.error || "ไม่สามารถแก้ไขข้อมูลได้");
        closeDialog(dialog); await reloadActiveDataset();
      } catch (error) { status.textContent = error.message; status.classList.add("error"); submit.disabled = false; }
    });
  };
  const deleteCustomRecord = async position => {
    if (!window.confirm("ยืนยันลบรายการนี้? ข้อมูลเดิมจะยังอยู่ในประวัติรุ่นข้อมูล")) return;
    try {
      const response = await fetch(`/imported_datasets/${activeDataset.id}/records/${position}`, { method: "DELETE", headers: { Accept: "application/json", "X-CSRF-Token": csrfToken } });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "ไม่สามารถลบข้อมูลได้");
      await reloadActiveDataset();
    } catch (error) { window.alert(error.message); }
  };
  const deleteCustomDataset = async () => {
    if (!activeDataset?.editable || !window.confirm(`ยืนยันลบชุดข้อมูล “${activeDataset.name}”? ข้อมูลและประวัติรุ่นข้อมูลทั้งหมดจะถูกลบ`)) return;
    try {
      const response = await fetch(`/imported_datasets/${activeDataset.id}`, { method: "DELETE", headers: { Accept: "application/json", "X-CSRF-Token": csrfToken } });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "ไม่สามารถลบชุดข้อมูลได้");
      window.location.assign(payload.redirect_url || "/imported_datasets");
    } catch (error) { window.alert(error.message); }
  };
  const showVersionRecords = async url => {
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } });
      const version = await response.json();
      if (!response.ok) throw new Error(version.error || "ไม่สามารถโหลดข้อมูลรุ่นนี้ได้");
      const headers = version.schema.map(field => `<th>${escapeHtml(field.label)}</th>`).join("");
      const rows = version.records.map(record => `<tr>${version.schema.map(field => `<td>${escapeHtml(record[field.key] ?? "—")}</td>`).join("")}</tr>`).join("") || `<tr><td colspan="${version.schema.length}">ไม่มีข้อมูลในรุ่นนี้</td></tr>`;
      dialogShell(`ข้อมูลรุ่นที่ ${version.version_number}`, `<div class="version-preview-modal fixed-table-wrap"><table class="fixed-data-table"><thead><tr>${headers}</tr></thead><tbody>${rows}</tbody></table></div>`);
    } catch (error) { window.alert(error.message); }
  };
  const restoreVersion = async url => {
    if (!window.confirm("ยืนยันสร้างรุ่นข้อมูลใหม่จากข้อมูลชุดนี้?")) return;
    try {
      const response = await fetch(url, { method: "POST", headers: { Accept: "application/json", "X-CSRF-Token": csrfToken } });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "ไม่สามารถสร้างรุ่นข้อมูลได้");
      await reloadActiveDataset();
    } catch (error) { window.alert(error.message); }
  };
  const openRecordForm = () => {
    if (!activeDataset) return;
    const fields = activeDataset.schema.map(field => `<label>${escapeHtml(field.label)}${field.required ? " *" : ""}<input name="field_${escapeHtml(field.key)}" type="${field.type === "number" || field.type === "integer" ? "number" : field.type === "date" ? "date" : "text"}" ${field.required ? "required" : ""}></label>`).join("");
    const dialog = dialogShell("เพิ่มข้อมูลทีละรายการ", `<form method="post" action="/imported_datasets/${escapeHtml(activeDataset.id)}/versions" class="manual-record-form"><input type="hidden" name="authenticity_token" value="${escapeHtml(csrfToken)}"><input type="hidden" name="append_records" value="1"><input type="hidden" name="manual_records"><div class="manual-fixed-grid">${fields}</div><label class="record-change-note">หมายเหตุการอัปเดต<input name="change_note" value="เพิ่มข้อมูลทีละรายการ"></label><footer><button type="button" class="button-link" data-cancel>ยกเลิก</button><button class="data-layer-add">บันทึกข้อมูล</button></footer></form>`);
    const form = dialog.querySelector("form");
    form.querySelector("[data-cancel]").addEventListener("click", () => closeDialog(dialog));
    form.addEventListener("submit", () => {
      const record = {};
      activeDataset.schema.forEach(field => { record[field.key] = form.elements[`field_${field.key}`]?.value || ""; });
      form.elements.manual_records.value = JSON.stringify([record]);
    });
  };
  const openFileForm = () => {
    if (!activeDataset) return;
    let draft = null;
    const dialog = dialogShell("นำเข้าไฟล์ข้อมูล", `<div class="custom-file-wizard" data-file-wizard></div>`);
    const wizard = dialog.querySelector("[data-file-wizard]");
    const request = async (url, options = {}) => {
      const response = await fetch(url, { ...options, headers: { Accept: "application/json", "X-CSRF-Token": csrfToken, ...(options.headers || {}) } });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "ไม่สามารถดำเนินการได้");
      return payload;
    };
    const downloadTemplate = () => {
      const csv = `\uFEFF${activeDataset.schema.map(field => `"${String(field.label).replaceAll('"', '""')}"`).join(",")}\n`;
      const link = document.createElement("a");
      link.href = URL.createObjectURL(new Blob([csv], { type: "text/csv;charset=utf-8" }));
      link.download = `${activeDataset.name}_template.csv`;
      link.click();
      URL.revokeObjectURL(link.href);
    };
    const renderChoose = () => {
      wizard.innerHTML = `<div class="template-banner custom-template-banner"><div><b>Template สำหรับ ${escapeHtml(activeDataset.name)}</b><small>ดาวน์โหลดหัวคอลัมน์ให้ตรงกับโครงสร้างปัจจุบัน</small></div><button type="button" class="button-link" data-template>⇩ ดาวน์โหลด Template</button></div><label class="file-upload-field">เลือกไฟล์ข้อมูล<input type="file" accept=".csv,.xls,.xlsx,.pdf" data-custom-file required><small>รองรับ CSV, Excel (.xls, .xlsx) และ PDF สูงสุด 20 MB</small></label><p class="modal-status" data-status></p><footer><button type="button" class="button-link" data-cancel>ยกเลิก</button><button type="button" class="data-layer-add" data-upload>ตรวจสอบไฟล์</button></footer>`;
      wizard.querySelector("[data-template]").addEventListener("click", downloadTemplate);
      wizard.querySelector("[data-cancel]").addEventListener("click", () => closeDialog(dialog));
      wizard.querySelector("[data-upload]").addEventListener("click", uploadFile);
    };
    const uploadFile = async () => {
      const file = wizard.querySelector("[data-custom-file]").files[0];
      const status = wizard.querySelector("[data-status]");
      if (!file) { status.textContent = "กรุณาเลือกไฟล์ข้อมูล"; status.classList.add("error"); return; }
      status.textContent = "กำลังอ่านหัวคอลัมน์…";
      try {
        const body = new FormData(); body.append("file", file); body.append("target_dataset_id", activeDataset.id);
        draft = await request("/dataset_import_drafts", { method: "POST", body });
        renderMapping();
      } catch (error) { status.textContent = error.message; status.classList.add("error"); }
    };
    const renderMapping = () => {
      const mappingRows = draft.schema.map(field => {
        const options = ['<option value="">ไม่จับคู่</option>', ...draft.headers.map(header => `<option value="${escapeHtml(header)}" ${draft.mapping[field.key] === header ? "selected" : ""}>${escapeHtml(header)}</option>`)].join("");
        const matched = Boolean(draft.mapping[field.key]);
        return `<label><span>${escapeHtml(field.label)}${field.required ? " *" : ""}<small>${escapeHtml(field.key)}</small></span><b>→</b><select data-map-key="${escapeHtml(field.key)}">${options}</select><em class="${matched ? "" : "unmatched"}">${matched ? "จับคู่แล้ว" : "ยังไม่จับคู่"}</em></label>`;
      }).join("");
      wizard.innerHTML = `<div class="panel-heading custom-mapping-heading"><div><h3>จับคู่ Column กับ Field</h3><p>ระบบจับคู้อัตโนมัติ และสามารถเลือกคอลัมน์ใหม่ได้</p></div></div><div class="mapping-list">${mappingRows}</div><p class="modal-status" data-status></p><footer><button type="button" class="button-link" data-back>ย้อนกลับ</button><button type="button" class="data-layer-add" data-validate>ตรวจสอบข้อมูล</button></footer>`;
      wizard.querySelectorAll("[data-map-key]").forEach(select => select.addEventListener("change", () => { const badge = select.nextElementSibling; badge.textContent = select.value ? "จับคู่แล้ว" : "ยังไม่จับคู่"; badge.classList.toggle("unmatched", !select.value); }));
      wizard.querySelector("[data-back]").addEventListener("click", renderChoose);
      wizard.querySelector("[data-validate]").addEventListener("click", validateMapping);
    };
    const validateMapping = async () => {
      const status = wizard.querySelector("[data-status]");
      const body = new FormData();
      wizard.querySelectorAll("[data-map-key]").forEach(select => body.append(`mapping[${select.dataset.mapKey}]`, select.value));
      status.textContent = "กำลังตรวจสอบข้อมูล…";
      try {
        draft = await request(`/dataset_import_drafts/${draft.id}/validate`, { method: "POST", body });
        if (draft.validation?.errors?.length) throw new Error(draft.validation.errors.join(" · "));
        renderPreview();
      } catch (error) { status.textContent = error.message; status.classList.add("error"); }
    };
    const renderPreview = () => {
      const headers = draft.schema.map(field => `<th>${escapeHtml(field.label)}</th>`).join("");
      const rows = draft.records.slice(0, 5).map(record => `<tr>${draft.schema.map(field => `<td>${escapeHtml(record[field.key] ?? "—")}</td>`).join("")}</tr>`).join("");
      const incomingCount = Number(draft.validation.total || 0);
      const currentCount = Number(activeDataset.record_count || 0);
      wizard.innerHTML = `<div class="panel-heading custom-mapping-heading"><div><h3>ตรวจสอบข้อมูลก่อนบันทึก</h3><p>ไฟล์นี้มีข้อมูล ${incomingCount.toLocaleString()} รายการ</p></div></div><div class="preview-table"><table><thead><tr>${headers}</tr></thead><tbody>${rows}</tbody></table><small>ตัวอย่างข้อมูล 5 รายการแรก</small></div><fieldset class="custom-import-mode"><legend>ต้องการนำเข้าข้อมูลแบบไหน?</legend><label><input type="radio" name="import_mode" value="replace" checked><span><b>ใช้ข้อมูลจากไฟล์แทนข้อมูลเดิม</b><small>ข้อมูลชุดใหม่จะมีเฉพาะข้อมูลจากไฟล์นี้ ${incomingCount.toLocaleString()} รายการ ส่วนข้อมูลเดิมยังดูได้ในประวัติ</small></span></label><label><input type="radio" name="import_mode" value="append"><span><b>เพิ่มข้อมูลจากไฟล์ต่อจากข้อมูลเดิม</b><small>เก็บข้อมูลเดิม ${currentCount.toLocaleString()} รายการ และเพิ่มข้อมูลใหม่อีก ${incomingCount.toLocaleString()} รายการ รวมเป็น ${(currentCount + incomingCount).toLocaleString()} รายการ</small></span></label></fieldset><label class="record-change-note">หมายเหตุการนำเข้า<input data-change-note value="นำเข้าข้อมูลจากไฟล์ ${escapeHtml(draft.filename)}"></label><p class="modal-status" data-status></p><footer><button type="button" class="button-link" data-back>กลับไปจับคู่คอลัมน์</button><button type="button" class="data-layer-add" data-finalize>บันทึกข้อมูล</button></footer>`;
      wizard.querySelector("[data-back]").addEventListener("click", renderMapping);
      wizard.querySelector("[data-finalize]").addEventListener("click", finalizeImport);
    };
    const finalizeImport = async () => {
      const status = wizard.querySelector("[data-status]");
      const body = new FormData();
      body.append("change_note", wizard.querySelector("[data-change-note]").value);
      body.append("import_mode", wizard.querySelector('input[name="import_mode"]:checked').value);
      status.textContent = "กำลังบันทึกข้อมูล…";
      try {
        const result = await request(`/dataset_import_drafts/${draft.id}/finalize`, { method: "POST", body });
        const response = await fetch(`/imported_datasets/${result.dataset_id}`, { headers: { Accept: "application/json" } });
        if (!response.ok) throw new Error("นำเข้าสำเร็จ แต่ไม่สามารถโหลดรายละเอียดล่าสุดได้");
        closeDialog(dialog);
        renderDetail(await response.json());
      } catch (error) { status.textContent = error.message; status.classList.add("error"); }
    };
    renderChoose();
  };
  const openSchemaForm = () => {
    if (!activeDataset) return;
    const makeRow = field => `<div class="schema-row" data-key="${escapeHtml(field.key || "")}"><input value="${escapeHtml(field.label || "")}" placeholder="ชื่อหัวข้อ" data-label><select data-type><option value="text" ${field.type === "text" ? "selected" : ""}>ข้อความ</option><option value="number" ${field.type === "number" ? "selected" : ""}>ตัวเลข</option><option value="integer" ${field.type === "integer" ? "selected" : ""}>จำนวนเต็ม</option><option value="date" ${field.type === "date" ? "selected" : ""}>วันที่</option><option value="boolean" ${field.type === "boolean" ? "selected" : ""}>ใช่/ไม่ใช่</option></select><label><input type="checkbox" data-required ${field.required ? "checked" : ""}> บังคับกรอก</label><button type="button" data-remove aria-label="ลบ">×</button></div>`;
    const card = list.querySelector(".schema-detail-card");
    card.innerHTML = `<form class="inline-schema-form" action="/imported_datasets/${escapeHtml(activeDataset.id)}"><div class="detail-section-heading"><div><h3>แก้ไขหัวข้อรายละเอียดข้อมูล</h3><p>เปลี่ยนชื่อ ประเภท หรือเพิ่มหัวข้อสำหรับข้อมูลชุดนี้</p></div><div class="inline-schema-actions"><button type="button" class="button-link add-schema-field" data-add>＋ เพิ่มหัวข้อ</button><button type="button" class="button-link" data-cancel>ยกเลิก</button><button type="submit" class="data-layer-add">บันทึกการแก้ไข</button></div></div><div class="schema-table-head inline-schema-head"><span>ชื่อหัวข้อ</span><span>ประเภทข้อมูลที่เก็บ</span><span>การกรอกข้อมูล</span></div><div class="inline-schema-rows" data-schema-rows>${activeDataset.schema.map(makeRow).join("")}</div><p class="inline-schema-status" data-schema-status></p></form>`;
    const form = card.querySelector("form");
    const rows = form.querySelector("[data-schema-rows]");
    form.querySelector("[data-cancel]").addEventListener("click", () => renderDetail(activeDataset));
    form.querySelector("[data-add]").addEventListener("click", () => rows.insertAdjacentHTML("beforeend", makeRow({ key: `field_${Date.now()}`, type: "text", required: false })));
    rows.addEventListener("click", event => { if (event.target.closest("[data-remove]")) event.target.closest(".schema-row").remove(); });
    form.addEventListener("submit", async event => {
      event.preventDefault();
      const fields = [...rows.querySelectorAll(".schema-row")].map(row => ({ key: row.dataset.key, label: row.querySelector("[data-label]").value.trim(), type: row.querySelector("[data-type]").value, required: row.querySelector("[data-required]").checked })).filter(field => field.label);
      const status = form.querySelector("[data-schema-status]");
      const submit = form.querySelector('[type="submit"]');
      if (!fields.length) { status.textContent = "กรุณาเพิ่มอย่างน้อย 1 หัวข้อ"; return; }
      const body = new FormData();
      body.append("_method", "patch");
      body.append("authenticity_token", csrfToken);
      body.append("imported_dataset[name]", activeDataset.name);
      body.append("imported_dataset[geometry_type]", activeDataset.geometry_type);
      body.append("imported_dataset[map_enabled]", activeDataset.map_enabled ? "1" : "0");
      body.append("schema_definition", JSON.stringify(fields));
      submit.disabled = true;
      status.textContent = "กำลังบันทึก…";
      try {
        const response = await fetch(form.action, { method: "POST", headers: { Accept: "application/json" }, body });
        const payload = await response.json();
        if (!response.ok) throw new Error(payload.error || "ไม่สามารถบันทึกโครงสร้างได้");
        activeDataset.schema = payload.schema;
        renderDetail(activeDataset);
      } catch (error) {
        status.textContent = error.message;
        submit.disabled = false;
      }
    });
  };
  list.addEventListener("change", async event => {
    const toggle = event.target.closest("[data-custom-map-toggle]");
    if (!toggle || !activeDataset) return;
    const enabled = toggle.checked;
    toggle.disabled = true;
    const body = new FormData();
    body.append("_method", "patch");
    body.append("authenticity_token", csrfToken);
    body.append("imported_dataset[map_enabled]", enabled ? "1" : "0");
    try {
      const response = await fetch(`/imported_datasets/${activeDataset.id}`, { method: "POST", headers: { Accept: "application/json" }, body });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "ไม่สามารถเปลี่ยนการแสดงบนแผนที่ได้");
      activeDataset.map_enabled = payload.map_enabled;
      activeDataset.updated_at = payload.updated_at;
      renderDetail(activeDataset);
    } catch (error) {
      toggle.checked = !enabled;
      toggle.disabled = false;
      window.alert(error.message);
    }
  });
  list.addEventListener("click", async event => {
    const detailTab = event.target.closest("[data-custom-detail-tab]");
    if (detailTab) {
      const selected = detailTab.dataset.customDetailTab;
      list.querySelectorAll("[data-custom-detail-tab]").forEach(tab => {
        const active = tab === detailTab;
        tab.classList.toggle("active", active);
        tab.setAttribute("aria-selected", String(active));
      });
      list.querySelectorAll("[data-custom-detail-panel]").forEach(panel => {
        const active = panel.dataset.customDetailPanel === selected;
        panel.hidden = !active;
        panel.classList.toggle("active", active);
      });
      return;
    }
    const auditToggle = event.target.closest("[data-custom-audit-toggle]");
    if (auditToggle) {
      const detailRow = document.getElementById(auditToggle.dataset.customAuditToggle);
      if (!detailRow) return;
      const expanded = auditToggle.getAttribute("aria-expanded") === "true";
      auditToggle.setAttribute("aria-expanded", String(!expanded));
      detailRow.hidden = expanded;
      return;
    }
    if (event.target.closest("[data-custom-back]")) { returnToList(); return; }
    if (event.target.closest("[data-custom-edit-schema]")) { openSchemaForm(); return; }
    if (event.target.closest("[data-custom-add-record]")) { openRecordForm(); return; }
    if (event.target.closest("[data-custom-upload-file]")) { openFileForm(); return; }
    if (event.target.closest("[data-custom-delete-dataset]")) { deleteCustomDataset(); return; }
    if (event.target.closest("[data-show-all-versions]")) { openAllVersions(); return; }
    const viewVersion = event.target.closest("[data-view-version]");
    if (viewVersion) { showVersionRecords(viewVersion.dataset.viewVersion); return; }
    const restore = event.target.closest("[data-restore-version]");
    if (restore) { restoreVersion(restore.dataset.restoreVersion); return; }
    const editRecord = event.target.closest("[data-custom-record-edit]");
    if (editRecord) { openCustomRecordEditor(Number(editRecord.dataset.customRecordEdit)); return; }
    const deleteRecord = event.target.closest("[data-custom-record-delete]");
    if (deleteRecord) { deleteCustomRecord(Number(deleteRecord.dataset.customRecordDelete)); return; }
    const row = event.target.closest("[data-custom-row]");
    if (!row) return;
    try {
      await loadDetail(row.dataset.detailUrl);
    } catch (error) {
      window.alert(error.message);
    }
  });
  list.addEventListener("keydown", event => {
    if ((event.key === "Enter" || event.key === " ") && event.target.matches("[data-custom-row]")) {
      event.preventDefault();
      event.target.click();
    }
  });
  window.addEventListener("popstate", () => {
    if (window.location.pathname === "/imported_datasets") returnToList(false);
    else loadDetail(window.location.href, false).catch(error => window.alert(error.message));
  });
  if (initialDetailUrl) {
    list.innerHTML = '<div class="custom-detail-loading"><span class="material-symbols-outlined">progress_activity</span><p>กำลังโหลดรายละเอียดชุดข้อมูล…</p></div>';
    loadDetail(initialDetailUrl, false).catch(error => { returnToList(false); window.alert(error.message); });
  } else {
    renderList();
  }
});
