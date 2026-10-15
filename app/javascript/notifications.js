// Notification settings pages: template variable chips + live preview, test-page mode switching,
// Telegram/Signal chat lookup, and copy-to-clipboard for the LINE webhook URL.
(() => {
  const render = (body, variables) => String(body || "")
    .replace(/\{\{\s*([a-z_]+)\s*\}\}/g, (_, name) => (variables[name] ?? "").toString())
    .replace(/\n{3,}/g, "\n\n").trim();

  const initTemplateEditor = (root) => {
    const body = root.querySelector("[data-notify-body]");
    const preview = root.querySelector("[data-notify-preview]");
    const sample = JSON.parse(root.dataset.sample || "{}");
    const update = () => { preview.textContent = render(body.value, sample) || "(ข้อความว่าง)"; };
    body.addEventListener("input", update);
    document.querySelectorAll("[data-variable]").forEach((chip) => chip.addEventListener("click", () => {
      const token = `{{${chip.dataset.variable}}}`;
      const start = body.selectionStart ?? body.value.length;
      const end = body.selectionEnd ?? start;
      body.setRangeText(token, start, end, "end");
      body.focus();
      update();
    }));
    update();
  };

  const initTestForm = (form) => {
    const tag = form.querySelector("select[name=tag]");
    const sync = () => {
      const mode = form.querySelector("[data-notify-mode]:checked")?.value;
      form.querySelectorAll("[data-notify-show]").forEach((node) => {
        const tokens = node.dataset.notifyShow.split(" ");
        node.hidden = !(tokens.includes(mode) || (tokens.includes("announcement") && tag?.value === "announcement"));
      });
      let any = false;
      form.querySelectorAll("[data-channel-tags]").forEach((chip) => {
        const match = chip.dataset.channelTags.split(" ").includes(tag?.value);
        chip.hidden = !match;
        any ||= match;
      });
      const none = form.querySelector("[data-notify-no-target]");
      if (none) none.hidden = any;
    };
    form.querySelectorAll("[data-notify-mode]").forEach((radio) => radio.addEventListener("change", sync));
    tag?.addEventListener("change", sync);
    form.querySelector("[data-notify-send]")?.addEventListener("click", (event) => {
      if (!confirm("ส่งข้อความทดสอบเข้ากลุ่มจริงใช่ไหม?")) event.preventDefault();
    });
    sync();
  };

  const initLookup = (box) => {
    const results = box.querySelector("[data-notify-lookup-results]");
    const target = document.querySelector("[data-notify-target]");
    const token = document.querySelector("[data-notify-token]");
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
    box.querySelector("[data-notify-lookup-button]").addEventListener("click", async () => {
      results.replaceChildren(Object.assign(document.createElement("li"), { textContent: "กำลังค้นหา…" }));
      const telegram = box.dataset.notifyLookup === "telegram";
      try {
        const response = await fetch(box.dataset.url, {
          method: telegram ? "POST" : "GET",
          headers: { Accept: "application/json", "Content-Type": "application/json", "X-CSRF-Token": csrf },
          body: telegram ? JSON.stringify({ token: token?.value || "", channel_id: box.dataset.channelId || "" }) : undefined
        });
        const data = await response.json();
        if (!response.ok) throw new Error(data.error || `ผิดพลาด (${response.status})`);
        if (!data.length) {
          results.replaceChildren(Object.assign(document.createElement("li"), { textContent: telegram ? "ไม่พบ — เพิ่มบอทเข้ากลุ่มแล้วพิมพ์ข้อความในกลุ่มก่อน แล้วลองใหม่" : "ไม่พบกลุ่ม" }));
          return;
        }
        results.replaceChildren(...data.map((chat) => {
          const item = document.createElement("li");
          const pick = document.createElement("button");
          pick.type = "button";
          pick.className = "button-link";
          pick.textContent = "ใช้ค่านี้";
          pick.addEventListener("click", () => { target.value = chat.id; });
          const label = document.createElement("span");
          label.textContent = `${chat.title || "(ไม่มีชื่อ)"} · ${chat.type} · ${chat.id}`;
          item.append(label, pick);
          return item;
        }));
      } catch (error) {
        results.replaceChildren(Object.assign(document.createElement("li"), { textContent: error.message, className: "notify-error" }));
      }
    });
  };

  const init = () => {
    document.querySelectorAll("[data-notify-template-editor]").forEach(initTemplateEditor);
    document.querySelectorAll("[data-notify-test-form]").forEach(initTestForm);
    document.querySelectorAll("[data-notify-lookup]").forEach(initLookup);
    document.querySelectorAll("[data-copy-button]").forEach((button) => button.addEventListener("click", () => {
      const text = button.parentElement.querySelector("[data-copy-source]")?.textContent;
      navigator.clipboard?.writeText(text).then(() => { button.lastChild.textContent = "คัดลอกแล้ว"; });
    }));
  };

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
