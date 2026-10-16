// Announcement popups rendered by app/views/announcements/_popup.html.erb.
document.addEventListener("DOMContentLoaded", () => {
  const root = document.querySelector("[data-announcements]");
  if (!root) return;
  const csrfToken = document.querySelector("meta[name=csrf-token]")?.content;
  const backdrop = root.querySelector("[data-announcement-backdrop]");
  const modals = [...root.querySelectorAll("[data-announcement-modal]")];

  const showNext = () => {
    const next = modals.find(modal => modal.isConnected);
    if (!next) {
      backdrop?.remove();
      document.body.classList.remove("announcement-open");
      return;
    }
    next.hidden = false;
    next.querySelector("[data-announcement-ack]")?.focus();
  };

  if (modals.length) document.body.classList.add("announcement-open");
  modals.forEach(modal => modal.querySelector("[data-announcement-ack]").addEventListener("click", async event => {
    const button = event.currentTarget;
    button.disabled = true;
    try {
      const response = await fetch(modal.dataset.acknowledgeUrl, {
        method: "POST",
        headers: { "X-CSRF-Token": csrfToken, Accept: "application/json" },
        credentials: "same-origin"
      });
      if (!response.ok && response.status !== 404) throw new Error(`HTTP ${response.status}`);
      modal.remove();
      showNext();
    } catch (error) {
      button.disabled = false;
      window.alert("บันทึกการรับทราบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง");
    }
  }));
  showNext();

  // Corner boxes cannot be closed, only collapsed; the collapsed state lasts for this tab.
  root.querySelectorAll("[data-announcement-corner]").forEach((corner, index) => {
    const toggle = corner.querySelector("[data-announcement-corner-toggle]");
    const key = `announcement-corner-collapsed:${index}:${toggle.textContent.trim()}`;
    const apply = collapsed => {
      corner.classList.toggle("collapsed", collapsed);
      toggle.setAttribute("aria-expanded", String(!collapsed));
    };
    try { apply(sessionStorage.getItem(key) === "1"); } catch (_) { apply(false); }
    toggle.addEventListener("click", () => {
      const collapsed = !corner.classList.contains("collapsed");
      apply(collapsed);
      try { sessionStorage.setItem(key, collapsed ? "1" : "0"); } catch (_) { /* storage unavailable */ }
    });
  });
});
