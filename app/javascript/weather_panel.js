// Dashboard weather panel. Data comes from /api/weather (Rails), which proxies the standalone weather
// service (services/weather). Values the model does not provide arrive as null and are shown as "—".
(() => {
  const STORAGE_KEY = "smartTambon.weatherLocation";
  const EXPANDED_KEY = "smartTambon.weatherExpanded";
  const TH_DAYS = ["อา.", "จ.", "อ.", "พ.", "พฤ.", "ศ.", "ส."];
  const CODES = {
    0: ["ท้องฟ้าแจ่มใส", "sunny", "clear_night"],
    1: ["มีเมฆเล็กน้อย", "partly_cloudy_day", "partly_cloudy_night"],
    2: ["มีเมฆบางส่วน", "partly_cloudy_day", "partly_cloudy_night"],
    3: ["มีเมฆมาก", "cloud"],
    45: ["มีหมอก", "foggy"], 48: ["หมอกน้ำค้างแข็ง", "foggy"],
    51: ["ฝนละอองเล็กน้อย", "rainy_light"], 53: ["ฝนละออง", "rainy_light"], 55: ["ฝนละอองหนาแน่น", "rainy_light"],
    56: ["ฝนละอองเยือกแข็ง", "weather_mix"], 57: ["ฝนละอองเยือกแข็ง", "weather_mix"],
    61: ["ฝนเล็กน้อย", "rainy_light"], 63: ["ฝนปานกลาง", "rainy"], 65: ["ฝนหนัก", "rainy_heavy"],
    66: ["ฝนเยือกแข็ง", "weather_mix"], 67: ["ฝนเยือกแข็งหนัก", "weather_mix"],
    71: ["หิมะเล็กน้อย", "weather_snowy"], 73: ["หิมะ", "weather_snowy"], 75: ["หิมะหนัก", "weather_snowy"],
    77: ["เกล็ดหิมะ", "weather_snowy"],
    80: ["ฝนซู่เล็กน้อย", "rainy_light"], 81: ["ฝนซู่", "rainy"], 82: ["ฝนซู่หนัก", "rainy_heavy"],
    85: ["หิมะโปรย", "weather_snowy"], 86: ["หิมะโปรยหนัก", "weather_snowy"],
    95: ["พายุฝนฟ้าคะนอง", "thunderstorm"], 96: ["พายุฝนฟ้าคะนอง ลูกเห็บ", "thunderstorm"],
    99: ["พายุฝนฟ้าคะนอง ลูกเห็บหนัก", "thunderstorm"]
  };
  const DIRS = ["เหนือ", "ตะวันออกเฉียงเหนือ", "ตะวันออก", "ตะวันออกเฉียงใต้", "ใต้", "ตะวันตกเฉียงใต้", "ตะวันตก", "ตะวันตกเฉียงเหนือ"];
  const DIRS_SHORT = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];

  const esc = value => String(value ?? "").replace(/[&<>"']/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch]));
  const num = (value, digits = 0) => (value === null || value === undefined ? null : Number(value).toFixed(digits));
  const deg = value => (value === null || value === undefined ? "—" : `${Math.round(value)}°`);
  const icon = (name, extra = "") => `<span class="material-symbols-outlined ${extra}" aria-hidden="true">${name}</span>`;
  const condition = (code, isDay = true) => {
    const entry = CODES[code];
    if (!entry) return { label: "ไม่มีข้อมูล", icon: "help" };
    return { label: entry[0], icon: (!isDay && entry[2]) || entry[1] };
  };

  function timeIn(tz, iso, opts = { hour: "2-digit", minute: "2-digit", hour12: false }) {
    return new Intl.DateTimeFormat("en-GB", { timeZone: tz, ...opts }).format(new Date(iso));
  }
  function localDateKey(tz, date) {
    return new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
  }
  function compass(degrees) {
    const i = Math.round(((degrees % 360) + 360) % 360 / 45) % 8;
    return { th: DIRS[i], short: DIRS_SHORT[i] };
  }
  function tile(title, iconName, body) {
    return `<h3>${icon(iconName)}${esc(title)}</h3>${body}`;
  }
  function unavailable(reason) {
    return `<div class="wx-big">—</div><p class="wx-note">${esc(reason)}</p>`;
  }

  // Moon phase from the mean synodic month (astronomical calculation, not a data feed).
  function moonPhase(date) {
    const synodic = 29.530588853;
    const knownNewMoon = Date.UTC(2000, 0, 6, 18, 14) / 86400000;
    const age = (((date.getTime() / 86400000 - knownNewMoon) % synodic) + synodic) % synodic;
    const illumination = (1 - Math.cos((2 * Math.PI * age) / synodic)) / 2;
    const waxing = age < synodic / 2;
    const day = waxing ? Math.max(1, Math.round(age)) : Math.max(1, Math.round(age - synodic / 2));
    let name;
    if (illumination < 0.03) name = "เดือนมืด (จันทร์ดับ)";
    else if (illumination > 0.97) name = "จันทร์เต็มดวง";
    else if (illumination < 0.45) name = waxing ? "จันทร์เสี้ยวข้างขึ้น" : "จันทร์เสี้ยวข้างแรม";
    else if (illumination <= 0.55) name = waxing ? "ข้างขึ้นครึ่งดวง" : "ข้างแรมครึ่งดวง";
    else name = waxing ? "ข้างขึ้นค่อนดวง" : "ข้างแรมค่อนดวง";
    return { age, illumination, waxing, name, lunarDay: `${waxing ? "ขึ้น" : "แรม"} ${Math.min(day, 15)} ค่ำ` };
  }
  function moonSvg(phase) {
    // Lit fraction drawn as a terminator ellipse over a dark disc.
    const r = 40;
    const k = Math.cos(2 * Math.PI * phase.age / 29.530588853); // 1 new, -1 full
    const rx = Math.abs(k) * r;
    const litRight = phase.waxing;
    const outer = `M50 10 A${r} ${r} 0 0 ${litRight ? 1 : 0} 50 90`;
    const inner = `A${rx} ${r} 0 0 ${(k > 0) === litRight ? 0 : 1} 50 10`;
    return `<svg viewBox="0 0 100 100" class="wx-moon" role="img" aria-label="${esc(phase.name)}">
      <circle cx="50" cy="50" r="${r}" class="wx-moon-dark"/><path d="${outer} ${inner} Z" class="wx-moon-lit"/></svg>`;
  }

  function renderHero(root, data) {
    const { location, current, forecast } = data;
    const today = forecast.days[0];
    const cond = condition(current?.weather_code, current?.is_day !== false);
    const name = location.name_th || location.name;
    const range = today ? `สูงสุด ${deg(today.temperature_max_c)}  ต่ำสุด ${deg(today.temperature_min_c)}` : "";
    root.querySelector("[data-wx-name]").textContent = name;
    root.querySelector("[data-wx-compact-name]").textContent = name;
    const dist = root.querySelector("[data-wx-distance]");
    dist.hidden = !(data.distance_km > 10);
    if (!dist.hidden) dist.textContent = `จุดพยากรณ์ที่ใกล้พื้นที่ของคุณที่สุด ห่าง ${num(data.distance_km)} กม.`;
    root.querySelector("[data-wx-temp]").textContent = deg(current?.temperature_c);
    root.querySelector("[data-wx-compact-temp]").textContent = deg(current?.temperature_c);
    root.querySelector("[data-wx-compact-icon]").textContent = cond.icon;
    root.querySelector("[data-wx-condition]").textContent = cond.label;
    root.querySelector("[data-wx-compact-condition]").textContent = cond.label;
    root.querySelector("[data-wx-range]").textContent = range;
    root.querySelector("[data-wx-compact-range]").textContent = range;
  }

  // Compact view: next 12 hours + 7 days, everything else lives in the full view.
  function renderCompact(root, data) {
    const tz = data.location.timezone;
    const now = Date.now();
    const hours = data.hourly.filter(h => new Date(h.valid_time).getTime() > now - 3600000).slice(0, 12);
    root.querySelector("[data-wx-next12]").innerHTML = hours.map((h, i) => {
      const cond = condition(h.weather_code, h.is_day !== false);
      const prob = h.precipitation_probability_pct;
      return `<div class="wx-cell" role="listitem" title="${esc(cond.label)}"><b>${i === 0 ? "ตอนนี้" : timeIn(tz, h.valid_time, { hour: "2-digit", hour12: false })}</b>
        ${icon(cond.icon)}<em>${prob !== null && prob >= 20 ? `${Math.round(prob)}%` : "&nbsp;"}</em><span>${deg(h.temperature_c)}</span></div>`;
    }).join("");
    const todayKey = localDateKey(tz, new Date());
    root.querySelector("[data-wx-week]").innerHTML = data.forecast.days.map(d => {
      const cond = condition(d.weather_code);
      const prob = d.precipitation_probability_max_pct;
      const label = d.forecast_date === todayKey ? "วันนี้" : TH_DAYS[new Date(`${d.forecast_date}T12:00:00Z`).getUTCDay()];
      return `<div class="wx-cell" role="listitem" title="${esc(cond.label)}"><b>${label}</b>${icon(cond.icon)}
        <em>${prob !== null && prob >= 20 ? `${Math.round(prob)}%` : "&nbsp;"}</em>
        <span>${deg(d.temperature_max_c)}<small>${deg(d.temperature_min_c)}</small></span></div>`;
    }).join("");
  }

  function setExpanded(root, expanded, remember = true) {
    root.dataset.expanded = String(expanded);
    root.querySelector("[data-wx-toggle]").setAttribute("aria-expanded", String(expanded));
    root.querySelector("[data-wx-toggle-label]").textContent = expanded ? "ย่อ" : "ดูรายละเอียดเต็ม";
    if (remember) {
      try { localStorage.setItem(EXPANDED_KEY, expanded ? "1" : "0"); } catch { /* ignore */ }
    }
    if (!root._wxData) return;
    root.querySelector("[data-wx-full]").hidden = !expanded;
    root.querySelector("[data-wx-compact]").hidden = expanded;
    if (expanded) renderRadar(root, root._wxData);
  }

  function renderHourly(root, data) {
    const tz = data.location.timezone;
    const now = Date.now();
    const hours = data.hourly.filter(h => new Date(h.valid_time).getTime() > now - 3600000).slice(0, 25);
    const events = [];
    data.forecast.days.forEach(day => {
      [["sunrise", "ดวงอาทิตย์ขึ้น", "wb_twilight"], ["sunset", "ดวงอาทิตย์ตก", "wb_twilight"]].forEach(([key, label, ico]) => {
        if (!day[key]) return;
        const t = new Date(day[key]).getTime();
        if (hours.length && t > new Date(hours[0].valid_time).getTime() && t < new Date(hours[hours.length - 1].valid_time).getTime()) {
          events.push({ t, label, ico, key });
        }
      });
    });
    const items = hours.map((h, i) => ({ t: new Date(h.valid_time).getTime(), h, first: i === 0 })).concat(events).sort((a, b) => a.t - b.t);
    root.querySelector("[data-wx-hourly]").innerHTML = items.map(item => {
      if (!item.h) {
        return `<div class="wx-hour wx-hour-event" role="listitem"><b>${timeIn(tz, new Date(item.t).toISOString())}</b>${icon(item.ico, `wx-${item.key}`)}<span>${item.label}</span></div>`;
      }
      const h = item.h;
      const cond = condition(h.weather_code, h.is_day !== false);
      const prob = h.precipitation_probability_pct;
      return `<div class="wx-hour" role="listitem" title="${esc(cond.label)}"><b>${item.first ? "ตอนนี้" : timeIn(tz, h.valid_time, { hour: "2-digit", hour12: false })}</b>
        ${icon(cond.icon)}<em>${prob !== null && prob >= 20 ? `${Math.round(prob)}%` : "&nbsp;"}</em><span>${deg(h.temperature_c)}</span></div>`;
    }).join("");

    const next24 = hours.slice(0, 24);
    const rainy = next24.find(h => (h.precipitation_probability_pct ?? 0) >= 50 || (h.precipitation_mm ?? 0) >= 0.5);
    const gusts = next24.map(h => h.wind_gusts_kmh).filter(v => v !== null);
    const parts = [rainy ? `คาดว่าจะมีฝนช่วงประมาณ ${timeIn(tz, rainy.valid_time)} น.` : "ไม่คาดว่าจะมีฝนตกใน 24 ชั่วโมงข้างหน้า"];
    if (gusts.length) parts.push(`ลมกระโชกสูงสุด ${Math.round(Math.max(...gusts))} กม./ชม.`);
    root.querySelector("[data-wx-summary]").textContent = parts.join(" ");
  }

  function renderDaily(root, data) {
    const tz = data.location.timezone;
    const days = data.forecast.days;
    const mins = days.map(d => d.temperature_min_c).filter(v => v !== null);
    const maxs = days.map(d => d.temperature_max_c).filter(v => v !== null);
    const lo = Math.min(...mins), hi = Math.max(...maxs), span = Math.max(hi - lo, 1);
    const todayKey = localDateKey(tz, new Date());
    const currentTemp = data.current?.temperature_c;
    root.querySelector("[data-wx-daily]").innerHTML = days.map(d => {
      const date = new Date(`${d.forecast_date}T12:00:00Z`);
      const isToday = d.forecast_date === todayKey;
      const cond = condition(d.weather_code);
      const prob = d.precipitation_probability_max_pct;
      const left = d.temperature_min_c === null ? 0 : ((d.temperature_min_c - lo) / span) * 100;
      const width = d.temperature_max_c === null || d.temperature_min_c === null ? 0 : ((d.temperature_max_c - d.temperature_min_c) / span) * 100;
      const dot = isToday && currentTemp !== null && currentTemp !== undefined
        ? `<i class="wx-bar-dot" style="left:${Math.min(100, Math.max(0, ((currentTemp - lo) / span) * 100))}%"></i>` : "";
      return `<li><b>${isToday ? "วันนี้" : TH_DAYS[date.getUTCDay()]}</b>
        <span class="wx-day-icon" title="${esc(cond.label)}">${icon(cond.icon)}${prob !== null && prob >= 20 ? `<em>${Math.round(prob)}%</em>` : ""}</span>
        <span class="wx-day-min">${deg(d.temperature_min_c)}</span>
        <span class="wx-bar"><i style="left:${left}%;width:${width}%"></i>${dot}</span>
        <span class="wx-day-max">${deg(d.temperature_max_c)}</span></li>`;
    }).join("");
  }

  function renderTiles(root, data) {
    const tz = data.location.timezone;
    const cur = data.current || {};
    const days = data.forecast.days;
    const today = days[0] || {};
    const tomorrow = days[1] || {};
    const model = data.forecast.run?.model || cur.model || "";
    const missing = new Set([...(cur.unavailable_params || []), ...(data.forecast.run?.unavailable_params || [])]);
    const set = (key, html) => { root.querySelector(`[data-wx-tile="${key}"]`).innerHTML = html; };

    // UV
    if (cur.uv_index === null || cur.uv_index === undefined) {
      set("uv", tile("ดัชนี UV", "light_mode", unavailable(missing.has("uv_index") ? `โมเดล ${model} ไม่มีข้อมูล UV` : "ไม่มีข้อมูล")));
    } else {
      const uv = cur.uv_index;
      const level = uv < 3 ? "ต่ำ" : uv < 6 ? "ปานกลาง" : uv < 8 ? "สูง" : uv < 11 ? "สูงมาก" : "อันตราย";
      set("uv", tile("ดัชนี UV", "light_mode", `<div class="wx-big">${num(uv)}</div><p class="wx-sub">${level}</p>
        <span class="wx-uv-scale"><i style="left:${Math.min(100, (uv / 11) * 100)}%"></i></span>`));
    }

    // Sunrise / sunset
    const now = Date.now();
    const nextSunrise = days.map(d => d.sunrise).find(t => t && new Date(t).getTime() > now);
    const sunsetToday = today.sunset;
    const sunUp = today.sunrise && sunsetToday && now > new Date(today.sunrise).getTime() && now < new Date(sunsetToday).getTime();
    const headline = sunUp ? { label: "ดวงอาทิตย์ตก", t: sunsetToday } : { label: "ดวงอาทิตย์ขึ้น", t: nextSunrise || today.sunrise };
    let sunX = 0;
    if (sunUp) sunX = (now - new Date(today.sunrise).getTime()) / (new Date(sunsetToday).getTime() - new Date(today.sunrise).getTime());
    const sunY = 30 - Math.sin(Math.PI * sunX) * 22;
    set("sun", tile(headline.label, "wb_twilight", `<div class="wx-big">${headline.t ? timeIn(tz, headline.t) : "—"}</div>
      <svg viewBox="0 0 100 40" class="wx-sun-curve" aria-hidden="true"><path d="M0 30 Q 50 -14 100 30" /><line x1="0" y1="30" x2="100" y2="30"/>
      ${sunUp ? `<circle cx="${sunX * 100}" cy="${sunY}" r="3.5"/>` : ""}</svg>
      <p class="wx-note">${sunUp ? `ขึ้นเมื่อ ${timeIn(tz, today.sunrise)} น.` : sunsetToday ? `ตกเมื่อ ${timeIn(tz, sunsetToday)} น.` : ""}</p>`));

    // Wind
    if (cur.wind_speed_kmh === null || cur.wind_speed_kmh === undefined) {
      set("wind", tile("ลม", "air", unavailable("ไม่มีข้อมูลลม")));
    } else {
      const dir = cur.wind_direction_deg ?? 0;
      const c = compass(dir);
      const ticks = Array.from({ length: 36 }, (_, i) => `<line x1="50" y1="8" x2="50" y2="${i % 9 === 0 ? 14 : 11}" transform="rotate(${i * 10} 50 50)"/>`).join("");
      set("wind", tile("ลม", "air", `<svg viewBox="0 0 100 100" class="wx-compass" role="img" aria-label="ลมจากทิศ${c.th}">
        <g class="wx-ticks">${ticks}</g><text x="50" y="24">N</text><text x="80" y="54">E</text><text x="50" y="84">S</text><text x="20" y="54">W</text>
        <g transform="rotate(${dir + 180} 50 50)"><line x1="50" y1="78" x2="50" y2="20" class="wx-arrow"/><path d="M50 14 L45 24 L55 24 Z" class="wx-arrow-head"/><circle cx="50" cy="80" r="3" class="wx-arrow-tail"/></g>
        <circle cx="50" cy="50" r="15" class="wx-compass-hub"/><text x="50" y="50" class="wx-compass-speed">${num(cur.wind_speed_kmh)}</text><text x="50" y="59" class="wx-compass-unit">กม./ชม.</text></svg>
        <p class="wx-note">ลมจากทิศ${c.th}${cur.wind_gusts_kmh !== null ? ` · กระโชก ${num(cur.wind_gusts_kmh)} กม./ชม.` : ""}</p>`));
    }

    // Moon
    const phase = moonPhase(new Date());
    set("moon", tile(phase.name, "dark_mode", `${moonSvg(phase)}<p class="wx-note">${phase.lunarDay} · สว่าง ${Math.round(phase.illumination * 100)}%<br>คำนวณทางดาราศาสตร์</p>`));

    // Precipitation
    set("precip", tile("ปริมาณฝน", "water_drop", today.precipitation_sum_mm === null || today.precipitation_sum_mm === undefined
      ? unavailable("ไม่มีข้อมูลปริมาณฝน")
      : `<div class="wx-big">${num(today.precipitation_sum_mm, 1)} <small>มม.</small></div><p class="wx-sub">วันนี้ (พยากรณ์)</p>
         <p class="wx-note">${tomorrow.precipitation_sum_mm !== null && tomorrow.precipitation_sum_mm !== undefined ? `คาดว่าพรุ่งนี้ ${num(tomorrow.precipitation_sum_mm, 1)} มม.` : ""}</p>`));

    // Feels like
    if (cur.apparent_temperature_c === null || cur.apparent_temperature_c === undefined) {
      set("feels", tile("อุณหภูมิที่รู้สึก", "thermostat", unavailable("ไม่มีข้อมูล")));
    } else {
      const diff = cur.apparent_temperature_c - (cur.temperature_c ?? cur.apparent_temperature_c);
      const text = diff >= 2 ? "รู้สึกร้อนกว่าอุณหภูมิจริง เนื่องจากความชื้นสูง" : diff <= -2 ? "รู้สึกเย็นกว่าอุณหภูมิจริง เนื่องจากลม" : "ใกล้เคียงกับอุณหภูมิจริง";
      set("feels", tile("อุณหภูมิที่รู้สึก", "thermostat", `<div class="wx-big">${deg(cur.apparent_temperature_c)}</div><p class="wx-note">${text}</p>`));
    }

    // Humidity
    set("humidity", tile("ความชื้น", "humidity_percentage", cur.relative_humidity_pct === null || cur.relative_humidity_pct === undefined
      ? unavailable("ไม่มีข้อมูลความชื้น")
      : `<div class="wx-big">${num(cur.relative_humidity_pct)}%</div><p class="wx-note">${cur.dew_point_c !== null ? `จุดน้ำค้างขณะนี้ ${deg(cur.dew_point_c)}` : ""}</p>`));

    // Visibility
    if (cur.visibility_m === null || cur.visibility_m === undefined) {
      set("visibility", tile("ทัศนวิสัย", "visibility", unavailable(missing.has("visibility") ? `โมเดล ${model} ไม่มีข้อมูลทัศนวิสัย` : "ไม่มีข้อมูล")));
    } else {
      const km = cur.visibility_m / 1000;
      const text = km >= 10 ? "มองเห็นได้ชัดเจน" : km >= 4 ? "มองเห็นได้ปานกลาง" : "ทัศนวิสัยต่ำ ระวังการเดินทาง";
      set("visibility", tile("ทัศนวิสัย", "visibility", `<div class="wx-big">${num(km)} <small>กม.</small></div><p class="wx-note">${text}</p>`));
    }

    // Pressure
    if (cur.pressure_msl_hpa === null || cur.pressure_msl_hpa === undefined) {
      set("pressure", tile("ความกดอากาศ", "speed", unavailable("ไม่มีข้อมูล")));
    } else {
      const p = cur.pressure_msl_hpa;
      const later = data.hourly.find(h => new Date(h.valid_time).getTime() >= now + 6 * 3600000)?.pressure_msl_hpa;
      const trend = later === null || later === undefined ? "" : later - p > 1 ? "แนวโน้มสูงขึ้น" : p - later > 1 ? "แนวโน้มลดลง" : "ค่อนข้างคงที่";
      const angle = -120 + (Math.min(1040, Math.max(980, p)) - 980) / 60 * 240;
      const ticks = Array.from({ length: 41 }, (_, i) => `<line x1="50" y1="10" x2="50" y2="16" transform="rotate(${-120 + i * 6} 50 50)"/>`).join("");
      set("pressure", tile("ความกดอากาศ", "speed", `<svg viewBox="0 0 100 100" class="wx-gauge" role="img" aria-label="${num(p)} hPa">
        <g class="wx-ticks">${ticks}</g><line x1="50" y1="8" x2="50" y2="20" class="wx-needle" transform="rotate(${angle} 50 50)"/>
        <text x="50" y="52" class="wx-gauge-value">${Number(p).toLocaleString("th-TH", { maximumFractionDigits: 0 })}</text><text x="50" y="63" class="wx-gauge-unit">hPa</text>
        <text x="24" y="90" class="wx-gauge-end">ต่ำ</text><text x="76" y="90" class="wx-gauge-end">สูง</text></svg>
        <p class="wx-note">${trend}</p>`));
    }

    // Average comparison against recently observed highs (ERA5 reanalysis)
    const recent = data.recent_high;
    if (!recent || today.temperature_max_c === null || today.temperature_max_c === undefined) {
      set("average", tile("เทียบค่าเฉลี่ย", "query_stats", unavailable("ยังไม่มีข้อมูลย้อนหลังเพียงพอ")));
    } else {
      const diff = today.temperature_max_c - recent.average_c;
      const rounded = Math.round(diff);
      const text = rounded === 0 ? "ใกล้เคียงค่าเฉลี่ย" : rounded > 0 ? "สูงกว่าค่าเฉลี่ยอุณหภูมิสูงสุด" : "ต่ำกว่าค่าเฉลี่ยอุณหภูมิสูงสุด";
      set("average", tile("เทียบค่าเฉลี่ย", "query_stats", `<div class="wx-big">${rounded > 0 ? "+" : ""}${rounded}°</div>
        <p class="wx-sub">${text} ${recent.days} วันที่ผ่านมา</p>
        <dl class="wx-avg"><dt>วันนี้</dt><dd>สูงสุด ${deg(today.temperature_max_c)}</dd><dt>เฉลี่ย ${recent.days} วัน</dt><dd>สูงสุด ${deg(recent.average_c)}</dd></dl>`));
    }
  }

  let radarMap = null;
  async function renderRadar(root, data) {
    const target = root.querySelector("[data-wx-radar]");
    const note = root.querySelector("[data-wx-radar-note]");
    if (!window.ol) { note.textContent = "ไม่สามารถโหลดแผนที่ได้"; return; }
    const center = ol.proj.fromLonLat([data.location.longitude, data.location.latitude]);
    if (radarMap && radarMap.getTargetElement() !== target) radarMap = null;
    if (!radarMap) {
      radarMap = new ol.Map({
        target,
        controls: [],
        layers: [new ol.layer.Tile({ className: "wx-basemap", source: new ol.source.OSM() })],
        view: new ol.View({ center, zoom: 7, minZoom: 5, maxZoom: 7 })
      });
      radarMap.getInteractions().forEach(i => { if (i instanceof ol.interaction.MouseWheelZoom) i.setActive(false); });
    } else {
      radarMap.updateSize();
      radarMap.getView().setCenter(center);
    }
    radarMap.getLayers().getArray().slice(1).forEach(layer => radarMap.removeLayer(layer));
    const marker = document.createElement("div");
    marker.className = "wx-radar-marker";
    marker.textContent = data.current?.temperature_c === null || data.current?.temperature_c === undefined ? "—" : Math.round(data.current.temperature_c);
    radarMap.getOverlays().clear();
    radarMap.addOverlay(new ol.Overlay({ element: marker, position: center, positioning: "center-center" }));
    try {
      const meta = await fetch("https://api.rainviewer.com/public/weather-maps.json").then(r => r.json());
      const frame = meta.radar?.past?.[meta.radar.past.length - 1];
      if (!frame) throw new Error("no frame");
      radarMap.addLayer(new ol.layer.Tile({ opacity: 0.75, source: new ol.source.XYZ({
        url: `${meta.host}${frame.path}/256/{z}/{x}/{y}/2/1_1.png`, maxZoom: 7, attributions: "Radar © RainViewer"
      }) }));
      note.textContent = `เรดาร์ฝนจาก RainViewer เวลา ${timeIn(data.location.timezone, new Date(frame.time * 1000).toISOString())} น.`;
    } catch {
      note.textContent = "ไม่สามารถโหลดข้อมูลเรดาร์ได้ในขณะนี้";
    }
  }

  function renderSource(root, data) {
    const run = data.forecast.run;
    const tz = data.location.timezone;
    const parts = [];
    if (run) {
      parts.push(`พยากรณ์: Open-Meteo · ${esc(run.model)} · รอบ ${run.run_init_time ? `${timeIn("UTC", run.run_init_time, { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit", hour12: false })} UTC` : esc(run.run_id)}`);
      if (run.is_fallback) parts.push(`<b class="wx-fallback">ใช้ผู้ให้บริการสำรอง (${esc(run.provider)})</b>`);
    }
    if (data.current?.observed_at) parts.push(`สภาพปัจจุบันจากโมเดล ณ ${timeIn(tz, data.current.observed_at)} น.`);
    if (data.recent_high) parts.push(`ค่าเฉลี่ยย้อนหลัง: ${esc(data.recent_high.source)}`);
    root.querySelector("[data-wx-source]").innerHTML = parts.join(" · ");
  }

  function fillLocations(root, data, requested) {
    const select = root.querySelector("[data-wx-location]");
    const chosen = requested ? String(data.location.id) : "";
    const options = data.locations.some(l => String(l.id) === String(data.location.id)) ? data.locations : [data.location, ...data.locations];
    select.innerHTML = `<option value="" ${chosen === "" ? "selected" : ""}>พื้นที่ของฉัน</option>` +
      options.map(l => `<option value="${l.id}" ${String(l.id) === chosen ? "selected" : ""}>${esc(l.name_th || l.name)}${l.province ? ` · ${esc(l.province)}` : ""}</option>`).join("");
  }

  async function load(root, locationId) {
    root.setAttribute("aria-busy", "true");
    const url = new URL(root.dataset.weatherUrl, window.location.origin);
    if (locationId) url.searchParams.set("location_id", locationId);
    const error = root.querySelector("[data-wx-error]");
    try {
      const response = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "โหลดข้อมูลสภาพอากาศไม่สำเร็จ");
      fillLocations(root, data, locationId);
      if (!data.forecast.days.length) throw new Error("ยังไม่มีข้อมูลพยากรณ์สำหรับพื้นที่นี้ กรุณารอรอบซิงก์ถัดไป");
      error.hidden = true;
      renderHero(root, data);
      renderCompact(root, data);
      renderHourly(root, data);
      renderDaily(root, data);
      renderTiles(root, data);
      renderSource(root, data);
      root._wxData = data;
      setExpanded(root, root.dataset.expanded === "true", false);
    } catch (err) {
      error.textContent = err.message;
      error.hidden = false;
      root._wxData = null;
      root.querySelector("[data-wx-full]").hidden = true;
      root.querySelector("[data-wx-compact]").hidden = true;
    } finally {
      root.setAttribute("aria-busy", "false");
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    const root = document.querySelector("[data-weather-panel]");
    if (!root) return;
    let saved = null;
    try {
      saved = localStorage.getItem(STORAGE_KEY);
      root.dataset.expanded = String(localStorage.getItem(EXPANDED_KEY) === "1");
    } catch { /* storage unavailable */ }
    root.querySelector("[data-wx-toggle]").addEventListener("click", () => setExpanded(root, root.dataset.expanded !== "true"));
    const compact = root.querySelector("[data-wx-compact]");
    compact.addEventListener("click", () => setExpanded(root, true));
    compact.addEventListener("keydown", event => {
      if (event.key === "Enter" || event.key === " ") { event.preventDefault(); setExpanded(root, true); }
    });
    root.querySelector("[data-wx-location]").addEventListener("change", event => {
      try {
        if (event.target.value) localStorage.setItem(STORAGE_KEY, event.target.value);
        else localStorage.removeItem(STORAGE_KEY);
      } catch { /* ignore */ }
      load(root, event.target.value || null);
    });
    load(root, saved);
    setInterval(() => load(root, root.querySelector("[data-wx-location]").value || null), 15 * 60 * 1000);
  });
})();
