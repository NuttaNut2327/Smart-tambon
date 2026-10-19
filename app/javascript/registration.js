// Registration wizard: cascading area pickers with availability, live duplicate checks, read-before-accept and OTP timers.
document.addEventListener("DOMContentLoaded", () => {
  const lookupUrl = "/register/lookup";
  const getJson = async url => (await fetch(url, { headers: { Accept: "application/json" } })).json();
  const option = (value, label, extra = {}) => Object.assign(document.createElement("option"), { value, textContent: label, ...extra });

  // Step 1: province → district → subdistrict, each subdistrict marked with whether it can be registered.
  const areaForm = document.querySelector("[data-area-form]");
  if (areaForm) {
    const province = areaForm.querySelector("[data-area-province]");
    const district = areaForm.querySelector("[data-area-district]");
    const subdistrict = areaForm.querySelector("[data-area-subdistrict]");
    const status = areaForm.querySelector("[data-area-status]");
    const submit = areaForm.querySelector("[data-area-submit]");
    const statusText = { available: "", taken: " — มีผู้ดูแลแล้ว", pending: " — มีคำขอรออนุมัติ" };
    const showStatus = () => {
      const selected = subdistrict.selectedOptions[0];
      const state = selected?.dataset.status;
      status.hidden = !state;
      status.className = `registration-area-status ${state || ""}`;
      status.textContent = { available: "✓ ตำบลนี้ลงทะเบียนได้", taken: "ตำบลนี้มีผู้ดูแลในระบบแล้ว — หากต้องการเข้าร่วม โปรดติดต่อผู้ดูแลของหน่วยงานหรือผู้ดูแลระบบ", pending: "ตำบลนี้มีคำขอลงทะเบียนที่รออนุมัติอยู่แล้ว" }[state] || "";
      submit.disabled = state !== "available";
    };
    const loadSubdistricts = async (code, selected) => {
      subdistrict.disabled = true;
      subdistrict.replaceChildren(option("", "กำลังโหลด…"));
      const items = await getJson(`${lookupUrl}?district_code=${encodeURIComponent(code)}`);
      subdistrict.replaceChildren(option("", "เลือกตำบล"), ...items.map(item => {
        const node = option(item.id, `${item.name}${statusText[item.status] || ""}`);
        node.dataset.status = item.status;
        return node;
      }));
      subdistrict.disabled = false;
      if (selected) subdistrict.value = selected;
      showStatus();
    };
    const loadDistricts = async (id, selected, selectedSubdistrict) => {
      district.disabled = true;
      district.replaceChildren(option("", "กำลังโหลด…"));
      subdistrict.disabled = true;
      subdistrict.replaceChildren(option("", "เลือกอำเภอก่อน"));
      const items = await getJson(`${lookupUrl}?province_id=${encodeURIComponent(id)}`);
      district.replaceChildren(option("", "เลือกอำเภอ"), ...items.map(item => option(item.code, item.name)));
      district.disabled = false;
      if (selected) { district.value = selected; await loadSubdistricts(selected, selectedSubdistrict); }
      showStatus();
    };
    getJson(lookupUrl).then(async items => {
      province.replaceChildren(option("", "เลือกจังหวัด"), ...items.map(item => option(item.id, item.name)));
      if (province.dataset.selected) { province.value = province.dataset.selected; await loadDistricts(province.value, district.dataset.selected, subdistrict.dataset.selected); }
    });
    province.addEventListener("change", () => province.value && loadDistricts(province.value));
    district.addEventListener("change", () => district.value && loadSubdistricts(district.value));
    subdistrict.addEventListener("change", showStatus);
    submit.disabled = true;
  }

  // Step 3: live checks that the username, email and phone are not already used.
  document.querySelectorAll("[data-check]").forEach(input => {
    const result = document.querySelector(`[data-check-result="${input.dataset.check}"]`);
    let timer;
    const check = async () => {
      if (!input.value.trim()) { result.textContent = ""; result.className = ""; return; }
      const response = await getJson(`/register/check?field=${input.dataset.check}&value=${encodeURIComponent(input.value.trim())}`);
      result.textContent = response.ok ? "✓ ใช้ได้" : response.message;
      result.className = response.ok ? "ok" : "error";
      input.setCustomValidity(response.ok ? "" : response.message);
    };
    input.addEventListener("input", () => { clearTimeout(timer); input.setCustomValidity(""); timer = setTimeout(check, 450); });
    if (input.value) check();
  });
  const password = document.querySelector("[data-password]");
  const confirmation = document.querySelector("[data-password-confirmation]");
  const syncPassword = () => {
    if (!password || !confirmation) return;
    const weak = password.value && !(password.value.length >= 8 && /[A-Za-z]/.test(password.value) && /\d/.test(password.value));
    password.setCustomValidity(weak ? "รหัสผ่านต้องยาวอย่างน้อย 8 ตัว และมีทั้งตัวอักษรและตัวเลข" : "");
    confirmation.setCustomValidity(password.value && confirmation.value !== password.value ? "ยืนยันรหัสผ่านไม่ตรงกัน" : "");
  };
  password?.addEventListener("input", syncPassword);
  confirmation?.addEventListener("input", syncPassword);

  // Step 4: each acceptance checkbox unlocks only after its document has been scrolled to the end.
  document.querySelectorAll("[data-must-read]").forEach(doc => {
    const checkbox = document.querySelector(`[data-accept="${doc.dataset.mustRead}"] input`);
    const unlock = () => {
      if (doc.scrollTop + doc.clientHeight >= doc.scrollHeight - 8) {
        checkbox.disabled = false;
        doc.classList.add("read");
      }
    };
    doc.addEventListener("scroll", unlock);
    unlock();
  });

  // Step 5: countdown for expiry and for when a new code can be requested.
  const meta = document.querySelector("[data-otp-expires]");
  if (meta) {
    const expires = new Date(meta.dataset.otpExpires), resend = new Date(meta.dataset.otpResend);
    const channels = document.querySelectorAll(".registration-channel");
    const tick = () => {
      const now = new Date(), left = Math.max(0, Math.round((expires - now) / 1000)), wait = Math.max(0, Math.round((resend - now) / 1000));
      meta.textContent = left ? `รหัสหมดอายุใน ${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")} นาที${wait ? ` · ขอรหัสใหม่ได้ใน ${wait} วินาที` : " · ขอรหัสใหม่ได้"}` : "รหัสหมดอายุแล้ว กรุณาขอรหัสใหม่";
      channels.forEach(button => { if (!button.dataset.unavailable) button.disabled = wait > 0; });
    };
    channels.forEach(button => { if (button.disabled) button.dataset.unavailable = "true"; });
    tick();
    setInterval(tick, 1000);
  }
});
