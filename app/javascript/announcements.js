// Announcement popups rendered by app/views/announcements/_popup.html.erb. The page also polls the feed so
// signed-in users see new alerts (e.g. a news programme's internal alert) without reloading.
const POLL_MS = 60_000;

const mountAnnouncements = root => {
  const csrfToken = document.querySelector("meta[name=csrf-token]")?.content;
  const backdrop = root.querySelector("[data-announcement-backdrop]");
  const modals = [...root.querySelectorAll("[data-announcement-modal]")];

  const showNext = () => {
    const next = modals.find(modal => modal.isConnected);
    if (!next) {
      backdrop?.remove();
      if (!document.querySelector("[data-announcement-modal]")) document.body.classList.remove("announcement-open");
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
  root.querySelectorAll("[data-announcement-corner]").forEach(corner => {
    const toggle = corner.querySelector("[data-announcement-corner-toggle]");
    const key = `announcement-corner-collapsed:${corner.dataset.announcementId}`;
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
};

const pollAnnouncements = async feedUrl => {
  if (document.hidden) return;
  const url = new URL(feedUrl, window.location.origin);
  document.querySelectorAll("[data-announcement-id]").forEach(node => url.searchParams.append("shown[]", node.dataset.announcementId));
  try {
    const response = await fetch(url, { headers: { Accept: "text/html" }, credentials: "same-origin" });
    if (response.status !== 200) return;
    const holder = document.createElement("div");
    holder.innerHTML = await response.text();
    const root = holder.querySelector("[data-announcements]");
    if (!root) return;
    document.body.append(root);
    mountAnnouncements(root);
    // Keep corner boxes in one stack instead of overlapping asides.
    const stack = document.querySelector(".announcement-corners");
    const added = root.querySelector(".announcement-corners");
    if (stack && added && stack !== added) {
      stack.append(...added.children);
      added.remove();
    }
  } catch (_) { /* offline or signed out; try again next round */ }
};

document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-announcements]").forEach(mountAnnouncements);
  const feedUrl = document.body.dataset.announcementFeedUrl;
  if (!feedUrl) return;
  window.setInterval(() => pollAnnouncements(feedUrl), POLL_MS);
  document.addEventListener("visibilitychange", () => { if (!document.hidden) pollAnnouncements(feedUrl); });
});
