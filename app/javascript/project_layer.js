// Project markers and map popup content, shared by the dashboard map and the project form.
(() => {
  const statusColors = {
    planned: "#7b6fb0",
    procurement: "#c17d11",
    in_progress: "#2f6fb0",
    completed: "#2d8a55",
    suspended: "#8a8f94"
  };

  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);
  const formatBudget = value => value === null || value === undefined || value === "" ? "-" : `${Number(value).toLocaleString("th-TH", { maximumFractionDigits: 2 })} บาท`;

  const markerStyles = {};
  function markerStyle(status) {
    if (!window.ol) return undefined;
    const color = statusColors[status] || statusColors.planned;
    markerStyles[color] ||= new ol.style.Style({
      image: new ol.style.Icon({
        anchor: [0.5, 1],
        src: "data:image/svg+xml;charset=utf-8," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="34" height="42" viewBox="0 0 34 42"><path d="M17 41s15-14.2 15-24A15 15 0 0 0 2 17c0 9.8 15 24 15 24z" fill="${color}" stroke="#fff" stroke-width="2"/><rect x="10" y="9" width="14" height="17" rx="2" fill="#fff"/><rect x="13" y="7" width="8" height="4" rx="1" fill="#fff" stroke="${color}" stroke-width="1.2"/><path d="M13 15h8M13 18.5h8M13 22h5" stroke="${color}" stroke-width="1.6" stroke-linecap="round"/></svg>`)
      })
    });
    return markerStyles[color];
  }

  function popupHtml(project) {
    const place = [project.location_name, project.subdistrict_name && `ต.${project.subdistrict_name}`, project.district_name && `อ.${project.district_name}`].filter(Boolean).join(" ");
    const progress = Math.max(0, Math.min(100, Number(project.progress_percent) || 0));
    const photos = (project.photos || []).filter(photo => photo.url);
    const gallery = photos.length ? `<div class="project-popup-gallery">${photos.map((photo, index) => `<a href="${escapeHtml(photo.url)}" target="_blank" rel="noopener" title="${escapeHtml(photo.filename)}"><img src="${escapeHtml(photo.url)}" alt="ภาพที่ ${index + 1}" loading="lazy"></a>`).join("")}</div>` : "";
    const rows = [
      ["กลุ่ม", project.group_label],
      ["ประเภท", project.project_type],
      ["ปีงบประมาณ", project.fiscal_year],
      ["งบประมาณ", formatBudget(project.budget)],
      ["การอนุมัติ", project.approval_status_label],
      ["แหล่งงบ", project.budget_source],
      ["หน่วยงาน", project.agency],
      ["สถานที่", place]
    ].filter(([, value]) => value !== null && value !== undefined && value !== "");
    return `<div class="project-popup">
      ${gallery}
      <strong>${escapeHtml(project.name)}</strong>${project.code ? `<small class="project-popup-code">${escapeHtml(project.code)}</small>` : ""}
      <p><span class="project-status ${escapeHtml(project.status)}">${escapeHtml(project.status_label)}</span> <span class="project-popup-progress"><i style="width:${progress}%"></i></span> ${progress}%</p>
      <dl>${rows.map(([label, value]) => `<dt>${label}</dt><dd>${escapeHtml(value)}</dd>`).join("")}</dl>
      ${project.description ? `<p class="project-popup-description">${escapeHtml(project.description)}</p>` : ""}
    </div>`;
  }

  window.SmartTambonProjects = { markerStyle, popupHtml, statusColors };
})();
