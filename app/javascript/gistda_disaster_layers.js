// GISTDA Disaster Open API layers (/api/gistda/*): flood polygons, VIIRS hotspots and drought-risk (DRI+) tiles.
// Data is cached by the weather service; the GISTDA key stays on the server.
(() => {
  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);
  const CONFIDENCE_LABELS = { low: "ต่ำ", l: "ต่ำ", nominal: "ปกติ", n: "ปกติ", high: "สูง", h: "สูง" };
  const SQ_M_PER_RAI = 1600;

  const floodStyle = new ol.style.Style({
    fill: new ol.style.Fill({ color: "rgba(30, 136, 229, .45)" }),
    stroke: new ol.style.Stroke({ color: "#1565c0", width: 1.2 })
  });
  const hotspotStyle = new ol.style.Style({
    image: new ol.style.RegularShape({ points: 3, radius: 7, fill: new ol.style.Fill({ color: "#c2255c" }), stroke: new ol.style.Stroke({ color: "#fff", width: 1.5 }) })
  });

  function formatTime(value) {
    const time = value && new Date(value);
    if (!time || Number.isNaN(time.getTime())) return "ไม่ทราบเวลา";
    return `${time.toLocaleString("th-TH", { timeZone: "Asia/Bangkok", day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" })} น.`;
  }

  const number = (value, digits = 0) => (value == null || value === "" ? "ไม่มีข้อมูล" : Number(value).toLocaleString("th-TH", { maximumFractionDigits: digits }));
  const rai = sqm => (sqm == null ? "ไม่มีข้อมูล" : `${number(Number(sqm) / SQ_M_PER_RAI, 1)} ไร่`);
  const place = props => [props.village, props.tambon, props.amphoe, props.province].filter(Boolean).join(" ") || "ไม่ระบุพื้นที่";

  function popupHtml(props) {
    if (props.kind === "flood") {
      return `<div class="gistda-popup"><strong><span class="gistda-popup-swatch flood"></span>พื้นที่น้ำท่วม (GISTDA)</strong>
        <p>${escapeHtml(place(props))}</p>
        <p>พื้นที่: ${escapeHtml(rai(props.area_sq_m))} · นาข้าว: ${escapeHtml(rai(props.rice_area_sq_m))}</p>
        <p>ประชากร: ${escapeHtml(number(props.population))} · อาคาร: ${escapeHtml(number(props.buildings))} · โรงเรียน: ${escapeHtml(number(props.schools))} · โรงพยาบาล: ${escapeHtml(number(props.hospitals))}</p>
        <p class="gistda-popup-meta">ปรับปรุง ${escapeHtml(formatTime(props.updated_at))}${props.scenes ? ` · ภาพ ${escapeHtml(props.scenes)}` : ""}</p></div>`;
    }
    const confidence = CONFIDENCE_LABELS[String(props.confidence || "").toLowerCase()] || props.confidence || "ไม่ระบุ";
    return `<div class="gistda-popup"><strong><span class="gistda-popup-swatch hotspot"></span>จุดความร้อน VIIRS (GISTDA)</strong>
      <p>${escapeHtml(place(props))}${props.land_use ? ` · ${escapeHtml(props.land_use)}` : ""}</p>
      <p>เวลาตรวจพบ: ${escapeHtml(formatTime(props.acquired_at))}</p>
      <p>ค่าความเชื่อมั่น: ${escapeHtml(confidence)} · FRP: ${props.frp == null ? "ไม่มีข้อมูล" : `${escapeHtml(Number(props.frp).toFixed(1))} MW`}</p></div>`;
  }

  async function load(dataset, { period, bbox } = {}) {
    const params = new URLSearchParams({ period: period || 1 });
    if (bbox) params.set("bbox", bbox.map(value => Number(value).toFixed(4)).join(","));
    const response = await fetch(`/api/gistda/${encodeURIComponent(dataset)}?${params}`, { headers: { Accept: "application/json" } });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw Object.assign(new Error(payload.error || `HTTP ${response.status}`), { payload });
    return payload;
  }

  // XYZ tiles proxied by Rails; tiles outside the user's area come back empty (204).
  function tileSource(layer, period = 7) {
    return new ol.source.XYZ({ url: `/api/gistda/tiles/${layer}/{z}/{x}/{y}?period=${period}`, minZoom: 5, maxZoom: 18, crossOrigin: "anonymous",
      attributions: "© GISTDA Disaster Open API" });
  }

  window.SmartTambonGistda = { floodStyle, hotspotStyle, popupHtml, load, tileSource, formatTime };
})();
