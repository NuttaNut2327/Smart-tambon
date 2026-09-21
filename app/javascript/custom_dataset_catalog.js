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
  const sourceLabels = { manual: "กรอกหรือแก้ไขข้อมูล", file: "นำเข้าจากไฟล์", restored: "สร้างจาก Version เดิม" };
  const versionCardMarkup = (version, editable) => `<article class="custom-version-row ${version.current ? "current" : ""}"><span class="custom-version-badge">v${version.version_number}</span><div class="custom-version-info"><b>${escapeHtml(version.change_note)}</b><small>${escapeHtml(sourceLabels[version.source_kind] || version.source_kind)} · ${Number(version.record_count || 0).toLocaleString()} รายการ · ${escapeHtml(version.user_name)} · ${escapeHtml(formatThaiDateTime(version.created_at))}</small>${version.source_filename ? `<em>ไฟล์: ${escapeHtml(version.source_filename)}</em>` : ""}</div><div class="custom-version-actions"><button type="button" class="button-link" data-view-version="${escapeHtml(version.view_url)}">ดูข้อมูล</button>${version.downloadable ? `<a href="${escapeHtml(version.download_url)}" class="button-link">ดาวน์โหลดไฟล์</a>` : ""}${editable ? `<button type="button" class="button-link" data-restore-version="${escapeHtml(version.restore_url)}">สร้าง Version จากชุดนี้</button>` : ""}</div></article>`;
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
  renderList();
  const renderDetail = data => {
    activeDataset = data;
    const headers = data.schema.map(field => `<th>${escapeHtml(field.label)}</th>`).join("") + (data.editable ? '<th class="record-actions-heading">จัดการ</th>' : "");
    const rows = data.records.map((record, position) => `<tr>${data.schema.map(field => `<td>${escapeHtml(record[field.key] ?? "—")}</td>`).join("")}${data.editable ? `<td class="record-actions"><button type="button" class="record-icon-button edit" title="แก้ไขข้อมูล" aria-label="แก้ไขข้อมูล" data-custom-record-edit="${position}">✎</button><button type="button" class="record-icon-button delete" title="ลบข้อมูล" aria-label="ลบข้อมูล" data-custom-record-delete="${position}">♲</button></td>` : ""}</tr>`).join("") || `<tr><td colspan="${Math.max(data.schema.length + (data.editable ? 1 : 0), 1)}">ยังไม่มีข้อมูลในชุดนี้</td></tr>`;
    const versions = Array.isArray(data.versions) ? data.versions : [];
    const versionCards = versions.slice(0, 3).map(version => versionCardMarkup(version, data.editable)).join("") || '<p class="custom-empty">ยังไม่มีประวัติ Version</p>';
    const moreVersionsButton = versions.length > 3 ? '<button type="button" class="button-link custom-version-more" data-show-all-versions>ดูเพิ่มเติม</button>' : "";
    const geometry = { none: "ไม่แสดงบนแผนที่", point: "จุด", line: "เส้นทาง", polygon: "ขอบเขตพื้นที่" }[data.geometry_type] || "—";
    if (catalogHero) catalogHero.hidden = true;
    if (createDatasetButton) createDatasetButton.hidden = true;
    catalog?.classList.add("custom-detail-mode");
    list.classList.remove("custom-dataset-table");
    const typeLabel = { text: "ข้อความ", number: "ตัวเลข", integer: "จำนวนเต็ม", date: "วันที่", boolean: "ใช่/ไม่ใช่" };
    list.innerHTML = `<button type="button" class="custom-back-link" data-custom-back>‹ กลับไปรายการชุดข้อมูล</button><section class="custom-detail-card"><header class="custom-detail-header"><div><small>ชุดข้อมูลแบบกำหนดเอง</small><h2>${escapeHtml(data.name)}</h2><p>${escapeHtml(data.type)} · เจ้าของข้อมูล · อัปเดตล่าสุด</p></div><div class="custom-detail-actions">${data.editable ? '<button type="button" class="custom-delete-dataset" data-custom-delete-dataset>♲ ลบชุดข้อมูล</button>' : ""}<button type="button" class="button-link" data-custom-add-record>＋ เพิ่มข้อมูล</button><button type="button" class="data-layer-add" data-custom-upload-file>⇧ นำเข้าไฟล์</button></div></header><section class="custom-detail-stats"><div><small>Version ข้อมูลปัจจุบัน</small><b>${data.current_version_number ? `v${data.current_version_number}` : "ยังไม่มี Version"}</b></div><div><small>จำนวนข้อมูล</small><b>${data.record_count} รายการ</b></div><div><small>สถานะแผนที่</small><b class="map-enabled-state">${data.map_enabled ? "เปิดแสดง" : "ไม่แสดง"}</b></div><div><small>รูปแบบตำแหน่ง</small><b>${geometry}</b></div></section><section class="custom-detail-section schema-detail-card"><div class="detail-section-heading"><div><h3>โครงสร้างรายละเอียดข้อมูล</h3><p>กด “แก้ไขโครงสร้าง” ก่อนเปลี่ยนหัวข้อรายละเอียดข้อมูล</p></div><button type="button" class="button-link" data-custom-edit-schema>⚙ แก้ไขโครงสร้าง</button></div><div class="fixed-table-wrap"><table class="fixed-data-table"><thead><tr><th>ชื่อหัวข้อ</th><th>ประเภทข้อมูลที่เก็บ</th><th>การกรอกข้อมูล</th></tr></thead><tbody>${data.schema.map(field => `<tr><td>${escapeHtml(field.label)}</td><td>${typeLabel[field.type] || escapeHtml(field.type)}</td><td>${field.required ? "☑ จำเป็นต้องกรอก" : "☐ ไม่บังคับ"}</td></tr>`).join("")}</tbody></table></div></section><section class="custom-detail-section data-detail-card"><div class="detail-section-heading"><div><h3>ข้อมูลในชุดนี้</h3><p>แสดงรายละเอียดที่ถูกนำเข้าและบันทึกไว้ทั้งหมด</p></div><input type="search" placeholder="⌕ ค้นหาข้อมูลในตาราง" data-detail-search></div><div class="fixed-table-wrap"><table class="fixed-data-table"><thead><tr>${headers}</tr></thead><tbody>${rows}</tbody></table></div></section><section class="custom-detail-section custom-version-history"><div class="detail-section-heading"><div><h3>ประวัติ Version</h3><p>แสดง 3 Version ล่าสุด กดดูเพิ่มเติมเพื่อดูประวัติทั้งหมด</p></div><span>${versions.length} Version</span></div><div class="version-history-cards">${versionCards}</div>${moreVersionsButton ? `<div class="custom-version-more-wrap">${moreVersionsButton}</div>` : ""}</section></section>`;
    list.querySelector("[data-detail-search]").addEventListener("input", event => {
      const query = event.target.value.trim().toLowerCase();
      list.querySelectorAll(".data-detail-card tbody tr").forEach(row => row.hidden = Boolean(query) && !row.textContent.toLowerCase().includes(query));
    });
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
    const cards = versions.map(version => versionCardMarkup(version, activeDataset.editable)).join("") || '<p class="custom-empty">ยังไม่มีประวัติ Version</p>';
    const dialog = dialogShell(`ประวัติ Version ทั้งหมด (${versions.length})`, `<div class="custom-version-history version-history-modal"><div class="version-history-cards">${cards}</div></div>`);
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
    const dialog = dialogShell("แก้ไขข้อมูล", `<form class="manual-record-form"><div class="modal-info">เมื่อบันทึก ระบบจะสร้าง Version ใหม่และเก็บข้อมูลเดิมไว้ในประวัติ</div><div class="manual-fixed-grid">${fields}</div><label class="record-change-note">รายละเอียดการแก้ไข<input name="change_note" placeholder="ระบุรายละเอียดที่แก้ไข"></label><p class="modal-status" data-status></p><footer><button type="button" class="button-link" data-cancel>ยกเลิก</button><button class="data-layer-add" type="submit">บันทึกการแก้ไข</button></footer></form>`);
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
    if (!window.confirm("ยืนยันลบรายการนี้? ข้อมูลเดิมจะยังอยู่ในประวัติ Version")) return;
    try {
      const response = await fetch(`/imported_datasets/${activeDataset.id}/records/${position}`, { method: "DELETE", headers: { Accept: "application/json", "X-CSRF-Token": csrfToken } });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "ไม่สามารถลบข้อมูลได้");
      await reloadActiveDataset();
    } catch (error) { window.alert(error.message); }
  };
  const deleteCustomDataset = async () => {
    if (!activeDataset?.editable || !window.confirm(`ยืนยันลบชุดข้อมูล “${activeDataset.name}”? ข้อมูลและประวัติ Version ทั้งหมดจะถูกลบ`)) return;
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
      if (!response.ok) throw new Error(version.error || "ไม่สามารถโหลดข้อมูล Version ได้");
      const headers = version.schema.map(field => `<th>${escapeHtml(field.label)}</th>`).join("");
      const rows = version.records.map(record => `<tr>${version.schema.map(field => `<td>${escapeHtml(record[field.key] ?? "—")}</td>`).join("")}</tr>`).join("") || `<tr><td colspan="${version.schema.length}">ไม่มีข้อมูลใน Version นี้</td></tr>`;
      dialogShell(`ข้อมูล Version ${version.version_number}`, `<div class="version-preview-modal fixed-table-wrap"><table class="fixed-data-table"><thead><tr>${headers}</tr></thead><tbody>${rows}</tbody></table></div>`);
    } catch (error) { window.alert(error.message); }
  };
  const restoreVersion = async url => {
    if (!window.confirm("ยืนยันสร้าง Version ใหม่จากข้อมูลชุดนี้?")) return;
    try {
      const response = await fetch(url, { method: "POST", headers: { Accept: "application/json", "X-CSRF-Token": csrfToken } });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "ไม่สามารถสร้าง Version ได้");
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
  list.addEventListener("click", async event => {
    if (event.target.closest("[data-custom-back]")) { window.location.assign("/imported_datasets"); return; }
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
    window.location.assign(row.dataset.detailUrl);
  });
  list.addEventListener("keydown", event => {
    if ((event.key === "Enter" || event.key === " ") && event.target.matches("[data-custom-row]")) {
      event.preventDefault();
      event.target.click();
    }
  });
  if (initialDetailUrl) {
    fetch(initialDetailUrl, { headers: { Accept: "application/json" } })
      .then(response => { if (!response.ok) throw new Error(); return response.json(); })
      .then(renderDetail)
      .catch(() => window.alert("ไม่สามารถเปิดรายละเอียดชุดข้อมูลได้"));
  }
});
