// Results map for the look-back search on the incident and disaster pages: every matched incident as a point and,
// when it has been assessed, its impact area as a polygon. Clicking a point or area opens that incident.
document.addEventListener("DOMContentLoaded", () => {
  const element = document.querySelector("[data-incident-history-map]");
  if (!element || !window.ol) return;

  const items = JSON.parse(element.dataset.features || "[]");
  const selectedId = element.dataset.selectedId;
  const colors = { critical: "#b42318", very_urgent: "#d9480f", urgent: "#c98a1b", watch: "#c98a1b", non_urgent: "#567f6d", waiting: "#567f6d", general: "#3f6b8a" };
  const statusLabels = { pending: "รอรับเรื่อง", assessing: "กำลังประเมิน", in_progress: "กำลังดำเนินการ", completed: "เสร็จสิ้น" };
  const geojson = new ol.format.GeoJSON();
  const pointFeatures = [], areaFeatures = [];

  items.forEach((item) => {
    const props = { item, selected: item.id === selectedId };
    if (item.area) {
      try {
        const geometry = geojson.readGeometry(item.area, { dataProjection: "EPSG:4326", featureProjection: "EPSG:3857" });
        areaFeatures.push(new ol.Feature({ geometry, ...props }));
      } catch { /* skip an unreadable stored area */ }
    }
    if (Number.isFinite(item.longitude) && Number.isFinite(item.latitude)) {
      pointFeatures.push(new ol.Feature({ geometry: new ol.geom.Point(ol.proj.fromLonLat([item.longitude, item.latitude])), ...props }));
    }
  });

  const areaStyle = (feature) => {
    const color = colors[feature.get("item").severity] || colors.general, selected = feature.get("selected");
    return new ol.style.Style({ stroke: new ol.style.Stroke({ color: selected ? "#1f2a24" : color, width: selected ? 3 : 2, lineDash: selected ? undefined : [6, 4] }), fill: new ol.style.Fill({ color: `${color}${selected ? "40" : "22"}` }) });
  };
  const pointStyle = (feature) => {
    const color = colors[feature.get("item").severity] || colors.general, selected = feature.get("selected");
    return new ol.style.Style({ zIndex: selected ? 10 : 1, image: new ol.style.Circle({ radius: selected ? 9 : 7, fill: new ol.style.Fill({ color }), stroke: new ol.style.Stroke({ color: selected ? "#1f2a24" : "#ffffff", width: 3 }) }) });
  };

  const areaSource = new ol.source.Vector({ features: areaFeatures });
  const pointSource = new ol.source.Vector({ features: pointFeatures });
  const map = new ol.Map({
    target: element,
    layers: [
      new ol.layer.Tile({ source: new ol.source.OSM() }),
      new ol.layer.Vector({ source: areaSource, style: areaStyle }),
      new ol.layer.Vector({ source: pointSource, style: pointStyle })
    ],
    view: new ol.View({ center: ol.proj.fromLonLat([100.5, 13.75]), zoom: 6 }),
    controls: ol.control.defaults.defaults({ attribution: false, rotate: false })
  });

  const extent = ol.extent.createEmpty();
  [areaSource, pointSource].forEach((source) => { if (source.getFeatures().length) ol.extent.extend(extent, source.getExtent()); });
  if (!ol.extent.isEmpty(extent)) map.getView().fit(extent, { padding: [36, 36, 36, 36], maxZoom: 15 });

  const tooltip = document.createElement("div");
  tooltip.className = "incident-history-tooltip";
  tooltip.hidden = true;
  element.append(tooltip);
  const formatTime = (value) => value ? new Date(value).toLocaleString("th-TH", { dateStyle: "medium", timeStyle: "short" }) : "";
  const featureAt = (pixel) => map.forEachFeatureAtPixel(pixel, (feature) => feature, { hitTolerance: 4 });

  map.on("pointermove", (event) => {
    const feature = event.dragging ? null : featureAt(event.pixel);
    element.style.cursor = feature ? "pointer" : "";
    if (!feature) { tooltip.hidden = true; return; }
    const item = feature.get("item");
    tooltip.replaceChildren(
      Object.assign(document.createElement("b"), { textContent: item.title || item.reference_code }),
      Object.assign(document.createElement("small"), { textContent: [item.reference_code, statusLabels[item.status], formatTime(item.event_time)].filter(Boolean).join(" · ") })
    );
    tooltip.style.left = `${event.pixel[0] + 14}px`;
    tooltip.style.top = `${event.pixel[1] + 14}px`;
    tooltip.hidden = false;
  });
  element.addEventListener("mouseleave", () => { tooltip.hidden = true; });
  map.on("singleclick", (event) => {
    const item = featureAt(event.pixel)?.get("item");
    if (item?.url) window.location.assign(item.url);
  });
});
