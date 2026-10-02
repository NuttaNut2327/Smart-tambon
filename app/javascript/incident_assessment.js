document.addEventListener("DOMContentLoaded", () => {
  const page = document.querySelector("[data-incident-assessment]");
  const mapElement = page?.querySelector("[data-assessment-map]");
  if (!page || !mapElement || !window.ol) return;

  const escapeHtml = (value) => String(value ?? "").replace(/[&<>'"]/g, (character) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[character]);
  const boundarySource = new ol.source.Vector();
  const villageBoundarySource = new ol.source.Vector();
  const maskSource = new ol.source.Vector();
  const placesSource = new ol.source.Vector();
  const waterSource = new ol.source.Vector();
  const selectionSource = new ol.source.Vector();
  const simulationPointSource = new ol.source.Vector();
  const simulationGridSource = new ol.source.Vector();
  const isCityMap = page.dataset.cityMap === "true";
  const cityIncidents = (() => {
    try { return JSON.parse(page.querySelector("[data-city-incidents]")?.textContent || "[]"); }
    catch (_error) { return []; }
  })();
  const incidentSourceNames = [...new Set(cityIncidents.map((incident) => incident.source || "ไม่ระบุแหล่งที่มา"))];
  const visibleIncidentSources = new Set(incidentSourceNames);
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
  const reportedIncidentMarkerIcon = () => {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="36" height="44" viewBox="0 0 42 52"><path d="M21 1C10 1 2 9.5 2 20c0 14.2 19 30.4 19 30.4S40 34.2 40 20C40 9.5 32 1 21 1z" fill="#ef3340" stroke="#facc15" stroke-width="3"/></svg>';
    return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
  };
  const datasetColors = { agencies: "#2563eb", resources: "#0f766e", workforce: "#2563eb", teams: "#ea580c", consumables: "#16a34a", population: "#475569", custom: "#9333ea" };
  const datasetIcons = { agencies: "account_balance", resources: "construction", workforce: "person", teams: "groups", consumables: "inventory_2", population: "home", custom: "location_on" };
  const importedDatasetLayers = new Map([...page.querySelectorAll("[data-city-dataset-toggle]")].map((input) => {
    const source = new ol.source.Vector();
    const color = datasetColors[input.dataset.datasetType] || "#7c3aed";
    const icon = datasetIcons[input.dataset.datasetType] || "location_on";
    const layer = new ol.layer.Vector({ source, zIndex: 17, style: (feature) => {
      const geometryType = feature.getGeometry()?.getType();
      const highlighted = !lastAssessmentGeometry || geometryType !== "Point" || lastAssessmentGeometry.intersectsCoordinate(feature.getGeometry().getCoordinates());
      const displayColor = highlighted ? color : "#94a3b8";
      if (geometryType === "Polygon" || geometryType === "MultiPolygon") return new ol.style.Style({ stroke: new ol.style.Stroke({ color: displayColor, width: 2.5 }), fill: new ol.style.Fill({ color: `${displayColor}22` }) });
      return new ol.style.Style({
        image: new ol.style.Icon({ src: placeMarkerIcon(displayColor), anchor: [0.5, 1], anchorXUnits: "fraction", anchorYUnits: "fraction" }),
        text: new ol.style.Text({ text: icon, font: '18px "Material Symbols Outlined"', fill: new ol.style.Fill({ color: "#fff" }), offsetY: -25 })
      });
    } });
    return [input.dataset.cityDatasetToggle, { input, source, layer, color }];
  }));
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
  const villageBoundaryLayer = new ol.layer.Vector({ source: villageBoundarySource, style: (feature) => new ol.style.Style({
    stroke: new ol.style.Stroke({ color: "#2563eb", width: 2.5 }),
    fill: new ol.style.Fill({ color: "rgba(37,99,235,0)" }),
    text: new ol.style.Text({ text: feature.get("village_name") || `หมู่ ${feature.get("village_number") || ""}`, font: '600 11px "Google Sans",sans-serif', fill: new ol.style.Fill({ color: "#17457a" }), stroke: new ol.style.Stroke({ color: "#fff", width: 3 }), overflow: true })
  }) });
  const maskLayer = new ol.layer.Vector({ source: maskSource, style: new ol.style.Style({ fill: new ol.style.Fill({ color: "rgba(12,29,48,.55)" }) }) });
  const placesLayer = new ol.layer.Vector({ source: placesSource, declutter: true, style: (feature) => {
    const selectedGeometry = lastAssessmentGeometry;
    const highlighted = !selectedGeometry || selectedGeometry.intersectsCoordinate(feature.getGeometry().getCoordinates());
    return cityPlaceStyle(feature.get("category"), highlighted);
  } });
  const waterLayer = new ol.layer.Vector({ source: waterSource, style: new ol.style.Style({ image: new ol.style.Circle({ radius: 6, fill: new ol.style.Fill({ color: "#0891b2" }), stroke: new ol.style.Stroke({ color: "#fff", width: 2 }) }) }) });
  const selectionLayer = new ol.layer.Vector({ source: selectionSource, style: new ol.style.Style({ stroke: new ol.style.Stroke({ color: "#f97316", width: 3, lineDash: [8, 5] }), fill: new ol.style.Fill({ color: "rgba(249,115,22,.18)" }) }) });
  const simulationGridLayer = new ol.layer.Vector({ source: simulationGridSource, zIndex: 18, style: (feature) => {
    const severity = Number(feature.get("severity") || 1);
    const colors = severity >= .67 ? ["#dc2626", "rgba(220,38,38,.58)"] : severity >= .34 ? ["#f59e0b", "rgba(245,158,11,.5)"] : ["#2563eb", "rgba(37,99,235,.42)"];
    return new ol.style.Style({ stroke: new ol.style.Stroke({ color: colors[0], width: 1 }), fill: new ol.style.Fill({ color: colors[1] }) });
  } });
  const simulationPointLayer = new ol.layer.Vector({ source: simulationPointSource, style: new ol.style.Style({ image: new ol.style.Circle({ radius: 7, fill: new ol.style.Fill({ color: "#176fe5" }), stroke: new ol.style.Stroke({ color: "#fff", width: 3 }) }) }) });
  const longitude = Number(mapElement.dataset.incidentLongitude);
  const latitude = Number(mapElement.dataset.incidentLatitude);
  const incidentMarkerSvg = '<svg xmlns="http://www.w3.org/2000/svg" width="56" height="70" viewBox="-7 -7 56 70"><defs><filter id="shadow" x="-60%" y="-50%" width="220%" height="230%"><feDropShadow dx="0" dy="4" stdDeviation="3.5" flood-color="#7f1d1d" flood-opacity=".5"/></filter></defs><circle cx="21" cy="21" r="25" fill="#facc15" opacity=".24"/><path fill="#ef3340" stroke="#fff" stroke-width="6" stroke-linejoin="round" filter="url(#shadow)" d="M21 1.5C10.2 1.5 1.5 10.2 1.5 21c0 15.2 19.5 31.5 19.5 31.5S40.5 36.2 40.5 21C40.5 10.2 31.8 1.5 21 1.5z"/><path fill="#ef3340" stroke="#facc15" stroke-width="2.5" stroke-linejoin="round" d="M21 1.5C10.2 1.5 1.5 10.2 1.5 21c0 15.2 19.5 31.5 19.5 31.5S40.5 36.2 40.5 21C40.5 10.2 31.8 1.5 21 1.5z"/><path fill="#ffffff" stroke="#ffffff" stroke-width="18" stroke-linejoin="round" transform="translate(10 33) scale(.023)" d="M720-440v-80h160v80H720Zm48 280-128-96 48-64 128 96-48 64Zm-80-480-48-64 128-96 48 64-128 96ZM200-200v-160h-40q-33 0-56.5-23.5T80-440v-80q0-33 23.5-56.5T160-600h160l200-120v480L320-360h-40v160h-80Zm240-182v-196l-98 58H160v80h182l98 58Zm120 36v-268q27 24 43.5 58.5T620-480q0 41-16.5 75.5T560-346ZM300-480Z"/></svg>';
  const incidentMarkerUrl = `data:image/svg+xml;charset=UTF-8,${encodeURIComponent(incidentMarkerSvg)}`;
  const incidentSource = new ol.source.Vector();
  if (Number.isFinite(longitude) && Number.isFinite(latitude)) incidentSource.addFeature(new ol.Feature(new ol.geom.Point(ol.proj.fromLonLat([longitude, latitude]))));
  const incidentLayer = new ol.layer.Vector({ source: incidentSource, zIndex: 30, style: new ol.style.Style({ image: new ol.style.Icon({ src: incidentMarkerUrl, anchor: [0.5, 1], scale: 1 }) }) });
  const cityIncidentLayers = new Map(incidentSourceNames.map((sourceName, index) => {
    const source = new ol.source.Vector();
    cityIncidents.filter((incident) => (incident.source || "ไม่ระบุแหล่งที่มา") === sourceName).forEach((incident) => {
      const feature = new ol.Feature(new ol.geom.Point(ol.proj.fromLonLat([Number(incident.longitude), Number(incident.latitude)])));
      feature.set("cityIncident", incident);
      source.addFeature(feature);
    });
    const layer = new ol.layer.Vector({ source, zIndex: 19, style: new ol.style.Style({
      image: new ol.style.Icon({ src: reportedIncidentMarkerIcon(), anchor: [0.5, 1], scale: 0.9 }),
      text: new ol.style.Text({ text: "campaign", font: '18px "Material Symbols Outlined"', fill: new ol.style.Fill({ color: "#fff" }), offsetY: -23 })
    }) });
    return [sourceName, layer];
  }));
  const roadLayer = new ol.layer.Tile({ source: new ol.source.OSM() });
  const satelliteLayer = new ol.layer.Tile({ source: new ol.source.XYZ({ url: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}", attributions: "Tiles © Esri", maxZoom: 18, wrapX: false }), visible: false });
  const map = new ol.Map({ target: mapElement, layers: [roadLayer, satelliteLayer, maskLayer, boundaryLayer, villageBoundaryLayer, placesLayer, waterLayer, ...importedDatasetLayers.values()].map((entry) => entry.layer || entry).concat([...cityIncidentLayers.values(), selectionLayer, simulationGridLayer, simulationPointLayer, incidentLayer]), view: new ol.View({ center: ol.proj.fromLonLat([Number.isFinite(longitude) ? longitude : 100.5, Number.isFinite(latitude) ? latitude : 13.7]), zoom: 13, minZoom: 5, maxZoom: 18, extent: ol.proj.get("EPSG:3857").getExtent() }), controls: [] });
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
  let lastAnalysisGeometry = null;
  let lastSimulationGeometry = null;
  let simulationOrigin = null;
  let simulationRunId = 0;
  let assessmentMode = isCityMap ? "map" : "analysis";
  page.classList.add(`mode-${assessmentMode}`);
  let accessBoundaryGeoJSON = null;
  let cesiumViewer = null;
  let cesiumBoundary = null;
  let cesiumVillageBoundaries = null;
  let cesiumSelection = null;
  let cesiumPlaces = null;
  let cesiumWater = null;
  let cesiumIncidentDataSource = null;
  let placesPayload = [];
  let importedAgencyPlaces = [];
  let waterPayload = [];
  const refreshPlaceLayerStyles = () => {
    placesLayer.changed();
    importedDatasetLayers.forEach((entry) => entry.layer.changed());
  };

  const areaUnit = page.querySelector("[data-area-unit]");
  const areaResult = page.querySelector("[data-result-area]");
  const rulePicker = page.querySelector("[data-rule-picker]");
  const ruleSelect = page.querySelector("[data-rule-select]");
  const disasterTypeSelect = page.querySelector("[data-assessment-disaster-type]");
  const disasterType = () => disasterTypeSelect?.value || page.dataset.disasterType || "other";
  let analysisDisasterType = disasterType();
  const mapWrap = page.querySelector(".assessment-map-wrap");
  const cesiumElement = page.querySelector("[data-assessment-cesium]");
  const placeDetail = page.querySelector("[data-city-place-detail]");
  const placeCategoryLabels = { government: "สถานที่ราชการ", education: "การศึกษา", health: "สาธารณสุข", culture: "ศาสนาและวัฒนธรรม", tourism: "ท่องเที่ยว", transport: "คมนาคม", service: "ร้านค้าและบริการ", emergency: "ความปลอดภัยและฉุกเฉิน" };
  const renderAffectedPlaces = (geometry = lastAssessmentGeometry) => {
    const container = page.querySelector("[data-affected-places]"); const count = page.querySelector("[data-affected-place-count]");
    if (!container || !count) return;
    if (!geometry) { count.textContent = "0 แห่ง"; container.innerHTML = "<p>ยังไม่มีพื้นที่สำหรับตรวจสอบสถานที่</p>"; return; }
    const affected = [...placesPayload, ...importedAgencyPlaces].filter((place, index, allPlaces) => {
      const lon = Number(place.lon); const lat = Number(place.lat);
      const uniqueKey = `${String(place.name || "").trim().toLowerCase()}:${lon.toFixed(5)}:${lat.toFixed(5)}`;
      const firstIndex = allPlaces.findIndex((candidate) => `${String(candidate.name || "").trim().toLowerCase()}:${Number(candidate.lon).toFixed(5)}:${Number(candidate.lat).toFixed(5)}` === uniqueKey);
      return firstIndex === index && Number.isFinite(lon) && Number.isFinite(lat) && geometry.intersectsCoordinate(ol.proj.fromLonLat([lon, lat]));
    });
    count.textContent = `${affected.length.toLocaleString("th-TH")} แห่ง`;
    const grouped = Object.entries(placeCategoryLabels).map(([category, label]) => [category, label, affected.filter((place) => place.assessmentCategory === category)]).filter(([, , places]) => places.length);
    container.innerHTML = affected.length ? grouped.map(([category, label, places]) => `<details class="affected-place-group" open><summary><span class="material-symbols-outlined">${escapeHtml((placeConfig[category] || placeConfig.service).icon)}</span><b>${escapeHtml(label)}</b><small>${places.length.toLocaleString("th-TH")} แห่ง</small><i class="material-symbols-outlined">expand_more</i></summary><div>${places.map((place) => `<article><b>${escapeHtml(place.name || "ไม่ระบุชื่อสถานที่")}</b><small>${place.address ? escapeHtml(place.address) : "ไม่มีรายละเอียดที่อยู่"}</small></article>`).join("")}</div></details>`).join("") : "<p>ไม่พบสถานที่สำคัญในพื้นที่ที่ได้รับผลกระทบ</p>";
  };
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
    link.removeAttribute("href"); link.textContent = ""; link.hidden = true;
    placeDetail.hidden = false;
  };
  const showIncidentDetail = (incident) => {
    if (!placeDetail || !incident) return;
    placeDetail.querySelector("[data-place-detail-icon]").textContent = "campaign";
    placeDetail.querySelector("[data-place-detail-icon]").style.backgroundColor = "#dc2635";
    placeDetail.querySelector("[data-place-detail-category]").textContent = `แจ้งเหตุโดย ${incident.source || "ไม่ระบุแหล่งที่มา"}`;
    placeDetail.querySelector("[data-place-detail-name]").textContent = incident.title || "เหตุการณ์";
    const severityLabels = { critical: "วิกฤต", very_urgent: "เร่งด่วนมาก", urgent: "เร่งด่วน", non_urgent: "ไม่เร่งด่วน", general: "ทั่วไป", waiting: "ไม่เร่งด่วน", watch: "เร่งด่วน" };
    const address = placeDetail.querySelector("[data-place-detail-address]");
    address.textContent = `ระดับความเร่งด่วน: ${severityLabels[incident.severity] || "ทั่วไป"}`; address.hidden = false;
    const contact = placeDetail.querySelector("[data-place-detail-contact]");
    contact.textContent = incident.description || "ไม่มีรายละเอียดเพิ่มเติม"; contact.hidden = false;
    const link = placeDetail.querySelector("[data-place-detail-link]");
    link.removeAttribute("href"); link.textContent = ""; link.hidden = true;
    placeDetail.hidden = false;
  };
  const showImportedDatasetDetail = (properties) => {
    if (!placeDetail || !properties) return;
    const dataType = properties.data_type || "custom";
    const titleKeys = { agencies: "agency_name", resources: "resource_name", workforce: "full_name", teams: "team_name", consumables: "name", population: "village_name" };
    const ignored = new Set(["data_type", "dataset_id", "dataset_name", "version"]);
    const titleKey = titleKeys[dataType];
    const title = properties[titleKey] || properties.name || properties.title || properties.dataset_name || "ข้อมูลบนแผนที่";
    const details = Object.entries(properties).filter(([key, value]) => !ignored.has(key) && key !== titleKey && value !== null && value !== "").slice(0, 3).map(([, value]) => value).join(" · ");
    placeDetail.querySelector("[data-place-detail-icon]").textContent = datasetIcons[dataType] || "location_on";
    placeDetail.querySelector("[data-place-detail-icon]").style.backgroundColor = datasetColors[dataType] || "#7c3aed";
    placeDetail.querySelector("[data-place-detail-category]").textContent = properties.dataset_name || "ชุดข้อมูลบนแผนที่";
    placeDetail.querySelector("[data-place-detail-name]").textContent = title;
    const address = placeDetail.querySelector("[data-place-detail-address]");
    address.textContent = properties.address || properties.location || details || ""; address.hidden = !address.textContent;
    const contact = placeDetail.querySelector("[data-place-detail-contact]");
    contact.textContent = properties.phone ? `โทร. ${properties.phone}` : ""; contact.hidden = !contact.textContent;
    const link = placeDetail.querySelector("[data-place-detail-link]");
    link.removeAttribute("href"); link.textContent = ""; link.hidden = true;
    placeDetail.hidden = false;
  };
  page.querySelectorAll("[data-city-incident-toggle]").forEach((button) => {
    button.addEventListener("change", () => {
      const sourceName = button.dataset.cityIncidentToggle;
      const visible = button.checked;
      cityIncidentLayers.get(sourceName)?.setVisible(visible);
      if (visible) visibleIncidentSources.add(sourceName); else visibleIncidentSources.delete(sourceName);
      if (cesiumIncidentDataSource) {
        const now = window.Cesium.JulianDate.now();
        cesiumIncidentDataSource.entities.values.forEach((entity) => {
          entity.show = visibleIncidentSources.has(entity.properties?.source?.getValue(now));
        });
      }
    });
  });
  page.querySelectorAll("[data-city-dataset-toggle]").forEach((input) => input.addEventListener("change", () => {
    importedDatasetLayers.get(input.dataset.cityDatasetToggle)?.layer.setVisible(input.checked);
  }));
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
  const terrainTileCache = new Map();
  const terrainHeightAt = async (coordinate, level = 13) => {
    const [lon, lat] = ol.proj.toLonLat(coordinate);
    const count = 2 ** level;
    const tileX = (lon + 180) / 360 * count;
    const latitudeRadians = Math.max(-85.0511, Math.min(85.0511, lat)) * Math.PI / 180;
    const tileY = (1 - Math.log(Math.tan(latitudeRadians) + 1 / Math.cos(latitudeRadians)) / Math.PI) / 2 * count;
    const x = Math.floor(tileX); const y = Math.floor(tileY); const key = `${level}/${x}/${y}`;
    if (!terrainTileCache.has(key)) terrainTileCache.set(key, terrainHeights(x, y, level));
    const heights = await terrainTileCache.get(key);
    const pixelX = Math.max(0, Math.min(256, Math.round((tileX - x) * 256)));
    const pixelY = Math.max(0, Math.min(256, Math.round((tileY - y) * 256)));
    return heights[pixelY * 257 + pixelX];
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
    cesiumViewer.scene.screenSpaceCameraController.enableCollisionDetection = true;
    cesiumViewer.scene.screenSpaceCameraController.minimumZoomDistance = 1_200;
    cesiumViewer.scene.screenSpaceCameraController.maximumZoomDistance = 4_000_000;
    cesiumViewer.scene.globe.baseColor = Cesium.Color.fromCssColorString("#d9e2e8");
    cesiumViewer.scene.backgroundColor = Cesium.Color.fromCssColorString("#d9e2e8");
    if (isCityMap) {
      const placeClickHandler = new Cesium.ScreenSpaceEventHandler(cesiumViewer.scene.canvas);
      placeClickHandler.setInputAction((movement) => {
        const picked = cesiumViewer.scene.pick(movement.position);
        if (picked?.id?.assessmentPlace) showPlaceDetail(picked.id.assessmentPlace);
        else if (picked?.id?.cityIncident) showIncidentDetail(picked.id.cityIncident);
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
    if (villageBoundarySource.getFeatures().length) await syncCesiumVillageBoundaries();
    if (Number.isFinite(longitude) && Number.isFinite(latitude)) {
      cesiumViewer.entities.add({ name: "ตำแหน่งเกิดเหตุ", position: Cesium.Cartesian3.fromDegrees(longitude, latitude, 4), billboard: { image: incidentMarkerUrl, width: 56, height: 70, verticalOrigin: Cesium.VerticalOrigin.BOTTOM, heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND, disableDepthTestDistance: Number.POSITIVE_INFINITY } });
    }
    if (cityIncidents.length) {
      cesiumIncidentDataSource = new Cesium.CustomDataSource("reported-incidents");
      cityIncidents.forEach((reportedIncident) => {
        const entity = cesiumIncidentDataSource.entities.add({
          properties: { source: reportedIncident.source || "ไม่ระบุแหล่งที่มา" },
          position: Cesium.Cartesian3.fromDegrees(Number(reportedIncident.longitude), Number(reportedIncident.latitude), 4),
          billboard: { image: reportedIncidentMarkerIcon(), width: 36, height: 44, verticalOrigin: Cesium.VerticalOrigin.BOTTOM, heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND, disableDepthTestDistance: Number.POSITIVE_INFINITY }
        });
        entity.cityIncident = reportedIncident;
      });
      cesiumViewer.dataSources.add(cesiumIncidentDataSource);
    }
    syncCesiumPointLayers();
    return cesiumViewer;
  };
  const syncCesiumVillageBoundaries = async () => {
    if (!cesiumViewer || !window.Cesium || !villageBoundarySource.getFeatures().length) return;
    const Cesium = window.Cesium;
    if (cesiumVillageBoundaries) cesiumViewer.dataSources.remove(cesiumVillageBoundaries, true);
    const geojson = new ol.format.GeoJSON().writeFeaturesObject(villageBoundarySource.getFeatures(), { featureProjection: "EPSG:3857", dataProjection: "EPSG:4326" });
    cesiumVillageBoundaries = await Cesium.GeoJsonDataSource.load(geojson, { clampToGround: true, stroke: Cesium.Color.fromCssColorString("#2563eb"), fill: Cesium.Color.TRANSPARENT, strokeWidth: 3 });
    cesiumVillageBoundaries.show = page.querySelector('[data-layer-toggle="village-boundaries"]')?.checked !== false;
    cesiumViewer.dataSources.add(cesiumVillageBoundaries);
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
      const marker = { billboard: { image: placeMarkerIcon(config.color), width: 36, height: 44, verticalOrigin: Cesium.VerticalOrigin.BOTTOM, heightReference: Cesium.HeightReference.RELATIVE_TO_GROUND, disableDepthTestDistance: Number.POSITIVE_INFINITY } };
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
      if (entity.billboard) {
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
  const simulationMetrics = () => {
    const metrics = Object.fromEntries([...page.querySelectorAll("[data-simulation-metric]")].filter((input) => !input.closest("[data-simulation-field]")?.hidden && input.value !== "").map((input) => [input.dataset.simulationMetric, Number(input.value)]));
    if (Number.isFinite(metrics.water_rise_cm)) metrics.water_level = metrics.water_rise_cm / 100;
    return metrics;
  };
  const areaDistance = () => Math.max(0, Number(page.querySelector("[data-area-distance]")?.value) || 0);

  const geometryArea = (geometry) => {
    const areaGeometry = geometry.getType() === "Circle"
      ? ol.geom.Polygon.fromCircle(geometry, 96)
      : geometry;

    return ol.sphere.getArea(areaGeometry, { projection: "EPSG:3857" }) / 1_000_000;
  };
  const updateSimulationFields = () => {
    page.querySelectorAll("[data-simulation-field]").forEach((field) => { field.hidden = disasterType() !== "flood"; });
    page.querySelector("[data-simulation-description]").textContent = "ระบุระดับน้ำหรือปริมาณน้ำฝน ระบบจะตรวจระดับความสูงและแสดงกริดพื้นที่ลุ่มต่ำที่น้ำไหลถึง";
  };
  const updateSimulationAvailability = () => {
    const button = page.querySelector('[data-assessment-mode="simulation"]');
    const available = isCityMap || disasterType() === "flood";
    button.disabled = !available;
    button.setAttribute("aria-disabled", String(!available));
    button.title = available ? "จำลองพื้นที่น้ำท่วม" : "ขณะนี้การจำลองสถานการณ์รองรับเฉพาะน้ำท่วม";
    if (!available && assessmentMode === "simulation") page.querySelector('[data-assessment-mode="analysis"]')?.click();
  };
  const makeGridCell = (x, y, size, severity) => {
    const gap = Math.min(1, size * .01);
    const polygon = new ol.geom.Polygon([[[x + gap, y + gap], [x + size - gap, y + gap], [x + size - gap, y + size - gap], [x + gap, y + size - gap], [x + gap, y + gap]]]);
    const feature = new ol.Feature(polygon); feature.set("severity", severity);
    return feature;
  };
  const runSimulation = async (origin) => {
    const runId = ++simulationRunId;
    const type = disasterType(); const metrics = simulationMetrics();
    const hint = page.querySelector("[data-assessment-hint]");
    if (type !== "flood") { hint.textContent = "ขณะนี้การจำลองสถานการณ์รองรับเฉพาะน้ำท่วม"; return; }
    if (!accessBoundary) { hint.textContent = "กำลังโหลดขอบเขตพื้นที่ดูแล กรุณาลองอีกครั้ง"; return; }
    if (type === "flood" && !(Number(metrics.water_rise_cm) > 0 || Number(metrics.rainfall) > 0)) { hint.textContent = "กรุณาระบุระดับน้ำที่เพิ่มขึ้นหรือปริมาณน้ำฝน"; return; }
    if (type === "fire" && !(Number(metrics.hotspot_count) > 0)) { hint.textContent = "กรุณาระบุจำนวน Hotspot"; return; }
    if (type === "wind" && !(Number(metrics.wind_speed) > 0)) { hint.textContent = "กรุณาระบุความเร็วลม"; return; }
    if (accessBoundary && !accessBoundary.intersectsCoordinate(origin)) { hint.textContent = "กรุณาเลือกจุดเริ่มต้นภายในขอบเขตพื้นที่ดูแล"; return; }
    hint.textContent = "กำลังอ่านระดับความสูงทั่วพื้นที่ดูแล…";
    const extent = accessBoundary.getExtent();
    const width = extent[2] - extent[0]; const height = extent[3] - extent[1];
    const cellSize = Math.max(50, Math.max(width, height) / 45);
    const cells = [];
    for (let column = 0, x = extent[0]; x < extent[2]; column += 1, x += cellSize) for (let row = 0, y = extent[1]; y < extent[3]; row += 1, y += cellSize) {
      const center = [x + cellSize / 2, y + cellSize / 2];
      if (!accessBoundary.intersectsCoordinate(center)) continue;
      cells.push({ x, y, center, row, column });
    }
    let affected = [];
    if (type === "flood") {
      const heights = await Promise.all([origin, ...cells.map((cell) => cell.center)].map((coordinate) => terrainHeightAt(coordinate)));
      if (runId !== simulationRunId) return;
      const originHeight = heights[0]; const rise = Math.max(0, Number(metrics.water_rise_cm) || 0) / 100 + Math.max(0, Number(metrics.rainfall) || 0) / 100;
      const waterLevel = originHeight + rise;
      cells.forEach((cell, index) => { cell.height = heights[index + 1]; });
      const byGrid = new Map(cells.map((cell) => [`${cell.row}/${cell.column}`, cell]));
      const seed = cells.reduce((nearest, cell) => !nearest || Math.hypot(cell.center[0] - origin[0], cell.center[1] - origin[1]) < Math.hypot(nearest.center[0] - origin[0], nearest.center[1] - origin[1]) ? cell : nearest, null);
      if (seed) seed.height = Math.min(seed.height, originHeight);
      const flooded = new Set(); const queue = seed ? [seed] : [];
      const neighbors = [[1,0],[-1,0],[0,1],[0,-1],[1,1],[1,-1],[-1,1],[-1,-1]];
      while (queue.length) {
        const cell = queue.shift(); const key = `${cell.row}/${cell.column}`;
        if (flooded.has(key) || !Number.isFinite(cell.height) || cell.height > waterLevel) continue;
        flooded.add(key);
        neighbors.forEach(([row, column]) => { const next = byGrid.get(`${cell.row + row}/${cell.column + column}`); if (next && !flooded.has(`${next.row}/${next.column}`) && next.height <= waterLevel) queue.push(next); });
      }
      affected = [...flooded].map((key) => { const cell = byGrid.get(key); cell.severity = Math.min(1, Math.max(.12, (waterLevel - cell.height) / Math.max(rise, .1))); return cell; });
      hint.textContent = affected.length ? `จุดเริ่มต้นสูง ${originHeight.toFixed(1)} ม. · น้ำเพิ่มขึ้น ${Number(metrics.water_rise_cm || 0).toLocaleString("th-TH")} ซม. · พื้นที่ต่ำที่น้ำไหลต่อเนื่องถึง ${affected.length.toLocaleString("th-TH")} ช่องกริด` : "ไม่พบพื้นที่ต่ำที่น้ำไหลต่อเนื่องถึงจากจุดเริ่มต้น";
    }
    simulationGridSource.clear();
    const features = affected.map((cell) => makeGridCell(cell.x, cell.y, cellSize, cell.severity));
    simulationGridSource.addFeatures(features);
    page.querySelector("[data-simulation-grid-legend]").hidden = features.length === 0;
    if (!features.length) return;
    const geometry = new ol.geom.MultiPolygon(features.map((feature) => feature.getGeometry().getCoordinates()));
    lastSimulationGeometry = geometry;
    page.querySelector("[data-clear-simulation]").disabled = false;
    await calculate(geometry, "", "simulation");
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
    lastAnalysisGeometry = geometry;
    calculate(geometry, "", "analysis");
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

  const calculate = async (geometry, ruleId = "", calculationMode = assessmentMode) => {
    lastAssessmentGeometry = geometry;
    if (calculationMode === "simulation") lastSimulationGeometry = geometry; else lastAnalysisGeometry = geometry;
    refreshPlaceLayerStyles();
    updateCesiumPlaceEmphasis();
    renderAffectedPlaces(geometry);
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
      const response = await fetch(page.dataset.calculateUrl, { method: "POST", headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content }, body: JSON.stringify({ geometry: geometryGeoJSON, area_sq_km: area, coverage_ratio: ratio, rule_id: ruleId, disaster_type: disasterTypeSelect?.value, simulation_metrics: calculationMode === "simulation" ? simulationMetrics() : {} }) });
      const responseType = response.headers.get("content-type") || "";
      if (!responseType.includes("application/json")) throw new Error("ระบบประเมินผลขัดข้อง กรุณาลองใหม่อีกครั้ง");
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || "คำนวณไม่สำเร็จ");
      if (assessmentMode !== calculationMode) return;
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
      resourceContainer.innerHTML = result.resources.length ? `<div class="assessment-resource-table"><div class="assessment-resource-head"><span>ทรัพยากร</span><span>ต้องใช้</span><span>พร้อมใช้</span><span>ผลเปรียบเทียบ</span></div>${result.resources.map((resource) => { const shortage = Math.max(resource.required - resource.available, 0); return `<article><b>${escapeHtml(resource.name)}</b><div class="resource-amount required"><strong>${resource.required.toLocaleString()} <em>${escapeHtml(resource.unit)}</em></strong></div><div class="resource-amount available"><strong>${resource.available.toLocaleString()} <em>${escapeHtml(resource.unit)}</em></strong></div><span class="resource-comparison ${resource.sufficient ? "enough" : "shortage"}"><b>${resource.sufficient ? "เพียงพอ" : `ขาดอีก ${shortage.toLocaleString()} ${escapeHtml(resource.unit)}`}</b></span></article>`; }).join("")}</div>` : `<p>${result.evaluated_rule_count > 0 ? "ยังไม่มีกฎที่ผ่านเงื่อนไขจากข้อมูลล่าสุด" : "ไม่พบกฎที่เปิดใช้งานสำหรับประเภทเหตุการณ์นี้"}</p>`;
      const savePopulation = page.querySelector("[data-save-population]");
      const saveArea = page.querySelector("[data-save-area]");
      const saveHouseholds = page.querySelector("[data-save-households]");
      const saveResources = page.querySelector("[data-save-resources]");
      const saveButton = page.querySelector("[data-save-button]");
      if (saveArea) saveArea.value = result.area_sq_km;
      if (savePopulation) savePopulation.value = result.affected_people;
      if (saveHouseholds) saveHouseholds.value = result.affected_households;
      if (saveResources) saveResources.value = result.resources.map((resource) => `${resource.name} | ${resource.required} | ${resource.available} | ${resource.unit}`).join("\n");
      if (saveButton) saveButton.disabled = false;
      hint.textContent = result.rule_names.length ? `คำนวณด้วยกฎที่ผ่านเงื่อนไข: ${result.rule_names.join(", ")}` : result.evaluated_rule_count > 0 ? `ตรวจสอบ ${result.evaluated_rule_count} กฎแล้ว แต่ยังไม่มีเงื่อนไขใดผ่าน` : "ไม่พบกฎที่เปิดใช้งานสำหรับประเภทเหตุการณ์นี้";
    } catch (error) { hint.textContent = error.message; }
  };

  page.querySelectorAll("[data-assessment-mode]").forEach((button) => button.addEventListener("click", () => {
    const previousMode = assessmentMode;
    assessmentMode = button.dataset.assessmentMode;
    if (previousMode === "analysis" && assessmentMode === "simulation") {
      selectionSource.clear();
      lastAnalysisGeometry = null;
      areaAnchor = null; areaLine = null; areaPolygon = null;
      page.querySelector("[data-area-status]").textContent = "";
      page.querySelector("[data-clear-area]").disabled = true;
      page.querySelectorAll("[data-area-mode]").forEach((item) => item.classList.remove("active"));
    }
    if (disasterTypeSelect) {
      if (assessmentMode === "simulation") {
        if (previousMode !== "simulation") analysisDisasterType = disasterTypeSelect.value;
        disasterTypeSelect.value = "flood";
        disasterTypeSelect.disabled = true;
      } else {
        disasterTypeSelect.disabled = false;
        if (previousMode === "simulation") disasterTypeSelect.value = analysisDisasterType;
      }
      updateSimulationFields();
    }
    page.classList.toggle("mode-map", assessmentMode === "map");
    page.classList.toggle("mode-analysis", assessmentMode === "analysis");
    page.classList.toggle("mode-simulation", assessmentMode === "simulation");
    page.querySelectorAll("[data-assessment-mode]").forEach((item) => { const active = item === button; item.classList.toggle("active", active); item.setAttribute("aria-selected", String(active)); });
    page.querySelectorAll("[data-mode-panel]").forEach((panel) => { panel.hidden = panel.dataset.modePanel !== assessmentMode; });
    if (draw) { map.removeInteraction(draw); draw = null; }
    selectionLayer.setVisible(assessmentMode === "analysis");
    simulationGridLayer.setVisible(assessmentMode === "simulation");
    simulationPointLayer.setVisible(assessmentMode === "simulation");
    const modeGeometry = assessmentMode === "simulation" ? lastSimulationGeometry : assessmentMode === "analysis" ? lastAnalysisGeometry : null;
    lastAssessmentGeometry = modeGeometry;
    refreshPlaceLayerStyles(); updateCesiumPlaceEmphasis();
    page.querySelector("[data-assessment-hint]").textContent = assessmentMode === "simulation" ? "กำหนดค่าจำลองแล้วกดปักจุดบนแผนที่" : "";
    if (modeGeometry) calculate(modeGeometry, "", assessmentMode); else clearDisplayedResults();
    window.setTimeout(() => { map.updateSize(); cesiumViewer?.resize(); }, 0);
  }));
  page.querySelector("[data-pick-simulation-point]").addEventListener("click", () => {
    mapWrap.classList.remove("is-3d"); roadLayer.setVisible(true); satelliteLayer.setVisible(false);
    page.querySelectorAll("[data-basemap]").forEach((button) => button.classList.toggle("active", button.dataset.basemap === "road"));
    window.setTimeout(() => map.updateSize(), 0);
    page.querySelector("[data-assessment-hint]").textContent = "คลิกตำแหน่งเริ่มต้นสถานการณ์บนแผนที่";
    map.once("singleclick", (event) => {
      simulationOrigin = event.coordinate;
      simulationPointSource.clear(); simulationGridSource.clear();
      simulationPointSource.addFeature(new ol.Feature(new ol.geom.Point(event.coordinate)));
      runSimulation(event.coordinate);
    });
  });
  page.querySelectorAll("[data-simulation-metric],[data-simulation-radius]").forEach((input) => input.addEventListener("change", () => { if (assessmentMode === "simulation" && simulationOrigin) runSimulation(simulationOrigin); }));
  page.querySelectorAll("[data-area-mode]").forEach((button) => button.addEventListener("click", () => setDrawing(button.dataset.areaMode)));
  page.querySelector("[data-area-distance]").addEventListener("input", (event) => {
    page.querySelector("[data-distance-output]").textContent = `${Number(event.target.value).toLocaleString("th-TH")} เมตร`;
    const previewGeometry = areaMode === "point" && areaAnchor ? new ol.geom.Circle(areaAnchor, areaDistance()) : areaMode === "line" && areaLine ? bufferedLineGeometry(areaLine, areaDistance()) : areaMode === "polygon" && areaPolygon ? bufferedPolygonGeometry(areaPolygon, areaDistance()) : null;
    if (!previewGeometry) return;
    selectionSource.clear(); selectionSource.addFeature(new ol.Feature(previewGeometry));
    lastAnalysisGeometry = previewGeometry; lastAssessmentGeometry = previewGeometry;
    refreshPlaceLayerStyles();
    page.querySelector("[data-area-status]").textContent = "กำลังปรับระยะพื้นที่…";
  });
  page.querySelector("[data-area-distance]").addEventListener("change", () => { if (areaMode === "point" && areaAnchor) useSelectedGeometry(new ol.geom.Circle(areaAnchor, areaDistance())); if (areaMode === "line" && areaLine) useSelectedGeometry(bufferedLineGeometry(areaLine, areaDistance())); if (areaMode === "polygon" && areaPolygon) useSelectedGeometry(bufferedPolygonGeometry(areaPolygon, areaDistance())); });
  areaUnit.addEventListener("change", formatArea);
  ruleSelect.addEventListener("change", () => { if (lastAssessmentGeometry && ruleSelect.value) calculate(lastAssessmentGeometry, ruleSelect.value, assessmentMode); });
  disasterTypeSelect?.addEventListener("change", () => { if (assessmentMode !== "simulation") analysisDisasterType = disasterTypeSelect.value; updateSimulationFields(); updateSimulationAvailability(); simulationGridSource.clear(); lastSimulationGeometry = null; if (assessmentMode === "analysis" && lastAnalysisGeometry) calculate(lastAnalysisGeometry, "", "analysis"); });
  page.querySelectorAll("[data-basemap]").forEach((button) => button.addEventListener("click", async () => { const mode = button.dataset.basemap; const is3d = mode === "3d"; mapWrap.classList.toggle("is-3d", is3d); roadLayer.setVisible(mode === "road"); satelliteLayer.setVisible(mode === "satellite"); page.querySelectorAll("[data-basemap]").forEach((item) => item.classList.toggle("active", item === button)); if (is3d) { try { await initializeCesium(); if (lastAssessmentGeometry) { const geometry = lastAssessmentGeometry.getType() === "Circle" ? ol.geom.Polygon.fromCircle(lastAssessmentGeometry, 96) : lastAssessmentGeometry; const geojson = new ol.format.GeoJSON().writeGeometryObject(geometry, { featureProjection: "EPSG:3857", dataProjection: "EPSG:4326" }); await syncCesiumSelection(geojson); } cesiumViewer.resize(); } catch (error) { page.querySelector("[data-assessment-hint]").textContent = error.message; } } else { window.setTimeout(() => map.updateSize(), 0); } }));
  const clearDisplayedResults = () => { if (cesiumViewer && cesiumSelection) { cesiumViewer.dataSources.remove(cesiumSelection, true); cesiumSelection = null; } selectedAreaSqKm = null; lastAssessmentGeometry = null; refreshPlaceLayerStyles(); renderAffectedPlaces(null); rulePicker.hidden = true; ruleSelect.innerHTML = '<option value="">ยังไม่มีกฎที่ผ่านเงื่อนไข</option>'; ruleSelect.disabled = true; page.querySelectorAll("[data-result-area],[data-result-population],[data-result-households],[data-result-villages]").forEach((element) => { element.textContent = "—"; }); page.querySelector("[data-resource-results]").innerHTML = "<p>ยังไม่มีผลการคำนวณ</p>"; const saveButton = page.querySelector("[data-save-button]"); if (saveButton) saveButton.disabled = true; };
  page.querySelector("[data-clear-area]").addEventListener("click", () => { selectionSource.clear(); lastAnalysisGeometry = null; areaAnchor = null; areaLine = null; page.querySelector("[data-area-status]").textContent = ""; page.querySelector("[data-clear-area]").disabled = true; clearDisplayedResults(); });
  page.querySelector("[data-clear-simulation]").addEventListener("click", () => { simulationPointSource.clear(); simulationGridSource.clear(); simulationOrigin = null; lastSimulationGeometry = null; simulationRunId += 1; page.querySelector("[data-simulation-grid-legend]").hidden = true; page.querySelector("[data-clear-simulation]").disabled = true; clearDisplayedResults(); page.querySelector("[data-assessment-hint]").textContent = "กำหนดค่าจำลองแล้วกดปักจุดบนแผนที่"; });
  page.querySelector("[data-clear-area]").addEventListener("click", () => { areaPolygon = null; refreshPlaceLayerStyles(); updateCesiumPlaceEmphasis(); });
  page.querySelectorAll("[data-layer-toggle]").forEach((input) => input.addEventListener("change", () => {
    ({ boundary: boundaryLayer, "village-boundaries": villageBoundaryLayer, places: placesLayer, water: waterLayer }[input.dataset.layerToggle]).setVisible(input.checked);
    if (input.dataset.layerToggle === "boundary" && cesiumBoundary) cesiumBoundary.show = input.checked;
    if (input.dataset.layerToggle === "village-boundaries" && cesiumVillageBoundaries) cesiumVillageBoundaries.show = input.checked;
    if (input.dataset.layerToggle === "places" && cesiumPlaces) cesiumPlaces.show = input.checked;
    if (input.dataset.layerToggle === "water" && cesiumWater) cesiumWater.show = input.checked;
  }));
  updateSimulationFields();
  updateSimulationAvailability();
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
    const incidentFeature = map.forEachFeatureAtPixel(event.pixel, (candidate) => candidate.get("cityIncident") ? candidate : null);
    if (incidentFeature) { showIncidentDetail(incidentFeature.get("cityIncident")); return; }
    const datasetFeature = map.forEachFeatureAtPixel(event.pixel, (candidate) => candidate.get("importedDataset") ? candidate : null);
    if (datasetFeature) { showImportedDatasetDetail(datasetFeature.get("importedDataset")); return; }
    const placeFeature = map.forEachFeatureAtPixel(event.pixel, (candidate, layer) => layer === placesLayer ? candidate : null);
    if (!placeFeature) { if (placeDetail) placeDetail.hidden = true; return; }
    showPlaceDetail(placeFeature.get("place"));
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
  fetch("/api/imported_datasets", { headers: { Accept: "application/json" } }).then((response) => response.ok ? response.json() : null).then((data) => {
    if (!data) return;
    const features = new ol.format.GeoJSON().readFeatures(data, { featureProjection: "EPSG:3857" });
    villageBoundarySource.addFeatures(features.filter((feature) => feature.get("data_type") === "village_boundaries"));
    importedAgencyPlaces = features.filter((feature) => feature.get("data_type") === "agencies" && feature.getGeometry()?.getType() === "Point").map((feature) => {
      const properties = feature.getProperties();
      const [lon, lat] = ol.proj.toLonLat(feature.getGeometry().getCoordinates());
      return {
        id: `agency:${properties.dataset_id || "dataset"}:${properties.agency_code || properties.agency_name || `${lon}:${lat}`}`,
        name: properties.agency_name || properties.name || properties.dataset_name || "ไม่ระบุชื่อหน่วยงาน",
        address: properties.address || properties.location || "",
        tel: properties.phone || properties.tel || "",
        lon,
        lat,
        assessmentCategory: "government"
      };
    });
    features.filter((feature) => feature.get("data_type") !== "village_boundaries").forEach((feature) => {
      const datasetId = String(feature.get("dataset_id") || "");
      const entry = importedDatasetLayers.get(datasetId);
      if (!entry) return;
      feature.set("importedDataset", { ...feature.getProperties(), geometry: undefined });
      entry.source.addFeature(feature);
    });
    refreshPlaceLayerStyles();
    renderAffectedPlaces();
    if (cesiumViewer) syncCesiumVillageBoundaries();
  }).catch((error) => console.warn("Unable to load imported map layers", error));
  const placesByCategory = {};
  const renderAssessmentPlaces = () => {
    const seen = new Set();
    placesPayload = Object.entries(placesByCategory).flatMap(([category, places]) => places.map((place) => ({ ...place, assessmentCategory: category }))).filter((place) => {
      const key = place.id || `${place.name}:${place.lon}:${place.lat}`;
      if (seen.has(key)) return false;
      seen.add(key); return true;
    });
    renderAffectedPlaces();
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
