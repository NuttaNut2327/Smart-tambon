const initializeMainSidebarCollapse = () => {
  const shell = document.querySelector(".dashboard-shell");
  const button = document.querySelector("[data-sidebar-collapse]");
  if (!shell || !button || button.dataset.sidebarCollapseReady === "true") return;

  button.dataset.sidebarCollapseReady = "true";

  const storageKey = "smartTambonMainSidebarCollapsed";
  let collapsed = false;
  try {
    collapsed = window.localStorage.getItem(storageKey) === "true";
  } catch (_error) {
    collapsed = false;
  }

  const render = () => {
    shell.classList.toggle("sidebar-collapsed", collapsed);
    button.setAttribute("aria-expanded", String(!collapsed));
    button.setAttribute("aria-label", collapsed ? "ขยายเมนูหลัก" : "ย่อเมนูหลัก");
    button.title = collapsed ? "ขยายเมนูหลัก" : "ย่อเมนูหลัก";
    const icon = button.querySelector(".material-symbols-outlined");
    if (icon) icon.textContent = collapsed ? "chevron_right" : "chevron_left";
  };

  button.addEventListener("click", () => {
    collapsed = !collapsed;
    try {
      window.localStorage.setItem(storageKey, String(collapsed));
    } catch (_error) {
      // The visual state still works when browser storage is unavailable.
    }
    render();
  });

  render();
};

document.addEventListener("DOMContentLoaded", initializeMainSidebarCollapse);
document.addEventListener("turbo:load", initializeMainSidebarCollapse);
