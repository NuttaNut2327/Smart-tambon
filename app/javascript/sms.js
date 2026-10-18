// "ส่ง SMS" modal on the incident detail: choose a mode, preview (GET send_sms), send (POST send_sms&ajax=1)
// and show the result — phone, the link that was sent (copy/open) and the provider's status — without leaving the page.
(() => {
  const text = (tag, value, className) => Object.assign(document.createElement(tag), { textContent: value ?? "", className: className || "" });

  const init = (dialog) => {
    if (dialog.dataset.smsReady) return;
    dialog.dataset.smsReady = "1";
    const url = dialog.dataset.url;
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
    const template = dialog.querySelector("[data-sms-template]");
    const previewLink = dialog.querySelector("[data-sms-preview-link]");
    const result = dialog.querySelector("[data-sms-result]");
    const send = dialog.querySelector("[data-sms-send]");
    const mode = () => dialog.querySelector("[data-sms-mode]:checked")?.value || "tracking";
    const withParams = (extra) => `${url}${url.includes("?") ? "&" : "?"}${new URLSearchParams({ mode: mode(), ajax: "1", ...extra })}`;

    const preview = async () => {
      template.textContent = "กำลังโหลดตัวอย่าง…";
      try {
        const response = await fetch(withParams({}), { headers: { Accept: "application/json" }, credentials: "same-origin" });
        const data = await response.json();
        if (!response.ok) throw new Error(data.error || `ผิดพลาด (${response.status})`);
        template.textContent = data.template;
        previewLink.textContent = data.link || "(ยังไม่ได้ตั้งค่า host_url)";
      } catch (error) {
        template.textContent = error.message;
      }
    };

    const showResult = (data) => {
      result.hidden = false;
      result.className = `sms-result ${data.ok ? "ok" : "fail"}`;
      const rows = [text("b", data.ok ? "ส่ง SMS สำเร็จ" : "ส่ง SMS ไม่สำเร็จ")];
      if (data.error) rows.push(text("p", data.error));
      const dl = document.createElement("dl");
      const add = (label, node) => { const wrap = document.createElement("div"); wrap.append(text("dt", label), node); dl.append(wrap); };
      add("เบอร์ปลายทาง", text("dd", data.phone || "-"));
      if (data.link) {
        const dd = document.createElement("dd");
        const link = Object.assign(document.createElement("a"), { href: data.link, target: "_blank", rel: "noopener noreferrer", textContent: data.link });
        const copy = Object.assign(document.createElement("button"), { type: "button", className: "incident-secondary-action sms-copy", textContent: "คัดลอกลิงก์" });
        copy.addEventListener("click", () => navigator.clipboard?.writeText(data.link).then(() => { copy.textContent = "คัดลอกแล้ว"; }));
        dd.append(link, copy);
        add("ลิงก์ที่ส่ง", dd);
      }
      add("สถานะจากผู้ให้บริการ", text("dd", `HTTP ${data.status || "-"}${data.code ? ` · code ${data.code}` : ""}${data.provider?.detail ? ` · ${data.provider.detail}` : ""}`));
      rows.push(dl);
      if (data.provider && Object.keys(data.provider).length) {
        const details = document.createElement("details");
        details.append(text("summary", "ข้อมูลตอบกลับทั้งหมด"), text("pre", JSON.stringify(data.provider, null, 2)));
        rows.push(details);
      }
      result.replaceChildren(...rows);
    };

    send.addEventListener("click", async () => {
      if (!confirm("ส่ง SMS ถึงผู้แจ้งตอนนี้?")) return;
      send.disabled = true;
      const label = send.lastChild.textContent;
      send.lastChild.textContent = "กำลังส่ง…";
      try {
        const response = await fetch(withParams({}), { method: "POST", credentials: "same-origin", headers: { Accept: "application/json", "X-CSRF-Token": csrf } });
        const data = await response.json().catch(() => ({ ok: false, error: `ผิดพลาด (${response.status})` }));
        showResult(data);
      } catch (error) {
        showResult({ ok: false, error: error.message });
      } finally {
        send.lastChild.textContent = label;
        // Keep the button off briefly to avoid double sends; the server enforces its own cooldown too.
        setTimeout(() => { send.disabled = false; }, 5000);
      }
    });

    dialog.querySelectorAll("[data-sms-mode]").forEach((radio) => radio.addEventListener("change", preview));
    dialog.addEventListener("smsopen", () => { result.hidden = true; preview(); });
  };

  document.addEventListener("click", (event) => {
    const opener = event.target.closest("[data-sms-open]");
    if (!opener || opener.disabled) return;
    const dialog = document.getElementById(opener.dataset.smsOpen);
    if (!dialog) return;
    init(dialog);
    dialog.showModal();
    dialog.dispatchEvent(new Event("smsopen"));
  });
})();
