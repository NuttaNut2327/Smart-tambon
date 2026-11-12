// Notification settings pages: template variable chips + live preview, test-page mode switching,
// Telegram/Signal chat lookup, and copy-to-clipboard for the LINE webhook URL.
(() => {
  const render = (body, variables) => String(body || "")
    .replace(/\{\{\s*([a-z_]+)\s*\}\}/g, (_, name) => (variables[name] ?? "").toString())
    .replace(/\n{3,}/g, "\n\n").trim();

  const initTemplateEditor = (root) => {
    const body = root.querySelector("[data-notify-body]");
    const preview = root.querySelector("[data-notify-preview]");
    const form = root.closest("form");
    const tag = form?.querySelector("[data-notify-tag]");
    const chips = form?.querySelectorAll("[data-variable]") || [];
    const sample = JSON.parse(root.dataset.sample || "{}");
    const update = () => { preview.textContent = render(body.value, sample) || "(ข้อความว่าง)"; };
    const syncVariables = () => {
      const citizen = tag?.value.startsWith("citizen.");
      chips.forEach((chip) => {
        chip.hidden = citizen ? chip.dataset.citizenVariable !== "true" : chip.dataset.staffVariable !== "true";
      });
    };
    body.addEventListener("input", update);
    chips.forEach((chip) => chip.addEventListener("click", () => {
      const token = `{{${chip.dataset.variable}}}`;
      const start = body.selectionStart ?? body.value.length;
      const end = body.selectionEnd ?? start;
      body.setRangeText(token, start, end, "end");
      body.focus();
      update();
    }));
    tag?.addEventListener("change", syncVariables);
    syncVariables();
    update();
  };

  const initTestForm = (form) => {
    const tag = form.querySelector("select[name=tag]");
    const previewButton = form.querySelector("[data-notify-preview]");
    const sendButton = form.querySelector("[data-notify-send]");
    const channelPicker = form.querySelector("[data-notify-channel-picker]");
    const channelSelect = channelPicker?.querySelector("select");
    const preview = form.querySelector("[data-notify-test-preview]");
    const previewSource = form.querySelector("[data-notify-preview-source]");
    const result = form.querySelector("[data-notify-ajax-result]");
    const sync = () => {
      const mode = form.querySelector("[data-notify-mode]:checked")?.value;
      const citizen = tag?.value.startsWith("citizen.");
      form.querySelectorAll("[data-notify-show]").forEach((node) => {
        const tokens = node.dataset.notifyShow.split(" ");
        node.hidden = !(tokens.includes(mode) || (tokens.includes("announcement") && tag?.value === "announcement"));
      });
      form.querySelectorAll("[data-notify-staff-only]").forEach((node) => {
        const tokens = node.dataset.notifyShow?.split(" ") || [];
        const modeVisible = tokens.length === 0 || tokens.includes(mode) || (tokens.includes("announcement") && tag?.value === "announcement");
        node.hidden = citizen || !modeVisible;
      });
      form.querySelectorAll("[data-notify-citizen-only]").forEach((node) => { node.hidden = !citizen; });
      let any = false;
      channelSelect?.querySelectorAll("option[data-channel-tags]").forEach((option) => {
        const match = option.dataset.channelTags.split(" ").includes(tag?.value);
        option.hidden = !match;
        option.disabled = !match;
        if (!match && option.selected) option.selected = false;
        any ||= match;
      });
      const none = form.querySelector("[data-notify-no-target]");
      if (none) none.hidden = citizen || any;
      channelPicker?.dispatchEvent(new CustomEvent("notify:filter"));
    };
    form.querySelectorAll("[data-notify-mode]").forEach((radio) => radio.addEventListener("change", sync));
    tag?.addEventListener("change", () => {
      sync();
      form.requestSubmit(previewButton);
    });
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const submitter = event.submitter;
      const sending = submitter?.dataset.notifySend !== undefined;
      if (sending && !confirm("ส่งข้อความทดสอบจริงใช่ไหม?")) return;

      const body = new FormData(form);
      if (submitter?.name) body.set(submitter.name, submitter.value);
      const csrf = document.querySelector('meta[name="csrf-token"]')?.content;
      [previewButton, sendButton].forEach((button) => { if (button) button.disabled = true; });
      result.textContent = sending ? "กำลังส่งข้อความ…" : "กำลังสร้างตัวอย่าง…";
      result.className = "notify-ajax-result is-loading";

      try {
        const response = await fetch(form.action, {
          method: "POST",
          headers: { Accept: "application/json", "X-CSRF-Token": csrf },
          body
        });
        const data = await response.json();
        if (preview && data.preview !== undefined) preview.textContent = data.preview || "(ข้อความว่าง)";
        if (previewSource && data.preview_source) previewSource.textContent = data.preview_source;
        result.textContent = data.message || (response.ok ? "อัปเดตตัวอย่างแล้ว" : "ดำเนินการไม่สำเร็จ");
        result.className = `notify-ajax-result ${response.ok && data.ok !== false ? "is-success" : "is-error"}`;
      } catch (_error) {
        result.textContent = "เชื่อมต่อระบบไม่สำเร็จ กรุณาลองอีกครั้ง";
        result.className = "notify-ajax-result is-error";
      } finally {
        [previewButton, sendButton].forEach((button) => { if (button) button.disabled = false; });
      }
    });
    sync();
  };

  const initSearchableSelect = (box) => {
    const search = box.querySelector("[data-notify-select-search]");
    const select = box.querySelector("[data-notify-select]");
    if (!search || !select) return;
    const list = document.createElement("div");
    list.className = "notify-combobox-list";
    list.id = `notify-options-${Math.random().toString(36).slice(2)}`;
    list.setAttribute("role", "listbox");
    list.hidden = true;
    search.setAttribute("role", "combobox");
    search.setAttribute("aria-autocomplete", "list");
    search.setAttribute("aria-controls", list.id);
    search.setAttribute("aria-expanded", "false");
    box.append(list);

    const availableOptions = () => Array.from(select.options).slice(1).filter((option) => !option.disabled);
    const close = () => {
      list.hidden = true;
      search.setAttribute("aria-expanded", "false");
    };
    const choose = (option) => {
      select.value = option.value;
      search.value = option.text;
      search.setCustomValidity("");
      select.dispatchEvent(new Event("change", { bubbles: true }));
      close();
    };
    const renderOptions = () => {
      const query = search.value.trim().toLocaleLowerCase("th");
      const matches = availableOptions().filter((option) => !query || option.text.toLocaleLowerCase("th").includes(query));
      const items = matches.map((option) => {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "notify-combobox-option";
        button.setAttribute("role", "option");
        button.setAttribute("aria-selected", String(option.value === select.value));
        button.textContent = option.text;
        button.addEventListener("mousedown", (event) => {
          event.preventDefault();
          choose(option);
        });
        return button;
      });
      if (items.length === 0) {
        const empty = document.createElement("div");
        empty.className = "notify-combobox-empty";
        empty.textContent = "ไม่พบรายการที่ค้นหา";
        items.push(empty);
      }
      list.replaceChildren(...items);
      list.hidden = false;
      search.setAttribute("aria-expanded", "true");
    };
    const rebuild = () => {
      const selected = select.selectedOptions[0];
      search.value = selected?.value ? selected.text : "";
      close();
    };
    search.addEventListener("focus", renderOptions);
    search.addEventListener("click", renderOptions);
    search.addEventListener("input", () => {
      const typed = search.value.trim().toLocaleLowerCase("th");
      const match = availableOptions().find((option) => option.text.trim().toLocaleLowerCase("th") === typed);
      select.value = match?.value || "";
      renderOptions();
    });
    search.addEventListener("change", () => {
      if (!select.value && search.value.trim()) search.setCustomValidity("กรุณาเลือกรายการจากผลการค้นหา");
      else search.setCustomValidity("");
    });
    search.addEventListener("input", () => search.setCustomValidity(""));
    search.addEventListener("keydown", (event) => {
      if (event.key === "Escape") close();
      if (event.key === "Enter" && !list.hidden) {
        const first = list.querySelector(".notify-combobox-option");
        if (first) {
          event.preventDefault();
          first.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));
        }
      }
    });
    search.addEventListener("blur", () => setTimeout(close, 0));
    box.addEventListener("notify:filter", rebuild);
    rebuild();
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
    document.querySelectorAll("[data-notify-searchable-select]").forEach(initSearchableSelect);
    document.querySelectorAll("[data-notify-lookup]").forEach(initLookup);
    document.querySelectorAll("[data-copy-button]").forEach((button) => button.addEventListener("click", () => {
      const text = button.parentElement.querySelector("[data-copy-source]")?.textContent;
      navigator.clipboard?.writeText(text).then(() => { button.lastChild.textContent = "คัดลอกแล้ว"; });
    }));
  };

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
