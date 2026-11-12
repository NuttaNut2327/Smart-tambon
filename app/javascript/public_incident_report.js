document.addEventListener("DOMContentLoaded", () => {
  const page = document.querySelector("[data-public-report-page]");
  if (!page) return;
  const dialog = page.parentElement?.querySelector("[data-line-choice-dialog]") || document.querySelector("[data-line-choice-dialog]");
  const storageKey = `skip-line:${page.dataset.reportToken}`;
  if (dialog && sessionStorage.getItem(storageKey) !== "1") dialog.showModal();
  document.querySelector("[data-skip-line]")?.addEventListener("click", () => {
    sessionStorage.setItem(storageKey, "1");
    dialog?.close();
  });
  if (page.dataset.liffMode !== "true") return;
  const status = page.querySelector("[data-line-identity-status] p");
  const tokenInput = page.querySelector("[data-line-id-token]");
  const initialize = async () => {
    try {
      await liff.init({ liffId: page.dataset.liffId });
      if (!liff.isLoggedIn()) return liff.login({ redirectUri: window.location.href });
      tokenInput.value = liff.getIDToken() || "";
      const profile = await liff.getProfile();
      page.dataset.liffReady = tokenInput.value ? "true" : "false";
      status.textContent = `เชื่อมต่อ LINE แล้ว: ${profile.displayName}`;
      page.dispatchEvent(new CustomEvent("line-identity-ready"));
    } catch (error) {
      page.dataset.liffReady = "false";
      status.textContent = "เชื่อมต่อ LINE ไม่สำเร็จ กรุณาปิดแล้วเปิดแบบฟอร์มจาก LINE อีกครั้ง";
    }
  };
  initialize();
});

