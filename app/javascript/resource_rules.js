document.addEventListener("DOMContentLoaded", () => {
  const workspace = document.querySelector(".rules-workspace");
  const dialog = document.querySelector("[data-rule-wizard]");
  if (!workspace || !dialog) return;

  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, character => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" }[character]));
  const resourceOptions = JSON.parse(workspace.dataset.ruleResourceOptions || "[]");
  const variableLabels = { water_level: "ระดับน้ำ", rainfall: "ปริมาณฝน", wind_speed: "ความเร็วลม", hotspot_count: "จำนวน Hotspot", population: "จำนวนประชากร", households: "จำนวนครัวเรือน", area: "พื้นที่" };
  const variableUnits = { water_level: "ม.", rainfall: "มม.", wind_speed: "กม./ชม.", hotspot_count: "จุด", population: "คน", households: "ครัวเรือน", area: "ตร.กม." };
  const comparatorLabels = { gte: "มากกว่าหรือเท่ากับ", gt: "มากกว่า", lte: "น้อยกว่าหรือเท่ากับ", lt: "น้อยกว่า", eq: "เท่ากับ" };
  const basisLabels = { population: "จำนวนประชากร", households: "จำนวนครัวเรือน", area: "พื้นที่ที่ได้รับผลกระทบ", villages: "จำนวนหมู่บ้าน" };
  const areaUnitLabels = { sqm: "ตร.ม.", sqkm: "ตร.กม.", rai: "ไร่" };
  const unitOptions = ["คน", "คัน", "เครื่อง", "ลำ", "ชุด", "ลิตร", "มื้อ", "ทีม"];
  const titles = ["ข้อมูลกฎ", "เงื่อนไขในการคำนวณ", "สูตรทรัพยากร", "ตรวจสอบและเปิดใช้"];
  let step = 1;
  let draft;
  let editingId = null;

  const blankDraft = () => ({ name: "", disaster_type: "flood", severity: "watch", description: "", active: true, conditions: [{ variable: "water_level", comparator: "gte", value: "" }], formulas: [{ resource: resourceOptions[0]?.label || "", amount: "1", unit: "คัน", basis: "population", per_value: "1", basis_unit: "person" }] });
  const options = (items, selected) => Object.entries(items).map(([value, label]) => `<option value="${escapeHtml(value)}" ${value === selected ? "selected" : ""}>${escapeHtml(label)}</option>`).join("");
  const resourceSelectOptions = selected => resourceOptions.length ? resourceOptions.map(item => `<option value="${escapeHtml(item.label)}" ${item.label === selected ? "selected" : ""}>${escapeHtml(item.label)} · ${item.source_type === "workforce" ? "ทีมงาน" : "ทรัพยากร"}</option>`).join("") : '<option value="">ยังไม่มีข้อมูลทรัพยากรหรือทีมงาน</option>';

  const collectCurrentStep = () => {
    if (step === 1) {
      draft.name = dialog.querySelector('[name="rule_name"]')?.value.trim() || "";
      draft.disaster_type = dialog.querySelector('[name="disaster_type"]')?.value || "flood";
      draft.severity = dialog.querySelector('[name="severity"]')?.value || "watch";
      draft.description = dialog.querySelector('[name="description"]')?.value.trim() || "";
    } else if (step === 2) {
      draft.conditions = [...dialog.querySelectorAll("[data-condition-row]")].map(row => {
        const variable = row.querySelector("[data-condition-variable]").value;
        const condition = { variable, comparator: row.querySelector("[data-condition-comparator]").value, value: row.querySelector("[data-condition-value]").value };
        if (variable === "hotspot_count") {
          condition.area_value = row.querySelector("[data-condition-area-value]")?.value || "";
          condition.area_unit = row.querySelector("[data-condition-area-unit]")?.value || "sqkm";
        }
        return condition;
      });
    } else if (step === 3) {
      draft.formulas = [...dialog.querySelectorAll("[data-formula-row]")].map(row => ({ resource: row.querySelector("[data-formula-resource]").value, amount: row.querySelector("[data-formula-amount]").value, unit: row.querySelector("[data-formula-unit]").value, basis: row.querySelector("[data-formula-basis]").value, per_value: row.querySelector("[data-formula-per]").value, basis_unit: row.querySelector("[data-formula-basis-unit]")?.value || row.querySelector("[data-formula-basis-unit-label]")?.dataset.unit || "" }));
    } else if (step === 4) {
      draft.active = dialog.querySelector("[data-rule-active]")?.checked ?? true;
    }
  };

  const validateStep = () => {
    collectCurrentStep();
    if (step === 1 && !draft.name) return "กรุณากรอกชื่อกฎ";
    if (step === 2 && (!draft.conditions.length || draft.conditions.some(item => item.value === "" || Number(item.value) < 0))) return "กรุณากรอกค่าตัวเลขของทุกเงื่อนไข";
    if (step === 2 && draft.conditions.some(item => item.variable === "hotspot_count" && (item.area_value === "" || Number(item.area_value) <= 0))) return "กรุณาระบุขนาดพื้นที่สำหรับเงื่อนไขจำนวน Hotspot";
    if (step === 3 && (!draft.formulas.length || draft.formulas.some(item => !item.resource || Number(item.amount) <= 0 || Number(item.per_value) <= 0))) return resourceOptions.length ? "กรุณากรอกสูตรทรัพยากรให้ครบ" : "ยังไม่มีข้อมูลทรัพยากรหรือทีมงาน กรุณานำเข้าข้อมูลก่อนสร้างสูตร";
    return "";
  };

  const hotspotAreaControl = item => item.variable === "hotspot_count" ? `<div class="condition-area-control"><span>ในพื้นที่</span><input type="number" min="0.01" step="any" value="${escapeHtml(item.area_value || "")}" placeholder="ขนาดพื้นที่" data-condition-area-value><select data-condition-area-unit>${options(areaUnitLabels, item.area_unit || "sqkm")}</select></div>` : '<span class="condition-area-empty">—</span>';
  const conditionDescription = item => {
    const base = `${variableLabels[item.variable]} ${comparatorLabels[item.comparator]} ${item.value} ${variableUnits[item.variable]}`;
    return item.variable === "hotspot_count" ? `${base} ในพื้นที่ ${item.area_value} ${areaUnitLabels[item.area_unit || "sqkm"]}` : base;
  };
  const conditionRow = (item, index) => `<div class="rule-builder-row condition-row ${item.variable === "hotspot_count" ? "has-area" : ""}" data-condition-row><select data-condition-variable>${options(variableLabels, item.variable)}</select><select data-condition-comparator>${options(comparatorLabels, item.comparator)}</select><input type="number" min="0" step="any" value="${escapeHtml(item.value)}" placeholder="ระบุจำนวน" data-condition-value><span data-condition-unit>${escapeHtml(variableUnits[item.variable])}</span>${hotspotAreaControl(item)}<button type="button" data-remove-row="condition" data-index="${index}" aria-label="ลบ">×</button></div>`;
  const basisUnitControl = item => item.basis === "area" ? `<select data-formula-basis-unit>${options(areaUnitLabels, item.basis_unit || "sqkm")}</select>` : `<span class="formula-basis-unit" data-formula-basis-unit-label data-unit="${item.basis === "population" ? "person" : item.basis}">${item.basis === "population" ? "คน" : item.basis === "households" ? "ครัวเรือน" : "หมู่บ้าน"}</span>`;
  const formulaDenominator = item => {
    const amount = Number(item.per_value || 1);
    if (item.basis === "area") return `พื้นที่ ${amount.toLocaleString()} ${areaUnitLabels[item.basis_unit || "sqkm"]}`;
    const unit = item.basis === "population" ? "คน" : item.basis === "households" ? "ครัวเรือน" : "หมู่บ้าน";
    return amount === 1 ? unit : `${amount.toLocaleString()} ${unit}`;
  };
  const formulaRow = (item, index) => `<div class="rule-builder-row formula-row" data-formula-row><select data-formula-resource>${resourceSelectOptions(item.resource)}</select><input type="number" min="0.01" step="any" value="${escapeHtml(item.amount)}" data-formula-amount><select data-formula-unit>${unitOptions.map(unit => `<option ${unit === item.unit ? "selected" : ""}>${unit}</option>`).join("")}</select><span>ต่อ</span><input type="number" min="0.01" step="any" value="${escapeHtml(item.per_value || 1)}" data-formula-per><select data-formula-basis>${options(basisLabels, item.basis)}</select>${basisUnitControl(item)}<button type="button" data-remove-row="formula" data-index="${index}" aria-label="ลบ">×</button></div>`;

  const render = () => {
    dialog.querySelector("[data-rule-wizard-kicker]").textContent = editingId ? "แก้ไขกฎการประเมิน" : "สร้างกฎการประเมินใหม่";
    dialog.querySelector("[data-rule-wizard-title]").textContent = titles[step - 1];
    dialog.querySelector("[data-rule-step-count]").textContent = `ขั้นตอน ${step} จาก 4`;
    dialog.querySelectorAll(".rule-wizard-steps li").forEach((item, index) => { item.classList.toggle("active", index + 1 === step); item.classList.toggle("complete", index + 1 < step); item.querySelector("span").textContent = index + 1 < step ? "✓" : index + 1; });
    const body = dialog.querySelector("[data-rule-wizard-body]");
    if (step === 1) body.innerHTML = `<div class="rule-form-grid"><label>ชื่อกฎ *<input name="rule_name" value="${escapeHtml(draft.name)}" placeholder="เช่น กฎน้ำท่วมชุมชนริมแม่น้ำ"></label><div class="rule-form-columns"><label>ประเภทภัย *<select name="disaster_type"><option value="flood" ${draft.disaster_type === "flood" ? "selected" : ""}>น้ำท่วม</option><option value="fire" ${draft.disaster_type === "fire" ? "selected" : ""}>ไฟป่า</option><option value="wind" ${draft.disaster_type === "wind" ? "selected" : ""}>วาตภัย</option><option value="drought" ${draft.disaster_type === "drought" ? "selected" : ""}>ภัยแล้ง</option><option value="other" ${draft.disaster_type === "other" ? "selected" : ""}>อื่น ๆ</option></select></label><label>ระดับความรุนแรง *<select name="severity"><option value="watch" ${draft.severity === "watch" ? "selected" : ""}>เฝ้าระวัง</option><option value="urgent" ${draft.severity === "urgent" ? "selected" : ""}>เร่งด่วน</option><option value="critical" ${draft.severity === "critical" ? "selected" : ""}>วิกฤต</option></select></label></div><label>คำอธิบายเพิ่มเติม<textarea name="description" rows="4" placeholder="อธิบายวัตถุประสงค์และการใช้งานกฎนี้">${escapeHtml(draft.description)}</textarea></label></div>`;
    if (step === 2) body.innerHTML = `<div class="rule-wizard-info"><b>กำหนดเงื่อนไขที่ทำให้กฎเริ่มทำงาน</b><small>เมื่อเลือกจำนวน Hotspot ต้องระบุขนาดพื้นที่ที่ใช้ตรวจนับด้วย</small></div><div class="rule-builder-head condition-head"><span>ตัวแปร</span><span>เงื่อนไข</span><span>ค่า</span><span>หน่วย</span><span>พื้นที่อ้างอิง</span></div><div data-condition-rows>${draft.conditions.map(conditionRow).join("")}</div><button type="button" class="rule-add-row" data-add-condition>＋ เพิ่มเงื่อนไข</button>`;
    if (step === 3) body.innerHTML = `<div class="rule-wizard-info"><b>กำหนดทรัพยากรที่ต้องใช้</b><small>รายการทรัพยากรและทีมงานมาจากข้อมูลที่คุณเคยนำเข้าไว้</small></div><div class="rule-builder-head formula-head"><span>ทรัพยากรในพื้นที่</span><span>จำนวน</span><span>หน่วย</span><span></span><span>ทุกจำนวน</span><span>ข้อมูลประกอบ</span><span>หน่วยคำนวณ</span></div><div data-formula-rows>${draft.formulas.map(formulaRow).join("")}</div><button type="button" class="rule-add-row" data-add-formula>＋ เพิ่มทรัพยากร</button><div class="rule-formula-preview"><b>สูตรที่ระบบจะใช้</b>${draft.formulas.map(item => `<p>= ${escapeHtml(item.resource || "ทรัพยากร")} ${escapeHtml(item.amount)} ${escapeHtml(item.unit)} / ${escapeHtml(formulaDenominator(item))}</p>`).join("")}</div>`;
    if (step === 4) body.innerHTML = `<div class="rule-review-title"><div class="rule-icon">⌁</div><div><b>${escapeHtml(draft.name)}</b><small>${escapeHtml({ flood: "น้ำท่วม", fire: "ไฟป่า", wind: "วาตภัย", drought: "ภัยแล้ง", other: "อื่น ๆ" }[draft.disaster_type])} · ${escapeHtml({ watch: "เฝ้าระวัง", urgent: "เร่งด่วน", critical: "วิกฤต" }[draft.severity])}</small></div><label class="rule-switch"><input type="checkbox" data-rule-active ${draft.active ? "checked" : ""}><span></span><b>เปิดใช้ทันที</b></label></div><dl class="rule-review-list"><div><dt>คำอธิบาย</dt><dd>${escapeHtml(draft.description || "—")}</dd></div><div><dt>เงื่อนไข</dt><dd>${draft.conditions.map(item => escapeHtml(conditionDescription(item))).join(" หรือ ")}</dd></div><div><dt>ทรัพยากรในสูตร</dt><dd>${draft.formulas.length} รายการ</dd></div><div><dt>วิธีคำนวณ</dt><dd>${draft.formulas.map(item => `${escapeHtml(item.resource)} ${escapeHtml(item.amount)} ${escapeHtml(item.unit)} / ${escapeHtml(formulaDenominator(item))}`).join(" · ")}</dd></div></dl><div class="rule-review-example">♢ ตัวอย่าง: ระบบจะคำนวณจำนวนทรัพยากรตามข้อมูลจริงเมื่อเงื่อนไขของกฎเป็นจริง</div>`;
    const back = dialog.querySelector("[data-rule-wizard-back]");
    back.textContent = step === 1 ? "‹ ยกเลิก" : "‹ ย้อนกลับ";
    dialog.querySelector("[data-rule-wizard-next]").textContent = step === 4 ? (editingId ? "บันทึกการแก้ไข" : "สร้างและเปิดใช้กฎ") : "ถัดไป ›";
    dialog.querySelector("[data-rule-wizard-status]").textContent = "";
  };

  const open = () => { editingId = null; draft = blankDraft(); step = 1; render(); dialog.showModal(); };
  const openEdit = payload => { editingId = payload.id; draft = { ...blankDraft(), ...payload, conditions: Array.isArray(payload.conditions) ? payload.conditions : [], formulas: Array.isArray(payload.formulas) ? payload.formulas : [] }; step = 1; render(); dialog.showModal(); };
  const close = () => dialog.close();
  document.querySelector("[data-open-rule-wizard]").addEventListener("click", open);
  document.querySelector("[data-rules-list]").addEventListener("click", event => {
    const editButton = event.target.closest("[data-edit-rule]");
    if (!editButton) return;
    event.preventDefault();
    event.stopPropagation();
    openEdit(JSON.parse(editButton.closest("[data-rule-card]").dataset.rulePayload));
  });
  dialog.querySelector("[data-close-rule-wizard]").addEventListener("click", close);
  dialog.querySelector("[data-rule-wizard-back]").addEventListener("click", () => { if (step === 1) return close(); collectCurrentStep(); step -= 1; render(); });
  dialog.querySelector("[data-rule-wizard-next]").addEventListener("click", async () => {
    const error = validateStep();
    if (error) { dialog.querySelector("[data-rule-wizard-status]").textContent = error; return; }
    if (step < 4) { step += 1; render(); return; }
    const button = dialog.querySelector("[data-rule-wizard-next]");
    button.disabled = true;
    try {
      const body = new FormData(); body.append("resource_rule_payload", JSON.stringify(draft));
      const response = await fetch(editingId ? `/resource_rules/${editingId}` : "/resource_rules", { method: editingId ? "PATCH" : "POST", headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" }, body });
      const payload = await response.json();
      if (!response.ok) throw new Error(payload.error || "ไม่สามารถสร้างกฎได้");
      window.location.assign(payload.redirect_url);
    } catch (saveError) { dialog.querySelector("[data-rule-wizard-status]").textContent = saveError.message; button.disabled = false; }
  });
  dialog.addEventListener("change", event => {
    if (event.target.matches("[data-condition-variable]")) { collectCurrentStep(); const rowIndex = [...dialog.querySelectorAll("[data-condition-row]")].indexOf(event.target.closest("[data-condition-row]")); draft.conditions[rowIndex].variable = event.target.value; if (event.target.value === "hotspot_count") { draft.conditions[rowIndex].area_value ||= "1"; draft.conditions[rowIndex].area_unit ||= "sqkm"; } else { delete draft.conditions[rowIndex].area_value; delete draft.conditions[rowIndex].area_unit; } render(); }
    if (event.target.matches("[data-formula-basis]")) { collectCurrentStep(); const rowIndex = [...dialog.querySelectorAll("[data-formula-row]")].indexOf(event.target.closest("[data-formula-row]")); draft.formulas[rowIndex].basis_unit = event.target.value === "area" ? "sqkm" : event.target.value === "population" ? "person" : event.target.value; draft.formulas[rowIndex].per_value = "1"; render(); }
  });
  dialog.addEventListener("click", event => {
    if (event.target.closest("[data-add-condition]")) { collectCurrentStep(); draft.conditions.push({ variable: "water_level", comparator: "gte", value: "" }); render(); }
    if (event.target.closest("[data-add-formula]")) { collectCurrentStep(); draft.formulas.push({ resource: resourceOptions[0]?.label || "", amount: "1", unit: "คัน", basis: "population", per_value: "1", basis_unit: "person" }); render(); }
    const remove = event.target.closest("[data-remove-row]");
    if (remove) { collectCurrentStep(); const collection = remove.dataset.removeRow === "condition" ? draft.conditions : draft.formulas; if (collection.length > 1) collection.splice(Number(remove.dataset.index), 1); render(); }
  });
});
