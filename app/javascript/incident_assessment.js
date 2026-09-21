document.addEventListener("DOMContentLoaded", () => {
  const page = document.querySelector("[data-incident-assessment]");
  const mapElement = page?.querySelector("[data-assessment-map]");
  if (!page || !mapElement || !window.ol) return;

  const escapeHtml = (value) => String(value ?? "").replace(/[&<>'"]/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[character]);
  const boundarySource = new ol.source.Vector();
  const maskSource = new ol.source.Vector();
  const placesSource = new ol.source.Vector();
  const waterSource = new ol.source.Vector();
  const selectionSource = new ol.source.Vector();
  const simulationPointSource = new ol.source.Vector();
  const isCityMap = page.dataset.cityMap === "true";
  const placeConfig = {
    government: { color: "#2563eb", icon: "account_balance" }, education: { color: "#f59e0b", icon: "school" },
    health: { color: "#e11d48", icon: "heart_plus" }, culture: { color: "#8b5cf6", icon: "folded_hands" },
    tourism: { color: "#f97316", icon: "star" }, transport: { color: "#0ea5a4", icon: "directions_car" },
    service: { color: "#ec4899", icon: "local_mall" }, emergency: { color: "#dc2626", icon: "emergency_home" }
  };
  const placeMarkerIcon = (color) => {
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="36" height="44" viewBox="0 0 42 52"><path d="M21 1C10 1 2 9.5 2 20c0 14.2 19 30.4 19 30.4S40 34.2 40 20C40 9.5 32 1 21 1z" fill="${color}" stroke="#fff" stroke-width="3"/></svg>`;
    return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
  };
  const placeStyleCache = {};
  const visiblePlaceCategories = new Set(Object.keys(placeConfig));
  const cityPlaceStyle = (category, highlighted) => {
    if (!visiblePlaceCategories.has(category)) return null;
    const config = placeConfig[category] || placeConfig.service;
    const key = `${category}:${highlighted}`;
    if (!placeStyleCache[key]) placeStyleCache[key] = new ol.style.Style({
      image: new ol.style.Icon({ src: placeMarkerIcon(highlighted ? config.color : "#94a3b8"), anchor: [0.5, 1], anchorXUnits: "fraction", anchorYUnits: "fraction" }),
      text: new ol.style.Text({ text: config.icon, font: '20px "Material Symbols Outlined"', fill: new ol.style.Fill({ color: "#fff" }), offsetY: -25 })
    });
    return placeStyleCache[key];
  };
  const boundaryLayer = new ol.layer.Vector({ source: boundarySource, style: new ol.style.Style({ stroke: new ol.style.Stroke({ color: "#42b99a", width: 3 }), fill: new ol.style.Fill({ color: "rgba(0,0,0,0)" }) }) });
  const maskLayer = new ol.layer.Vector({ source: maskSource, style: new ol.style.Style({ fill: new ol.style.Fill({ color: "rgba(12,29,48,.55)" }) }) });
  const placesLayer = new ol.layer.Vector({ source: placesSource, declutter: true, style: (feature) => {
    const selectedGeometry = lastAssessmentGeometry;
    const highlighted = !selectedGeometry || selectedGeometry.intersectsCoordinate(feature.getGeometry().getCoordinates());
    if (isCityMap) return cityPlaceStyle(feature.get("category"), highlighted);
    return new ol.style.Style({ image: new ol.style.Circle({ radius: 5, fill: new ol.style.Fill({ color: highlighted ? "#176fe5" : "#9aa8b5" }), stroke: new ol.style.Stroke({ color: "#fff", width: 2 }) }), text: new ol.style.Text({ text: feature.get("name") || "", offsetY: -13, font: '500 11px "Google Sans",sans-serif', fill: new ol.style.Fill({ color: highlighted ? "#173653" : "#7e8c98" }), stroke: new ol.style.Stroke({ color: "#fff", width: 3 }) }) });
  } });
  const waterLayer = new ol.layer.Vector({ source: waterSource, style: new ol.style.Style({ image: new ol.style.Circle({ radius: 6, fill: new ol.style.Fill({ color: "#0891b2" }), stroke: new ol.style.Stroke({ color: "#fff", width: 2 }) }) }) });
  const selectionLayer = new ol.layer.Vector({ source: selectionSource, style: new ol.style.Style({ stroke: new ol.style.Stroke({ color: "#f97316", width: 3, lineDash: [8, 5] }), fill: new ol.style.Fill({ color: "rgba(249,115,22,.18)" }) }) });
  const simulationPointLayer = new ol.layer.Vector({ source: simulationPointSource, style: new ol.style.Style({ image: new ol.style.Circle({ radius: 7, fill: new ol.style.Fill({ color: "#176fe5" }), stroke: new ol.style.Stroke({ color: "#fff", width: 3 }) }) }) });
  const longitude = Number(mapElement.dataset.incidentLongitude);
  const latitude = Number(mapElement.dataset.incidentLatitude);
  const incidentMarkerSvg = '<svg xmlns="http://www.w3.org/2000/svg" width="42" height="54" viewBox="0 0 42 54"><path fill="#ef3340" d="M21 1.5C10.2 1.5 1.5 10.2 1.5 21c0 15.2 19.5 31.5 19.5 31.5S40.5 36.2 40.5 21C40.5 10.2 31.8 1.5 21 1.5z"/><path fill="none" stroke="#fff" stroke-width="2.2" stroke-linejoin="round" d="M21 10.5 31 28H11z"/><rect x="19.7" y="15" width="2.6" height="7.5" rx="1.3" fill="#fff"/><circle cx="21" cy="25" r="1.5" fill="#fff"/></svg>';
  const incidentMarkerUrl = `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(incidentMarkerSvg)}`;
  const incidentSource = new ol.source.Vector();
  if (Number.isFinite(longitude) && Number.isFinite(latitude)) incidentSource.addFeature(new ol.Feature(new ol.geom.Point(ol.proj.fromLonLat([longitude, latitude]))));
  const incidentLayer = new ol.layer.Vector({ source: incidentSource, zIndex: 20, style: new ol.style.Style({ image: new ol.style.Icon({ src: incidentMarkerUrl, anchor: [0.5, 1], scale: 0.9 }) }) });
  const roadLayer = new ol.layer.Tile({ source: new ol.source.OSM() });
  const satelliteLayer = new ol.layer.Tile({ source: new ol.source.XYZ({ url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", attributions: "Tiles © Esri" }), visible: false });
  const map = new ol.Map({ target: mapElement, layers: [roadLayer, satelliteLayer, maskLayer, boundaryLayer, placesLayer, waterLayer, selectionLayer, simulationPointLayer, incidentLayer], view: new ol.View({ center: ol.proj.fromLonLat([Number.isFinite(longitude) ? longitude : 100.5, Number.isFinite(latitude) ? latitude : 13.7]), zoom: 13 }), controls: [] });
  let accessBoundary;
  let accessAreaSqKm = 0;
  let draw;
  let areaMode = null;
  let areaAnchor = null;
  let areaLine = null;
  let areaPolygon = null;
  let pointClickKey = null;
  let selectedAreaSqKm = null;
  let lastAssessmentGeometry = null;
  let assessmentMode = isCityMap ? "map" : "analysis";
  page.classList.add(`mode-${assessmentMode}`);
  let accessBoundaryGeoJSON = null;
  let cesiumViewer = null;
  let cesiumBoundary = null;
  let cesiumSelection = null;
  let cesiumPlaces = null;
  let cesiumWater = null;
  let placesPayload = [];
  let waterPayload = [];

  const areaUnit = page.querySelector("[data-area-unit]");
  const areaResult = page.querySelector("[data-result-area]");
  const rulePicker = page.querySelector("[data-rule-picker]");
  const ruleSelect = page.querySelector("[data-rule-select]");
  const disasterTypeSelect = page.querySelector("[data-assessment-disaster-type]");
  const mapWrap = page.querySelector(".assessment-map-wrap");
  const cesiumElement = page.querySelector("[data-assessment-cesium]");
  const placeDetail = page.querySelector("[data-city-place-detail]");
  const placeCategoryLabels = { government: "สถานที่ราชการ", education: "การศึกษา", health: "สาธารณสุข", culture: "ศาสนาและวัฒนธรรม", tourism: "ท่องเที่ยว", transport: "คมนาคม", service: "ร้านค้าและบริการ", emergency: "ความปลอดภัยและฉุกเฉิน" };
  const showPlaceDetail = (place) => {
    if (!placeDetail || !place) return;
    const config = placeConfig[place.assessmentCategory] || placeConfig.service;
    placeDetail.querySelector("[data-place-detail-icon]").textContent = config.icon;
    placeDetail.querySelector("[data-place-detail-icon]").style.backgroundColor = config.color;
    placeDetail.querySelector("[data-place-detail-category]").textContent = placeCategoryLabels[place.assessmentCategory] || "สถานที่สำคัญ";
    placeDetail.querySelector("[data-place-detail-name]").textContent = place.name || "ไม่ระบุชื่อสถานที่";
    const address = placeDetail.querySelector("[data-place-detail-address]");
    address.textContent = place.address || ""; address.hidden = !place.address;
    const contact = placeDetail.querySelector("[data-place-detail-contact]");
    contact.textContent = place.tel ? `โทร. ${place.tel}` : ""; contact.hidden = !place.tel;
    const link = placeDetail.querySelector("[data-place-detail-link]");
    const safeUrl = /^https?:\/\//i.test(place.url || "") ? place.url : "";
    link.href = safeUrl; link.hidden = !safeUrl;
    placeDetail.hidden = false;
  };

  const terrainHeights = async (x, y, level) => {
    try {
      const response = await fetch(`/api/terrain_tiles/${level}/${x}/${y}`);
      if (!response.ok) throw new Error("terrain unavailable");
      const image = await createImageBitmap(await response.blob());
      const canvas = document.createElement("canvas");
      canvas.width = 257; canvas.height = 257;
      const context = canvas.getContext("2d", { willReadFrequently: true });
      context.drawImage(image, 0, 0, 257, 257); image.close?.();
      const pixels = context.getImageData(0, 0, 257, 257).data;
      const heights = new Float32Array(257 * 257);
      for (let index = 0; index < heights.length; index += 1) {
        const offset = index * 4;
        heights[index] = pixels[offset] * 256 + pixels[offset + 1] + pixels[offset + 2] / 256 - 32768;
      }
      return heights;
    } catch (_) { return new Float32Array(257 * 257); }
  };
  const initializeCesium = async () => {
    if (cesiumViewer) return cesiumViewer;
    if (!window.Cesium) throw new Error("ไม่สามารถโหลดแผนที่ 3D ได้");
    const Cesium = window.Cesium;
    cesiumViewer = new Cesium.Viewer(cesiumElement, {
      terrainProvider: new Cesium.CustomHeightmapTerrainProvider({ width: 257, height: 257, tilingScheme: new Cesium.WebMercatorTilingScheme(), callback: terrainHeights }),
      baseLayer: new Cesium.ImageryLayer(new Cesium.OpenStreetMapImageryProvider({ url: "https://tile.openstreetmap.org/" })),
      animation: false, baseLayerPicker: false, fullscreenButton: false, geocoder: false, homeButton: true, infoBox: false, sceneModePicker: false, selectionIndicator: false, timeline: false, navigationHelpButton: false
    });
    cesiumViewer.scene.globe.depthTestAgainstTerrain = true;
    cesiumViewer.scene.verticalExaggeration = 2.5;
    if (isCityMap) {
      const placeClickHandler = new Cesium.ScreenSpaceEventHandler(cesiumViewer.scene.canvas);
      placeClickHandler.setInputAction((movement) => {
        const picked = cesiumViewer.scene.pick(movement.position);
        if (picked?.id?.assessmentPlace) showPlaceDetail(picked.id.assessmentPlace);
        else if (placeDetail) placeDetail.hidden = true;
      }, Cesium.ScreenSpaceEventType.LEFT_CLICK);
    }
    if (accessBoundaryGeoJSON) {
      cesiumBoundary = await Cesium.GeoJsonDataSource.load(accessBoundaryGeoJSON, { clampToGround: true, stroke: Cesium.Color.fromCssColorString("#42b99a"), fill: Cesium.Color.TRANSPARENT, strokeWidth: 4 });
      cesiumViewer.dataSources.add(cesiumBoundary);
      const boundaryGeometry = accessBoundaryGeoJSON.type === "Feature" ? accessBoundaryGeoJSON.geometry : accessBoundaryGeoJSON;
      const boundaryPolygons = boundaryGeometry?.type === "Polygon" ? [boundaryGeometry.coordinates] : boundaryGeometry?.type === "MultiPolygon" ? boundaryGeometry.coordinates : [];
      boundaryPolygons.forEach((polygon) => polygon.forEach((ring) => {
        const positions = ring.flatMap((coordinate) => [Number(coordinate[0]), Number(coordinate[1])]);
        cesiumBoundary.entities.add({ polyline: { positions: Cesium.Cartesian3.fromDegreesArray(positions), width: 5, material: Cesium.Color.fromCssColorString("#42b99a"), clampToGround: true, arcType: Cesium.ArcType.GEODESIC } });
      }));
      cesiumBoundary.show = page.querySelector('[data-layer-toggle="boundary"]').checked;
      await cesiumViewer.flyTo(cesiumBoundary, { duration: 0.8 });
    }
    if (Number.isFinite(longitude) && Number.isFinite(latitude)) {
      cesiumViewer.entities.add({ name: "ตำแหน่งเกิดเหตุ", position: Cesium.Cartesian3.fromDegrees(longitude, latitude, 4), billboard: { image: incidentMarkerUrl, width: 38, height: 49, verticalOrigin: Cesium.VerticalOrigin.BOTTOM, heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND, disableDepthTestDistance: Number.POSITIVE_INFINITY } });
    }
    syncCesiumPointLayers();
    return cesiumViewer;
  };
  const syncCesiumPointLayers = () => {
    if (!cesiumViewer || !window.Cesium) return;
    const Cesium = window.Cesium;
    if (cesiumPlaces) cesiumViewer.dataSources.remove(cesiumPlaces, true);
    if (cesiumWater) cesiumViewer.dataSources.remove(cesiumWater, true);
    cesiumPlaces = new Cesium.CustomDataSource("assessment-places");
    cesiumWater = new Cesium.CustomDataSource("assessment-water-stations");
    placesPayload.forEach((place) => {
      const lon = Number(place.lon); const lat = Number(place.lat);
      if (!Number.isFinite(lon) || !Number.isFinite(lat)) return;
      const config = placeConfig[place.assessmentCategory] || placeConfig.service;
      const marker = isCityMap ? { billboard: { image: placeMarkerIcon(config.color), width: 36, height: 44, verticalOrigin: Cesium.VerticalOrigin.BOTTOM, heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND, disableDepthTestDistance: Number.POSITIVE_INFINITY } } : { point: { pixelSize: 10, color: Cesium.Color.fromCssColorString("#176fe5"), outlineColor: Cesium.Color.WHITE, outlineWidth: 2, heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND, disableDepthTestDistance: Number.POSITIVE_INFINITY }, label: { text: place.name || "", font: '500 12px "Google Sans"', pixelOffset: new Cesium.Cartesian2(0, -20), fillColor: Cesium.Color.fromCssColorString("#173653"), outlineColor: Cesium.Color.WHITE, outlineWidth: 3, style: Cesium.LabelStyle.FILL_AND_OUTLINE, heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND, disableDepthTestDistance: Number.POSITIVE_INFINITY } };
      const entity = cesiumPlaces.entities.add({ properties: { longitude: lon, latitude: lat, category: place.assessmentCategory }, position: Cesium.Cartesian3.fromDegrees(lon, lat, 3), ...marker });
      entity.assessmentPlace = place;
      entity.show = visiblePlaceCategories.has(place.assessmentCategory);
    });
    waterPayload.forEach((station) => {
      const lon = Number(station.lon); const lat = Number(station.lat);
      if (!Number.isFinite(lon) || !Number.isFinite(lat)) return;
      cesiumWater.entities.add({ position: Cesium.Cartesian3.fromDegrees(lon, lat, 3), point: { pixelSize: 12, color: Cesium.Color.fromCssColorString("#0891b2"), outlineColor: Cesium.Color.WHITE, outlineWidth: 2, heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND, disableDepthTestDistance: Number.POSITIVE_INFINITY } });
    });
    cesiumViewer.dataSources.add(cesiumPlaces); cesiumViewer.dataSources.add(cesiumWater);
    cesiumPlaces.show = placesLayer.getVisible(); cesiumWater.show = waterLayer.getVisible();
    updateCesiumPlaceEmphasis();
  };
  const updateCesiumPlaceEmphasis = () => {
    if (!cesiumPlaces || !window.Cesium) return;
    const now = window.Cesium.JulianDate.now();
    cesiumPlaces.entities.values.forEach((entity) => {
      const lon = Number(entity.properties?.longitude?.getValue(now)); const lat = Number(entity.properties?.latitude?.getValue(now));
      const highlighted = !lastAssessmentGeometry || lastAssessmentGeometry.intersectsCoordinate(ol.proj.fromLonLat([lon, lat]));
      if (isCityMap && entity.billboard) {
        const category = entity.properties?.category?.getValue(now);
        entity.billboard.image = placeMarkerIcon(highlighted ? (placeConfig[category] || placeConfig.service).color : "#94a3b8");
        return;
      }
      entity.point.color = window.Cesium.Color.fromCssColorString(highlighted ? "#176fe5" : "#9aa8b5");
      entity.label.fillColor = window.Cesium.Color.fromCssColorString(highlighted ? "#173653" : "#7e8c98");
    });
  };
  const syncCesiumSelection = async (geometryGeoJSON) => {
    if (!cesiumViewer || !geometryGeoJSON) return;
    const Cesium = window.Cesium;
    if (cesiumSelection) cesiumViewer.dataSources.remove(cesiumSelection, true);
    cesiumSelection = await Cesium.GeoJsonDataSource.load({ type: "Feature", properties: {}, geometry: geometryGeoJSON }, { clampToGround: true, stroke: Cesium.Color.fromCssColorString("#f97316"), fill: Cesium.Color.fromCssColorString("#f97316").withAlpha(0.28), strokeWidth: 4 });
    cesiumViewer.dataSources.add(cesiumSelection);
  };
  const formatArea = () => {
    if (!Number.isFinite(selectedAreaSqKm)) {
      areaResult.textContent = "—";
      return;
    }

    const units = {
      sq_km: { multiplier: 1, label: "ตร.กม." },
      rai: { multiplier: 625, label: "ไร่" },
      sq_m: { multiplier: 1_000_000, label: "ตร.ม." }
    };
    const unit = units[areaUnit.value] || units.sq_km;
    const value = selectedAreaSqKm * unit.multiplier;
    areaResult.textContent = `${value.toLocaleString("th-TH", { maximumFractionDigits: value < 10 ? 3 : 2 })} ${unit.label}`;
  };
  const simulationMetrics = () => Object.fromEntries([...page.querySelectorAll("[data-simulation-metric]")].filter((input) => input.value !== "").map((input) => [input.dataset.simulationMetric, Number(input.value)]));
  const areaDistance = () => Math.max(0, Number(page.querySelector("[data-area-distance]")?.value) || 0);

  const geometryArea = (geometry) => {
    const areaGeometry = geometry.getType() === "Circle"
      ? ol.geom.Polygon.fromCircle(geometry, 96)
      : geometry;

    return ol.sphere.getArea(areaGeometry, { projection: "EPSG:3857" }) / 1_000_000;
  };
  const showDrawingMap = () => {
    mapWrap.classList.remove("is-3d");
    roadLayer.setVisible(true); satelliteLayer.setVisible(false);
    page.querySelectorAll("[data-basemap]").forEach((button) => button.classList.toggle("active", button.dataset.basemap === "road"));
    window.setTimeout(() => map.updateSize(), 0);
  };
  const bufferedLineGeometry = (line, distance) => {
    const coordinates = line.getCoordinates();
    if (coordinates.length < 2 || distance <= 0) return null;
    const left = []; const right = [];
    coordinates.forEach((coordinate, index) => {
      const previous = coordinates[Math.max(0, index - 1)]; const next = coordinates[Math.min(coordinates.length - 1, index + 1)];
      const dx = next[0] - previous[0]; const dy = next[1] - previous[1]; const length = Math.hypot(dx, dy) || 1;
      const x = -dy / length * distance; const y = dx / length * distance;
      left.push([coordinate[0] + x, coordinate[1] + y]); right.push([coordinate[0] - x, coordinate[1] - y]);
    });
    return new ol.geom.Polygon([[...left, ...right.reverse(), left[0]]]);
  };
  const bufferedPolygonGeometry = (polygon, distance) => {
    if (distance <= 0) return polygon.clone();
    const ring = polygon.getCoordinates()[0];
    if (!ring || ring.length < 4) return polygon.clone();
    const vertices = ring.slice(0, -1);
    const signedArea = vertices.reduce((sum, point, index) => { const next = vertices[(index + 1) % vertices.length]; return sum + point[0] * next[1] - next[0] * point[1]; }, 0);
    const direction = signedArea >= 0 ? 1 : -1;
    const normal = (from, to) => { const dx = to[0] - from[0]; const dy = to[1] - from[1]; const length = Math.hypot(dx, dy) || 1; return direction > 0 ? [dy / length, -dx / length] : [-dy / length, dx / length]; };
    const expanded = vertices.map((point, index) => {
      const previous = vertices[(index - 1 + vertices.length) % vertices.length]; const next = vertices[(index + 1) % vertices.length];
      const before = normal(previous, point); const after = normal(point, next);
      const sumX = before[0] + after[0]; const sumY = before[1] + after[1]; const sumLength = Math.hypot(sumX, sumY) || 1;
      const bisector = [sumX / sumLength, sumY / sumLength];
      const correction = Math.max(0.25, Math.abs(bisector[0] * after[0] + bisector[1] * after[1]));
      return [point[0] + bisector[0] * distance / correction, point[1] + bisector[1] * distance / correction];
    });
    return new ol.geom.Polygon([[...expanded, expanded[0]]]);
  };
  const useSelectedGeometry = (geometry) => {
    if (!geometry) return;
    selectionSource.clear(); selectionSource.addFeature(new ol.Feature(geometry));
    page.querySelector("[data-area-status]").textContent = "เลือกพื้นที่แล้ว กำลังคำนวณผลกระทบ";
    page.querySelector("[data-clear-area]").disabled = false;
    calculate(geometry);
  };
  const setDrawing = (type) => {
    showDrawingMap();
    if (draw) map.removeInteraction(draw);
    if (pointClickKey) { ol.Observable.unByKey(pointClickKey); pointClickKey = null; }
    areaMode = type; areaAnchor = null; areaLine = null; areaPolygon = null;
    page.querySelectorAll("[data-area-mode]").forEach((button) => button.classList.toggle("active", button.dataset.areaMode === type));
    if (type === "point") {
      page.querySelector("[data-area-status]").textContent = "คลิกจุดบนแผนที่เพื่อเลือกพื้นที่";
      pointClickKey = map.once("singleclick", (event) => { areaAnchor = event.coordinate; pointClickKey = null; useSelectedGeometry(new ol.geom.Circle(areaAnchor, areaDistance())); });
      return;
    }
    const temporarySource = new ol.source.Vector();
    draw = new ol.interaction.Draw({ source: temporarySource, type: type === "line" ? "LineString" : "Polygon" });
    map.addInteraction(draw);
    draw.once("drawstart", () => selectionSource.clear());
    draw.once("drawend", (event) => {
      window.setTimeout(() => map.removeInteraction(draw), 0);
      areaLine = type === "line" ? event.feature.getGeometry() : null;
      areaPolygon = type === "polygon" ? event.feature.getGeometry() : null;
      useSelectedGeometry(type === "line" ? bufferedLineGeometry(areaLine, areaDistance()) : bufferedPolygonGeometry(areaPolygon, areaDistance()));
    });
  };

  const calculate = async (geometry, ruleId = "") => {
    lastAssessmentGeometry = geometry;
    placesLayer.changed();
    updateCesiumPlaceEmphasis();
    const area = geometryArea(geometry);
    selectedAreaSqKm = area;
    formatArea();
    const ratio = Math.min(area / Math.max(accessAreaSqKm, area), 1);
    const calculationGeometry = geometry.getType() === "Circle" ? ol.geom.Polygon.fromCircle(geometry, 96) : geometry;
    const geometryGeoJSON = new ol.format.GeoJSON().writeGeometryObject(calculationGeometry, { featureProjection: "EPSG:3857", dataProjection: "EPSG:4326" });
    syncCesiumSelection(geometryGeoJSON);
    const hint = page.querySelector("[data-assessment-hint]");
    hint.textContent = "กำลังคำนวณเฉพาะพื้นที่ภายในขอบเขตดูแล…";
    try {
      const response = await fetch(page.dataset.calculateUrl, { method: "POST", headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content }, body: JSON.stringify({ geometry: geometryGeoJSON, area_sq_km: area, coverage_ratio: ratio, rule_id: ruleId, disaster_type: disasterTypeSelect?.value, simulation_metrics: assessmentMode === "simulation" ? simulationMetrics() : {} }) });
      const responseType = response.headers.get("content-type") || "";
      if (!responseType.includes("application/json")) throw new Error("ระบบประเมินผลขัดข้อง กรุณาลองใหม่อีกครั้ง");
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || "คำนวณไม่สำเร็จ");
      selectedAreaSqKm = Number(result.area_sq_km);
      formatArea();
      const areaStatus = page.querySelector("[data-area-status]");
      if (areaStatus && assessmentMode === "analysis") areaStatus.textContent = `เลือกพื้นที่แล้ว ${result.area_sq_km.toLocaleString("th-TH")} ตร.กม.`;
      page.querySelector("[data-result-population]").textContent = `${result.affected_people.toLocaleString()} คน`;
      page.querySelector("[data-result-households]").textContent = `${result.affected_households.toLocaleString()} ครัวเรือน`;
      page.querySelector("[data-result-villages]").textContent = `${result.affected_villages.toLocaleString()} หมู่บ้าน`;
      rulePicker.hidden = false;
      ruleSelect.innerHTML = result.available_rules.length ? result.available_rules.map((rule) => `<option value="${escapeHtml(rule.id)}" ${rule.id === result.selected_rule_id ? "selected" : ""}>${escapeHtml(rule.name)}</option>`).join("") : '<option value="">ยังไม่มีกฎที่ผ่านเงื่อนไข</option>';
      ruleSelect.disabled = result.available_rules.length === 0;
      const resourceContainer = page.querySelector("[data-resource-results]");
      resourceContainer.innerHTML = result.resources.length ? result.resources.map((resource) => `<article><div><b>${escapeHtml(resource.name)}</b><small>ต้องใช้ ${resource.required.toLocaleString()} ${escapeHtml(resource.unit)} · พร้อมใช้ ${resource.available.toLocaleString()} ${escapeHtml(resource.unit)}</small></div><span class="${resource.sufficient ? "enough" : "shortage"}">${resource.sufficient ? "เพียงพอ" : `ขาด ${Math.max(resource.required - resource.available, 0).toLocaleString()}`}</span></article>`).join("") : `<p>${result.evaluated_rule_count > 0 ? "ยังไม่มีกฎที่ผ่านเงื่อนไขจากข้อมูลล่าสุด" : "ไม่พบกฎที่เปิดใช้งานสำหรับประเภทเหตุการณ์นี้"}</p>`;
      const savePopulation = page.querySelector("[data-save-population]");
      const saveResources = page.querySelector("[data-save-resources]");
      const saveButton = page.querySelector("[data-save-button]");
      if (savePopulation) savePopulation.value = result.affected_people;
      if (saveResources) saveResources.value = result.resources.map((resource) => `${resource.name} | ${resource.required} | ${resource.available} | ${resource.unit}`).join("\n");
      if (saveButton) saveButton.disabled = false;
      hint.textContent = result.rule_names.length ? `คำนวณด้วยกฎที่ผ่านเงื่อนไข: ${result.rule_names.join(", ")}` : result.evaluated_rule_count > 0 ? `ตรวจสอบ ${result.evaluated_rule_count} กฎแล้ว แต่ยังไม่มีกฎที่ผ่านทุกเงื่อนไข` : "ไม่พบกฎที่เปิดใช้งานสำหรับประเภทเหตุการณ์นี้";
    } catch (error) { hint.textContent = error.message; }
  };

  page.querySelectorAll("[data-assessment-mode]").forEach((button) => button.addEventListener("click", () => {
    assessmentMode = button.dataset.assessmentMode;
    page.classList.toggle("mode-map", assessmentMode === "map");
    page.classList.toggle("mode-analysis", assessmentMode === "analysis");
    page.classList.toggle("mode-simulation", assessmentMode === "simulation");
    page.querySelectorAll("[data-assessment-mode]").forEach((item) => { const active = item === button; item.classList.toggle("active", active); item.setAttribute("aria-selected", String(active)); });
    page.querySelectorAll("[data-mode-panel]").forEach((panel) => { panel.hidden = panel.dataset.modePanel !== assessmentMode; });
    if (draw) { map.removeInteraction(draw); draw = null; }
    page.querySelector("[data-assessment-hint]").textContent = assessmentMode === "simulation" ? "กำหนดค่าจำลองแล้วกดปักจุดบนแผนที่" : "";
    window.setTimeout(() => { map.updateSize(); cesiumViewer?.resize(); }, 0);
  }));
  page.querySelector("[data-pick-simulation-point]").addEventListener("click", () => {
    mapWrap.classList.remove("is-3d"); roadLayer.setVisible(true); satelliteLayer.setVisible(false);
    page.querySelectorAll("[data-basemap]").forEach((button) => button.classList.toggle("active", button.dataset.basemap === "road"));
    window.setTimeout(() => map.updateSize(), 0);
    page.querySelector("[data-assessment-hint]").textContent = "คลิกตำแหน่งเริ่มต้นสถานการณ์บนแผนที่";
    map.once("singleclick", (event) => {
      const radius = Math.max(100, Number(page.querySelector("[data-simulation-radius]").value) || 1000);
      const circle = new ol.geom.Circle(event.coordinate, radius);
      simulationPointSource.clear(); selectionSource.clear();
      simulationPointSource.addFeature(new ol.Feature(new ol.geom.Point(event.coordinate)));
      selectionSource.addFeature(new ol.Feature(circle));
      calculate(circle);
    });
  });
  page.querySelectorAll("[data-simulation-metric],[data-simulation-radius]").forEach((input) => input.addEventListener("change", () => { if (assessmentMode === "simulation" && lastAssessmentGeometry) calculate(lastAssessmentGeometry); }));
  page.querySelectorAll("[data-area-mode]").forEach((button) => button.addEventListener("click", () => setDrawing(button.dataset.areaMode)));
  page.querySelector("[data-area-distance]").addEventListener("input", (event) => {
    page.querySelector("[data-distance-output]").textContent = `${Number(event.target.value).toLocaleString("th-TH")} เมตร`;
    const previewGeometry = areaMode === "point" && areaAnchor ? new ol.geom.Circle(areaAnchor, areaDistance()) : areaMode === "line" && areaLine ? bufferedLineGeometry(areaLine, areaDistance()) : areaMode === "polygon" && areaPolygon ? bufferedPolygonGeometry(areaPolygon, areaDistance()) : null;
    if (!previewGeometry) return;
    selectionSource.clear(); selectionSource.addFeature(new ol.Feature(previewGeometry));
    lastAssessmentGeometry = previewGeometry;
    placesLayer.changed();
    page.querySelector("[data-area-status]").textContent = "กำลังปรับระยะพื้นที่…";
  });
  page.querySelector("[data-area-distance]").addEventListener("change", () => { if (areaMode === "point" && areaAnchor) useSelectedGeometry(new ol.geom.Circle(areaAnchor, areaDistance())); if (areaMode === "line" && areaLine) useSelectedGeometry(bufferedLineGeometry(areaLine, areaDistance())); if (areaMode === "polygon" && areaPolygon) useSelectedGeometry(bufferedPolygonGeometry(areaPolygon, areaDistance())); });
  areaUnit.addEventListener("change", formatArea);
  ruleSelect.addEventListener("change", () => { if (lastAssessmentGeometry && ruleSelect.value) calculate(lastAssessmentGeometry, ruleSelect.value); });
  disasterTypeSelect?.addEventListener("change", () => { if (lastAssessmentGeometry) calculate(lastAssessmentGeometry); });
  page.querySelectorAll("[data-basemap]").forEach((button) => button.addEventListener("click", async () => { const mode = button.dataset.basemap; const is3d = mode === "3d"; mapWrap.classList.toggle("is-3d", is3d); roadLayer.setVisible(mode === "road"); satelliteLayer.setVisible(mode === "satellite"); page.querySelectorAll("[data-basemap]").forEach((item) => item.classList.toggle("active", item === button)); if (is3d) { try { await initializeCesium(); if (lastAssessmentGeometry) { const geometry = lastAssessmentGeometry.getType() === "Circle" ? ol.geom.Polygon.fromCircle(lastAssessmentGeometry, 96) : lastAssessmentGeometry; const geojson = new ol.format.GeoJSON().writeGeometryObject(geometry, { featureProjection: "EPSG:3857", dataProjection: "EPSG:4326" }); await syncCesiumSelection(geojson); } cesiumViewer.resize(); } catch (error) { page.querySelector("[data-assessment-hint]").textContent = error.message; } } else { window.setTimeout(() => map.updateSize(), 0); } }));
  page.querySelector("[data-clear-area]").addEventListener("click", () => { selectionSource.clear(); simulationPointSource.clear(); areaAnchor = null; areaLine = null; page.querySelector("[data-area-status]").textContent = ""; page.querySelector("[data-clear-area]").disabled = true; if (cesiumViewer && cesiumSelection) { cesiumViewer.dataSources.remove(cesiumSelection, true); cesiumSelection = null; } selectedAreaSqKm = null; lastAssessmentGeometry = null; rulePicker.hidden = true; ruleSelect.innerHTML = '<option value="">ยังไม่มีกฎที่ผ่านเงื่อนไข</option>'; ruleSelect.disabled = true; page.querySelectorAll("[data-result-area],[data-result-population],[data-result-households],[data-result-villages]").forEach((element) => { element.textContent = "—"; }); page.querySelector("[data-resource-results]").innerHTML = "<p>ยังไม่มีผลการคำนวณ</p>"; const saveButton = page.querySelector("[data-save-button]"); if (saveButton) saveButton.disabled = true; });
  page.querySelector("[data-clear-area]").addEventListener("click", () => { areaPolygon = null; placesLayer.changed(); updateCesiumPlaceEmphasis(); });
  page.querySelectorAll("[data-layer-toggle]").forEach((input) => input.addEventListener("change", () => {
    ({ boundary: boundaryLayer, places: placesLayer, water: waterLayer }[input.dataset.layerToggle]).setVisible(input.checked);
    if (input.dataset.layerToggle === "boundary" && cesiumBoundary) cesiumBoundary.show = input.checked;
    if (input.dataset.layerToggle === "places" && cesiumPlaces) cesiumPlaces.show = input.checked;
    if (input.dataset.layerToggle === "water" && cesiumWater) cesiumWater.show = input.checked;
  }));
  page.querySelectorAll("[data-city-place-toggle]").forEach((button) => button.addEventListener("click", () => {
    const category = button.dataset.cityPlaceToggle;
    if (visiblePlaceCategories.has(category)) visiblePlaceCategories.delete(category); else visiblePlaceCategories.add(category);
    const active = visiblePlaceCategories.has(category);
    button.classList.toggle("active", active); button.setAttribute("aria-pressed", String(active));
    placesLayer.changed();
    if (cesiumPlaces) cesiumPlaces.entities.values.forEach((entity) => {
      const value = entity.properties?.category?.getValue(window.Cesium.JulianDate.now());
      if (value === category) entity.show = active;
    });
  }));
  page.querySelector("[data-close-place-detail]")?.addEventListener("click", () => { placeDetail.hidden = true; });
  map.on("singleclick", (event) => {
    if (!isCityMap) return;
    const feature = map.forEachFeatureAtPixel(event.pixel, (candidate, layer) => layer === placesLayer ? candidate : null);
    if (!feature) { if (placeDetail) placeDetail.hidden = true; return; }
    showPlaceDetail(feature.get("place"));
  });

  fetch("/api/access_area", { headers: { Accept: "application/json" } }).then((response) => response.json()).then((data) => {
    accessBoundaryGeoJSON = data;
    const feature = new ol.format.GeoJSON().readFeature(data, { featureProjection: "EPSG:3857" });
    accessBoundary = feature.getGeometry(); boundarySource.addFeature(feature); accessAreaSqKm = geometryArea(accessBoundary);
    const world = ol.geom.Polygon.fromExtent(ol.proj.get("EPSG:3857").getExtent());
    const polygons = accessBoundary.getType() === "Polygon" ? [accessBoundary] : accessBoundary.getPolygons();
    polygons.forEach((polygon) => world.appendLinearRing(new ol.geom.LinearRing(polygon.getCoordinates()[0])));
    maskSource.addFeature(new ol.Feature(world)); map.getView().fit(accessBoundary.getExtent(), { padding: [30, 30, 30, 30], maxZoom: 15 });
  });
  const placesByCategory = {};
  const renderAssessmentPlaces = () => {
    const seen = new Set();
    placesPayload = Object.entries(placesByCategory).flatMap(([category, places]) => places.map((place) => ({ ...place, assessmentCategory: category }))).filter((place) => {
      const key = place.id || `${place.name}:${place.lon}:${place.lat}`;
      if (seen.has(key)) return false;
      seen.add(key); return true;
    });
    placesSource.clear();
    placesPayload.forEach((place) => {
      const lon = Number(place.lon); const lat = Number(place.lat);
      if (!Number.isFinite(lon) || !Number.isFinite(lat)) return;
      placesSource.addFeature(new ol.Feature({ geometry: new ol.geom.Point(ol.proj.fromLonLat([lon, lat])), name: place.name, category: place.assessmentCategory, place }));
    });
    syncCesiumPointLayers();
  };
  const loadAssessmentPlaces = async (category, loadMore = false, attempt = 0) => {
    try {
      const suffix = loadMore ? "&load_more=1" : "";
      const response = await fetch(`/api/places?category=${category}${suffix}`, { headers: { Accept: "application/json" } });
      if (!response.ok) return;
      const payload = await response.json();
      placesByCategory[category] = payload.data || [];
      renderAssessmentPlaces();
      if (payload.meta?.pagination?.complete === false && attempt < 16) {
        const delay = Math.max(500, Number(payload.meta.pagination.retry_after_seconds || 1) * 1000);
        window.setTimeout(() => loadAssessmentPlaces(category, true, attempt + 1), delay);
      }
    } catch (_) { /* Keep the places already loaded from other categories. */ }
  };
  ["government", "education", "health", "culture", "tourism", "transport", "service", "emergency"].forEach((category, index) => window.setTimeout(() => loadAssessmentPlaces(category), index * 180));
  fetch("/api/water_stations", { headers: { Accept: "application/json" } }).then((response) => response.ok ? response.json() : []).then((stations) => { waterPayload = stations; stations.forEach((station) => waterSource.addFeature(new ol.Feature(new ol.geom.Point(ol.proj.fromLonLat([Number(station.lon), Number(station.lat)]))))); syncCesiumPointLayers(); }).catch(() => {});
});
