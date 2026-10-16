// Map markers and popup content for area activities (Incident category "activity").
// The activity's main photo is drawn as a round icon; activities without one show their type's symbol.
(() => {
  const PHASE_COLORS = { upcoming: "#7a5cc2", ongoing: "#2e8b57", finished: "#8a8f98" };
  const SIZE = 46, RING = 4, TAIL = 9;
  const styles = new Map();
  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);

  function drawMarker(activity, image) {
    const ratio = window.devicePixelRatio || 1;
    const canvas = document.createElement("canvas");
    canvas.width = SIZE * ratio;
    canvas.height = (SIZE + TAIL) * ratio;
    const ctx = canvas.getContext("2d");
    ctx.scale(ratio, ratio);
    const color = PHASE_COLORS[activity.phase] || PHASE_COLORS.upcoming;
    const radius = SIZE / 2;
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.moveTo(radius - 7, SIZE - 6);
    ctx.lineTo(radius, SIZE + TAIL - 1);
    ctx.lineTo(radius + 7, SIZE - 6);
    ctx.fill();
    ctx.beginPath();
    ctx.arc(radius, radius, radius - 1, 0, Math.PI * 2);
    ctx.fill();
    ctx.save();
    ctx.beginPath();
    ctx.arc(radius, radius, radius - RING, 0, Math.PI * 2);
    ctx.clip();
    if (image) {
      // Cover-fit the photo inside the circle.
      const scale = Math.max((SIZE - RING * 2) / image.naturalWidth, (SIZE - RING * 2) / image.naturalHeight);
      const width = image.naturalWidth * scale, height = image.naturalHeight * scale;
      ctx.drawImage(image, radius - width / 2, radius - height / 2, width, height);
    } else {
      ctx.fillStyle = "#fff";
      ctx.fillRect(0, 0, SIZE, SIZE);
      ctx.fillStyle = color;
      ctx.font = '26px "Material Symbols Outlined"';
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(activity.icon || "event", radius, radius + 1);
    }
    ctx.restore();
    return new ol.style.Style({ image: new ol.style.Icon({ img: canvas, size: [canvas.width, canvas.height], scale: 1 / ratio, anchor: [0.5, 1] }) });
  }

  // Returns a style now and calls onChange once the photo (or icon font) is ready, so the layer can redraw.
  function markerStyle(activity, onChange) {
    const key = `${activity.id}:${activity.phase}:${activity.cover_url || ""}`;
    if (styles.has(key)) return styles.get(key);
    styles.set(key, drawMarker(activity, null));
    if (activity.cover_url) {
      const image = new Image();
      image.onload = () => { styles.set(key, drawMarker(activity, image)); onChange?.(); };
      image.src = activity.cover_url;
    } else {
      document.fonts?.ready.then(() => { styles.set(key, drawMarker(activity, null)); onChange?.(); });
    }
    return styles.get(key);
  }

  function formatPeriod(activity) {
    const start = activity.starts_at && new Date(activity.starts_at), end = activity.ends_at && new Date(activity.ends_at);
    if (!start || !end) return "";
    const date = { day: "numeric", month: "short", year: "numeric" }, time = { hour: "2-digit", minute: "2-digit" };
    return start.toDateString() === end.toDateString()
      ? `${start.toLocaleDateString("th-TH", date)} ${start.toLocaleTimeString("th-TH", time)}–${end.toLocaleTimeString("th-TH", time)} น.`
      : `${start.toLocaleDateString("th-TH", date)} ${start.toLocaleTimeString("th-TH", time)} – ${end.toLocaleDateString("th-TH", date)} ${end.toLocaleTimeString("th-TH", time)} น.`;
  }

  function popupHtml(activity) {
    const cover = activity.cover_url ? `<img src="${escapeHtml(activity.cover_url)}" alt="">` : `<span class="material-symbols-outlined">${escapeHtml(activity.icon || "event")}</span>`;
    return `<div class="activity-popup"><div class="activity-popup-cover phase-${escapeHtml(activity.phase)}">${cover}<span>${escapeHtml(activity.phase_label)}</span></div>
      <strong>${escapeHtml(activity.title)}</strong>
      <p>${escapeHtml(activity.activity_type_label)} · ${escapeHtml(activity.status_label)}</p>
      <p><span class="material-symbols-outlined">schedule</span>${escapeHtml(formatPeriod(activity))}</p>
      ${activity.location_name ? `<p><span class="material-symbols-outlined">location_on</span>${escapeHtml(activity.location_name)}</p>` : ""}
      <a href="${escapeHtml(activity.url)}">ดูรายละเอียดกิจกรรม</a></div>`;
  }

  async function load() {
    const response = await fetch("/api/activities", { headers: { Accept: "application/json" } });
    if (!response.ok) throw new Error(response.status);
    return (await response.json()).filter(activity => Number.isFinite(Number(activity.longitude)) && Number.isFinite(Number(activity.latitude)));
  }

  window.SmartTambonActivities = { markerStyle, popupHtml, formatPeriod, load, PHASE_COLORS };
})();
