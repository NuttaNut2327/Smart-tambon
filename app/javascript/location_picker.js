// Place/road search for any OpenLayers map, plus a self-contained picker for forms with latitude/longitude.
//
//   SmartTambonLocation.attachSearch(map, { onSelect: (lon, lat, result) => ... })
//     adds a search box on top of an existing map (geocoder: <meta name="geocoder-url">, Nominatim API).
//   <div data-location-picker data-lat-input="#id" data-lon-input="#id" data-name-input="#id" data-center="[lon,lat]" data-zoom="14">
//     is initialised automatically: click or drag the pin, or search, and the inputs are filled.
(() => {
  const geocoderUrl = () => (document.querySelector('meta[name="geocoder-url"]')?.content || "https://geocode.pcm-life.com").replace(/\/$/, "");
  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);

  async function search(query, { map, signal } = {}) {
    const params = new URLSearchParams({ q: query, format: "jsonv2", limit: "6", countrycodes: "th", "accept-language": "th", addressdetails: "1" });
    // Prefer results near the area currently shown on the map without excluding the rest of Thailand.
    const extent = map?.getView().calculateExtent(map.getSize?.() || undefined);
    if (extent && extent.every(Number.isFinite)) {
      const [west, south] = ol.proj.toLonLat([extent[0], extent[1]]);
      const [east, north] = ol.proj.toLonLat([extent[2], extent[3]]);
      params.set("viewbox", [west, north, east, south].map(value => value.toFixed(5)).join(","));
    }
    const response = await fetch(`${geocoderUrl()}/search?${params}`, { headers: { Accept: "application/json" }, signal });
    if (!response.ok) throw new Error(`ค้นหาไม่สำเร็จ (${response.status})`);
    return (await response.json()).filter(result => Number.isFinite(Number(result.lat)) && Number.isFinite(Number(result.lon)));
  }

  const shortName = result => result.name || String(result.display_name || "").split(",")[0];
  const detailLine = result => String(result.display_name || "").split(",").slice(1, 5).map(part => part.trim()).filter(Boolean).join(", ");

  function attachSearch(map, { onSelect, placeholder = "ค้นหาสถานที่ ถนน หรือหมู่บ้าน" } = {}) {
    if (!map || !window.ol) return null;
    const box = document.createElement("div");
    box.className = "location-search ol-unselectable";
    box.innerHTML = `<label class="location-search-field"><span class="material-symbols-outlined" aria-hidden="true">search</span><input type="search" placeholder="${escapeHtml(placeholder)}" autocomplete="off" aria-label="${escapeHtml(placeholder)}" enterkeyhint="search"><span class="location-search-spinner" hidden></span></label><ul class="location-search-results" role="listbox" hidden></ul>`;
    const input = box.querySelector("input");
    const list = box.querySelector("ul");
    const spinner = box.querySelector(".location-search-spinner");
    // Keep typing and clicks inside the box from reaching the map or submitting the surrounding form.
    ["pointerdown", "click", "dblclick", "wheel", "keydown"].forEach(type => box.addEventListener(type, event => event.stopPropagation()));
    map.addControl(new ol.control.Control({ element: box }));

    let timer, controller, results = [], active = -1;
    const close = () => { list.hidden = true; active = -1; };
    const render = message => {
      list.innerHTML = message ? `<li class="location-search-empty">${escapeHtml(message)}</li>` : results.map((result, index) => `<li role="option" data-index="${index}" class="${index === active ? "active" : ""}"><b>${escapeHtml(shortName(result))}</b><small>${escapeHtml(detailLine(result))}</small></li>`).join("");
      list.hidden = false;
    };
    const choose = index => {
      const result = results[index];
      if (!result) return;
      const lon = Number(result.lon), lat = Number(result.lat);
      input.value = shortName(result);
      close();
      map.getView().animate({ center: ol.proj.fromLonLat([lon, lat]), zoom: Math.max(map.getView().getZoom() || 0, 17), duration: 350 });
      onSelect?.(lon, lat, { ...result, short_name: shortName(result) });
    };
    const run = async () => {
      const query = input.value.trim();
      if (query.length < 2) { close(); return; }
      controller?.abort();
      controller = new AbortController();
      spinner.hidden = false;
      try {
        results = await search(query, { map, signal: controller.signal });
        active = results.length ? 0 : -1;
        render(results.length ? null : "ไม่พบสถานที่ ลองพิมพ์ชื่อถนน ตำบล หรืออำเภอเพิ่มเติม");
      } catch (error) {
        if (error.name !== "AbortError") { results = []; render("ค้นหาไม่สำเร็จ กรุณาลองอีกครั้ง"); }
      } finally {
        spinner.hidden = true;
      }
    };
    input.addEventListener("input", () => { clearTimeout(timer); timer = setTimeout(run, 450); });
    input.addEventListener("keydown", event => {
      if (event.key === "Enter") {
        event.preventDefault();
        if (!list.hidden && results[active]) choose(active); else { clearTimeout(timer); run(); }
      } else if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        if (list.hidden || !results.length) return;
        event.preventDefault();
        active = (active + (event.key === "ArrowDown" ? 1 : -1) + results.length) % results.length;
        render();
      } else if (event.key === "Escape") close();
    });
    list.addEventListener("click", event => { const item = event.target.closest("[data-index]"); if (item) choose(Number(item.dataset.index)); });
    document.addEventListener("click", event => { if (!box.contains(event.target)) close(); });
    return { input, close };
  }

  const pinStyle = () => new ol.style.Style({
    image: new ol.style.Icon({ anchor: [0.5, 1], src: "data:image/svg+xml;charset=utf-8," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="34" height="44" viewBox="0 0 34 44"><path d="M17 43s15-14.5 15-26A15 15 0 0 0 2 17c0 11.5 15 26 15 26z" fill="#c2463a" stroke="#fff" stroke-width="2"/><circle cx="17" cy="17" r="6" fill="#fff"/></svg>') })
  });

  function initPicker(element) {
    if (element.dataset.locationPickerReady || !window.ol) return;
    element.dataset.locationPickerReady = "true";
    const scope = element.closest("form") || document;
    const find = selector => selector && (scope.querySelector(selector) || document.querySelector(selector));
    const latInput = find(element.dataset.latInput);
    const lonInput = find(element.dataset.lonInput);
    const nameInput = find(element.dataset.nameInput);
    if (!latInput || !lonInput) return;

    const mapElement = element.querySelector("[data-location-map]") || element;
    const marker = new ol.Feature();
    const markerLayer = new ol.layer.Vector({ source: new ol.source.Vector({ features: [marker] }), style: pinStyle(), zIndex: 10 });
    let center = [100.5018, 13.7563];
    try { center = JSON.parse(element.dataset.center || "null") || center; } catch {}
    const map = new ol.Map({
      target: mapElement,
      layers: [new ol.layer.Tile({ source: new ol.source.OSM() }), markerLayer],
      view: new ol.View({ center: ol.proj.fromLonLat(center), zoom: Number(element.dataset.zoom) || 6 })
    });
    const status = element.querySelector("[data-location-status]");
    const describe = () => {
      if (!status) return;
      const lat = parseFloat(latInput.value), lon = parseFloat(lonInput.value);
      status.textContent = Number.isFinite(lat) && Number.isFinite(lon) ? `ตำแหน่ง: ${lat.toFixed(6)}, ${lon.toFixed(6)}` : "ยังไม่ได้กำหนดตำแหน่ง — คลิกบนแผนที่ ลากหมุด หรือค้นหาชื่อสถานที่";
    };
    const setPoint = (lon, lat, { pan = false } = {}) => {
      latInput.value = Number(lat).toFixed(6);
      lonInput.value = Number(lon).toFixed(6);
      [latInput, lonInput].forEach(input => input.dispatchEvent(new Event("input", { bubbles: true })));
      marker.setGeometry(new ol.geom.Point(ol.proj.fromLonLat([Number(lon), Number(lat)])));
      if (pan) map.getView().animate({ center: marker.getGeometry().getCoordinates(), duration: 250 });
      describe();
    };
    const syncFromInputs = ({ pan = false } = {}) => {
      const lat = parseFloat(latInput.value), lon = parseFloat(lonInput.value);
      if (!Number.isFinite(lat) || !Number.isFinite(lon)) { marker.setGeometry(undefined); describe(); return; }
      marker.setGeometry(new ol.geom.Point(ol.proj.fromLonLat([lon, lat])));
      if (pan) map.getView().animate({ center: marker.getGeometry().getCoordinates(), zoom: Math.max(map.getView().getZoom(), 15), duration: 250 });
      describe();
    };
    map.on("singleclick", event => { const [lon, lat] = ol.proj.toLonLat(event.coordinate); setPoint(lon, lat); });
    const drag = new ol.interaction.Translate({ layers: [markerLayer] });
    drag.on("translateend", () => { const [lon, lat] = ol.proj.toLonLat(marker.getGeometry().getCoordinates()); setPoint(lon, lat); });
    map.addInteraction(drag);
    map.on("pointermove", event => { mapElement.style.cursor = map.hasFeatureAtPixel(event.pixel, { layerFilter: layer => layer === markerLayer }) ? "grab" : "crosshair"; });
    [latInput, lonInput].forEach(input => input.addEventListener("change", () => syncFromInputs({ pan: true })));
    attachSearch(map, {
      onSelect: (lon, lat, result) => {
        setPoint(lon, lat);
        if (nameInput && !nameInput.value.trim()) nameInput.value = result.short_name;
      }
    });
    element.querySelector("[data-location-current]")?.addEventListener("click", () => {
      navigator.geolocation?.getCurrentPosition(
        position => { setPoint(position.coords.longitude, position.coords.latitude); map.getView().animate({ center: marker.getGeometry().getCoordinates(), zoom: 17, duration: 300 }); },
        () => { if (status) status.textContent = "ไม่สามารถอ่านตำแหน่งปัจจุบันได้ กรุณาอนุญาตการเข้าถึงตำแหน่งในเบราว์เซอร์"; },
        { enableHighAccuracy: true, timeout: 10000 }
      );
    });
    syncFromInputs();
    // Maps inside dialogs or hidden tabs need a resize once they become visible.
    new ResizeObserver(() => map.updateSize()).observe(mapElement);
    element.smartTambonMap = map;
  }

  const initAll = (root = document) => root.querySelectorAll("[data-location-picker]").forEach(initPicker);
  window.SmartTambonLocation = { attachSearch, search, initPicker, initAll };
  document.addEventListener("DOMContentLoaded", () => initAll());
})();
