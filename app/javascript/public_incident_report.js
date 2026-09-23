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
  const coordinateLabel = page.querySelector("[data-public-coordinate]");
  const submit = page.querySelector("[data-public-report-submit]");
  const submitHint = page.querySelector("[data-public-submit-hint]");
  const consent = page.querySelector("[data-public-report-consent]");
  const form = page.querySelector(".public-report-form");
  const geoJson = new ol.format.GeoJSON();
  const boundaryFeatures = boundaryData ? geoJson.readFeatures(boundaryData, { dataProjection: "EPSG:4326", featureProjection: "EPSG:3857" }) : [];
  const boundarySource = new ol.source.Vector({ features: boundaryFeatures });
  const markerSource = new ol.source.Vector();
  const placesSource = new ol.source.Vector();
  const importantPlaceColors = { government: "#2563eb", education: "#d99000", health: "#e11d48", culture: "#7c3aed", tourism: "#ea580c", transport: "#0891b2", service: "#db2777", emergency: "#dc2626", imported: "#059669" };

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
    style: new ol.style.Style({ fill: new ol.style.Fill({ color: "rgba(12, 29, 48, 0.58)" }) })
  });

  const boundaryLayer = new ol.layer.Vector({
    source: boundarySource,
    style: new ol.style.Style({ fill: new ol.style.Fill({ color: "rgba(0, 0, 0, 0)" }), stroke: new ol.style.Stroke({ color: "#176fe5", width: 2.5 }) })
  });
  const placesLayer = new ol.layer.Vector({
    source: placesSource,
    declutter: true,
    style: (feature) => {
      const place = feature.get("place") || {};
      const color = importantPlaceColors[place.category] || "#475569";
      return new ol.style.Style({
        image: new ol.style.Circle({ radius: 5, fill: new ol.style.Fill({ color }), stroke: new ol.style.Stroke({ color: "#fff", width: 2 }) }),
        text: new ol.style.Text({ text: place.name || "สถานที่สำคัญ", offsetY: -13, font: '500 11px "Google Sans", sans-serif', fill: new ol.style.Fill({ color: "#173653" }), stroke: new ol.style.Stroke({ color: "rgba(255,255,255,.95)", width: 3 }), padding: [2, 3, 2, 3] })
      });
    }
  });
  const markerLayer = new ol.layer.Vector({ source: markerSource });

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
    const requiredFields = [...form.querySelectorAll("input[required], select[required], textarea[required]")].filter((field) => field !== consent);
    const hasRequiredFields = requiredFields.every((field) => field.value.trim() !== "" && field.checkValidity());
    const ready = hasLocation && hasConsent && hasRequiredFields;
    submit.disabled = !ready;
    submitHint.hidden = ready;
    if (!hasRequiredFields) submitHint.textContent = "กรุณากรอกข้อมูลที่มีเครื่องหมาย * ให้ครบถ้วน";
    else if (!hasLocation) submitHint.textContent = "กรุณาปักตำแหน่งที่เกิดเหตุก่อนส่งข้อมูล";
    else if (!hasConsent) submitHint.textContent = "กรุณากดยืนยันว่าข้อมูลที่แจ้งเป็นความจริงก่อนส่งข้อมูล";
  };
  const setLocation = (lon, lat, center = false) => {
    const coordinate = ol.proj.fromLonLat([lon, lat]);
    if (!isInsideBoundary(coordinate)) { showOutsideWarning(); return false; }
    latitudeInput.value = lat.toFixed(6);
    longitudeInput.value = lon.toFixed(6);
    markerSource.clear();
    const marker = new ol.Feature(new ol.geom.Point(coordinate));
    marker.setStyle(new ol.style.Style({ image: new ol.style.Circle({ radius: 8, fill: new ol.style.Fill({ color: "#176fe5" }), stroke: new ol.style.Stroke({ color: "#ffffff", width: 3 }) }) }));
    markerSource.addFeature(marker);
    coordinateLabel.textContent = `${lat.toFixed(6)}, ${lon.toFixed(6)}`;
    coordinateLabel.classList.remove("error");
    updateSubmitState();
    if (center) map.getView().animate({ center: coordinate, zoom: 16, duration: 350 });
    return true;
  };

  if (mapElement.dataset.latitude && mapElement.dataset.longitude) setLocation(initialLon, initialLat);
  consent?.addEventListener("change", updateSubmitState);
  form?.addEventListener("input", updateSubmitState);
  form?.addEventListener("change", updateSubmitState);
  updateSubmitState();
  map.on("click", (event) => { const [lon, lat] = ol.proj.toLonLat(event.coordinate); setLocation(lon, lat); });
  page.querySelector("[data-public-use-location]")?.addEventListener("click", () => {
    if (!navigator.geolocation) return window.alert("อุปกรณ์นี้ไม่รองรับการค้นหาตำแหน่ง");
    navigator.geolocation.getCurrentPosition(
      (position) => { if (!setLocation(position.coords.longitude, position.coords.latitude, true)) window.alert("ตำแหน่งปัจจุบันอยู่นอกพื้นที่รับแจ้ง กรุณาปักหมุดภายในขอบเขตสีน้ำเงิน"); },
      () => window.alert("ไม่สามารถอ่านตำแหน่งได้ กรุณาอนุญาตการเข้าถึงตำแหน่งหรือปักหมุดบนแผนที่")
    );
  });
});
