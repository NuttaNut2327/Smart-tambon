// Photos on resource and consumable rows: the table shows a thumbnail; clicking opens a gallery where editors can
// add photos (new uploads or pictures from the image library) or remove them. Large images are shrunk in the browser
// before upload to save bandwidth; the server stores them in the image library as WebP with a thumbnail.
(() => {
  const buttons = document.querySelectorAll("[data-record-photos]");
  if (!buttons.length) return;

  const MAX_PHOTOS = 6;
  const token = document.querySelector('meta[name="csrf-token"]')?.content;
  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);

  const dialog = document.createElement("dialog");
  dialog.className = "dataset-modal record-photo-modal";
  dialog.innerHTML = `<header><div><small>ภาพประกอบรายการ</small><h2 data-photo-title></h2></div><button type="button" aria-label="ปิด" data-photo-close>×</button></header>
    <div class="record-photo-viewer"><img alt="" data-photo-main hidden><p class="record-photo-empty" data-photo-empty>ยังไม่มีภาพของรายการนี้</p></div>
    <div class="record-photo-strip" data-photo-strip></div>
    <footer><label class="button-link record-photo-add" data-photo-add><span class="material-symbols-outlined" aria-hidden="true">add_a_photo</span>เพิ่มภาพ<input type="file" accept="image/jpeg,image/png,image/webp,image/heic,image/heif,.heic,.heif" multiple hidden></label><button type="button" class="button-link image-library-pick" data-image-library-picker data-photo-pick><span class="material-symbols-outlined" aria-hidden="true">photo_library</span>เลือกจากคลังภาพ</button><button type="button" class="button-link danger" data-photo-delete>ลบภาพนี้</button><p class="modal-status" data-photo-status></p></footer>`;
  document.body.append(dialog);

  const title = dialog.querySelector("[data-photo-title]");
  const main = dialog.querySelector("[data-photo-main]");
  const empty = dialog.querySelector("[data-photo-empty]");
  const strip = dialog.querySelector("[data-photo-strip]");
  const addLabel = dialog.querySelector("[data-photo-add]");
  const input = addLabel.querySelector("input");
  const pickButton = dialog.querySelector("[data-photo-pick]");
  const deleteButton = dialog.querySelector("[data-photo-delete]");
  const status = dialog.querySelector("[data-photo-status]");
  let current = { button: null, photos: [], index: 0, changed: false };

  const setStatus = (text, error = false) => { status.textContent = text; status.className = `modal-status${error ? " error" : ""}`; };

  const render = () => {
    const { photos, index, button } = current;
    const photo = photos[index];
    const editable = button.dataset.editable === "true";
    main.hidden = !photo; empty.hidden = Boolean(photo);
    if (photo) { main.src = photo.url; main.alt = photo.filename || ""; }
    strip.innerHTML = photos.map((item, position) => `<button type="button" class="${position === index ? "active" : ""}" data-index="${position}" aria-label="ภาพที่ ${position + 1}"><img src="${escapeHtml(item.thumb)}" alt=""></button>`).join("");
    strip.hidden = photos.length < 2;
    addLabel.hidden = !editable || !button.dataset.uploadUrl || photos.length >= MAX_PHOTOS;
    pickButton.hidden = addLabel.hidden;
    pickButton.dataset.max = String(MAX_PHOTOS - photos.length);
    deleteButton.hidden = !editable || !photo;
  };

  strip.addEventListener("click", event => {
    const target = event.target.closest("[data-index]");
    if (!target) return;
    current.index = Number(target.dataset.index); render();
  });

  buttons.forEach(button => button.addEventListener("click", () => {
    current = { button, photos: JSON.parse(button.dataset.photos || "[]"), index: 0, changed: false };
    title.textContent = button.dataset.name || "รายการ";
    setStatus(""); render(); dialog.showModal();
  }));

  // The table thumbnail reflects the latest photos only after a reload; do that once the gallery closes.
  dialog.querySelector("[data-photo-close]").addEventListener("click", () => dialog.close());
  dialog.addEventListener("close", () => { if (current.changed) window.location.reload(); });

  const loadImage = file => new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file), image = new Image();
    image.onload = () => { URL.revokeObjectURL(url); resolve(image); };
    image.onerror = () => { URL.revokeObjectURL(url); reject(new Error("เปิดไฟล์ภาพไม่ได้")); };
    image.src = url;
  });

  const resized = (image, maxSize, quality, name) => new Promise(resolve => {
    const scale = Math.min(1, maxSize / Math.max(image.naturalWidth, image.naturalHeight));
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(image.naturalWidth * scale); canvas.height = Math.round(image.naturalHeight * scale);
    canvas.getContext("2d").drawImage(image, 0, 0, canvas.width, canvas.height);
    canvas.toBlob(blob => resolve(blob && new File([blob], name, { type: "image/jpeg" })), "image/jpeg", quality);
  });

  input.addEventListener("change", async () => {
    const files = [...input.files];
    input.value = "";
    if (!files.length) return;
    if (current.photos.length + files.length > MAX_PHOTOS) return setStatus(`แนบรูปได้ไม่เกิน ${MAX_PHOTOS} รูปต่อรายการ`, true);

    setStatus("กำลังย่อขนาดและอัปโหลดภาพ…");
    const body = new FormData();
    for (const file of files) {
      const baseName = file.name.replace(/\.[^.]+$/, "") || "photo";
      try {
        body.append("photos[]", file.size > 2 * 1024 * 1024 ? ((await resized(await loadImage(file), 2048, 0.9, `${baseName}.jpg`)) || file) : file);
      } catch {
        body.append("photos[]", file);
      }
    }
    await submit(body, "อัปโหลดภาพแล้ว");
  });

  pickButton.addEventListener("image-library:select", async event => {
    const body = new FormData();
    event.detail.images.forEach(image => body.append("library_image_ids[]", image.id));
    setStatus("กำลังแนบภาพจากคลัง…");
    await submit(body, "แนบภาพจากคลังแล้ว");
  });

  async function submit(body, doneMessage) {
    addLabel.classList.add("busy");
    try {
      const response = await fetch(current.button.dataset.uploadUrl, { method: "POST", body, headers: { Accept: "application/json", "X-CSRF-Token": token } });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error || "อัปโหลดภาพไม่สำเร็จ");
      current.photos = payload.photos; current.index = payload.photos.length - 1; current.changed = true;
      setStatus(doneMessage); render();
    } catch (error) {
      setStatus(error.message, true);
    } finally {
      addLabel.classList.remove("busy");
    }
  }

  deleteButton.addEventListener("click", async () => {
    const photo = current.photos[current.index];
    if (!photo || !window.confirm("ลบภาพนี้ออกจากรายการ?")) return;
    deleteButton.disabled = true;
    try {
      const response = await fetch(photo.delete_url, { method: "DELETE", headers: { Accept: "application/json", "X-CSRF-Token": token } });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error || "ลบภาพไม่สำเร็จ");
      current.photos = payload.photos; current.index = Math.max(0, Math.min(current.index, current.photos.length - 1)); current.changed = true;
      setStatus("ลบภาพแล้ว"); render();
    } catch (error) {
      setStatus(error.message, true);
    } finally {
      deleteButton.disabled = false;
    }
  });
})();
