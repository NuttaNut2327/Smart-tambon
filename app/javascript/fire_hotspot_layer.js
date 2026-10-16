// Map markers and popup content for NASA FIRMS active-fire hotspots (/api/fire_hotspots).
// Marker size and colour follow the fire radiative power (FRP, MW): stronger fires are larger and redder.
(() => {
  const FRP_LEVELS = [
    { min: 50, color: "#b42318", radius: 9, label: "สูง (≥ 50 MW)" },
    { min: 10, color: "#e8590c", radius: 7, label: "ปานกลาง (10–50 MW)" },
    { min: -Infinity, color: "#f59f00", radius: 5, label: "ต่ำ (< 10 MW)" }
  ];
  const CONFIDENCE_LABELS = { l: "ต่ำ", low: "ต่ำ", n: "ปกติ", nominal: "ปกติ", h: "สูง", high: "สูง" };
  const DAYNIGHT_LABELS = { D: "กลางวัน", N: "กลางคืน" };
  const styles = new Map();
  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);

  const frpLevel = frp => FRP_LEVELS.find(level => (Number(frp) || 0) >= level.min);

  function markerStyle(hotspot) {
    const level = frpLevel(hotspot?.frp);
    if (!styles.has(level.color)) {
      styles.set(level.color, new ol.style.Style({
        image: new ol.style.Circle({ radius: level.radius, fill: new ol.style.Fill({ color: level.color }), stroke: new ol.style.Stroke({ color: "#fff", width: 1.5 }) })
      }));
    }
    return styles.get(level.color);
  }

  function formatTime(value) {
    const time = value && new Date(value);
    if (!time || Number.isNaN(time.getTime())) return "ไม่ทราบเวลา";
    return `${time.toLocaleString("th-TH", { timeZone: "Asia/Bangkok", day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" })} น.`;
  }

  function confidenceText(confidence) {
    if (confidence == null || confidence === "") return "ไม่ระบุ";
    const value = String(confidence).trim();
    if (/^\d+(\.\d+)?$/.test(value)) return `${Number(value)}%`;
    return CONFIDENCE_LABELS[value.toLowerCase()] || value;
  }

  function popupHtml(hotspot) {
    const level = frpLevel(hotspot.frp);
    const frp = hotspot.frp == null ? "ไม่มีข้อมูล" : `${Number(hotspot.frp).toFixed(1)} MW`;
    const satellite = [hotspot.source_label, hotspot.satellite && hotspot.satellite !== hotspot.source_label ? `(${hotspot.satellite})` : null].filter(Boolean).join(" ");
    return `<div class="hotspot-popup"><strong><span class="hotspot-popup-dot" style="background:${level.color}"></span>จุดความร้อน</strong>
      <p>เวลาตรวจพบ: ${escapeHtml(formatTime(hotspot.acquired_at))}${DAYNIGHT_LABELS[hotspot.daynight] ? ` · ${DAYNIGHT_LABELS[hotspot.daynight]}` : ""}</p>
      <p>ดาวเทียม: ${escapeHtml(satellite || "ไม่ระบุ")}</p>
      <p>ค่าความเชื่อมั่น: ${escapeHtml(confidenceText(hotspot.confidence))}</p>
      <p>FRP: ${escapeHtml(frp)} · ${escapeHtml(level.label)}</p>
      <p class="hotspot-popup-coords">${Number(hotspot.lat).toFixed(4)}, ${Number(hotspot.lon).toFixed(4)} · ข้อมูล NASA FIRMS</p></div>`;
  }

  async function load(hours) {
    const response = await fetch(`/api/fire_hotspots?hours=${encodeURIComponent(hours || 24)}`, { headers: { Accept: "application/json" } });
    if (!response.ok) throw new Error(response.status);
    const payload = await response.json();
    payload.hotspots = (payload.hotspots || []).filter(hotspot => Number.isFinite(Number(hotspot.lon)) && Number.isFinite(Number(hotspot.lat)));
    return payload;
  }

  window.SmartTambonHotspots = { markerStyle, popupHtml, formatTime, load, FRP_LEVELS };
})();
