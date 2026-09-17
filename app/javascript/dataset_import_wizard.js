document.addEventListener("DOMContentLoaded", () => {
  const token = document.querySelector('meta[name="csrf-token"]')?.content;
  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, character => ({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[character]));
  const request = async (url, options = {}) => {
    const response = await fetch(url, { ...options, headers: { Accept: "application/json", "X-CSRF-Token": token, ...(options.headers || {}) } });
    const payload = response.status === 204 ? {} : await response.json();
    if (!response.ok) throw new Error(payload.error || "ไม่สามารถดำเนินการได้");
    return payload;
  };

  document.querySelector("[data-fixed-search]")?.addEventListener("input", event => {
    const query = event.target.value.trim().toLowerCase();
    document.querySelectorAll("[data-fixed-row]").forEach(row => row.hidden = !row.dataset.search.includes(query));
  });

  document.querySelectorAll("[data-destination-fields]").forEach(container => {
    const target = container.querySelector("[data-target-dataset]");
    const sync = () => container.querySelectorAll("[data-new-dataset-field]").forEach(field => {
      field.hidden = Boolean(target.value);
      field.querySelectorAll("input,select").forEach(input => input.disabled = Boolean(target.value));
    });
    target.addEventListener("change", sync); sync();
  });

  const manualDialog = document.querySelector("#manual-data-dialog");
  document.querySelector("[data-open-manual]")?.addEventListener("click", () => manualDialog.showModal());
  document.querySelectorAll("[data-close-dialog]").forEach(button => button.addEventListener("click", () => button.closest("dialog").close()));
  document.querySelector("#manual-data-form")?.addEventListener("submit", async event => {
    event.preventDefault();
    const form = event.currentTarget, status = form.querySelector("[data-manual-status]"), submit = form.querySelector("[type=submit]");
    status.className = "modal-status"; status.textContent = "กำลังบันทึกข้อมูล…"; submit.disabled = true;
    try {
      const payload = await request("/dataset_import_drafts/manual", { method: "POST", body: new FormData(form) });
      status.textContent = `บันทึกเป็น Version ${payload.version} แล้ว`;
      window.location.assign(payload.redirect_url);
    } catch (error) { status.classList.add("error"); status.textContent = error.message; submit.disabled = false; }
  });

  const editPopulationDialog = document.querySelector("#edit-population-dialog");
  const editPopulationForm = document.querySelector("#edit-population-form");
  document.querySelectorAll("[data-edit-population]").forEach(button => button.addEventListener("click", () => {
    const record = JSON.parse(button.dataset.record);
    editPopulationForm.dataset.url = button.dataset.url;
    editPopulationForm.querySelectorAll("[data-edit-field]").forEach(input => input.value = record[input.dataset.editField] ?? "");
    editPopulationForm.querySelector("[name=change_note]").value = "";
    const status = editPopulationForm.querySelector("[data-edit-status]");
    status.className = "modal-status"; status.textContent = "";
    editPopulationDialog.showModal();
  }));
  editPopulationForm?.addEventListener("submit", async event => {
    event.preventDefault();
    const form = event.currentTarget, status = form.querySelector("[data-edit-status]"), submit = form.querySelector("[type=submit]");
    status.className = "modal-status"; status.textContent = "กำลังบันทึกและสร้าง Version ใหม่…"; submit.disabled = true;
    try {
      const payload = await request(form.dataset.url, { method: "PATCH", body: new FormData(form) });
      status.textContent = `แก้ไขเรียบร้อย เป็น Version ${payload.version}`;
      window.location.assign(payload.redirect_url);
    } catch (error) { status.classList.add("error"); status.textContent = error.message; submit.disabled = false; }
  });
  document.querySelectorAll("[data-delete-population]").forEach(button => button.addEventListener("click", async () => {
    const recordType = document.querySelector(".catalog-hero h2")?.textContent.trim() || "ข้อมูล";
    if (!window.confirm(`ยืนยันลบ${recordType}รายการนี้? ข้อมูลเดิมจะยังอยู่ในประวัติ Version`)) return;
    button.disabled = true;
    try {
      const payload = await request(button.dataset.url, { method: "DELETE" });
      window.location.assign(payload.redirect_url);
    } catch (error) { window.alert(error.message); button.disabled = false; }
  }));

  const resourceTable = document.querySelector(".fixed-data-table");
  if (resourceTable?.querySelector("thead th")?.textContent.trim() === "ชื่อทรัพยากร/อุปกรณ์") {
    const resourceFields = [
      ["name", "ชื่อทรัพยากร/อุปกรณ์", true], ["code", "รหัส", false], ["registration", "ทะเบียน", false],
      ["resource_type", "ประเภท", true], ["status", "สถานะ", false], ["storage_location", "สถานที่เก็บ", false],
      ["responsible_person", "ผู้รับผิดชอบ", false]
    ];
    if (!resourceTable.querySelector(".record-actions-heading")) resourceTable.querySelector("thead tr")?.insertAdjacentHTML("beforeend", '<th class="record-actions-heading">จัดการ</th>');
    const positions = {};
    resourceTable.querySelectorAll("tbody [data-fixed-row]").forEach(row => {
      const datasetLink = row.querySelector(".table-action");
      const match = datasetLink?.getAttribute("href")?.match(/\/imported_datasets\/([^/]+)/);
      if (!match) return;
      const datasetId = match[1], position = positions[datasetId] || 0;
      positions[datasetId] = position + 1;
      const record = Object.fromEntries(resourceFields.map(([key], index) => [key, row.cells[index]?.textContent.trim() === "—" ? "" : row.cells[index]?.textContent.trim()]));
      const url = `/imported_datasets/${datasetId}/records/${position}`;
      row.insertAdjacentHTML("beforeend", `<td class="record-actions"><button type="button" class="record-icon-button edit" title="แก้ไขข้อมูล" aria-label="แก้ไขข้อมูล" data-resource-edit>✎</button><button type="button" class="record-icon-button delete" title="ลบข้อมูล" aria-label="ลบข้อมูล" data-resource-delete>♲</button></td>`);
      row.querySelector("[data-resource-edit]").addEventListener("click", () => openResourceEditor(url, record));
      row.querySelector("[data-resource-delete]").addEventListener("click", event => deleteResourceRecord(event.currentTarget, url));
    });
    const resourceStatusTones = { "พร้อมใช้": "ready", "กำลังใช้งาน": "in-use", "ชำรุด": "damaged" };
    resourceTable.querySelectorAll("tbody [data-fixed-row]").forEach(row => {
      const statusCell = row.cells[4], status = statusCell?.textContent.trim(), tone = resourceStatusTones[status];
      if (tone) statusCell.innerHTML = `<span class="resource-status-badge ${tone}">${escapeHtml(status)}</span>`;
    });

    const editor = document.createElement("dialog");
    editor.className = "dataset-modal";
    editor.innerHTML = `<form><header><div><small>แก้ไขข้อมูลทรัพยากรและอุปกรณ์</small><h2>แก้ไขรายการ</h2></div><button type="button" aria-label="ปิด">×</button></header><div class="modal-info">เมื่อบันทึก ระบบจะสร้าง Version ใหม่และเก็บข้อมูลเดิมไว้ในประวัติ</div><div class="manual-fixed-grid">${resourceFields.map(([key, label, required]) => `<label>${label}${required ? " *" : ""}<input name="record[${key}]" ${required ? "required" : ""}></label>`).join("")}</div><label class="record-change-note">รายละเอียดการแก้ไข<input name="change_note" placeholder="เช่น ปรับสถานะอุปกรณ์"></label><p class="modal-status"></p><footer><button type="button" class="button-link" data-resource-close>ยกเลิก</button><button class="data-layer-add" type="submit">บันทึกเป็น Version ใหม่</button></footer></form>`;
    document.body.append(editor);
    const resourceForm = editor.querySelector("form"), resourceStatus = editor.querySelector(".modal-status");
    const openResourceEditor = (url, record) => {
      resourceForm.dataset.url = url;
      resourceFields.forEach(([key]) => resourceForm.elements[`record[${key}]`].value = record[key] || "");
      resourceForm.elements.change_note.value = ""; resourceStatus.className = "modal-status"; resourceStatus.textContent = "";
      editor.showModal();
    };
    const deleteResourceRecord = async (button, url) => {
      if (!window.confirm("ยืนยันลบข้อมูลทรัพยากร/อุปกรณ์รายการนี้? ข้อมูลเดิมจะยังอยู่ในประวัติ Version")) return;
      button.disabled = true;
      try { const payload = await request(url, { method: "DELETE" }); window.location.assign(payload.redirect_url); }
      catch (error) { window.alert(error.message); button.disabled = false; }
    };
    editor.querySelectorAll("[data-resource-close], header button").forEach(button => button.addEventListener("click", () => editor.close()));
    resourceForm.addEventListener("submit", async event => {
      event.preventDefault(); const submit = resourceForm.querySelector("[type=submit]");
      resourceStatus.className = "modal-status"; resourceStatus.textContent = "กำลังบันทึกและสร้าง Version ใหม่…"; submit.disabled = true;
      try { const payload = await request(resourceForm.dataset.url, { method: "PATCH", body: new FormData(resourceForm) }); window.location.assign(payload.redirect_url); }
      catch (error) { resourceStatus.classList.add("error"); resourceStatus.textContent = error.message; submit.disabled = false; }
    });
  }

  const workforceTable = document.querySelector(".fixed-data-table");
  if (workforceTable?.querySelector("thead th")?.textContent.trim() === "ชื่อทีม") {
    const workforceFields = [
      ["team_name", "ชื่อทีม", true], ["duty", "หน้าที่", true], ["member_count", "จำนวนสมาชิก", true],
      ["ready_count", "พร้อมปฏิบัติงาน", true], ["responsible_area", "พื้นที่รับผิดชอบ", true], ["team_leader", "หัวหน้าทีม", true]
    ];
    if (!workforceTable.querySelector(".record-actions-heading")) workforceTable.querySelector("thead tr")?.insertAdjacentHTML("beforeend", '<th class="record-actions-heading">จัดการ</th>');
    const positions = {};
    workforceTable.querySelectorAll("tbody [data-fixed-row]").forEach(row => {
      const datasetLink = row.querySelector(".table-action");
      const match = datasetLink?.getAttribute("href")?.match(/\/imported_datasets\/([^/]+)/);
      if (!match) return;
      const datasetId = match[1], position = positions[datasetId] || 0;
      positions[datasetId] = position + 1;
      const record = Object.fromEntries(workforceFields.map(([key], index) => [key, row.cells[index]?.textContent.trim() === "—" ? "" : row.cells[index]?.textContent.trim()]));
      const url = `/imported_datasets/${datasetId}/records/${position}`;
      row.insertAdjacentHTML("beforeend", '<td class="record-actions"><button type="button" class="record-icon-button edit" title="แก้ไขข้อมูล" aria-label="แก้ไขข้อมูล" data-workforce-edit>✎</button><button type="button" class="record-icon-button delete" title="ลบข้อมูล" aria-label="ลบข้อมูล" data-workforce-delete>♲</button></td>');
      row.querySelector("[data-workforce-edit]").addEventListener("click", () => openWorkforceEditor(url, record));
      row.querySelector("[data-workforce-delete]").addEventListener("click", event => deleteWorkforceRecord(event.currentTarget, url));
    });

    const editor = document.createElement("dialog");
    editor.className = "dataset-modal";
    editor.innerHTML = `<form><header><div><small>แก้ไขข้อมูลทีมงานและกำลังคน</small><h2>แก้ไขรายการ</h2></div><button type="button" aria-label="ปิด">×</button></header><div class="modal-info">เมื่อบันทึก ระบบจะสร้าง Version ใหม่และเก็บข้อมูลเดิมไว้ในประวัติ</div><div class="manual-fixed-grid">${workforceFields.map(([key, label, required]) => `<label>${label}${required ? " *" : ""}<input name="record[${key}]" ${required ? "required" : ""}></label>`).join("")}</div><label class="record-change-note">รายละเอียดการแก้ไข<input name="change_note" placeholder="เช่น ปรับจำนวนกำลังพลพร้อมปฏิบัติงาน"></label><p class="modal-status"></p><footer><button type="button" class="button-link" data-workforce-close>ยกเลิก</button><button class="data-layer-add" type="submit">บันทึกเป็น Version ใหม่</button></footer></form>`;
    document.body.append(editor);
    const workforceForm = editor.querySelector("form"), workforceStatus = editor.querySelector(".modal-status");
    const openWorkforceEditor = (url, record) => {
      workforceForm.dataset.url = url;
      workforceFields.forEach(([key]) => workforceForm.elements[`record[${key}]`].value = record[key] || "");
      workforceForm.elements.change_note.value = ""; workforceStatus.className = "modal-status"; workforceStatus.textContent = "";
      editor.showModal();
    };
    const deleteWorkforceRecord = async (button, url) => {
      if (!window.confirm("ยืนยันลบข้อมูลทีมงานรายการนี้? ข้อมูลเดิมจะยังอยู่ในประวัติ Version")) return;
      button.disabled = true;
      try { const payload = await request(url, { method: "DELETE" }); window.location.assign(payload.redirect_url); }
      catch (error) { window.alert(error.message); button.disabled = false; }
    };
    editor.querySelectorAll("[data-workforce-close], header button").forEach(button => button.addEventListener("click", () => editor.close()));
    workforceForm.addEventListener("submit", async event => {
      event.preventDefault(); const submit = workforceForm.querySelector("[type=submit]");
      workforceStatus.className = "modal-status"; workforceStatus.textContent = "กำลังบันทึกและสร้าง Version ใหม่…"; submit.disabled = true;
      try { const payload = await request(workforceForm.dataset.url, { method: "PATCH", body: new FormData(workforceForm) }); window.location.assign(payload.redirect_url); }
      catch (error) { workforceStatus.classList.add("error"); workforceStatus.textContent = error.message; submit.disabled = false; }
    });
  }

  const dialog = document.querySelector("#file-import-dialog");
  if (!dialog) return;
  const fileInput = dialog.querySelector("[data-import-file]"), selectedFile = dialog.querySelector("[data-selected-file]");
  const next = dialog.querySelector("[data-wizard-next]"), back = dialog.querySelector("[data-wizard-back]");
  const status = dialog.querySelector("[data-wizard-status]");
  let step = 1, draft = null, busy = false;

  const showStep = number => {
    step = number;
    dialog.querySelectorAll("[data-wizard-step]").forEach(panel => panel.hidden = Number(panel.dataset.wizardStep) !== step);
    dialog.querySelectorAll("[data-step-indicator]").forEach(item => {
      const itemStep = Number(item.dataset.stepIndicator); item.classList.toggle("active", itemStep === step); item.classList.toggle("done", itemStep < step);
    });
    dialog.querySelector("[data-step-count]").textContent = `ขั้นตอน ${step} จาก 6`;
    back.hidden = step === 1 || step === 6; next.hidden = step === 6;
    next.textContent = step === 5 ? "ยืนยันการนำเข้า" : "ดำเนินการต่อ";
    status.textContent = ""; status.classList.remove("error");
  };

  const upload = async () => {
    if (!fileInput.files[0]) throw new Error("กรุณาเลือกไฟล์ที่ต้องการนำเข้า");
    const body = new FormData(); body.append("file", fileInput.files[0]); body.append("data_type", dialog.dataset.selectedType);
    draft = await request("/dataset_import_drafts", { method: "POST", body });
    renderMapping();
  };

  const renderMapping = () => {
    dialog.querySelector("[data-mapping-list]").innerHTML = draft.schema.map(field => {
      const options = ['<option value="">ไม่จับคู่</option>', ...draft.headers.map(header => `<option value="${escapeHtml(header)}" ${draft.mapping[field.key] === header ? "selected" : ""}>${escapeHtml(header)}</option>`)].join("");
      return `<label><span>${escapeHtml(field.label)}${field.required ? " *" : ""}<small>${escapeHtml(field.key)}</small></span><b>→</b><select data-map-key="${escapeHtml(field.key)}">${options}</select><em class="${draft.mapping[field.key] ? "" : "unmatched"}">${draft.mapping[field.key] ? "จับคู่แล้ว" : "ยังไม่จับคู่"}</em></label>`;
    }).join("");
    dialog.querySelectorAll("[data-map-key]").forEach(select => select.addEventListener("change", () => {
      const badge = select.nextElementSibling;
      badge.textContent = select.value ? "จับคู่แล้ว" : "ยังไม่จับคู่";
      badge.classList.toggle("unmatched", !select.value);
    }));
  };

  const validate = async () => {
    const mapping = {};
    dialog.querySelectorAll("[data-map-key]").forEach(select => mapping[select.dataset.mapKey] = select.value);
    const body = new FormData(); Object.entries(mapping).forEach(([key, value]) => body.append(`mapping[${key}]`, value));
    draft = await request(`/dataset_import_drafts/${draft.id}/validate`, { method: "POST", body });
    const validation = draft.validation || {}, ok = !validation.errors?.length;
    dialog.querySelector("[data-validation-result]").innerHTML = `<div class="validation-icon ${ok ? "ok" : "bad"}">${ok ? "✓" : "!"}</div><h3>${ok ? "Validation เสร็จแล้ว" : "พบข้อมูลที่ต้องแก้ไข"}</h3><p>พบข้อมูล ${Number(validation.total || 0).toLocaleString()} รายการ · ${ok ? `ผ่าน ${Number(validation.valid || 0).toLocaleString()}` : `ข้อผิดพลาด ${Number(validation.invalid || 0).toLocaleString()}`}</p>${ok ? "" : `<ul>${validation.errors.map(error => `<li>${escapeHtml(error)}</li>`).join("")}</ul>`}`;
    if (!ok) throw new Error("กรุณาย้อนกลับไปแก้ไข Mapping หรือไฟล์ข้อมูล");
    renderPreview();
  };

  const renderPreview = () => {
    const header = draft.schema.map(field => `<th>${escapeHtml(field.label)}</th>`).join("");
    const rows = draft.records.map(record => `<tr>${draft.schema.map(field => `<td>${escapeHtml(record[field.key] ?? "—")}</td>`).join("")}</tr>`).join("");
    dialog.querySelector("[data-preview-table]").innerHTML = `<table><thead><tr>${header}</tr></thead><tbody>${rows}</tbody></table><small>แสดง ${draft.records.length} จาก ${Number(draft.validation.total || 0).toLocaleString()} รายการ</small>`;
  };

  const finalize = async () => {
    const fields = dialog.querySelector('[data-wizard-step="5"] [data-destination-fields]');
    const body = new FormData(); fields.querySelectorAll("input:not(:disabled),select:not(:disabled)").forEach(input => {
      if ((input.type !== "checkbox" && input.value) || (input.type === "checkbox" && input.checked)) body.append(input.name, input.value);
    });
    const payload = await request(`/dataset_import_drafts/${draft.id}/finalize`, { method: "POST", body });
    dialog.querySelector("[data-finish-message]").textContent = `นำเข้าสำเร็จ ${payload.records.toLocaleString()} รายการ เป็น Version ${payload.version}`;
    dialog.querySelector("[data-finish-link]").href = payload.redirect_url;
  };

  document.querySelector("[data-open-import]")?.addEventListener("click", () => { showStep(1); dialog.showModal(); });
  fileInput.addEventListener("change", () => { const file = fileInput.files[0]; selectedFile.hidden = !file; selectedFile.textContent = file ? `▤ ${file.name} · ${(file.size / 1024).toFixed(1)} KB` : ""; });
  back.addEventListener("click", () => showStep(Math.max(1, step - 1)));
  next.addEventListener("click", async () => {
    if (busy) return; busy = true; next.disabled = true; status.textContent = "กำลังประมวลผล…";
    try {
      if (step === 1) await upload();
      else if (step === 2) await validate();
      else if (step === 3 && draft.validation?.errors?.length) throw new Error("ข้อมูลยังไม่ผ่าน Validation กรุณาย้อนกลับไปแก้ไข");
      else if (step === 5) await finalize();
      showStep(Math.min(6, step + 1));
    } catch (error) { if (step === 2 && draft?.validation) showStep(3); status.classList.add("error"); status.textContent = error.message; }
    finally { busy = false; next.disabled = false; }
  });
  showStep(1);
});
