// Historical disaster footprints (/api/disaster_events): polygon styles by hazard and map popup content.
(() => {
  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);
  const number = (value, digits = 0) => Number(value || 0).toLocaleString("th-TH", { maximumFractionDigits: digits });
  const date = value => value ? new Date(value).toLocaleDateString("th-TH", { timeZone: "Asia/Bangkok", day: "numeric", month: "short", year: "numeric" }) : "";
  // Thai seasons by month (1-12), roughly following the Thai Meteorological Department calendar.
  const SEASONS = { summer: [3, 4, 5], rainy: [6, 7, 8, 9, 10], winter: [11, 12, 1, 2] };

  const hexToRgba = (hex, alpha) => {
    const value = parseInt(String(hex).replace("#", ""), 16);
    return `rgba(${(value >> 16) & 255},${(value >> 8) & 255},${value & 255},${alpha})`;
  };

  const styles = new Map();
  function style(event, colors) {
    const color = colors[event?.hazard] || "#6b756f";
    const key = `${color}-${event?.severity}`;
    if (!styles.has(key)) {
      // Stronger events get a more opaque fill and a heavier outline.
      const severity = Math.min(4, Math.max(1, Number(event?.severity) || 1));
      styles.set(key, new ol.style.Style({
        fill: new ol.style.Fill({ color: hexToRgba(color, 0.14 + severity * 0.06) }),
        stroke: new ol.style.Stroke({ color, width: 1 + severity * 0.5 })
      }));
    }
    return styles.get(key);
  }

  const inSeason = (event, season) => !season || SEASONS[season].includes(new Date(event.started_at).getMonth() + 1);

  function popupHtml(event, colors) {
    const period = [date(event.started_at), event.ended_at && date(event.ended_at)].filter(Boolean).join(" – ");
    const rows = [
      ["ช่วงเวลา", `${period}${event.duration_days ? ` (${event.duration_days} วัน)` : ""}`],
      ["หมู่บ้าน", (event.villages || []).length ? event.villages.map(moo => `หมู่ ${moo}`).join(", ") : null],
      ["สาเหตุ", event.cause],
      ["ครัวเรือนได้รับผลกระทบ", event.affected_households ? `${number(event.affected_households)} ครัวเรือน (${number(event.affected_people)} คน)` : null],
      ["บ้านเสียหาย", event.damaged_houses ? `${number(event.damaged_houses)} หลัง` : null],
      ["พื้นที่เกษตรเสียหาย", event.farmland_rai ? `${number(event.farmland_rai)} ไร่${event.area_rai ? ` (จากพื้นที่ภัย ${number(event.area_rai)} ไร่)` : ""}` : null],
      ["ถนนเสียหาย", event.roads_km ? `${number(event.roads_km, 1)} กม.` : null],
      ["บาดเจ็บ / เสียชีวิต", event.injuries || event.deaths ? `${number(event.injuries)} / ${number(event.deaths)} คน` : null],
      ["มูลค่าความเสียหาย", event.estimated_loss_baht ? `${number(event.estimated_loss_baht)} บาท` : null],
      ["ฝนสะสม 3 วันก่อนเกิด", event.rain_3d_mm != null ? `${number(event.rain_3d_mm)} มม.` : null]
    ].filter(([, value]) => value);
    return `<div class="disaster-event-popup" style="--hazard:${escapeHtml(colors[event.hazard] || "#6b756f")}">
      <p class="disaster-event-popup-kicker"><i></i>${escapeHtml(event.hazard_label)} · ${escapeHtml(event.severity_label)}${event.simulated ? `<span class="demo-badge">ข้อมูลจำลอง</span>` : ""}</p>
      <strong>${escapeHtml(event.title)}</strong>
      <dl>${rows.map(([label, value]) => `<dt>${label}</dt><dd>${escapeHtml(value)}</dd>`).join("")}</dl>
      ${event.description ? `<p class="disaster-event-popup-description">${escapeHtml(event.description)}</p>` : ""}
    </div>`;
  }

  async function load({ hazard, year } = {}) {
    const params = new URLSearchParams({ limit: 5000 });
    if (hazard) params.set("hazard", hazard);
    if (year) { params.set("from", `${year}-01-01`); params.set("to", `${year}-12-31`); }
    const response = await fetch(`/api/disaster_events?${params}`, { headers: { Accept: "application/json" } });
    if (!response.ok) throw new Error(response.status);
    return response.json();
  }

  window.SmartTambonDisasterEvents = { style, popupHtml, load, inSeason };
})();
