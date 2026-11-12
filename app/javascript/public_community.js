document.addEventListener("DOMContentLoaded", () => {
  const page = document.querySelector("[data-community-page]");
  const modal = page?.querySelector("[data-community-modal]");
  const modalContent = modal?.querySelector("[data-community-modal-content]");
  page?.querySelectorAll("[data-community-modal-target]").forEach((button) => button.addEventListener("click", () => {
    const template = document.getElementById(button.dataset.communityModalTarget);
    if (!modal || !modalContent || !template) return;
    modalContent.replaceChildren(template.content.cloneNode(true));
    modal.showModal();
  }));
  modal?.querySelector("[data-community-modal-close]")?.addEventListener("click", () => modal.close());
  modal?.addEventListener("click", (event) => {
    if (event.target !== modal) return;
    const bounds = modal.getBoundingClientRect();
    const outside = event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom;
    if (outside) modal.close();
  });
  const truncateNewsPreviews = () => page?.querySelectorAll(".community-news-card p").forEach((text) => {
    text.dataset.fullText ||= text.textContent.trim();
    const fullText = text.dataset.fullText;
    text.textContent = fullText;
    const lineHeight = Number.parseFloat(getComputedStyle(text).lineHeight) || 18;
    const maxHeight = lineHeight * 2 + 1;
    if (text.scrollHeight <= maxHeight) return;

    let low = 0;
    let high = fullText.length;
    while (low < high) {
      const middle = Math.ceil((low + high) / 2);
      text.textContent = `${fullText.slice(0, middle).trimEnd()}..`;
      if (text.scrollHeight <= maxHeight) low = middle;
      else high = middle - 1;
    }
    text.textContent = `${fullText.slice(0, low).trimEnd()}..`;
  });
  requestAnimationFrame(truncateNewsPreviews);
  window.addEventListener("resize", truncateNewsPreviews);
  const mapElement = page?.querySelector("[data-community-map]");
  if (!page || !mapElement || typeof ol === "undefined") return;

  const readJson = (selector, fallback) => {
    try { return JSON.parse(page.querySelector(selector)?.textContent || ""); }
    catch (_error) { return fallback; }
  };
  const boundary = readJson("[data-community-boundary]", null);
  const items = readJson("[data-community-items]", []);
  const detail = page.querySelector("[data-community-detail]");
  const geoJson = new ol.format.GeoJSON();
  const boundaryFeatures = boundary ? geoJson.readFeatures(boundary, { dataProjection: "EPSG:4326", featureProjection: "EPSG:3857" }) : [];
  const boundarySource = new ol.source.Vector({ features: boundaryFeatures });
  const markerSource = new ol.source.Vector();
  const worldExtent = 20037508.342789244;
  const boundaryOuterRings = boundaryFeatures.flatMap((feature) => {
    const geometry = feature.getGeometry();
    if (geometry?.getType() === "Polygon") return [geometry.getCoordinates()[0]];
    if (geometry?.getType() === "MultiPolygon") return geometry.getCoordinates().map((polygon) => polygon[0]);
    return [];
  });
  const maskGeometry = boundaryOuterRings.length ? new ol.geom.Polygon([[
    [-worldExtent, -worldExtent], [worldExtent, -worldExtent],
    [worldExtent, worldExtent], [-worldExtent, worldExtent], [-worldExtent, -worldExtent]
  ], ...boundaryOuterRings]) : null;
  const maskSource = new ol.source.Vector({
    features: maskGeometry ? [new ol.Feature({ geometry: maskGeometry })] : []
  });

  const markerColor = (item) => {
    if (item.category === "activity") return "#8b5fa8";
    if (item.category === "disaster") return "#b94755";
    return item.status === "assessing" ? "#d69b27" : "#3e78a0";
  };
  items.forEach((item) => {
    const feature = new ol.Feature({
      geometry: new ol.geom.Point(ol.proj.fromLonLat([Number(item.longitude), Number(item.latitude)])),
      communityItem: item
    });
    const color = markerColor(item);
    const markerSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="32" height="42" viewBox="0 0 32 42"><path d="M16 1.5C8.27 1.5 2 7.77 2 15.5 2 26 16 40 16 40s14-14 14-24.5C30 7.77 23.73 1.5 16 1.5Z" fill="${color}" stroke="white" stroke-width="2.5"/><circle cx="16" cy="15.5" r="5.2" fill="white" fill-opacity=".95"/></svg>`;
    const style = new ol.style.Style({
      image: new ol.style.Icon({
        src: `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(markerSvg)}`,
        anchor: [0.5, 1],
        anchorXUnits: "fraction",
        anchorYUnits: "fraction",
        scale: 0.9
      })
    });
    feature.set("communityStyle", style);
    feature.setStyle(style);
    markerSource.addFeature(feature);
  });

  const map = new ol.Map({
    target: mapElement,
    layers: [
      new ol.layer.Tile({ source: new ol.source.OSM() }),
      new ol.layer.Vector({ source: maskSource, style: new ol.style.Style({ fill: new ol.style.Fill({ color: "rgba(31,42,35,.55)" }) }) }),
      new ol.layer.Vector({ source: boundarySource, style: new ol.style.Style({ fill: new ol.style.Fill({ color: "rgba(91,121,103,.06)" }), stroke: new ol.style.Stroke({ color: "#557764", width: 2.5 }) }) }),
      new ol.layer.Vector({ source: markerSource })
    ],
    view: new ol.View({ center: ol.proj.fromLonLat([100.5, 13.75]), zoom: 13 }),
    controls: ol.control.defaults.defaults({ zoom: true, attribution: false, rotate: false })
  });
  if (boundaryFeatures.length) map.getView().fit(boundarySource.getExtent(), { padding: [38, 38, 38, 38], maxZoom: 16 });

  const thaiDate = (value) => value ? new Intl.DateTimeFormat("th-TH", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "—";
  const showDetail = (item) => {
    detail.replaceChildren();
    const close = document.createElement("button");
    close.type = "button";
    close.className = "community-detail-close";
    close.setAttribute("aria-label", "ปิดรายละเอียด");
    close.textContent = "×";
    close.addEventListener("click", () => { detail.hidden = true; });
    const heading = document.createElement("div");
    const badge = document.createElement("span");
    badge.className = `community-status ${item.status}`;
    badge.textContent = item.status_label;
    const title = document.createElement("h3");
    title.textContent = item.title;
    const type = document.createElement("small");
    type.textContent = `${item.category_label} · ${item.incident_type}`;
    heading.append(badge, title, type);
    const summary = document.createElement("p");
    summary.textContent = item.summary || "ไม่มีรายละเอียดเพิ่มเติม";
    const meta = document.createElement("div");
    meta.className = "community-detail-meta";
    const values = [
      ["confirmation_number", item.reference_code],
      ["location_on", item.location_name || "ตำแหน่งในพื้นที่"],
      ["update", `อัปเดต ${thaiDate(item.updated_at)}`]
    ];
    if (item.confirmations > 0) values.push(["group_add", `มีผู้ยืนยันเหตุเพิ่ม ${item.confirmations} คน`]);
    values.forEach(([icon, value]) => {
      const row = document.createElement("span");
      row.innerHTML = `<span class="material-symbols-outlined">${icon}</span>`;
      row.append(document.createTextNode(value));
      meta.append(row);
    });
    detail.append(close, heading, summary, meta);
    detail.hidden = false;
  };

  map.on("singleclick", (event) => {
    const feature = map.forEachFeatureAtPixel(event.pixel, (candidate) => candidate.get("communityItem") ? candidate : null);
    if (feature) showDetail(feature.get("communityItem"));
  });
  map.on("pointermove", (event) => { mapElement.style.cursor = map.hasFeatureAtPixel(event.pixel) ? "pointer" : ""; });

  page.querySelectorAll("[data-community-item-id]").forEach((button) => button.addEventListener("click", () => {
    const item = items.find((candidate) => candidate.id === button.dataset.communityItemId);
    const feature = markerSource.getFeatures().find((candidate) => candidate.get("communityItem")?.id === item?.id);
    if (!item || !feature) return;
    map.getView().animate({ center: feature.getGeometry().getCoordinates(), zoom: 16, duration: 350 });
    showDetail(item);
    mapElement.scrollIntoView({ behavior: "smooth", block: "center" });
  }));

  page.querySelectorAll("[data-community-filter]").forEach((button) => button.addEventListener("click", () => {
    const filter = button.dataset.communityFilter;
    page.querySelectorAll("[data-community-filter]").forEach((item) => item.classList.toggle("active", item === button));
    page.querySelectorAll("[data-community-category]").forEach((item) => { item.hidden = filter !== "all" && item.dataset.communityCategory !== filter; });
    markerSource.getFeatures().forEach((feature) => {
      const item = feature.get("communityItem");
      feature.setStyle(filter === "all" || item.category === filter ? feature.get("communityStyle") : new ol.style.Style({}));
    });
    detail.hidden = true;
  }));

  const archive = page.querySelector("[data-community-archive]");
  if (archive) {
    const archiveItems = Array.from(archive.querySelectorAll("[data-community-archive-item]"));
    const fromInput = archive.querySelector("[data-community-archive-from]");
    const toInput = archive.querySelector("[data-community-archive-to]");
    const count = archive.querySelector("[data-community-archive-count]");
    const empty = archive.querySelector("[data-community-archive-empty]");
    const filterToggle = archive.querySelector("[data-community-archive-filter-toggle]");
    const dateFilters = archive.querySelector("[data-community-archive-date-filters]");
    let archiveType = "all";
    const updateDateCue = (input) => {
      const wrapper = input?.closest(".community-date-input");
      if (!wrapper) return;
      wrapper.classList.toggle("has-value", Boolean(input.value));
      const cue = wrapper.querySelector(".community-date-placeholder");
      if (cue) cue.textContent = input.value ? new Intl.DateTimeFormat("th-TH", { dateStyle: "medium" }).format(new Date(`${input.value}T00:00:00`)) : "เลือกวันที่";
    };

    const applyArchiveFilters = () => {
      let visible = 0;
      archiveItems.forEach((item) => {
        const typeMatches = archiveType === "all" || item.dataset.archiveCategory === archiveType;
        const date = item.dataset.archiveDate || "";
        const dateMatches = (!fromInput?.value || date >= fromInput.value) && (!toInput?.value || date <= toInput.value);
        item.hidden = !(typeMatches && dateMatches);
        if (!item.hidden) visible += 1;
      });
      if (count) count.textContent = `${visible} รายการ`;
      if (empty) empty.hidden = visible !== 0;
    };

    archive.querySelectorAll("[data-community-archive-type]").forEach((button) => button.addEventListener("click", () => {
      archiveType = button.dataset.communityArchiveType;
      archive.querySelectorAll("[data-community-archive-type]").forEach((candidate) => candidate.classList.toggle("active", candidate === button));
      applyArchiveFilters();
    }));
    filterToggle?.addEventListener("click", () => {
      const expanded = filterToggle.getAttribute("aria-expanded") === "true";
      filterToggle.setAttribute("aria-expanded", String(!expanded));
      if (dateFilters) dateFilters.hidden = expanded;
      archive.classList.toggle("filters-expanded", !expanded);
      const label = filterToggle.querySelector("[data-community-filter-toggle-label]");
      if (label) label.textContent = expanded ? "ตัวกรองเพิ่มเติม" : "ซ่อนตัวกรอง";
    });
    [fromInput, toInput].forEach((input) => {
      updateDateCue(input);
      const wrapper = input?.closest(".community-date-input");
      const openPicker = (event) => {
        if (!input) return;
        event.preventDefault();
        input.focus({ preventScroll: true });
        try {
          if (typeof input.showPicker === "function") input.showPicker();
          else input.click();
        } catch (_error) {
          input.click();
        }
      };
      wrapper?.addEventListener("pointerdown", openPicker);
      wrapper?.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") openPicker(event);
      });
      input?.addEventListener("change", () => { updateDateCue(input); applyArchiveFilters(); });
      input?.addEventListener("input", () => updateDateCue(input));
    });
    archive.querySelector("[data-community-archive-reset]")?.addEventListener("click", () => {
      archiveType = "all";
      if (fromInput) fromInput.value = "";
      if (toInput) toInput.value = "";
      updateDateCue(fromInput);
      updateDateCue(toInput);
      archive.querySelectorAll("[data-community-archive-type]").forEach((button) => button.classList.toggle("active", button.dataset.communityArchiveType === "all"));
      applyArchiveFilters();
    });
  }
});
