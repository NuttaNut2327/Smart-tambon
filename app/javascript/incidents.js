document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll("[data-incident-backdated-toggle]").forEach((toggle) => {
    const form = toggle.closest("form");
    const dateField = form?.querySelector("[data-incident-occurred-on]");
    const dateInput = form?.querySelector("[data-incident-occurred-on-input]");
    const storedDateInput = form?.querySelector("[data-incident-occurred-on-value]");
    const datePicker = form?.querySelector("[data-incident-date-picker]");
    const datePickerButton = form?.querySelector("[data-incident-date-picker-button]");
    const timeField = form?.querySelector("[data-incident-occurred-time]");
    const occurredAtInput = form?.querySelector("[data-incident-occurred-at-value]");
    const timeHour = form?.querySelector("[data-incident-time-hour]");
    const timeMinute = form?.querySelector("[data-incident-time-minute]");
    if (!dateField || !dateInput || !storedDateInput || !datePicker || !datePickerButton || !timeField || !occurredAtInput || !timeHour || !timeMinute) return;

    const syncOccurredAt = () => {
      const hour = Number(timeHour.value);
      const minute = Number(timeMinute.value);
      const hourValid = /^\d{1,2}$/.test(timeHour.value) && hour >= 0 && hour <= 23;
      const minuteValid = /^\d{1,2}$/.test(timeMinute.value) && minute >= 0 && minute <= 59;
      occurredAtInput.value = storedDateInput.value && hourValid && minuteValid
        ? `${storedDateInput.value}T${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}:00+07:00`
        : "";
    };

    const syncStoredDate = () => {
      const match = dateInput.value.trim().match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
      if (!match) {
        storedDateInput.value = "";
        dateInput.setCustomValidity(dateInput.value ? "กรุณาระบุวันที่ในรูปแบบ วว/ดด/ปปปป" : "");
        syncOccurredAt();
        return;
      }
      const [, day, month, year] = match;
      const candidate = new Date(`${year}-${month}-${day}T00:00:00`);
      const valid = candidate.getFullYear() === Number(year) && candidate.getMonth() + 1 === Number(month) && candidate.getDate() === Number(day);
      storedDateInput.value = valid ? `${year}-${month}-${day}` : "";
      datePicker.value = valid ? `${year}-${month}-${day}` : "";
      dateInput.setCustomValidity(valid ? "" : "วันที่ไม่ถูกต้อง");
      syncOccurredAt();
    };

    const syncFromDatePicker = () => {
      if (!datePicker.value) return;
      const [year, month, day] = datePicker.value.split("-");
      dateInput.value = `${day}/${month}/${year}`;
      storedDateInput.value = datePicker.value;
      dateInput.setCustomValidity("");
      syncOccurredAt();
    };

    const syncOccurredTime = () => {
      const hour = Number(timeHour.value);
      const minute = Number(timeMinute.value);
      const hourValid = /^\d{1,2}$/.test(timeHour.value) && hour >= 0 && hour <= 23;
      const minuteValid = /^\d{1,2}$/.test(timeMinute.value) && minute >= 0 && minute <= 59;
      timeHour.setCustomValidity(timeHour.value && !hourValid ? "กรุณาระบุชั่วโมงระหว่าง 0–23" : "");
      timeMinute.setCustomValidity(timeMinute.value && !minuteValid ? "กรุณาระบุนาทีระหว่าง 0–59" : "");
      syncOccurredAt();
    };

    const updateBackdatedField = () => {
      dateField.hidden = !toggle.checked;
      timeField.hidden = !toggle.checked;
      dateInput.disabled = !toggle.checked;
      storedDateInput.disabled = !toggle.checked;
      datePicker.disabled = !toggle.checked;
      datePickerButton.disabled = !toggle.checked;
      occurredAtInput.disabled = !toggle.checked;
      timeHour.disabled = !toggle.checked;
      timeMinute.disabled = !toggle.checked;
      dateInput.required = toggle.checked;
      timeHour.required = toggle.checked;
      timeMinute.required = toggle.checked;
      if (!toggle.checked) {
        dateInput.value = "";
        storedDateInput.value = "";
        datePicker.value = "";
        occurredAtInput.value = "";
        timeHour.value = "";
        timeMinute.value = "";
        dateInput.setCustomValidity("");
        timeHour.setCustomValidity("");
        timeMinute.setCustomValidity("");
      }
    };

    dateInput.addEventListener("input", syncStoredDate);
    dateInput.addEventListener("blur", syncStoredDate);
    datePicker.addEventListener("change", syncFromDatePicker);
    timeHour.addEventListener("input", syncOccurredTime);
    timeMinute.addEventListener("input", syncOccurredTime);
    datePickerButton.addEventListener("click", () => {
      if (typeof datePicker.showPicker === "function") datePicker.showPicker();
      else datePicker.click();
    });
    toggle.addEventListener("change", updateBackdatedField);
    updateBackdatedField();
  });

  document.querySelectorAll("[data-incident-category-select]").forEach((categorySelect) => {
    const form = categorySelect.closest("form");
    const disasterField = form?.querySelector("[data-disaster-incident-type]");
    const generalField = form?.querySelector("[data-general-incident-type]");
    const disasterInput = disasterField?.querySelector("select");
    const generalInput = generalField?.querySelector("input");
    if (!disasterField || !generalField || !disasterInput || !generalInput) return;

    const updateIncidentTypeField = () => {
      const isDisaster = categorySelect.value === "disaster";
      disasterField.hidden = !isDisaster;
      disasterInput.disabled = !isDisaster;
      generalField.hidden = isDisaster;
      generalInput.disabled = isDisaster;
    };

    categorySelect.addEventListener("change", updateIncidentTypeField);
    updateIncidentTypeField();
  });

  document.querySelectorAll(".incident-list-panel").forEach((panel) => {
    const filters = panel.querySelector("[data-incident-status-filters]");
    const sourceFilters = panel.querySelector("[data-incident-source-filters]");
    if (!filters) return;
    const filterStorageKey = "smart-tambon:incident-status-filter";
    const list = panel.querySelector("[data-incident-card-list]");
    const countLabel = panel.querySelector("[data-incident-visible-count]");
    const emptyMessage = list?.querySelector("[data-incident-filter-empty]");
    if (!list) return;

    const cards = Array.from(list.querySelectorAll("[data-incident-status-group]"));
    let selectedStatus = "all";
    let selectedSource = "all";
    const applyFilters = () => {
      let visibleCount = 0;
      cards.forEach((card) => {
        const statusMatches = selectedStatus === "all" || card.dataset.incidentStatusGroup === selectedStatus;
        const sourceMatches = selectedSource === "all" || card.dataset.incidentSource === selectedSource;
        const visible = statusMatches && sourceMatches;
        card.classList.toggle("is-filtered-out", !visible);
        card.hidden = !visible;
        if (visible) visibleCount += 1;
      });
      if (countLabel) countLabel.textContent = `${visibleCount} รายการ`;
      if (emptyMessage) emptyMessage.hidden = visibleCount > 0;
    };
    filters.addEventListener("click", (event) => {
      const button = event.target.closest("[data-incident-status-filter]");
      if (!button) return;
      selectedStatus = button.dataset.incidentStatusFilter;
      sessionStorage.setItem(filterStorageKey, selectedStatus);
      filters.querySelectorAll("[data-incident-status-filter]").forEach((item) => item.classList.toggle("active", item === button));
      applyFilters();
    });
    sourceFilters?.addEventListener("click", (event) => {
      const button = event.target.closest("[data-incident-source-filter]");
      if (!button) return;
      selectedSource = button.dataset.incidentSourceFilter;
      sourceFilters.querySelectorAll("[data-incident-source-filter]").forEach((item) => item.classList.toggle("active", item === button));
      applyFilters();
    });
    const activeCardStatus = list.querySelector(".incident-list-card.active")?.dataset.incidentStatusGroup;
    const activeCardFilter = activeCardStatus && filters.querySelector(`[data-incident-status-filter="${activeCardStatus}"]`);
    const savedStatus = sessionStorage.getItem(filterStorageKey);
    const savedFilter = savedStatus && filters.querySelector(`[data-incident-status-filter="${savedStatus}"]`);
    (activeCardFilter || savedFilter || filters.querySelector("[data-incident-status-filter].active"))?.click();
    sourceFilters?.querySelector("[data-incident-source-filter].active")?.click();
  });

  const incidentNotification = document.querySelector("[data-incident-notification]");
  if (incidentNotification) {
    const storageKey = "smart-tambon:last-seen-incident";
    const codeElement = incidentNotification.querySelector("[data-incident-notification-code]");
    const titleElement = incidentNotification.querySelector("[data-incident-notification-title]");
    const openLink = incidentNotification.querySelector("[data-incident-notification-open]");
    let displayedIncidentId = null;

    const updatePendingBadge = (count) => {
      const navLink = document.querySelector("[data-incident-nav]");
      if (!navLink) return;
      let badge = navLink.querySelector("[data-pending-incident-count]");
      if (count > 0) {
        if (!badge) {
          badge = document.createElement("em");
          badge.className = "nav-alert-count";
          badge.dataset.pendingIncidentCount = "";
          navLink.appendChild(badge);
        }
        badge.textContent = count;
      } else {
        badge?.remove();
      }
    };

    const hideNotification = () => {
      if (displayedIncidentId) sessionStorage.setItem(storageKey, displayedIncidentId);
      incidentNotification.hidden = true;
    };

    incidentNotification.querySelector("[data-incident-notification-close]")?.addEventListener("click", hideNotification);
    openLink?.addEventListener("click", () => {
      if (displayedIncidentId) sessionStorage.setItem(storageKey, displayedIncidentId);
    });

    const refreshIncidentNotification = async () => {
      try {
        const response = await fetch(incidentNotification.dataset.notificationUrl, {
          headers: { Accept: "application/json" },
          credentials: "same-origin"
        });
        if (!response.ok) return;
        const payload = await response.json();
        updatePendingBadge(Number(payload.pending_count) || 0);
        const incident = payload.incident;
        if (!incident || incident.id === sessionStorage.getItem(storageKey)) return;

        displayedIncidentId = incident.id;
        codeElement.textContent = incident.reference_code || "เหตุการณ์ใหม่";
        titleElement.textContent = incident.title || "มีรายการแจ้งเหตุที่รอรับเรื่อง";
        openLink.href = incident.url;
        incidentNotification.dataset.severity = incident.severity || "general";
        incidentNotification.hidden = false;
      } catch (_error) {
        // Keep the page usable if notification polling is temporarily unavailable.
      }
    };

    refreshIncidentNotification();
    window.setInterval(refreshIncidentNotification, 15000);
  }

  document.querySelectorAll("[data-open-incident-dialog]").forEach((button) => {
    button.addEventListener("click", () => {
      document.getElementById(button.dataset.openIncidentDialog)?.showModal();
      const menu = button.closest("[data-incident-settings-menu]");
      const options = menu?.querySelector("[data-incident-settings-options]");
      const trigger = menu?.querySelector("[data-incident-settings-trigger]");
      if (options) options.hidden = true;
      trigger?.setAttribute("aria-expanded", "false");
    });
  });
  document.querySelectorAll("[data-incident-settings-menu]").forEach((menu) => {
    const trigger = menu.querySelector("[data-incident-settings-trigger]");
    const options = menu.querySelector("[data-incident-settings-options]");
    trigger?.addEventListener("click", (event) => {
      event.stopPropagation();
      const opening = options.hidden;
      document.querySelectorAll("[data-incident-settings-options]").forEach((other) => { other.hidden = true; });
      document.querySelectorAll("[data-incident-settings-trigger]").forEach((other) => other.setAttribute("aria-expanded", "false"));
      options.hidden = !opening;
      trigger.setAttribute("aria-expanded", String(opening));
    });
  });
  document.addEventListener("click", (event) => {
    if (event.target.closest("[data-incident-settings-menu]")) return;
    document.querySelectorAll("[data-incident-settings-options]").forEach((options) => { options.hidden = true; });
    document.querySelectorAll("[data-incident-settings-trigger]").forEach((trigger) => trigger.setAttribute("aria-expanded", "false"));
  });
  document.querySelectorAll("[data-close-incident-dialog]").forEach((button) => {
    button.addEventListener("click", () => button.closest("dialog")?.close());
  });
  document.querySelectorAll("dialog.incident-dialog").forEach((dialog) => {
    dialog.addEventListener("click", (event) => { if (event.target === dialog) dialog.close(); });
  });
  const shareUrlInput = document.querySelector("[data-public-report-share-url]");
  const shareSourceSelect = document.querySelector("[data-public-report-share-source]");
  const shareStatus = document.querySelector("[data-public-share-status]");
  shareSourceSelect?.addEventListener("change", () => {
    shareUrlInput.value = shareSourceSelect.value;
    if (shareStatus) shareStatus.textContent = "";
  });
  document.querySelector("[data-copy-public-form-link]")?.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(shareUrlInput.value);
      shareStatus.textContent = "คัดลอกลิงก์แล้ว";
    } catch (_error) {
      shareUrlInput.select();
      document.execCommand("copy");
      shareStatus.textContent = "คัดลอกลิงก์แล้ว";
    }
  });
  document.querySelector("[data-native-share-public-form]")?.addEventListener("click", async () => {
    if (navigator.share) await navigator.share({ title: "แบบฟอร์มแจ้งเหตุ Smart Tambon", url: shareUrlInput.value });
    else {
      await navigator.clipboard.writeText(shareUrlInput.value);
      shareStatus.textContent = "อุปกรณ์นี้ไม่รองรับเมนูแชร์ จึงคัดลอกลิงก์ให้แล้ว";
    }
  });
  document.querySelectorAll("[data-incident-usage-picker]").forEach((picker) => {
    const list = picker.querySelector("[data-incident-usage-list]");
    const template = picker.querySelector("[data-incident-usage-template]");
    const empty = picker.querySelector("[data-incident-usage-empty]");
    const updateEmpty = () => { if (empty) empty.hidden = list.children.length > 0; };
    picker.querySelector("[data-add-incident-usage]")?.addEventListener("click", () => {
      list.appendChild(template.content.cloneNode(true));
      updateEmpty();
    });
    list.addEventListener("click", (event) => {
      const removeButton = event.target.closest("[data-remove-incident-usage]");
      if (!removeButton) return;
      removeButton.closest(".incident-usage-row")?.remove();
      updateEmpty();
    });
    list.addEventListener("change", (event) => {
      const select = event.target.closest('select[name="progress[usages][][key]"]');
      if (!select) return;
      const quantity = select.closest(".incident-usage-row")?.querySelector('input[name="progress[usages][][quantity]"]');
      const option = select.selectedOptions[0];
      if (!quantity) return;
      quantity.max = option?.dataset.available || "";
      quantity.placeholder = option?.dataset.unit ? `สูงสุด ${option.dataset.available} ${option.dataset.unit}` : "";
      if (quantity.value && Number(quantity.value) > Number(quantity.max)) quantity.value = quantity.max;
    });
  });

  if (window.ol) {
    const importantPlaceCategories = ["government", "education", "health", "culture", "tourism", "transport", "service", "emergency"];
    const importantPlaceColors = { government: "#2563eb", education: "#d99000", health: "#e11d48", culture: "#7c3aed", tourism: "#ea580c", transport: "#0891b2", service: "#db2777", emergency: "#dc2626", imported: "#059669" };
    const importantPlacesPromise = Promise.all([
      ...importantPlaceCategories.map((category) => fetch(`/api/places?category=${category}`, { headers: { Accept: "application/json" } })
        .then((response) => response.ok ? response.json() : { data: [] })
        .then((payload) => (payload.data || []).map((place) => ({ ...place, category })))
        .catch(() => [])),
      fetch("/api/dynamic_layers?layer_key=important_place", { headers: { Accept: "application/json" } })
        .then((response) => response.ok ? response.json() : [])
        .then((records) => records.map((record) => ({ name: record.name, lon: record.location?.[0], lat: record.location?.[1], category: "imported" })))
        .catch(() => [])
    ]).then((groups) => groups.flat().filter((place) => Number.isFinite(Number(place.lon)) && Number.isFinite(Number(place.lat))).slice(0, 350));

    document.querySelectorAll("[data-incident-location-picker]").forEach((picker) => {
      const mapElement = picker.querySelector("[data-picker-map]");
      const latitudeInput = picker.querySelector("[data-picker-latitude]");
      const longitudeInput = picker.querySelector("[data-picker-longitude]");
      const coordinateLabel = picker.querySelector("[data-picker-coordinate]");
      const savedLongitude = Number(mapElement.dataset.longitude);
      const savedLatitude = Number(mapElement.dataset.latitude);
      const hasSavedPoint = Number.isFinite(savedLongitude) && Number.isFinite(savedLatitude);
      const defaultLongitude = Number(mapElement.dataset.defaultLongitude);
      const defaultLatitude = Number(mapElement.dataset.defaultLatitude);
      const center = ol.proj.fromLonLat(hasSavedPoint ? [savedLongitude, savedLatitude] : [defaultLongitude, defaultLatitude]);
      const markerSource = new ol.source.Vector();
      const markerLayer = new ol.layer.Vector({ source: markerSource });
      const placesSource = new ol.source.Vector();
      const placesLayer = new ol.layer.Vector({
        source: placesSource,
        declutter: true,
        style: (feature) => {
          const place = feature.get("place");
          const color = importantPlaceColors[place.category] || "#475569";
          return new ol.style.Style({
            image: new ol.style.Circle({ radius: 5, fill: new ol.style.Fill({ color }), stroke: new ol.style.Stroke({ color: "#fff", width: 2 }) }),
            text: new ol.style.Text({ text: place.name || "สถานที่สำคัญ", offsetY: -13, font: '500 11px "Google Sans", sans-serif', fill: new ol.style.Fill({ color: "#173653" }), stroke: new ol.style.Stroke({ color: "rgba(255,255,255,.95)", width: 3 }), padding: [2, 3, 2, 3] })
          });
        }
      });
      const boundarySource = new ol.source.Vector();
      const maskSource = new ol.source.Vector();
      const boundaryLayer = new ol.layer.Vector({
        source: boundarySource,
        style: new ol.style.Style({
          fill: new ol.style.Fill({ color: "rgba(0, 0, 0, 0)" }),
          stroke: new ol.style.Stroke({ color: "#176fe5", width: 2.5 })
        })
      });
      const maskLayer = new ol.layer.Vector({
        source: maskSource,
        style: new ol.style.Style({ fill: new ol.style.Fill({ color: "rgba(12, 29, 48, 0.58)" }) })
      });
      let accessBoundary = null;

      const setMarker = (longitude, latitude) => {
        markerSource.clear();
        const marker = new ol.Feature(new ol.geom.Point(ol.proj.fromLonLat([longitude, latitude])));
        marker.setStyle(new ol.style.Style({
          image: new ol.style.Circle({ radius: 8, fill: new ol.style.Fill({ color: "#176fe5" }), stroke: new ol.style.Stroke({ color: "#ffffff", width: 3 }) })
        }));
        markerSource.addFeature(marker);
        latitudeInput.value = latitude.toFixed(6);
        longitudeInput.value = longitude.toFixed(6);
        coordinateLabel.textContent = `${latitude.toFixed(6)}, ${longitude.toFixed(6)}`;
      };

      const pickerMap = new ol.Map({
        target: mapElement,
        layers: [new ol.layer.Tile({ source: new ol.source.OSM() }), maskLayer, boundaryLayer, placesLayer, markerLayer],
        view: new ol.View({ center, zoom: hasSavedPoint ? 15 : 12 }),
        controls: []
      });
      if (hasSavedPoint) setMarker(savedLongitude, savedLatitude);
      pickerMap.on("click", (event) => {
        if (accessBoundary && !accessBoundary.intersectsCoordinate(event.coordinate)) {
          coordinateLabel.textContent = "กรุณาปักหมุดภายในขอบเขตพื้นที่ที่ดูแล";
          return;
        }
        const [longitude, latitude] = ol.proj.toLonLat(event.coordinate);
        setMarker(longitude, latitude);
      });

      fetch("/api/access_area", { headers: { Accept: "application/json" } })
        .then((response) => {
          if (!response.ok) throw new Error("boundary unavailable");
          return response.json();
        })
        .then((data) => {
          const boundaryFeature = new ol.format.GeoJSON().readFeature(data, { featureProjection: "EPSG:3857" });
          accessBoundary = boundaryFeature.getGeometry();
          boundarySource.addFeature(boundaryFeature);

          const world = ol.geom.Polygon.fromExtent(ol.proj.get("EPSG:3857").getExtent());
          const polygons = accessBoundary.getType() === "Polygon" ? [accessBoundary] : accessBoundary.getPolygons();
          polygons.forEach((polygon) => world.appendLinearRing(new ol.geom.LinearRing(polygon.getCoordinates()[0])));
          maskSource.addFeature(new ol.Feature(world));

          importantPlacesPromise.then((places) => {
            places.filter((place) => accessBoundary.intersectsCoordinate(ol.proj.fromLonLat([Number(place.lon), Number(place.lat)]))).forEach((place) => {
              placesSource.addFeature(new ol.Feature({ geometry: new ol.geom.Point(ol.proj.fromLonLat([Number(place.lon), Number(place.lat)])), place }));
            });
          });

          if (!hasSavedPoint) pickerMap.getView().fit(accessBoundary.getExtent(), { padding: [24, 24, 24, 24], maxZoom: 16, duration: 250 });
        })
        .catch(() => {
          coordinateLabel.textContent = "ไม่สามารถโหลดขอบเขตพื้นที่ได้ กรุณาลองเปิดฟอร์มใหม่";
        });
      picker.closest("form")?.addEventListener("submit", (event) => {
        if (latitudeInput.value && longitudeInput.value) return;
        event.preventDefault();
        coordinateLabel.textContent = "กรุณาคลิกปักหมุดสถานที่เกิดเหตุบนแผนที่";
        coordinateLabel.scrollIntoView({ behavior: "smooth", block: "center" });
      });
      const pickerDialog = picker.closest("dialog");
      if (pickerDialog) {
        pickerDialog.addEventListener("toggle", () => setTimeout(() => pickerMap.updateSize(), 0));
        pickerDialog._incidentPickerMaps ||= [];
        pickerDialog._incidentPickerMaps.push(pickerMap);
      }
    });

    document.querySelectorAll("[data-open-incident-dialog]").forEach((button) => {
      button.addEventListener("click", () => {
        const dialog = document.getElementById(button.dataset.openIncidentDialog);
        setTimeout(() => dialog?._incidentPickerMaps?.forEach((map) => map.updateSize()), 50);
      });
    });
  }

  const element = document.querySelector("[data-incident-map]");
  if (!element || !window.ol) return;

  const longitude = Number(element.dataset.longitude);
  const latitude = Number(element.dataset.latitude);
  if (!Number.isFinite(longitude) || !Number.isFinite(latitude)) return;

  const point = ol.proj.fromLonLat([longitude, latitude]);
  const marker = new ol.Feature(new ol.geom.Point(point));
  marker.setStyle(new ol.style.Style({
    image: new ol.style.Circle({ radius: 7, fill: new ol.style.Fill({ color: "#176fe5" }), stroke: new ol.style.Stroke({ color: "#ffffff", width: 3 }) })
  }));

  new ol.Map({
    target: element,
    layers: [
      new ol.layer.Tile({ source: new ol.source.OSM() }),
      new ol.layer.Vector({ source: new ol.source.Vector({ features: [marker] }) })
    ],
    view: new ol.View({ center: point, zoom: 15 }),
    controls: []
  });
});
