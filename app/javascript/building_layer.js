// Building footprints from a vector-tile server (TileServer GL / tippecanoe, OSM attributes such as BUILDING,
// B_LEVELS, NAME, A_* address fields). The URL is set by the system admin; tiles load straight from that server.
(() => {
  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);
  // Tiles stop at z14 and are simplified, so drawing earlier is a smear of a million polygons.
  const MIN_ZOOM = 15;

  const CATEGORIES = {
    residential: { label: "ที่อยู่อาศัย", fill: "rgba(214, 160, 92, .45)", stroke: "#a06a2c" },
    commercial: { label: "พาณิชย์/สำนักงาน", fill: "rgba(66, 133, 244, .4)", stroke: "#2f63b8" },
    industrial: { label: "อุตสาหกรรม/คลังสินค้า", fill: "rgba(128, 104, 168, .42)", stroke: "#5e4a85" },
    public: { label: "หน่วยงาน/การศึกษา/สาธารณสุข", fill: "rgba(198, 52, 74, .42)", stroke: "#9b2337" },
    religious: { label: "ศาสนสถาน", fill: "rgba(230, 180, 40, .5)", stroke: "#a77d0a" },
    other: { label: "อาคารทั่วไป", fill: "rgba(120, 128, 136, .35)", stroke: "#5f666d" }
  };
  const TYPES = {
    house: ["residential", "บ้าน"], residential: ["residential", "ที่อยู่อาศัย"], apartments: ["residential", "อพาร์ตเมนต์/แฟลต"], condo: ["residential", "คอนโดมิเนียม"],
    detached: ["residential", "บ้านเดี่ยว"], semidetached_house: ["residential", "บ้านแฝด"], terrace: ["residential", "ทาวน์เฮาส์/ห้องแถว"], bungalow: ["residential", "บังกะโล"],
    dormitory: ["residential", "หอพัก"], hut: ["residential", "กระท่อม"], cabin: ["residential", "กระท่อม"], farm: ["residential", "บ้านไร่"],
    commercial: ["commercial", "อาคารพาณิชย์"], retail: ["commercial", "ร้านค้า"], office: ["commercial", "สำนักงาน"], hotel: ["commercial", "โรงแรม"],
    supermarket: ["commercial", "ซูเปอร์มาร์เก็ต"], kiosk: ["commercial", "ซุ้มขายของ"], hostel: ["commercial", "โฮสเทล"],
    industrial: ["industrial", "อุตสาหกรรม"], warehouse: ["industrial", "โกดัง/คลังสินค้า"], factory: ["industrial", "โรงงาน"], manufacture: ["industrial", "โรงงาน"],
    barn: ["industrial", "ยุ้งฉาง/โรงนา"], farm_auxiliary: ["industrial", "อาคารการเกษตร"], greenhouse: ["industrial", "โรงเรือน"],
    school: ["public", "โรงเรียน"], university: ["public", "มหาวิทยาลัย"], college: ["public", "วิทยาลัย"], kindergarten: ["public", "โรงเรียนอนุบาล"],
    hospital: ["public", "โรงพยาบาล"], clinic: ["public", "คลินิก/สถานพยาบาล"], government: ["public", "หน่วยงานราชการ"], public: ["public", "อาคารสาธารณะ"],
    civic: ["public", "อาคารสาธารณะ"], fire_station: ["public", "สถานีดับเพลิง"], police: ["public", "สถานีตำรวจ"], train_station: ["public", "สถานีรถไฟ"],
    transportation: ["public", "อาคารคมนาคม"], airport_terminal: ["public", "อาคารผู้โดยสาร"],
    temple: ["religious", "วัด"], buddhist_monastery: ["religious", "วัด"], chedi: ["religious", "เจดีย์"], shrine: ["religious", "ศาลเจ้า"],
    church: ["religious", "โบสถ์"], chapel: ["religious", "โบสถ์"], cathedral: ["religious", "อาสนวิหาร"], mosque: ["religious", "มัสยิด"], religious: ["religious", "ศาสนสถาน"],
    roof: ["other", "หลังคา/เพิงคลุม"], carport: ["other", "ที่จอดรถมีหลังคา"], garage: ["other", "โรงรถ"], pavilion: ["other", "ศาลา"],
    construction: ["other", "กำลังก่อสร้าง"], ruins: ["other", "ซากอาคาร"], collapsed: ["other", "อาคารพังทลาย"], abandoned: ["other", "อาคารร้าง"]
  };

  const typeOf = props => {
    const raw = String(props.BUILDING || "yes").split(";")[0].trim();
    const [category, label] = TYPES[raw.toLowerCase()] || ["other", raw && raw !== "yes" && raw !== "building" ? raw : "อาคาร (ไม่ระบุประเภท)"];
    return { category, label };
  };
  const present = value => value != null && value !== "" && value !== "-";

  const styles = Object.fromEntries(Object.entries(CATEGORIES).map(([key, info]) => [key, new ol.style.Style({
    fill: new ol.style.Fill({ color: info.fill }), stroke: new ol.style.Stroke({ color: info.stroke, width: 0.8 })
  })]));
  const selectedStyle = new ol.style.Style({
    fill: new ol.style.Fill({ color: "rgba(255, 214, 0, .55)" }), stroke: new ol.style.Stroke({ color: "#d35400", width: 2.5 }), zIndex: 1
  });

  // Fetches the TileJSON when given one, so the tile template, zoom range and layer name come from the server.
  async function resolveTiles(config) {
    if (/\{z\}/.test(config.url)) return { tiles: [config.url], maxzoom: 14, layer: config.layer };
    const response = await fetch(config.url, { headers: { Accept: "application/json" } });
    if (!response.ok) throw new Error(`โหลด TileJSON ไม่สำเร็จ (HTTP ${response.status})`);
    const tilejson = await response.json();
    if (!Array.isArray(tilejson.tiles) || !tilejson.tiles.length) throw new Error("TileJSON ไม่มีรายการ tiles");
    const layers = (tilejson.vector_layers || []).map(layer => layer.id);
    return { tiles: tilejson.tiles, maxzoom: tilejson.maxzoom ?? 14, layer: config.layer || (layers.length === 1 ? null : layers.find(id => /building/i.test(id))) };
  }

  function createLayer(config) {
    let selectedId = null;
    const layer = new ol.layer.VectorTile({
      visible: false, zIndex: 11, minZoom: MIN_ZOOM - 0.01, declutter: false,
      style: feature => (selectedId != null && feature.get("OSM_ID") === selectedId ? selectedStyle : styles[typeOf(feature.getProperties()).category])
    });
    const ready = config?.url ? resolveTiles(config).then(tiles => {
      layer.setSource(new ol.source.VectorTile({
        format: new ol.format.MVT(tiles.layer ? { layers: [tiles.layer] } : {}),
        urls: tiles.tiles, maxZoom: tiles.maxzoom, attributions: "อาคาร © ผู้ร่วมให้ข้อมูล OpenStreetMap"
      }));
      return tiles;
    }) : Promise.reject(new Error("ยังไม่ได้ตั้งค่า URL ข้อมูลอาคาร"));
    ready.catch(() => {});
    const select = feature => { selectedId = feature ? feature.get("OSM_ID") : null; layer.changed(); };
    return { layer, ready, select, minZoom: MIN_ZOOM };
  }

  // Footprint area from the (simplified) tile geometry, so it is an estimate.
  function areaSqM(feature) {
    try {
      const geometry = feature.getType?.() === "Polygon" ? new ol.geom.Polygon(feature.getFlatCoordinates(), "XY", feature.getEnds()) : null;
      return geometry ? ol.sphere.getArea(geometry) : null;
    } catch (_error) {
      return null;
    }
  }

  function popupHtml(feature) {
    const props = feature.getProperties();
    const { category, label } = typeOf(props);
    const name = [props.NAME, props.NAME_EN].filter(present).filter((value, index, list) => list.indexOf(value) === index);
    const address = [present(props.A_HSNMBR) && `เลขที่ ${props.A_HSNMBR}`, props.A_STRT, props.A_PLACE, props.A_SBRB, props.ADDR_CITY, props.A_PSTCD].filter(value => value && present(value)).join(" ");
    const area = areaSqM(feature);
    const osmUrl = props.OSM_ID ? `https://www.openstreetmap.org/${props.OSM_TYPE === "relation" ? "relation" : "way"}/${encodeURIComponent(props.OSM_ID)}` : null;
    const rows = [
      ["ประเภท", `${label} · ${CATEGORIES[category].label}`],
      present(props.B_LEVELS) && ["จำนวนชั้น", `${props.B_LEVELS} ชั้น`],
      area && ["พื้นที่หลังคาโดยประมาณ", `${Math.round(area).toLocaleString("th-TH")} ตร.ม.`],
      address && ["ที่อยู่", address]
    ].filter(Boolean);
    return `<div class="building-popup"><strong><span class="building-popup-swatch ${category}"></span>${escapeHtml(name[0] || label)}</strong>
      ${name[1] ? `<p class="building-popup-sub">${escapeHtml(name[1])}</p>` : ""}
      <dl>${rows.map(([term, value]) => `<div><dt>${escapeHtml(term)}</dt><dd>${escapeHtml(value)}</dd></div>`).join("")}</dl>
      ${osmUrl ? `<p class="building-popup-meta">OSM ${escapeHtml(props.OSM_TYPE || "way")}/${escapeHtml(props.OSM_ID)} · <a href="${osmUrl}" target="_blank" rel="noopener">ดูใน OpenStreetMap</a></p>` : ""}</div>`;
  }

  window.SmartTambonBuildings = { createLayer, popupHtml, typeOf, CATEGORIES };
})();