document.addEventListener("DOMContentLoaded", () => {
  const page = document.querySelector("[data-public-report-page]");
  const mapElement = page?.querySelector("[data-public-report-map]");
  if (!page || !mapElement || typeof ol === "undefined") return;

  const readJson = (selector, fallback) => {
    try { return JSON.parse(page.querySelector(selector)?.textContent || ""); }
    catch (_error) { return fallback; }
  };
  const boundaryData = readJson("[data-public-boundary]", null);
  const importantPlaces = readJson("[data-public-important-places]", []);
  const latitudeInput = page.querySelector("[data-public-latitude]");
  const longitudeInput = page.querySelector("[data-public-longitude]");
  const locationNameInput = page.querySelector("[data-public-location-name]");
  const coordinateLabel = page.querySelector("[data-public-coordinate]");
  const addressLabel = page.querySelector("[data-public-address]");
  const submit = page.querySelector("[data-public-report-submit]");
  const submitHint = page.querySelector("[data-public-submit-hint]");
  const consent = page.querySelector("[data-public-report-consent]");
  const form = page.querySelector(".public-report-form");
  const incidentTypeSelect = page.querySelector("[data-incident-type-select]");
  const incidentTypePlaceholder = page.querySelector("[data-public-select-placeholder]");
  const severitySelect = page.querySelector("[data-public-severity-select]");
  const severityPlaceholder = page.querySelector("[data-public-severity-placeholder]");
  const incidentTypeOtherField = page.querySelector("[data-incident-type-other]");
  const incidentTypeOtherInput = page.querySelector("[data-incident-type-other-input]");
  const similarIncidents = page.querySelector("[data-public-similar-incidents]");
  const photoInput = page.querySelector("[data-public-photo-input]");
  const photoPreview = page.querySelector("[data-public-photo-preview]");
  const photoMessage = page.querySelector("[data-public-photo-message]");
  const photoLightbox = page.querySelector("[data-public-photo-lightbox]");
  const photoLightboxImage = page.querySelector("[data-public-photo-lightbox-image]");
  let selectedPhotos = [];
  let previewUrls = [];
  let duplicateReviewRequired = false;
  let duplicateReviewed = true;
  let duplicateConfirmed = false;
  let duplicateRequestId = 0;

  const syncIncidentTypePlaceholder = () => {
    incidentTypePlaceholder?.classList.toggle("is-empty", !incidentTypeSelect?.value);
  };
  if (incidentTypePlaceholder?.dataset.empty === "true" && incidentTypeSelect) incidentTypeSelect.selectedIndex = -1;
  incidentTypeSelect?.addEventListener("change", syncIncidentTypePlaceholder);
  syncIncidentTypePlaceholder();
  const syncSeverityPlaceholder = () => severityPlaceholder?.classList.toggle("is-empty", !severitySelect?.value);
  if (severityPlaceholder?.dataset.empty === "true" && severitySelect) severitySelect.selectedIndex = -1;
  severitySelect?.addEventListener("change", syncSeverityPlaceholder);
  syncSeverityPlaceholder();
  page.querySelectorAll("[data-public-custom-select]").forEach((wrapper) => {
    const select = wrapper.querySelector("select");
    const trigger = wrapper.querySelector("[data-public-custom-select-trigger]");
    const triggerText = trigger.querySelector("span");
    const menu = wrapper.querySelector("[data-public-custom-select-menu]");
    const options = [...menu.querySelectorAll("[data-value]")];
    const placeholder = triggerText.textContent;
    const close = () => { menu.hidden = true; trigger.setAttribute("aria-expanded", "false"); wrapper.classList.remove("is-open"); };
    trigger.addEventListener("click", () => {
      const willOpen = menu.hidden;
      page.querySelectorAll("[data-public-custom-select-menu]").forEach((other) => { other.hidden = true; });
      page.querySelectorAll("[data-public-custom-select-trigger]").forEach((other) => other.setAttribute("aria-expanded", "false"));
      page.querySelectorAll("[data-public-custom-select]").forEach((other) => other.classList.remove("is-open"));
      menu.hidden = !willOpen;
      trigger.setAttribute("aria-expanded", String(willOpen));
      wrapper.classList.toggle("is-open", willOpen);
    });
    options.forEach((option) => option.addEventListener("click", () => {
      select.value = option.dataset.value;
      triggerText.textContent = option.textContent;
      wrapper.classList.remove("is-empty");
      options.forEach((item) => item.setAttribute("aria-selected", String(item === option)));
      close();
      select.dispatchEvent(new Event("change", { bubbles: true }));
    }));
    document.addEventListener("click", (event) => { if (!wrapper.contains(event.target)) close(); });
    trigger.addEventListener("keydown", (event) => { if (event.key === "Escape") close(); });
    if (!select.value) { wrapper.classList.add("is-empty"); triggerText.textContent = placeholder; }
  });

  const syncPhotoInput = () => {
    const transfer = new DataTransfer();
    selectedPhotos.forEach((file) => transfer.items.add(file));
    photoInput.files = transfer.files;
  };
  const renderPhotoPreviews = () => {
    previewUrls.forEach((url) => URL.revokeObjectURL(url));
    previewUrls = selectedPhotos.map((file) => URL.createObjectURL(file));
    photoPreview.innerHTML = "";
    photoPreview.hidden = selectedPhotos.length === 0;
    selectedPhotos.forEach((file, index) => {
      const item = document.createElement("article");
      item.innerHTML = `<button type="button" class="public-photo-preview-open"><img alt=""></button><div><span></span><small></small></div><button type="button" class="public-photo-preview-remove"><span class="material-symbols-outlined">close</span></button>`;
      const openButton = item.querySelector(".public-photo-preview-open");
      const removeButton = item.querySelector(".public-photo-preview-remove");
      openButton.setAttribute("aria-label", `เปิดดู ${file.name}`);
      openButton.querySelector("img").src = previewUrls[index];
      openButton.querySelector("img").alt = `ภาพตัวอย่าง ${index + 1}`;
      item.querySelector("div span").textContent = index + 1;
      item.querySelector("div small").textContent = file.name;
      removeButton.setAttribute("aria-label", `ลบ ${file.name}`);
      openButton.addEventListener("click", () => {
        photoLightboxImage.src = previewUrls[index];
        photoLightboxImage.alt = file.name;
        photoLightbox.showModal();
      });
      removeButton.addEventListener("click", () => {
        selectedPhotos.splice(index, 1);
        syncPhotoInput();
        renderPhotoPreviews();
      });
      photoPreview.append(item);
    });
    photoMessage.textContent = selectedPhotos.length ? `เลือกแล้ว ${selectedPhotos.length} จาก 8 รูป` : "";
  };
  photoInput?.addEventListener("change", () => {
    const incoming = [...photoInput.files];
    const known = new Set(selectedPhotos.map((file) => `${file.name}:${file.size}:${file.lastModified}`));
    const valid = incoming.filter((file) => file.size <= 10 * 1024 * 1024 && ["image/jpeg", "image/png", "image/webp"].includes(file.type));
    let overLimit = false;
    valid.forEach((file) => {
      const key = `${file.name}:${file.size}:${file.lastModified}`;
      if (!known.has(key) && selectedPhotos.length < 8) {
        selectedPhotos.push(file);
        known.add(key);
      } else if (!known.has(key)) overLimit = true;
    });
    syncPhotoInput();
    renderPhotoPreviews();
    if (incoming.length !== valid.length) photoMessage.textContent += " · มีไฟล์ที่ไม่รองรับหรือใหญ่เกิน 10 MB";
    else if (overLimit) photoMessage.textContent += " · เลือกได้สูงสุด 8 รูป";
  });
  photoLightbox?.querySelector("[data-public-photo-lightbox-close]")?.addEventListener("click", () => photoLightbox.close());
  photoLightbox?.addEventListener("click", (event) => { if (event.target === photoLightbox) photoLightbox.close(); });
  const geoJson = new ol.format.GeoJSON();
  const boundaryFeatures = boundaryData ? geoJson.readFeatures(boundaryData, { dataProjection: "EPSG:4326", featureProjection: "EPSG:3857" }) : [];
  const boundarySource = new ol.source.Vector({ features: boundaryFeatures });
  const markerSource = new ol.source.Vector();
  const placesSource = new ol.source.Vector();
  const importantPlaceColors = { government: "#527f9d", education: "#a97924", health: "#b94755", culture: "#795f94", tourism: "#b96132", transport: "#438f86", service: "#985675", emergency: "#b7474d", imported: "#438a61" };

  const boundaryRings = boundaryFeatures.flatMap((feature) => {
    const geometry = feature.getGeometry();
    if (geometry?.getType() === "Polygon") return [geometry.getCoordinates()[0]];
    if (geometry?.getType() === "MultiPolygon") return geometry.getCoordinates().map((polygon) => polygon[0]);
    return [];
  });
  const world = 20037508.34;
  const maskSource = new ol.source.Vector({
    features: boundaryRings.length ? [new ol.Feature(new ol.geom.Polygon([[
      [-world, -world], [world, -world], [world, world], [-world, world], [-world, -world]
    ], ...boundaryRings]))] : []
  });
  const maskLayer = new ol.layer.Vector({
    source: maskSource,
    style: new ol.style.Style({ fill: new ol.style.Fill({ color: "rgba(44, 57, 48, 0.58)" }) })
  });

  const boundaryLayer = new ol.layer.Vector({
    source: boundarySource,
    style: new ol.style.Style({ fill: new ol.style.Fill({ color: "rgba(0, 0, 0, 0)" }), stroke: new ol.style.Stroke({ color: "#567f6d", width: 2.5 }) })
  });
  const placesLayer = new ol.layer.Vector({
    source: placesSource,
    declutter: true,
    style: (feature) => {
      const place = feature.get("place") || {};
      const color = importantPlaceColors[place.category] || "#806f5f";
      return new ol.style.Style({
        image: new ol.style.Circle({ radius: 5, fill: new ol.style.Fill({ color }), stroke: new ol.style.Stroke({ color: "#fff", width: 2 }) }),
        text: new ol.style.Text({ text: place.name || "สถานที่สำคัญ", offsetY: -13, font: '500 11px "Google Sans", sans-serif', fill: new ol.style.Fill({ color: "#674427" }), stroke: new ol.style.Stroke({ color: "rgba(255,255,255,.95)", width: 3 }), padding: [2, 3, 2, 3] })
      });
    }
  });
  const markerLayer = new ol.layer.Vector({ source: markerSource });
  let addressRequestId = 0;

  const updateApproximateAddress = async (lon, lat) => {
    const requestId = ++addressRequestId;
    locationNameInput.value = "ตำแหน่งที่ผู้แจ้งเหตุปักหมุด";
    addressLabel.textContent = "กำลังค้นหาที่อยู่โดยประมาณ...";
    addressLabel.classList.add("loading");
    try {
      const url = new URL(page.dataset.reverseGeocodeUrl, window.location.origin);
      url.searchParams.set("lat", lat);
      url.searchParams.set("lon", lon);
      const response = await fetch(url, { headers: { Accept: "application/json" } });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || "ไม่สามารถค้นหาที่อยู่ได้");
      if (requestId !== addressRequestId) return;
      const address = result.address?.trim();
      locationNameInput.value = address || "ตำแหน่งที่ผู้แจ้งเหตุปักหมุด";
      addressLabel.textContent = address || "ไม่พบรายละเอียดที่อยู่ ระบบจะบันทึกพิกัดที่ปักหมุดแทน";
    } catch (_error) {
      if (requestId !== addressRequestId) return;
      addressLabel.textContent = "ไม่สามารถค้นหาที่อยู่ได้ ระบบจะบันทึกพิกัดที่ปักหมุดแทน";
    } finally {
      if (requestId === addressRequestId) addressLabel.classList.remove("loading");
    }
  };

  const syncOtherIncidentType = () => {
    const show = incidentTypeSelect?.value === "อื่น ๆ";
    if (!incidentTypeOtherField || !incidentTypeOtherInput) return;
    incidentTypeOtherField.hidden = !show;
    incidentTypeOtherInput.disabled = !show;
    incidentTypeOtherInput.required = show;
    updateSubmitState();
  };

  importantPlaces.forEach((place) => {
    const lon = Number(place.lon ?? place.longitude);
    const lat = Number(place.lat ?? place.latitude);
    if (!Number.isFinite(lon) || !Number.isFinite(lat)) return;
    placesSource.addFeature(new ol.Feature({ geometry: new ol.geom.Point(ol.proj.fromLonLat([lon, lat])), place }));
  });

  const initialLon = Number(mapElement.dataset.longitude) || 100.5018;
  const initialLat = Number(mapElement.dataset.latitude) || 13.7563;
  const map = new ol.Map({
    target: mapElement,
    layers: [new ol.layer.Tile({ source: new ol.source.OSM() }), maskLayer, boundaryLayer, placesLayer, markerLayer],
    view: new ol.View({ center: ol.proj.fromLonLat([initialLon, initialLat]), zoom: 13 }),
    controls: []
  });
  if (boundaryFeatures.length) map.getView().fit(boundarySource.getExtent(), { padding: [30, 30, 30, 30], maxZoom: 16, duration: 0 });

  const isInsideBoundary = (coordinate) => boundaryFeatures.some((feature) => feature.getGeometry()?.intersectsCoordinate(coordinate));
  const showOutsideWarning = () => {
    coordinateLabel.textContent = "เลือกตำแหน่งได้เฉพาะภายในขอบเขตพื้นที่รับแจ้งเท่านั้น";
    coordinateLabel.classList.add("error");
  };
  const updateSubmitState = () => {
    const hasLocation = latitudeInput.value !== "" && longitudeInput.value !== "";
    const hasConsent = consent?.checked === true;
    const hasIncidentType = incidentTypeSelect?.value !== "";
    const hasSeverity = severitySelect?.value !== "";
    const requiredFields = [...form.querySelectorAll("input[required], select[required], textarea[required]")].filter((field) => field !== consent);
    const hasRequiredFields = requiredFields.every((field) => field.value.trim() !== "" && field.checkValidity());
    const hasLineIdentity = page.dataset.liffMode !== "true" || page.dataset.liffReady === "true";
    const duplicateReady = !duplicateReviewRequired || duplicateReviewed;
    const ready = hasLocation && hasConsent && hasIncidentType && hasSeverity && hasRequiredFields && hasLineIdentity && duplicateReady && !duplicateConfirmed;
    submit.disabled = !ready;
    submitHint.hidden = ready;
    if (duplicateConfirmed) submitHint.textContent = "ยืนยันเหตุการณ์เดิมเรียบร้อยแล้ว ระบบไม่ได้สร้างเรื่องใหม่";
    else if (duplicateReviewRequired && !duplicateReviewed) submitHint.textContent = "กรุณาตรวจสอบเหตุการณ์ใกล้เคียงก่อนส่งเรื่องใหม่";
    else if (!hasIncidentType || !hasSeverity || !hasRequiredFields) submitHint.textContent = "กรุณากรอกข้อมูลที่มีเครื่องหมาย * ให้ครบถ้วน";
    else if (!hasLocation) submitHint.textContent = "กรุณาปักตำแหน่งที่เกิดเหตุก่อนส่งข้อมูล";
    else if (!hasConsent) submitHint.textContent = "กรุณากดยืนยันว่าข้อมูลที่แจ้งเป็นความจริงก่อนส่งข้อมูล";
  };
  const formatReportedAt = (value) => {
    if (!value) return "";
    return new Intl.DateTimeFormat("th-TH", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
  };
  const confirmSameIncident = async (incident) => {
    const url = page.dataset.confirmSimilarUrlTemplate.replace("INCIDENT_ID", incident.id);
    const body = new FormData();
    body.set("incident_type", incidentTypeSelect.value);
    body.set("latitude", latitudeInput.value);
    body.set("longitude", longitudeInput.value);
    const lineToken = page.querySelector("[data-line-id-token]")?.value;
    if (lineToken) body.set("line_id_token", lineToken);
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "" },
        body
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || "ยืนยันเหตุการณ์ไม่สำเร็จ");
      duplicateConfirmed = true;
      duplicateReviewRequired = false;
      duplicateReviewed = true;
      similarIncidents.className = "public-similar-incidents is-confirmed";
      similarIncidents.replaceChildren();
      const heading = document.createElement("strong");
      heading.textContent = `ยืนยันเหตุการณ์เดิม ${result.reference_code} แล้ว`;
      const message = document.createElement("p");
      message.textContent = result.message;
      const status = document.createElement("p");
      status.textContent = `สถานะปัจจุบัน: ${result.status_label}`;
      const actions = document.createElement("div");
      actions.className = "public-similar-success-actions";
      if (!result.line_following && result.connect_line_url) {
        const connect = document.createElement("a");
        connect.href = result.connect_line_url;
        connect.className = "public-similar-connect";
        connect.textContent = "เชื่อมต่อ LINE เพื่อรับความคืบหน้า";
        actions.append(connect);
      }
      if (result.line_following && page.dataset.liffMode === "true") {
        const close = document.createElement("button");
        close.type = "button";
        close.className = "public-similar-connect";
        close.textContent = "ปิดหน้าต่าง";
        close.addEventListener("click", () => typeof liff !== "undefined" && liff.isInClient() ? liff.closeWindow() : window.close());
        actions.append(close);
      }
      const another = document.createElement("button");
      another.type = "button";
      another.className = "public-similar-another";
      another.textContent = "แจ้งเหตุอื่น";
      another.addEventListener("click", () => window.location.reload());
      actions.append(another);
      similarIncidents.append(heading, status, message, actions);
      submit.hidden = true;
      updateSubmitState();
      similarIncidents.scrollIntoView({ behavior: "smooth", block: "center" });
    } catch (error) {
      window.alert(error.message);
    }
  };
  const renderSimilarIncidents = (incidents) => {
    similarIncidents.replaceChildren();
    if (!incidents.length) {
      similarIncidents.hidden = true;
      duplicateReviewRequired = false;
      duplicateReviewed = true;
      updateSubmitState();
      return;
    }
    duplicateReviewRequired = true;
    duplicateReviewed = false;
    similarIncidents.hidden = false;
    similarIncidents.className = "public-similar-incidents";
    const header = document.createElement("header");
    header.innerHTML = '<span class="material-symbols-outlined">content_copy</span><div><strong>พบเหตุการณ์ที่อาจเป็นเรื่องเดียวกัน</strong><p>อยู่ภายใน 300 เมตร และแจ้งในช่วง 7 วันที่ผ่านมา กรุณาตรวจสอบก่อนสร้างเรื่องใหม่</p></div>';
    const list = document.createElement("div");
    list.className = "public-similar-list";
    incidents.forEach((incident) => {
      const card = document.createElement("article");
      const details = document.createElement("div");
      const title = document.createElement("strong");
      title.textContent = incident.title;
      const meta = document.createElement("p");
      meta.className = "public-similar-meta";
      const type = document.createElement("span");
      type.innerHTML = '<span class="material-symbols-outlined">category</span>';
      type.append(document.createTextNode(incident.incident_type));
      const status = document.createElement("span");
      status.className = `status-${incident.status}`;
      status.innerHTML = '<span class="material-symbols-outlined">schedule</span>';
      status.append(document.createTextNode(incident.status_label));
      const distance = document.createElement("span");
      distance.innerHTML = '<span class="material-symbols-outlined">near_me</span>';
      distance.append(document.createTextNode(`ห่างประมาณ ${incident.distance_meters} เมตร`));
      meta.append(type, status, distance);
      const time = document.createElement("small");
      time.innerHTML = '<span class="material-symbols-outlined">confirmation_number</span>';
      time.append(document.createTextNode(`${incident.reference_code} · แจ้งเมื่อ ${formatReportedAt(incident.reported_at)}`));
      details.append(title, meta, time);
      const same = document.createElement("button");
      same.type = "button";
      same.className = "public-similar-same";
      same.innerHTML = '<span class="material-symbols-outlined">check_circle</span><span>เป็นเหตุการณ์เดียวกัน</span>';
      same.addEventListener("click", () => confirmSameIncident(incident));
      card.append(details, same);
      list.append(card);
    });
    const different = document.createElement("button");
    different.type = "button";
    different.className = "public-similar-different";
    different.innerHTML = '<span class="material-symbols-outlined">add_location_alt</span><span>เป็นคนละเหตุ — ดำเนินการแจ้งเรื่องใหม่</span>';
    const reviewedMessage = document.createElement("div");
    reviewedMessage.className = "public-similar-reviewed-message";
    reviewedMessage.hidden = true;
    reviewedMessage.innerHTML = '<span class="material-symbols-outlined">check_circle</span><div><strong>ยืนยันแล้วว่าเป็นคนละเหตุ</strong><p>สามารถกรอกข้อมูลต่อและส่งเป็นเรื่องใหม่ได้</p></div>';
    different.addEventListener("click", () => {
      duplicateReviewed = !duplicateReviewed;
      similarIncidents.classList.toggle("is-reviewed", duplicateReviewed);
      reviewedMessage.hidden = !duplicateReviewed;
      similarIncidents.querySelectorAll(".public-similar-same").forEach((button) => {
        button.disabled = duplicateReviewed;
        button.setAttribute("aria-disabled", String(duplicateReviewed));
      });
      different.classList.toggle("is-change", duplicateReviewed);
      different.innerHTML = duplicateReviewed
        ? '<span class="material-symbols-outlined">edit</span><span>เปลี่ยนคำตอบ</span>'
        : '<span class="material-symbols-outlined">add_location_alt</span><span>เป็นคนละเหตุ — ดำเนินการแจ้งเรื่องใหม่</span>';
      updateSubmitState();
    });
    similarIncidents.append(header, list, reviewedMessage, different);
    updateSubmitState();
  };
  const checkSimilarIncidents = async () => {
    duplicateConfirmed = false;
    submit.hidden = false;
    const latitude = latitudeInput.value;
    const longitude = longitudeInput.value;
    const incidentType = incidentTypeSelect?.value;
    if (!latitude || !longitude || !incidentType) return renderSimilarIncidents([]);
    const requestId = ++duplicateRequestId;
    similarIncidents.hidden = false;
    similarIncidents.className = "public-similar-incidents is-loading";
    similarIncidents.textContent = "กำลังตรวจสอบเหตุการณ์ใกล้เคียง…";
    const url = new URL(page.dataset.similarIncidentsUrl, window.location.origin);
    url.searchParams.set("latitude", latitude);
    url.searchParams.set("longitude", longitude);
    url.searchParams.set("incident_type", incidentType);
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || "ตรวจสอบเหตุการณ์ไม่สำเร็จ");
      if (requestId === duplicateRequestId) renderSimilarIncidents(result.incidents || []);
    } catch (_error) {
      if (requestId !== duplicateRequestId) return;
      similarIncidents.hidden = true;
      duplicateReviewRequired = false;
      duplicateReviewed = true;
      updateSubmitState();
    }
  };
  page.addEventListener("line-identity-ready", updateSubmitState);
  const setLocation = (lon, lat, center = false) => {
    const coordinate = ol.proj.fromLonLat([lon, lat]);
    if (!isInsideBoundary(coordinate)) { showOutsideWarning(); return false; }
    latitudeInput.value = lat.toFixed(6);
    longitudeInput.value = lon.toFixed(6);
    markerSource.clear();
    const marker = new ol.Feature(new ol.geom.Point(coordinate));
    marker.setStyle(window.SmartTambonLocation.selectedPinStyle());
    markerSource.addFeature(marker);
    coordinateLabel.textContent = `${lat.toFixed(6)}, ${lon.toFixed(6)}`;
    coordinateLabel.classList.remove("error");
    updateApproximateAddress(lon, lat);
    updateSubmitState();
    checkSimilarIncidents();
    if (center) map.getView().animate({ center: coordinate, zoom: 16, duration: 350 });
    return true;
  };

  if (mapElement.dataset.latitude && mapElement.dataset.longitude) setLocation(initialLon, initialLat);
  incidentTypeSelect?.addEventListener("change", () => { syncOtherIncidentType(); checkSimilarIncidents(); });
  syncOtherIncidentType();
  consent?.addEventListener("change", updateSubmitState);
  form?.addEventListener("input", updateSubmitState);
  form?.addEventListener("change", updateSubmitState);
  updateSubmitState();
  map.on("click", (event) => { const [lon, lat] = ol.proj.toLonLat(event.coordinate); setLocation(lon, lat); });
  window.SmartTambonLocation?.attachSearch(map, {
    placeholder: "ค้นหาสถานที่ ถนน หรือหมู่บ้านที่เกิดเหตุ",
    onSelect: (lon, lat, result) => {
      if (!setLocation(lon, lat)) return;
      // Keep the searched place name instead of the reverse-geocoded address.
      addressRequestId += 1;
      locationNameInput.value = result.short_name;
      addressLabel.textContent = result.display_name || result.short_name;
      addressLabel.classList.remove("loading");
    }
  });
  page.querySelector("[data-public-use-location]")?.addEventListener("click", () => {
    if (!navigator.geolocation) return window.alert("อุปกรณ์นี้ไม่รองรับการค้นหาตำแหน่ง");
    navigator.geolocation.getCurrentPosition(
      (position) => { if (!setLocation(position.coords.longitude, position.coords.latitude, true)) window.alert("ตำแหน่งปัจจุบันอยู่นอกพื้นที่รับแจ้ง กรุณาปักหมุดภายในขอบเขตสีน้ำเงิน"); },
      () => window.alert("ไม่สามารถอ่านตำแหน่งได้ กรุณาอนุญาตการเข้าถึงตำแหน่งหรือปักหมุดบนแผนที่")
    );
  });
});
