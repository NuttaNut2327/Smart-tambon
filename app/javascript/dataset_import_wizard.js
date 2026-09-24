document.addEventListener("DOMContentLoaded", () => {
  const token = document.querySelector('meta[name="csrf-token"]')?.content;
  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, character => ({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"}[character]));
  const request = async (url, options = {}) => {
    const response = await fetch(url, { ...options, headers: { Accept: "application/json", "X-CSRF-Token": token, ...(options.headers || {}) } });
    const payload = response.status === 204 ? {} : await response.json();
    if (!response.ok) throw new Error(payload.error || "ไม่สามารถดำเนินการได้");
    return payload;
  };

  document.querySelector("[data-fixed-search]")?.addEventListener("input", event => {
    const query = event.target.value.trim().toLowerCase();
    document.querySelectorAll("[data-fixed-row]").forEach(row => row.hidden = !row.dataset.search.includes(query));
  });

  const manualDialog = document.querySelector("#manual-data-dialog");
  if (manualDialog) {
    const parseOptions = selector => { try { return JSON.parse(manualDialog.querySelector(selector)?.textContent || "[]"); } catch (_) { return []; } };
    const agencies = parseOptions("[data-agency-options]");
    const teams = parseOptions("[data-team-options]");
    manualDialog.querySelector("[data-agency-select]")?.addEventListener("change", event => {
      const agency = agencies.find(item => item.name === event.target.value);
      const codeInput = event.target.form.elements["record[agency_code]"];
      if (codeInput) codeInput.value = agency?.code || "";
    });
    manualDialog.querySelector("[data-team-select]")?.addEventListener("change", event => {
      const team = teams.find(item => item.name === event.target.value);
      const codeInput = event.target.form.elements["record[team_code]"];
      if (codeInput) codeInput.value = team?.code || "";
    });
  }
  const setupAgencyLocationPicker = form => {
    const selectedType = form?.elements.data_type?.value || document.querySelector("#file-import-dialog")?.dataset.selectedType;
    const latitudeInput = form?.elements["record[latitude]"];
    const longitudeInput = form?.elements["record[longitude]"];
    if (selectedType !== "agencies" || !latitudeInput || !longitudeInput || !window.ol) return null;

    const panel = document.createElement("section");
    panel.className = "agency-location-picker";
    panel.innerHTML = `<div class="boundary-editor-heading"><div><b>ปักหมุดสถานที่ตั้งหน่วยงาน *</b><small>คลิกบนแผนที่เพื่อระบุตำแหน่ง ระบบจะเติมข้อมูลที่อยู่ให้อัตโนมัติ</small></div></div><div class="agency-location-state" data-agency-location-state>กำลังโหลดขอบเขตพื้นที่ดูแล…</div><div class="agency-location-map" data-agency-location-map></div>`;
    const anchor = form.querySelector("[data-destination-fields]") || form.querySelector(".record-change-note");
    anchor.before(panel);
    const addressFields = document.createElement("div");
    addressFields.className = "agency-address-fields";
    ["address", "road", "subdistrict", "district", "province", "postcode"].forEach(key => {
      const label = form.elements[`record[${key}]`]?.closest("label");
      if (label) addressFields.append(label);
    });
    if (addressFields.children.length) panel.after(addressFields);

    const accessSource = new ol.source.Vector();
    const markerSource = new ol.source.Vector();
    const map = new ol.Map({ target: panel.querySelector("[data-agency-location-map]"), layers: [
      new ol.layer.Tile({ source: new ol.source.OSM() }),
      new ol.layer.Vector({ source: accessSource, style: new ol.style.Style({ stroke: new ol.style.Stroke({ color: "#20a67a", width: 3 }), fill: new ol.style.Fill({ color: "rgba(32,166,122,.06)" }) }) }),
      new ol.layer.Vector({ source: markerSource, style: new ol.style.Style({ image: new ol.style.Circle({ radius: 8, fill: new ol.style.Fill({ color: "#176fe5" }), stroke: new ol.style.Stroke({ color: "#fff", width: 3 }) }) }) })
    ], view: new ol.View({ center: ol.proj.fromLonLat([100.5, 14]), zoom: 10 }) });
    const format = new ol.format.GeoJSON();
    const state = panel.querySelector("[data-agency-location-state]");
    const addressKeys = ["address", "road", "subdistrict", "district", "province", "postcode"];
    const insideAccessArea = coordinate => accessSource.getFeatures().some(feature => feature.getGeometry()?.intersectsCoordinate(coordinate));
    const setMarker = (longitude, latitude, fit = false) => {
      const coordinate = ol.proj.fromLonLat([Number(longitude), Number(latitude)]);
      markerSource.clear(); markerSource.addFeature(new ol.Feature(new ol.geom.Point(coordinate)));
      latitudeInput.value = Number(latitude).toFixed(6); longitudeInput.value = Number(longitude).toFixed(6);
      if (fit) map.getView().animate({ center: coordinate, zoom: 16, duration: 250 });
    };
    const reverseGeocode = async (longitude, latitude) => {
      state.className = "agency-location-state loading"; state.textContent = "กำลังค้นหาที่อยู่จากตำแหน่ง…";
      try {
        const result = await request(`/api/reverse_geocode?lat=${encodeURIComponent(latitude)}&lon=${encodeURIComponent(longitude)}`);
        addressKeys.forEach(key => { const input = form.elements[`record[${key}]`]; if (input) input.value = result[key] || ""; });
        if (result.road) {
          state.className = "agency-location-state ready"; state.textContent = "ปักหมุดและเติมข้อมูลที่อยู่แล้ว สามารถตรวจสอบหรือแก้ไขข้อความได้";
        } else {
          state.className = "agency-location-state warning"; state.textContent = "พบข้อมูลตำบล อำเภอ จังหวัด แต่บริการแผนที่ไม่มีชื่อซอยหรือถนนของจุดนี้ กรุณาเติมในช่องที่อยู่ได้";
        }
      } catch (error) {
        state.className = "agency-location-state error"; state.textContent = `บันทึกพิกัดแล้ว แต่ค้นหาที่อยู่ไม่สำเร็จ: ${error.message}`;
      }
    };
    map.on("singleclick", event => {
      if (!accessSource.getFeatures().length) { state.className = "agency-location-state error"; state.textContent = "ยังโหลดขอบเขตพื้นที่ดูแลไม่สำเร็จ"; return; }
      if (!insideAccessArea(event.coordinate)) { state.className = "agency-location-state error"; state.textContent = "กรุณาปักหมุดภายในขอบเขตพื้นที่ดูแล"; return; }
      const [longitude, latitude] = ol.proj.toLonLat(event.coordinate);
      setMarker(longitude, latitude); reverseGeocode(longitude, latitude);
    });
    fetch("/api/access_area", { headers: { Accept: "application/json" } }).then(response => response.ok ? response.json() : null).then(json => {
      if (!json) throw new Error();
      const features = format.readFeatures(json, { dataProjection: "EPSG:4326", featureProjection: "EPSG:3857" });
      accessSource.addFeatures(features);
      if (!markerSource.getFeatures().length && features.length) map.getView().fit(accessSource.getExtent(), { padding: [28, 28, 28, 28], maxZoom: 15 });
      state.textContent = latitudeInput.value && longitudeInput.value ? "ตำแหน่งที่บันทึกไว้" : "คลิกบนแผนที่เพื่อปักหมุด";
    }).catch(() => { state.className = "agency-location-state error"; state.textContent = "ไม่สามารถโหลดขอบเขตพื้นที่ดูแลได้"; });
    return {
      activate: () => { map.updateSize(); if (latitudeInput.value && longitudeInput.value) setMarker(longitudeInput.value, latitudeInput.value, true); },
      load: record => { if (record.latitude && record.longitude) setMarker(record.longitude, record.latitude, true); else markerSource.clear(); setTimeout(() => map.updateSize()); }
    };
  };
  const setupBoundaryGeometryEditor = form => {
    if (form?.elements.data_type?.value !== "village_boundaries" || !window.ol) return null;
    const geometryInput = form.elements["record[geometry]"];
    if (!geometryInput) return null;
    const sourceInput = document.createElement("input");
    sourceInput.type = "hidden"; sourceInput.name = "record[boundary_source]"; sourceInput.value = "วาดขอบเขตเอง";
    form.append(sourceInput);
    const villageFieldKeys = ["subdistrict_code", "subdistrict", "village_code", "village_number", "village_name"];
    const villageFieldLabels = villageFieldKeys.map(key => form.elements[`record[${key}]`]?.closest("label")).filter(Boolean);
    villageFieldLabels.forEach(label => label.classList.add("boundary-source-field"));
    const openManualButton = document.querySelector("[data-open-manual]");
    const openImportButton = document.querySelector("[data-open-import]");
    if (openManualButton) openManualButton.textContent = "＋ กำหนดขอบเขตหมู่บ้าน";
    if (openImportButton) openImportButton.hidden = true;
    geometryInput.closest("label")?.classList.add("boundary-source-field");
    geometryInput.type = "hidden";

    const editor = document.createElement("section");
    editor.className = "boundary-geometry-editor";
    editor.innerHTML = `<label class="boundary-village-picker"><span>หมู่บ้านจากข้อมูลประชากร *</span><select data-boundary-village required><option value="">กำลังโหลดรายชื่อหมู่บ้าน…</option></select><small data-boundary-village-help>เลือกหมู่บ้านครั้งเดียว ระบบจะใช้ข้อมูลรหัสและชื่อเดิมให้อัตโนมัติ</small></label><div class="boundary-editor-heading"><div><b>กำหนดขอบเขตหมู่บ้าน *</b><small>เลือกวิธีกำหนดขอบเขตเพียงหนึ่งวิธี</small></div></div><div class="boundary-method-tabs" role="tablist"><button type="button" class="active" data-boundary-method="draw"><span>✎</span><b>วาดบนแผนที่</b><small>คลิกกำหนดแนวเขตด้วยตัวเอง</small></button><button type="button" data-boundary-method="upload"><span>⇧</span><b>อัปโหลด GeoJSON</b><small>ใช้ไฟล์ขอบเขตที่เตรียมไว้</small></button></div><div data-boundary-draw-panel><div class="boundary-draw-toolbar"><span data-boundary-state>กำลังเตรียมแผนที่…</span><button type="button" class="boundary-redraw" data-boundary-redraw hidden>↻ วาดใหม่</button></div><div class="boundary-draw-map" data-boundary-map></div><p class="boundary-map-help">คลิกตามแนวขอบเขต และดับเบิลคลิกเมื่อวาดเสร็จ</p></div><div class="boundary-upload-panel" data-boundary-upload-panel hidden><label><span>⇧</span><b>เลือกหรือลากไฟล์มาวาง</b><small>รองรับ .geojson หรือ .json · Polygon/MultiPolygon 1 ขอบเขต</small><input type="file" accept=".geojson,.json,application/geo+json,application/json" data-boundary-file></label></div>`;
    form.querySelector(".modal-info").before(editor);

    const vectorSource = new ol.source.Vector();
    const vectorLayer = new ol.layer.Vector({ source: vectorSource, style: new ol.style.Style({
      stroke: new ol.style.Stroke({ color: "#1976e9", width: 3 }),
      fill: new ol.style.Fill({ color: "rgba(25,118,233,.16)" }),
      image: new ol.style.Circle({ radius: 5, fill: new ol.style.Fill({ color: "#1976e9" }), stroke: new ol.style.Stroke({ color: "#fff", width: 2 }) })
    }) });
    const boundarySource = new ol.source.Vector();
    const boundaryLayer = new ol.layer.Vector({ source: boundarySource, style: new ol.style.Style({
      stroke: new ol.style.Stroke({ color: "#20a67a", width: 3, lineDash: [8, 5] }),
      fill: new ol.style.Fill({ color: "rgba(32,166,122,.06)" })
    }) });
    const map = new ol.Map({ target: editor.querySelector("[data-boundary-map]"), layers: [
      new ol.layer.Tile({ source: new ol.source.OSM() }), boundaryLayer, vectorLayer
    ], view: new ol.View({ center: ol.proj.fromLonLat([100.5, 14]), zoom: 10 }) });
    const format = new ol.format.GeoJSON();
    let draw;
    const state = editor.querySelector("[data-boundary-state]");
    const redrawButton = editor.querySelector("[data-boundary-redraw]");
    const villageSelect = editor.querySelector("[data-boundary-village]");
    const villageHelp = editor.querySelector("[data-boundary-village-help]");
    fetch("/data_layers/population_villages", { headers: { Accept: "application/json" } }).then(response => {
      if (!response.ok) throw new Error("ไม่สามารถโหลดรายชื่อหมู่บ้านได้"); return response.json();
    }).then(payload => {
      const villages = payload.villages || [];
      if (!villages.length) {
        villageSelect.innerHTML = '<option value="">ยังไม่มีข้อมูลหมู่บ้านในข้อมูลประชากร</option>';
        villageSelect.disabled = true; villageSelect.required = false;
        villageHelp.textContent = "ยังไม่มีข้อมูลหมู่บ้าน กรุณานำเข้าข้อมูลประชากรก่อนกำหนดขอบเขต";
        return;
      }
      villageSelect.innerHTML = '<option value="">เลือกหมู่บ้าน</option>' + villages.map((village, index) => `<option value="${index}">หมู่ ${escapeHtml(village.village_number)} · ${escapeHtml(village.village_name)} · ต.${escapeHtml(village.subdistrict)}</option>`).join("");
      villageSelect.addEventListener("change", () => {
        const village = villages[Number(villageSelect.value)];
        if (!village) return;
        villageFieldKeys.forEach(key => { const input = form.elements[`record[${key}]`]; if (input) input.value = village[key] ?? ""; });
      });
    }).catch(error => {
      villageSelect.innerHTML = '<option value="">กรอกข้อมูลหมู่บ้านด้วยตนเอง</option>'; villageSelect.disabled = true; villageSelect.required = false;
      villageHelp.textContent = error.message;
    });
    const pointInsideAccessArea = coordinate => boundarySource.getFeatures().some(feature => feature.getGeometry()?.intersectsCoordinate(coordinate));
    const geometryInsideAccessArea = geometry => {
      if (!boundarySource.getFeatures().length) return false;
      const coordinates = [];
      const collect = value => {
        if (Array.isArray(value) && value.length >= 2 && typeof value[0] === "number" && typeof value[1] === "number") coordinates.push(value);
        else if (Array.isArray(value)) value.forEach(collect);
      };
      collect(geometry.getCoordinates());
      return coordinates.length > 0 && coordinates.every(pointInsideAccessArea);
    };
    const showBoundaryError = message => { state.textContent = message; state.classList.remove("ready"); state.classList.add("error"); };
    const saveFeature = (feature, sourceMethod = "วาดขอบเขตเอง") => {
      if (!geometryInsideAccessArea(feature.getGeometry())) {
        vectorSource.clear(); geometryInput.value = "";
        showBoundaryError("ขอบเขตหมู่บ้านต้องอยู่ภายในพื้นที่ดูแลของ อบต.");
        return false;
      }
      vectorSource.clear(); vectorSource.addFeature(feature);
      geometryInput.value = JSON.stringify(format.writeGeometryObject(feature.getGeometry(), { featureProjection: "EPSG:3857", dataProjection: "EPSG:4326" }));
      sourceInput.value = sourceMethod;
      state.textContent = "กำหนดขอบเขตแล้ว"; state.classList.remove("error"); state.classList.add("ready");
      redrawButton.hidden = false;
      map.getView().fit(feature.getGeometry().getExtent(), { padding: [35, 35, 35, 35], maxZoom: 16 });
      return true;
    };
    const clearGeometry = () => { vectorSource.clear(); geometryInput.value = ""; state.textContent = "พร้อมวาดขอบเขต"; state.classList.remove("ready", "error"); redrawButton.hidden = true; };
    const startDrawing = () => {
      if (!boundarySource.getFeatures().length) { showBoundaryError("ยังโหลดขอบเขตพื้นที่ดูแลไม่สำเร็จ จึงยังไม่สามารถวาดได้"); return; }
      clearGeometry(); if (draw) map.removeInteraction(draw);
      draw = new ol.interaction.Draw({
        source: vectorSource,
        type: "Polygon",
        condition: event => {
          const allowed = pointInsideAccessArea(event.coordinate);
          if (!allowed) showBoundaryError("ไม่สามารถวาดจุดนอกขอบเขตพื้นที่ดูแลของ อบต. ได้");
          return allowed;
        }
      }); map.addInteraction(draw);
      state.textContent = "คลิกบนแผนที่เพื่อวาด และดับเบิลคลิกเมื่อเสร็จ";
      draw.once("drawend", event => { map.removeInteraction(draw); draw = null; setTimeout(() => saveFeature(event.feature)); });
    };
    redrawButton.addEventListener("click", startDrawing);
    editor.querySelectorAll("[data-boundary-method]").forEach(button => button.addEventListener("click", () => {
      const upload = button.dataset.boundaryMethod === "upload";
      editor.querySelectorAll("[data-boundary-method]").forEach(item => item.classList.toggle("active", item === button));
      editor.querySelector("[data-boundary-draw-panel]").hidden = upload;
      editor.querySelector("[data-boundary-upload-panel]").hidden = !upload;
      if (!upload) setTimeout(() => { map.updateSize(); if (!geometryInput.value && !draw) startDrawing(); });
    }));
    editor.querySelector("[data-boundary-file]").addEventListener("change", async event => {
      const file = event.target.files[0]; if (!file) return;
      try {
        const json = JSON.parse(await file.text());
        let geometry = json.type === "FeatureCollection" ? (json.features.length === 1 ? json.features[0]?.geometry : null) : json.type === "Feature" ? json.geometry : json;
        if (!geometry || !["Polygon", "MultiPolygon"].includes(geometry.type)) throw new Error("ไฟล์ต้องมีขอบเขต Polygon หรือ MultiPolygon จำนวน 1 ขอบเขต");
        const feature = new ol.Feature(format.readGeometry(geometry, { dataProjection: "EPSG:4326", featureProjection: "EPSG:3857" }));
        if (!boundarySource.getFeatures().length) throw new Error("ยังโหลดขอบเขตพื้นที่ดูแลไม่สำเร็จ กรุณาลองใหม่อีกครั้ง");
        saveFeature(feature, "อัปโหลดไฟล์");
      } catch (error) { clearGeometry(); showBoundaryError(error.message || "ไม่สามารถอ่านไฟล์ GeoJSON ได้"); }
    });
    fetch("/api/access_area", { headers: { Accept: "application/json" } }).then(response => response.ok ? response.json() : null).then(json => {
      if (!json) return; const features = format.readFeatures(json, { dataProjection: "EPSG:4326", featureProjection: "EPSG:3857" });
      boundarySource.addFeatures(features); if (features.length) {
        map.getView().fit(boundarySource.getExtent(), { padding: [28, 28, 28, 28], maxZoom: 15 }); state.textContent = "พร้อมวาดขอบเขต";
        if (manualDialog.open && !geometryInput.value && !draw) startDrawing();
      }
    }).catch(() => {});
    return { map, activate: () => { map.updateSize(); if (!geometryInput.value && !draw) startDrawing(); } };
  };
  const boundaryEditor = setupBoundaryGeometryEditor(document.querySelector("#manual-data-form"));
  const agencyLocationPicker = setupAgencyLocationPicker(document.querySelector("#manual-data-form"));
  document.querySelector("[data-open-manual]")?.addEventListener("click", () => { manualDialog.showModal(); setTimeout(() => { boundaryEditor?.activate(); agencyLocationPicker?.activate(); }); });
  document.querySelectorAll("[data-close-dialog]").forEach(button => button.addEventListener("click", () => button.closest("dialog").close()));
  document.querySelector("#manual-data-form")?.addEventListener("submit", async event => {
    event.preventDefault();
    const form = event.currentTarget, status = form.querySelector("[data-manual-status]"), submit = form.querySelector("[type=submit]");
    if (form.elements.data_type?.value === "village_boundaries" && !form.elements["record[geometry]"]?.value) {
      status.className = "modal-status error"; status.textContent = "กรุณาวาดขอบเขตหรืออัปโหลดไฟล์ GeoJSON ก่อนบันทึก"; return;
    }
    if (form.elements.data_type?.value === "agencies" && (!form.elements["record[latitude]"]?.value || !form.elements["record[longitude]"]?.value)) {
      status.className = "modal-status error"; status.textContent = "กรุณาปักหมุดสถานที่ตั้งหน่วยงานก่อนบันทึก"; return;
    }
    status.className = "modal-status"; status.textContent = "กำลังบันทึกข้อมูล…"; submit.disabled = true;
    try {
      const payload = await request("/dataset_import_drafts/manual", { method: "POST", body: new FormData(form) });
      status.textContent = `บันทึกเป็น Version ${payload.version} แล้ว`;
      window.location.assign(payload.redirect_url);
    } catch (error) { status.classList.add("error"); status.textContent = error.message; submit.disabled = false; }
  });

  const editPopulationDialog = document.querySelector("#edit-population-dialog");
  const editPopulationForm = document.querySelector("#edit-population-form");
  const setupBoundaryEditMap = form => {
    const geometryInput = form?.elements["record[geometry]"];
    if (!geometryInput || document.querySelector("#file-import-dialog")?.dataset.selectedType !== "village_boundaries" || !window.ol) return null;
    geometryInput.closest("label")?.classList.add("boundary-source-field");
    geometryInput.type = "hidden";
    const sourceInput = document.createElement("input"); sourceInput.type = "hidden"; sourceInput.name = "record[boundary_source]"; form.append(sourceInput);
    const panel = document.createElement("section"); panel.className = "boundary-edit-panel";
    panel.innerHTML = `<div class="boundary-editor-heading"><div><b>แก้ไขขอบเขตหมู่บ้าน</b><small>ลากจุดบนเส้นเพื่อปรับขอบเขต หรือเลือกวาดใหม่</small></div></div><div class="boundary-draw-toolbar"><span data-edit-boundary-state>กำลังโหลดขอบเขต…</span><button type="button" class="boundary-redraw" data-edit-boundary-redraw>↻ วาดใหม่</button><label class="boundary-edit-upload">⇧ อัปโหลดใหม่<input type="file" accept=".geojson,.json,application/geo+json,application/json" hidden></label></div><div class="boundary-draw-map" data-edit-boundary-map></div>`;
    form.querySelector(".record-change-note").before(panel);
    const accessSource = new ol.source.Vector(), editSource = new ol.source.Vector();
    const map = new ol.Map({ target: panel.querySelector("[data-edit-boundary-map]"), layers: [
      new ol.layer.Tile({ source: new ol.source.OSM() }),
      new ol.layer.Vector({ source: accessSource, style: new ol.style.Style({ stroke: new ol.style.Stroke({ color: "#20a67a", width: 3, lineDash: [8, 5] }), fill: new ol.style.Fill({ color: "rgba(32,166,122,.05)" }) }) }),
      new ol.layer.Vector({ source: editSource, style: new ol.style.Style({ stroke: new ol.style.Stroke({ color: "#1976e9", width: 3 }), fill: new ol.style.Fill({ color: "rgba(25,118,233,.16)" }), image: new ol.style.Circle({ radius: 5, fill: new ol.style.Fill({ color: "#1976e9" }), stroke: new ol.style.Stroke({ color: "#fff", width: 2 }) }) }) })
    ], view: new ol.View({ center: ol.proj.fromLonLat([100.5, 14]), zoom: 10 }) });
    const format = new ol.format.GeoJSON(), state = panel.querySelector("[data-edit-boundary-state]");
    let draw, modify = new ol.interaction.Modify({ source: editSource }); map.addInteraction(modify);
    const inside = coordinate => accessSource.getFeatures().some(feature => feature.getGeometry()?.intersectsCoordinate(coordinate));
    const geometryInside = geometry => { const points = []; const collect = value => { if (Array.isArray(value) && value.length >= 2 && typeof value[0] === "number") points.push(value); else if (Array.isArray(value)) value.forEach(collect); }; collect(geometry.getCoordinates()); return points.length > 0 && points.every(inside); };
    const syncGeometry = (feature, method) => {
      if (!geometryInside(feature.getGeometry())) { state.textContent = "ขอบเขตต้องอยู่ภายในพื้นที่ดูแลของ อบต."; state.className = "error"; return false; }
      geometryInput.value = JSON.stringify(format.writeGeometryObject(feature.getGeometry(), { featureProjection: "EPSG:3857", dataProjection: "EPSG:4326" }));
      if (method) sourceInput.value = method; state.textContent = "พร้อมบันทึกขอบเขต"; state.className = "ready"; return true;
    };
    modify.on("modifyend", event => { const feature = event.features.item(0); if (!syncGeometry(feature, "วาดขอบเขตเอง")) loadGeometry(geometryInput.defaultValue); });
    const loadGeometry = value => {
      try { const geometry = typeof value === "string" ? JSON.parse(value) : value; const feature = new ol.Feature(format.readGeometry(geometry, { dataProjection: "EPSG:4326", featureProjection: "EPSG:3857" })); editSource.clear(); editSource.addFeature(feature); geometryInput.value = JSON.stringify(geometry); geometryInput.defaultValue = geometryInput.value; map.getView().fit(feature.getGeometry().getExtent(), { padding: [35, 35, 35, 35], maxZoom: 16 }); state.textContent = "ลากจุดเพื่อแก้ไขขอบเขต"; state.className = "ready"; } catch (_) { editSource.clear(); state.textContent = "ไม่พบขอบเขตเดิม"; state.className = "error"; }
    };
    panel.querySelector("[data-edit-boundary-redraw]").addEventListener("click", () => {
      editSource.clear(); if (draw) map.removeInteraction(draw); draw = new ol.interaction.Draw({ source: editSource, type: "Polygon", condition: event => inside(event.coordinate) }); map.addInteraction(draw); state.textContent = "คลิกวาดขอบเขตใหม่ และดับเบิลคลิกเมื่อเสร็จ"; state.className = "";
      draw.once("drawend", event => { map.removeInteraction(draw); draw = null; setTimeout(() => syncGeometry(event.feature, "วาดขอบเขตเอง")); });
    });
    panel.querySelector(".boundary-edit-upload input").addEventListener("change", async event => {
      try { const json = JSON.parse(await event.target.files[0].text()); const geometry = json.type === "Feature" ? json.geometry : json.type === "FeatureCollection" && json.features.length === 1 ? json.features[0].geometry : json; if (!["Polygon", "MultiPolygon"].includes(geometry?.type)) throw new Error(); loadGeometry(geometry); const feature = editSource.getFeatures()[0]; if (!feature || !syncGeometry(feature, "อัปโหลดไฟล์")) editSource.clear(); } catch (_) { state.textContent = "ไฟล์ GeoJSON ไม่ถูกต้อง"; state.className = "error"; }
    });
    fetch("/api/access_area", { headers: { Accept: "application/json" } }).then(response => response.ok ? response.json() : null).then(json => { if (json) accessSource.addFeatures(format.readFeatures(json, { dataProjection: "EPSG:4326", featureProjection: "EPSG:3857" })); });
    editPopulationDialog.addEventListener("boundary:load", event => { sourceInput.value = event.detail.boundary_source || "วาดขอบเขตเอง"; loadGeometry(event.detail.geometry); setTimeout(() => map.updateSize()); });
    return map;
  };
  setupBoundaryEditMap(editPopulationForm);
  const agencyEditLocationPicker = setupAgencyLocationPicker(editPopulationForm);
  document.querySelectorAll("[data-edit-population]").forEach(button => button.addEventListener("click", () => {
    const record = JSON.parse(button.dataset.record);
    editPopulationForm.dataset.url = button.dataset.url;
    editPopulationForm.querySelectorAll("[data-edit-field]").forEach(input => input.value = record[input.dataset.editField] ?? "");
    editPopulationForm.querySelector("[name=change_note]").value = "";
    const status = editPopulationForm.querySelector("[data-edit-status]");
    status.className = "modal-status"; status.textContent = "";
    editPopulationDialog.showModal();
    editPopulationDialog.dispatchEvent(new CustomEvent("boundary:load", { detail: record }));
    agencyEditLocationPicker?.load(record);
  }));
  editPopulationForm?.addEventListener("submit", async event => {
    event.preventDefault();
    const form = event.currentTarget, status = form.querySelector("[data-edit-status]"), submit = form.querySelector("[type=submit]");
    if (document.querySelector("#file-import-dialog")?.dataset.selectedType === "agencies" && (!form.elements["record[latitude]"]?.value || !form.elements["record[longitude]"]?.value)) {
      status.className = "modal-status error"; status.textContent = "กรุณาปักหมุดสถานที่ตั้งหน่วยงานก่อนบันทึก"; return;
    }
    status.className = "modal-status"; status.textContent = "กำลังบันทึกและสร้าง Version ใหม่…"; submit.disabled = true;
    try {
      const payload = await request(form.dataset.url, { method: "PATCH", body: new FormData(form) });
      status.textContent = `แก้ไขเรียบร้อย เป็น Version ${payload.version}`;
      window.location.assign(payload.redirect_url);
    } catch (error) { status.classList.add("error"); status.textContent = error.message; submit.disabled = false; }
  });
  document.querySelectorAll("[data-delete-population]").forEach(button => button.addEventListener("click", async () => {
    const recordType = document.querySelector(".catalog-hero h2")?.textContent.trim() || "ข้อมูล";
    if (!window.confirm(`ยืนยันลบ${recordType}รายการนี้? ข้อมูลเดิมจะยังอยู่ในประวัติ Version`)) return;
    button.disabled = true;
    try {
      const payload = await request(button.dataset.url, { method: "DELETE" });
      window.location.assign(payload.redirect_url);
    } catch (error) { window.alert(error.message); button.disabled = false; }
  }));

  const resourceTable = document.querySelector(".fixed-data-table");
  if (resourceTable?.querySelector("thead th")?.textContent.trim() === "ชื่อทรัพยากร/อุปกรณ์") {
    const resourceFields = [
      ["name", "ชื่อทรัพยากร/อุปกรณ์", true], ["code", "รหัส", false], ["registration", "ทะเบียน", false],
      ["resource_type", "ประเภท", true], ["status", "สถานะ", false], ["responsible_person", "ผู้รับผิดชอบ", false],
      ["storage_location", "สถานที่เก็บ", false]
    ];
    if (!resourceTable.querySelector(".record-actions-heading")) resourceTable.querySelector("thead tr")?.insertAdjacentHTML("beforeend", '<th class="record-actions-heading">จัดการ</th>');
    const positions = {};
    resourceTable.querySelectorAll("tbody [data-fixed-row]").forEach(row => {
      const datasetLink = row.querySelector(".table-action");
      const match = datasetLink?.getAttribute("href")?.match(/\/imported_datasets\/([^/]+)/);
      if (!match) return;
      const datasetId = match[1], position = positions[datasetId] || 0;
      positions[datasetId] = position + 1;
      const record = Object.fromEntries(resourceFields.map(([key], index) => [key, row.cells[index]?.textContent.trim() === "—" ? "" : row.cells[index]?.textContent.trim()]));
      const url = `/imported_datasets/${datasetId}/records/${position}`;
      row.insertAdjacentHTML("beforeend", `<td class="record-actions"><button type="button" class="record-icon-button edit" title="แก้ไขข้อมูล" aria-label="แก้ไขข้อมูล" data-resource-edit>✎</button><button type="button" class="record-icon-button delete" title="ลบข้อมูล" aria-label="ลบข้อมูล" data-resource-delete>♲</button></td>`);
      row.querySelector("[data-resource-edit]").addEventListener("click", () => openResourceEditor(url, record));
      row.querySelector("[data-resource-delete]").addEventListener("click", event => deleteResourceRecord(event.currentTarget, url));
    });
    const resourceStatusTones = { "พร้อมใช้": "ready", "กำลังใช้งาน": "in-use", "ชำรุด": "damaged" };
    resourceTable.querySelectorAll("tbody [data-fixed-row]").forEach(row => {
      const statusCell = row.cells[4], status = statusCell?.textContent.trim(), tone = resourceStatusTones[status];
      if (tone) statusCell.innerHTML = `<span class="resource-status-badge ${tone}">${escapeHtml(status)}</span>`;
    });

    const editor = document.createElement("dialog");
    editor.className = "dataset-modal";
    editor.innerHTML = `<form><header><div><small>แก้ไขข้อมูลทรัพยากรและอุปกรณ์</small><h2>แก้ไขรายการ</h2></div><button type="button" aria-label="ปิด">×</button></header><div class="modal-info">เมื่อบันทึก ระบบจะสร้าง Version ใหม่และเก็บข้อมูลเดิมไว้ในประวัติ</div><div class="manual-fixed-grid">${resourceFields.map(([key, label, required]) => `<label>${label}${required ? " *" : ""}<input name="record[${key}]" ${required ? "required" : ""}></label>`).join("")}</div><label class="record-change-note">รายละเอียดการแก้ไข<input name="change_note" placeholder="เช่น ปรับสถานะอุปกรณ์"></label><p class="modal-status"></p><footer><button type="button" class="button-link" data-resource-close>ยกเลิก</button><button class="data-layer-add" type="submit">บันทึกเป็น Version ใหม่</button></footer></form>`;
    document.body.append(editor);
    const resourceForm = editor.querySelector("form"), resourceStatus = editor.querySelector(".modal-status");
    const openResourceEditor = (url, record) => {
      resourceForm.dataset.url = url;
      resourceFields.forEach(([key]) => resourceForm.elements[`record[${key}]`].value = record[key] || "");
      resourceForm.elements.change_note.value = ""; resourceStatus.className = "modal-status"; resourceStatus.textContent = "";
      editor.showModal();
    };
    const deleteResourceRecord = async (button, url) => {
      if (!window.confirm("ยืนยันลบข้อมูลทรัพยากร/อุปกรณ์รายการนี้? ข้อมูลเดิมจะยังอยู่ในประวัติ Version")) return;
      button.disabled = true;
      try { const payload = await request(url, { method: "DELETE" }); window.location.assign(payload.redirect_url); }
      catch (error) { window.alert(error.message); button.disabled = false; }
    };
    editor.querySelectorAll("[data-resource-close], header button").forEach(button => button.addEventListener("click", () => editor.close()));
    resourceForm.addEventListener("submit", async event => {
      event.preventDefault(); const submit = resourceForm.querySelector("[type=submit]");
      resourceStatus.className = "modal-status"; resourceStatus.textContent = "กำลังบันทึกและสร้าง Version ใหม่…"; submit.disabled = true;
      try { const payload = await request(resourceForm.dataset.url, { method: "PATCH", body: new FormData(resourceForm) }); window.location.assign(payload.redirect_url); }
      catch (error) { resourceStatus.classList.add("error"); resourceStatus.textContent = error.message; submit.disabled = false; }
    });
  }

  const workforceTable = document.querySelector(".fixed-data-table");
  if (workforceTable?.querySelector("thead th")?.textContent.trim() === "ชื่อทีม") {
    const workforceFields = [
      ["team_name", "ชื่อทีม", true], ["duty", "หน้าที่", true], ["member_count", "จำนวนสมาชิก", true],
      ["ready_count", "พร้อมปฏิบัติงาน", true], ["responsible_area", "พื้นที่รับผิดชอบ", true], ["team_leader", "หัวหน้าทีม", true]
    ];
    if (!workforceTable.querySelector(".record-actions-heading")) workforceTable.querySelector("thead tr")?.insertAdjacentHTML("beforeend", '<th class="record-actions-heading">จัดการ</th>');
    const positions = {};
    workforceTable.querySelectorAll("tbody [data-fixed-row]").forEach(row => {
      const datasetLink = row.querySelector(".table-action");
      const match = datasetLink?.getAttribute("href")?.match(/\/imported_datasets\/([^/]+)/);
      if (!match) return;
      const datasetId = match[1], position = positions[datasetId] || 0;
      positions[datasetId] = position + 1;
      const record = Object.fromEntries(workforceFields.map(([key], index) => [key, row.cells[index]?.textContent.trim() === "—" ? "" : row.cells[index]?.textContent.trim()]));
      const url = `/imported_datasets/${datasetId}/records/${position}`;
      row.insertAdjacentHTML("beforeend", '<td class="record-actions"><button type="button" class="record-icon-button edit" title="แก้ไขข้อมูล" aria-label="แก้ไขข้อมูล" data-workforce-edit>✎</button><button type="button" class="record-icon-button delete" title="ลบข้อมูล" aria-label="ลบข้อมูล" data-workforce-delete>♲</button></td>');
      row.querySelector("[data-workforce-edit]").addEventListener("click", () => openWorkforceEditor(url, record));
      row.querySelector("[data-workforce-delete]").addEventListener("click", event => deleteWorkforceRecord(event.currentTarget, url));
    });

    const editor = document.createElement("dialog");
    editor.className = "dataset-modal";
    editor.innerHTML = `<form><header><div><small>แก้ไขบุคลากรปฏิบัติงาน</small><h2>แก้ไขรายการ</h2></div><button type="button" aria-label="ปิด">×</button></header><div class="modal-info">เมื่อบันทึก ระบบจะสร้าง Version ใหม่และเก็บข้อมูลเดิมไว้ในประวัติ</div><div class="manual-fixed-grid">${workforceFields.map(([key, label, required]) => `<label>${label}${required ? " *" : ""}<input name="record[${key}]" ${required ? "required" : ""}></label>`).join("")}</div><label class="record-change-note">รายละเอียดการแก้ไข<input name="change_note" placeholder="เช่น ปรับจำนวนกำลังพลพร้อมปฏิบัติงาน"></label><p class="modal-status"></p><footer><button type="button" class="button-link" data-workforce-close>ยกเลิก</button><button class="data-layer-add" type="submit">บันทึกเป็น Version ใหม่</button></footer></form>`;
    document.body.append(editor);
    const workforceForm = editor.querySelector("form"), workforceStatus = editor.querySelector(".modal-status");
    const openWorkforceEditor = (url, record) => {
      workforceForm.dataset.url = url;
      workforceFields.forEach(([key]) => workforceForm.elements[`record[${key}]`].value = record[key] || "");
      workforceForm.elements.change_note.value = ""; workforceStatus.className = "modal-status"; workforceStatus.textContent = "";
      editor.showModal();
    };
    const deleteWorkforceRecord = async (button, url) => {
      if (!window.confirm("ยืนยันลบข้อมูลทีมงานรายการนี้? ข้อมูลเดิมจะยังอยู่ในประวัติ Version")) return;
      button.disabled = true;
      try { const payload = await request(url, { method: "DELETE" }); window.location.assign(payload.redirect_url); }
      catch (error) { window.alert(error.message); button.disabled = false; }
    };
    editor.querySelectorAll("[data-workforce-close], header button").forEach(button => button.addEventListener("click", () => editor.close()));
    workforceForm.addEventListener("submit", async event => {
      event.preventDefault(); const submit = workforceForm.querySelector("[type=submit]");
      workforceStatus.className = "modal-status"; workforceStatus.textContent = "กำลังบันทึกและสร้าง Version ใหม่…"; submit.disabled = true;
      try { const payload = await request(workforceForm.dataset.url, { method: "PATCH", body: new FormData(workforceForm) }); window.location.assign(payload.redirect_url); }
      catch (error) { workforceStatus.classList.add("error"); workforceStatus.textContent = error.message; submit.disabled = false; }
    });
  }

  const movementDialog = document.querySelector("#consumable-movement-dialog");
  document.querySelectorAll("[data-consumable-movement]").forEach(button => button.addEventListener("click", () => {
    if (!movementDialog) return;
    movementDialog.querySelector("[data-movement-dataset]").value = button.dataset.datasetId;
    movementDialog.querySelector("[data-movement-position]").value = button.dataset.position;
    movementDialog.querySelector("[data-movement-title]").textContent = `บันทึกความเคลื่อนไหว · ${button.dataset.name}`;
    movementDialog.querySelector("[data-movement-balance]").textContent = `ยอดคงเหลือปัจจุบัน ${Number(button.dataset.quantity || 0).toLocaleString()} ${button.dataset.unit || ""}`;
    movementDialog.querySelector("form").reset();
    movementDialog.querySelector("[data-movement-dataset]").value = button.dataset.datasetId;
    movementDialog.querySelector("[data-movement-position]").value = button.dataset.position;
    movementDialog.showModal();
  }));

  const dialog = document.querySelector("#file-import-dialog");
  if (!dialog) return;
  const fileInput = dialog.querySelector("[data-import-file]"), selectedFile = dialog.querySelector("[data-selected-file]");
  const next = dialog.querySelector("[data-wizard-next]"), back = dialog.querySelector("[data-wizard-back]");
  const status = dialog.querySelector("[data-wizard-status]");
  let step = 1, draft = null, busy = false;

  const showStep = number => {
    step = number;
    dialog.querySelectorAll("[data-wizard-step]").forEach(panel => panel.hidden = Number(panel.dataset.wizardStep) !== step);
    dialog.querySelectorAll("[data-step-indicator]").forEach(item => {
      const itemStep = Number(item.dataset.stepIndicator); item.classList.toggle("active", itemStep === step); item.classList.toggle("done", itemStep < step);
    });
    dialog.querySelector("[data-step-count]").textContent = `ขั้นตอน ${step} จาก 6`;
    back.hidden = step === 1 || step === 6; next.hidden = step === 6;
    next.textContent = step === 5 ? "ยืนยันการนำเข้า" : "ดำเนินการต่อ";
    status.textContent = ""; status.classList.remove("error");
  };

  const upload = async () => {
    if (!fileInput.files[0]) throw new Error("กรุณาเลือกไฟล์ที่ต้องการนำเข้า");
    const body = new FormData(); body.append("file", fileInput.files[0]); body.append("data_type", dialog.dataset.selectedType);
    draft = await request("/dataset_import_drafts", { method: "POST", body });
    renderMapping();
  };

  const renderMapping = () => {
    dialog.querySelector("[data-mapping-list]").innerHTML = draft.schema.map(field => {
      const options = ['<option value="">ไม่จับคู่</option>', ...draft.headers.map(header => `<option value="${escapeHtml(header)}" ${draft.mapping[field.key] === header ? "selected" : ""}>${escapeHtml(header)}</option>`)].join("");
      return `<label><span>${escapeHtml(field.label)}${field.required ? " *" : ""}<small>${escapeHtml(field.key)}</small></span><b>→</b><select data-map-key="${escapeHtml(field.key)}">${options}</select><em class="${draft.mapping[field.key] ? "" : "unmatched"}">${draft.mapping[field.key] ? "จับคู่แล้ว" : "ยังไม่จับคู่"}</em></label>`;
    }).join("");
    dialog.querySelectorAll("[data-map-key]").forEach(select => select.addEventListener("change", () => {
      const badge = select.nextElementSibling;
      badge.textContent = select.value ? "จับคู่แล้ว" : "ยังไม่จับคู่";
      badge.classList.toggle("unmatched", !select.value);
    }));
  };

  const validate = async () => {
    const mapping = {};
    dialog.querySelectorAll("[data-map-key]").forEach(select => mapping[select.dataset.mapKey] = select.value);
    const body = new FormData(); Object.entries(mapping).forEach(([key, value]) => body.append(`mapping[${key}]`, value));
    draft = await request(`/dataset_import_drafts/${draft.id}/validate`, { method: "POST", body });
    const validation = draft.validation || {}, ok = !validation.errors?.length;
    dialog.querySelector("[data-validation-result]").innerHTML = `<div class="validation-icon ${ok ? "ok" : "bad"}">${ok ? "✓" : "!"}</div><h3>${ok ? "Validation เสร็จแล้ว" : "พบข้อมูลที่ต้องแก้ไข"}</h3><p>พบข้อมูล ${Number(validation.total || 0).toLocaleString()} รายการ · ${ok ? `ผ่าน ${Number(validation.valid || 0).toLocaleString()}` : `ข้อผิดพลาด ${Number(validation.invalid || 0).toLocaleString()}`}</p>${ok ? "" : `<ul>${validation.errors.map(error => `<li>${escapeHtml(error)}</li>`).join("")}</ul>`}`;
    if (!ok) throw new Error("กรุณาย้อนกลับไปแก้ไข Mapping หรือไฟล์ข้อมูล");
    renderPreview();
  };

  const renderPreview = () => {
    const header = draft.schema.map(field => `<th>${escapeHtml(field.label)}</th>`).join("");
    const rows = draft.records.map(record => `<tr>${draft.schema.map(field => `<td>${escapeHtml(record[field.key] ?? "—")}</td>`).join("")}</tr>`).join("");
    dialog.querySelector("[data-preview-table]").innerHTML = `<table><thead><tr>${header}</tr></thead><tbody>${rows}</tbody></table><small>แสดง ${draft.records.length} จาก ${Number(draft.validation.total || 0).toLocaleString()} รายการ</small>`;
  };

  const finalize = async () => {
    const fields = dialog.querySelector('[data-wizard-step="5"] [data-destination-fields]');
    const body = new FormData(); fields.querySelectorAll("input:not(:disabled),select:not(:disabled)").forEach(input => {
      if ((input.type !== "checkbox" && input.value) || (input.type === "checkbox" && input.checked)) body.append(input.name, input.value);
    });
    const payload = await request(`/dataset_import_drafts/${draft.id}/finalize`, { method: "POST", body });
    dialog.querySelector("[data-finish-message]").textContent = `นำเข้าสำเร็จ ${payload.records.toLocaleString()} รายการ เป็น Version ${payload.version}`;
    dialog.querySelector("[data-finish-link]").href = payload.redirect_url;
  };

  document.querySelector("[data-open-import]")?.addEventListener("click", () => { showStep(1); dialog.showModal(); });
  fileInput.addEventListener("change", () => { const file = fileInput.files[0]; selectedFile.hidden = !file; selectedFile.textContent = file ? `▤ ${file.name} · ${(file.size / 1024).toFixed(1)} KB` : ""; });
  back.addEventListener("click", () => showStep(Math.max(1, step - 1)));
  next.addEventListener("click", async () => {
    if (busy) return; busy = true; next.disabled = true; status.textContent = "กำลังประมวลผล…";
    try {
      if (step === 1) await upload();
      else if (step === 2) await validate();
      else if (step === 3 && draft.validation?.errors?.length) throw new Error("ข้อมูลยังไม่ผ่าน Validation กรุณาย้อนกลับไปแก้ไข");
      else if (step === 5) await finalize();
      showStep(Math.min(6, step + 1));
    } catch (error) { if (step === 2 && draft?.validation) showStep(3); status.classList.add("error"); status.textContent = error.message; }
    finally { busy = false; next.disabled = false; }
  });
  showStep(1);
});
