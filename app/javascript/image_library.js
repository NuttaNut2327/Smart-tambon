// Image library (คลังข้อมูลภาพ): the library page's preview dialog, and the "เลือกจากคลังภาพ" picker used by every
// form that attaches images. A picker button looks like
//   <button type="button" data-image-library-picker data-field="project[library_image_ids][]" data-max="20">
// and writes hidden inputs (plus small previews) right after itself. Without data-field it only dispatches an
// "image-library:select" event with { images } so scripts such as record_photos.js can upload the choice themselves.
(() => {
  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);

  // Library page: auto-submit uploads and preview a picture with its usages, rename and delete.
  document.querySelectorAll("[data-image-library-upload] input[type=file]").forEach(input => {
    input.addEventListener("change", () => {
      if (!input.files.length) return;
      input.closest("label").classList.add("busy");
      input.form.requestSubmit();
    });
  });

  const preview = document.querySelector("[data-library-dialog]");
  if (preview) {
    const rename = preview.querySelector("[data-preview-rename]");
    const remove = preview.querySelector("[data-preview-delete]");
    preview.querySelector("[data-preview-close]").addEventListener("click", () => preview.close());
    preview.addEventListener("click", event => { if (event.target === preview) preview.close(); });
    document.querySelectorAll("[data-library-preview]").forEach(card => card.addEventListener("click", () => {
      const usages = JSON.parse(card.dataset.usages || "[]");
      preview.querySelector("[data-preview-title]").textContent = card.dataset.title;
      preview.querySelector("[data-preview-image]").src = card.dataset.url;
      preview.querySelector("[data-preview-link]").href = card.dataset.url;
      preview.querySelector("[data-preview-meta]").textContent = card.dataset.meta;
      preview.querySelector("[data-preview-usages]").innerHTML = usages.length
        ? usages.map(usage => `<li>${escapeHtml(usage)}</li>`).join("")
        : "<li class=\"muted\">ยังไม่ถูกใช้งาน ลบออกจากคลังได้</li>";
      const editable = Boolean(card.dataset.updateUrl);
      preview.querySelector("[data-preview-actions]").hidden = !editable;
      if (editable) {
        rename.action = card.dataset.updateUrl;
        rename.querySelector("input[type=text]").value = card.dataset.title;
        remove.action = card.dataset.updateUrl;
        remove.hidden = usages.length > 0;
      }
      preview.showModal();
    }));
  }

  // Picker dialog, shared by every picker button on the page. Clicks are delegated so buttons that other scripts
  // add later (the resource photo gallery) work too.
  const dialog = document.createElement("dialog");
  dialog.className = "dataset-modal image-library-picker";
  dialog.innerHTML = `<header><div><small>คลังข้อมูลภาพ</small><h2>เลือกภาพจากคลัง</h2></div><button type="button" aria-label="ปิด" data-picker-close>×</button></header>
    <form class="image-library-picker-search" data-picker-search><input type="search" placeholder="ค้นหาชื่อภาพ" aria-label="ค้นหาชื่อภาพ"><button type="submit" class="button-link">ค้นหา</button></form>
    <div class="image-library-picker-grid" data-picker-grid></div>
    <footer><button type="button" class="button-link" data-picker-more hidden>โหลดเพิ่ม</button><p class="modal-status" data-picker-status></p><button type="button" class="data-layer-add" data-picker-confirm disabled>ใช้ภาพที่เลือก</button></footer>`;
  document.body.append(dialog);

  const grid = dialog.querySelector("[data-picker-grid]");
  const status = dialog.querySelector("[data-picker-status]");
  const confirmButton = dialog.querySelector("[data-picker-confirm]");
  const moreButton = dialog.querySelector("[data-picker-more]");
  const searchInput = dialog.querySelector("[data-picker-search] input");
  let state = { trigger: null, max: 1, selected: new Map(), page: 1, query: "" };

  const updateConfirm = () => {
    confirmButton.disabled = state.selected.size === 0;
    confirmButton.textContent = state.selected.size ? `ใช้ภาพที่เลือก (${state.selected.size})` : "ใช้ภาพที่เลือก";
  };

  const load = async (append = false) => {
    status.textContent = "กำลังโหลดภาพ…";
    try {
      const params = new URLSearchParams({ page: state.page, q: state.query });
      const response = await fetch(`/image_library.json?${params}`, { headers: { Accept: "application/json" } });
      if (!response.ok) throw new Error();
      const payload = await response.json();
      const cards = payload.images.map(image => `<button type="button" class="image-library-card${state.selected.has(image.id) ? " selected" : ""}" data-id="${escapeHtml(image.id)}" title="${escapeHtml(image.title)}"><img src="${escapeHtml(image.thumb_url)}" alt="" loading="lazy"><span class="image-library-caption"><b>${escapeHtml(image.title)}</b><small>${escapeHtml(image.source)}</small></span></button>`).join("");
      if (append) grid.insertAdjacentHTML("beforeend", cards); else grid.innerHTML = cards;
      grid.querySelectorAll("[data-id]").forEach(card => {
        const image = payload.images.find(item => item.id === card.dataset.id);
        if (image) card.imageData = image;
      });
      moreButton.hidden = payload.page >= payload.page_count;
      status.textContent = payload.total ? `${payload.total} ภาพในคลัง` : "ยังไม่มีภาพในคลัง อัปโหลดได้ที่เมนูคลังข้อมูลภาพ";
    } catch {
      status.textContent = "โหลดภาพจากคลังไม่สำเร็จ";
    }
  };

  grid.addEventListener("click", event => {
    const card = event.target.closest("[data-id]");
    if (!card?.imageData) return;
    const id = card.dataset.id;
    if (state.selected.has(id)) {
      state.selected.delete(id);
    } else {
      if (state.max === 1) { state.selected.clear(); grid.querySelectorAll(".selected").forEach(item => item.classList.remove("selected")); }
      if (state.selected.size >= state.max) { status.textContent = `เลือกได้ไม่เกิน ${state.max} ภาพ`; return; }
      state.selected.set(id, card.imageData);
    }
    card.classList.toggle("selected", state.selected.has(id));
    updateConfirm();
  });

  dialog.querySelector("[data-picker-search]").addEventListener("submit", event => {
    event.preventDefault();
    state.query = searchInput.value.trim(); state.page = 1; load();
  });
  moreButton.addEventListener("click", () => { state.page += 1; load(true); });
  dialog.querySelector("[data-picker-close]").addEventListener("click", () => dialog.close());

  const selectionBox = trigger => {
    let box = trigger.nextElementSibling;
    if (!box?.matches("[data-image-library-selection]")) {
      box = document.createElement("div");
      box.className = "image-library-selection";
      box.dataset.imageLibrarySelection = "";
      trigger.after(box);
    }
    return box;
  };

  const renderSelection = (trigger, images) => {
    const box = selectionBox(trigger);
    box.innerHTML = images.map(image => `<span class="image-library-chip" data-id="${escapeHtml(image.id)}" data-title="${escapeHtml(image.title)}" data-thumb-url="${escapeHtml(image.thumb_url)}"><img src="${escapeHtml(image.thumb_url)}" alt=""><b>${escapeHtml(image.title)}</b><input type="hidden" name="${escapeHtml(trigger.dataset.field)}" value="${escapeHtml(image.id)}"><button type="button" aria-label="นำออก" data-chip-remove>×</button></span>`).join("");
  };

  // Chips rendered by the server (after a validation error) or by renderSelection.
  const chipsOf = trigger => [...selectionBox(trigger).querySelectorAll("[data-id]")]
    .map(chip => ({ id: chip.dataset.id, title: chip.dataset.title, thumb_url: chip.dataset.thumbUrl }));

  document.addEventListener("click", event => {
    const remove = event.target.closest("[data-image-library-selection] [data-chip-remove]");
    if (!remove) return;
    const trigger = remove.closest("[data-image-library-selection]").previousElementSibling;
    renderSelection(trigger, chipsOf(trigger).filter(image => image.id !== remove.closest("[data-id]").dataset.id));
  });

  confirmButton.addEventListener("click", () => {
    const images = [...state.selected.values()];
    const trigger = state.trigger;
    dialog.close();
    if (trigger.dataset.field) {
      const current = trigger.dataset.max === "1" ? [] : chipsOf(trigger);
      const merged = [...current, ...images.filter(image => !current.some(item => item.id === image.id))].slice(0, Number(trigger.dataset.max || 20));
      renderSelection(trigger, merged);
    }
    trigger.dispatchEvent(new CustomEvent("image-library:select", { bubbles: true, detail: { images } }));
  });

  document.addEventListener("click", event => {
    const trigger = event.target.closest("[data-image-library-picker]");
    if (!trigger) return;
    event.preventDefault();
    state = { trigger, max: Number(trigger.dataset.max || 20), selected: new Map(), page: 1, query: "" };
    searchInput.value = "";
    grid.innerHTML = "";
    updateConfirm();
    dialog.showModal();
    load();
  });
})();
