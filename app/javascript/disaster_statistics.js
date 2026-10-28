// Disaster statistics and outlook page (/disaster_statistics): renders /api/disaster_events/statistics and /outlook
// as plain HTML/CSS charts.
(() => {
  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);
  const number = (value, digits = 0) => Number(value || 0).toLocaleString("th-TH", { maximumFractionDigits: digits });
  const compactBaht = value => {
    const amount = Number(value || 0);
    if (amount >= 1e6) return `${number(amount / 1e6, 1)} ล้านบาท`;
    return `${number(amount)} บาท`;
  };
  const thaiDate = value => new Date(`${value}T00:00:00`).toLocaleDateString("th-TH", { day: "numeric", month: "short", year: "numeric" });
  const RISKS = {
    "สูงมาก": { level: "critical", icon: "error" },
    "สูง": { level: "serious", icon: "warning" },
    "ปานกลาง": { level: "warning", icon: "info" },
    "ต่ำ": { level: "good", icon: "check_circle" }
  };
  const TRENDS = { "เพิ่มขึ้น": "trending_up", "ลดลง": "trending_down", "ทรงตัว": "trending_flat", "นอกฤดูกาล": "remove" };

  // Round the axis top up to 1, 2, 2.5 or 5 × 10^n and return evenly spaced ticks.
  function axis(max, count = 4) {
    if (!(max > 0)) return { max: 1, ticks: [0, 1] };
    const raw = max / count;
    const power = 10 ** Math.floor(Math.log10(raw));
    const step = [1, 2, 2.5, 5, 10].map(factor => factor * power).find(candidate => candidate >= raw);
    const top = Math.ceil(max / step) * step;
    return { max: top, ticks: Array.from({ length: Math.round(top / step) + 1 }, (_, index) => +(index * step).toFixed(2)) };
  }
  const percent = (value, max) => `${Math.min(100, (Number(value) || 0) / max * 100).toFixed(2)}%`;

  document.addEventListener("DOMContentLoaded", () => {
    const root = document.querySelector("[data-disaster-stats]");
    if (!root) return;
    const hazards = JSON.parse(root.dataset.hazards);
    const hazardByKey = Object.fromEntries(hazards.map(hazard => [hazard.key, hazard]));
    const tooltip = root.querySelector("[data-stats-tooltip]");
    const swatch = key => `<i class="dstat-swatch" style="--hazard:${escapeHtml(hazardByKey[key]?.color)}"></i>`;

    // One shared tooltip: every mark with data-tip shows it on hover and keyboard focus.
    const showTip = target => {
      tooltip.innerHTML = target.dataset.tip;
      tooltip.hidden = false;
      const box = target.getBoundingClientRect(), page = root.getBoundingClientRect();
      const left = Math.min(box.right - page.left + 8, page.width - tooltip.offsetWidth - 4);
      tooltip.style.left = `${left < box.right - page.left && box.left - page.left - tooltip.offsetWidth - 8 > 0 ? box.left - page.left - tooltip.offsetWidth - 8 : left}px`;
      tooltip.style.top = `${Math.max(0, box.top - page.top + box.height / 2 - tooltip.offsetHeight / 2)}px`;
    };
    const hideTip = () => { tooltip.hidden = true; };
    root.addEventListener("pointerover", event => { const target = event.target.closest("[data-tip]"); if (target) showTip(target); });
    root.addEventListener("pointerout", event => { if (event.target.closest("[data-tip]")) hideTip(); });
    root.addEventListener("focusin", event => { const target = event.target.closest("[data-tip]"); if (target) showTip(target); });
    root.addEventListener("focusout", hideTip);
    const tipRows = rows => rows.map(([key, label, value]) => `<div>${key ? swatch(key) : ""}<span>${escapeHtml(label)}</span><b>${escapeHtml(value)}</b></div>`).join("");

    async function getJson(url) {
      const response = await fetch(url, { headers: { Accept: "application/json" } });
      const payload = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(payload.error || `HTTP ${response.status}`);
      return payload;
    }

    // ---------- Statistics ----------
    function renderStats(data) {
      const period = data.period || {};
      root.querySelector("[data-stats-period]").textContent = period.from
        ? `ข้อมูลตั้งแต่ ${thaiDate(period.from)} ถึง ${thaiDate(period.to)} (ประมาณ ${number(period.years, 1)} ปี)`
        : "ยังไม่มีข้อมูลภัยพิบัติในพื้นที่";
      const totals = Object.values(data.totals || {});
      // With the demo-data switch off (or nothing recorded yet) every section shows its empty state instead of zero charts.
      root.classList.toggle("dstat-no-data", !totals.some(row => row.count));
      const sum = field => totals.reduce((total, row) => total + Number(row[field] || 0), 0);
      const kpis = [
        ["เหตุทั้งหมด", `${number(sum("count"))} ครั้ง`, totals.map(row => `${row.label} ${number(row.count)}`).join(" · ")],
        ["ครัวเรือนได้รับผลกระทบ", number(sum("affected_households")), `${number(sum("affected_people"))} คน`],
        ["บ้านเสียหาย", `${number(sum("damaged_houses"))} หลัง`, `ถนนเสียหาย ${number(sum("roads_km"), 1)} กม.`],
        ["พื้นที่เกษตรเสียหาย", `${number(sum("farmland_rai"))} ไร่`, `พื้นที่ได้รับผลกระทบ ${number(sum("area_rai"))} ไร่`],
        ["มูลค่าความเสียหาย", compactBaht(sum("estimated_loss_baht")), `บาดเจ็บ ${number(sum("injuries"))} · เสียชีวิต ${number(sum("deaths"))} คน`]
      ];
      root.querySelector("[data-stats-kpis]").innerHTML = kpis.map(([label, value, note]) => `<article><p>${escapeHtml(label)}</p><strong>${escapeHtml(value)}</strong><small>${escapeHtml(note)}</small></article>`).join("");
      root.querySelector("[data-stats-legend]").innerHTML = hazards.map(hazard => `<li>${swatch(hazard.key)}<span>${escapeHtml(hazard.label)}</span><b>${number(data.totals?.[hazard.key]?.count)}</b></li>`).join("");
      renderYears(data.by_year || {}, period);
      renderSeason(data.by_month || {});
      renderImpact(data.totals || {});
      renderTop(data.top_subdistricts || []);
      renderRepeat(data.repeat_villages || []);
    }

    function renderYears(byYear, period) {
      const years = Object.keys(byYear);
      const chart = root.querySelector("[data-year-chart]");
      if (!years.length) { chart.innerHTML = `<p class="dstat-empty">ยังไม่มีข้อมูลภัยพิบัติ</p>`; return; }
      const totalOf = year => hazards.reduce((total, hazard) => total + (byYear[year][hazard.key] || 0), 0);
      const scale = axis(Math.max(...years.map(totalOf)));
      // The archive rarely starts on 1 Jan or ends on 31 Dec, so flag the partial first and last years.
      const firstYear = period.from ? new Date(period.from).getFullYear() + 543 : null;
      const lastYear = period.to ? new Date(period.to).getFullYear() + 543 : null;
      const partial = year => (Number(year) === firstYear && !String(period.from).endsWith("-01-01")) || (Number(year) === lastYear && !String(period.to).endsWith("-12-31"));
      chart.innerHTML = `<div class="dstat-grid" aria-hidden="true">${scale.ticks.map(tick => `<div style="bottom:${percent(tick, scale.max)}"><span>${number(tick)}</span></div>`).join("")}</div>
        <div class="dstat-columns">${years.map(year => {
          const total = totalOf(year);
          const rows = hazards.slice().reverse().map(hazard => [hazard.key, hazard.label, `${number(byYear[year][hazard.key] || 0)} ครั้ง`]);
          return `<div class="dstat-column" tabindex="0" aria-label="ปี ${year}: ${total} ครั้ง" data-tip="${escapeHtml(`<strong>ปี ${year}${partial(year) ? " (มีข้อมูลบางช่วง)" : ""}</strong>${tipRows(rows)}<div class="total"><span>รวม</span><b>${number(total)} ครั้ง</b></div>`)}">
            <span class="dstat-stack">
              <b class="dstat-total" style="bottom:${percent(total, scale.max)}">${number(total)}</b>
              ${hazards.filter(hazard => byYear[year][hazard.key]).map(hazard => `<i style="--hazard:${escapeHtml(hazard.color)};height:${percent(byYear[year][hazard.key], scale.max)}"></i>`).join("")}
            </span>
            <span class="dstat-axis-label">${escapeHtml(year)}${partial(year) ? "<small>บางช่วง</small>" : ""}</span>
          </div>`;
        }).join("")}</div>`;
      root.querySelector("[data-year-table]").innerHTML = `<table class="users-table"><thead><tr><th>ปี</th>${hazards.map(hazard => `<th class="numeric">${escapeHtml(hazard.label)}</th>`).join("")}<th class="numeric">รวม</th></tr></thead><tbody>${years.map(year => `<tr><td>${escapeHtml(year)}${partial(year) ? " (บางช่วง)" : ""}</td>${hazards.map(hazard => `<td class="numeric">${number(byYear[year][hazard.key] || 0)}</td>`).join("")}<td class="numeric"><b>${number(totalOf(year))}</b></td></tr>`).join("")}</tbody></table>`;
    }

    function renderSeason(byMonth) {
      const chart = root.querySelector("[data-season-chart]");
      const months = (byMonth[hazards[0].key] || []).map(row => row.month);
      const max = Math.max(0, ...hazards.flatMap(hazard => (byMonth[hazard.key] || []).map(row => row.per_year)));
      if (!max) { chart.innerHTML = `<p class="dstat-empty">ยังไม่มีข้อมูลภัยพิบัติ</p>`; return; }
      chart.innerHTML = hazards.map(hazard => {
        const rows = byMonth[hazard.key] || [];
        const peak = Math.max(...rows.map(row => row.per_year));
        return `<div class="dstat-season-row"><span class="dstat-season-label">${swatch(hazard.key)}${escapeHtml(hazard.label)}</span>${rows.map(row => `<span class="dstat-season-cell" tabindex="0" aria-label="${escapeHtml(hazard.label)} ${escapeHtml(row.month)} เฉลี่ย ${row.per_year} ครั้งต่อปี" data-tip="${escapeHtml(`<strong>${escapeHtml(hazard.label)} · ${escapeHtml(row.month)}</strong>${tipRows([[hazard.key, "เฉลี่ยต่อปี", `${number(row.per_year, 1)} ครั้ง`], [null, "รวมทุกปี", `${number(row.total)} ครั้ง`]])}`)}"><i style="--hazard:${escapeHtml(hazard.color)};--share:${(row.per_year / max).toFixed(4)}"></i>${row.per_year > 0 && row.per_year === peak ? `<b style="--share:${(row.per_year / max).toFixed(4)}">${number(row.per_year, 1)}</b>` : ""}</span>`).join("")}</div>`;
      }).join("") + `<div class="dstat-season-row dstat-season-months" aria-hidden="true"><span></span>${months.map(month => `<span>${escapeHtml(month)}</span>`).join("")}</div>`;
    }

    function renderImpact(totals) {
      const columns = [["count", "จำนวนเหตุ", 0], ["affected_households", "ครัวเรือน", 0], ["affected_people", "ประชาชน (คน)", 0], ["damaged_houses", "บ้านเสียหาย (หลัง)", 0], ["farmland_rai", "พื้นที่เกษตร (ไร่)", 0], ["roads_km", "ถนน (กม.)", 1], ["estimated_loss_baht", "มูลค่าความเสียหาย (บาท)", 0]];
      const rows = hazards.map(hazard => ({ key: hazard.key, ...totals[hazard.key] })).filter(row => row.count);
      const sum = field => rows.reduce((total, row) => total + Number(row[field] || 0), 0);
      root.querySelector("[data-impact-table]").innerHTML = rows.length ? `<table class="users-table dstat-impact"><thead><tr><th>ประเภทภัย</th>${columns.map(([, label]) => `<th class="numeric">${label}</th>`).join("")}</tr></thead><tbody>${rows.map(row => `<tr><td>${swatch(row.key)}${escapeHtml(hazardByKey[row.key].label)}</td>${columns.map(([field, , digits]) => `<td class="numeric">${number(row[field], digits)}</td>`).join("")}</tr>`).join("")}</tbody><tfoot><tr><td>รวม</td>${columns.map(([field, , digits]) => `<td class="numeric">${number(sum(field), digits)}</td>`).join("")}</tr></tfoot></table>` : `<p class="dstat-empty">ยังไม่มีข้อมูลภัยพิบัติ</p>`;
    }

    function renderTop(rows) {
      const list = root.querySelector("[data-top-subdistricts]");
      const max = Math.max(1, ...rows.map(row => row.count));
      list.innerHTML = rows.length ? rows.map(row => {
        const parts = hazards.filter(hazard => row.by_hazard?.[hazard.key]);
        const tip = `<strong>ต.${escapeHtml(row.name)}</strong>${tipRows(parts.slice().reverse().map(hazard => [hazard.key, hazard.label, `${row.by_hazard[hazard.key]} ครั้ง`]))}<div class="total"><span>ครัวเรือนได้รับผลกระทบ</span><b>${number(row.affected_households)}</b></div><div><span>มูลค่าความเสียหาย</span><b>${compactBaht(row.estimated_loss_baht)}</b></div>`;
        return `<li tabindex="0" data-tip="${escapeHtml(tip)}"><span>ต.${escapeHtml(row.name)}</span><span class="dstat-hbar" style="width:${percent(row.count, max)}">${parts.map(hazard => `<i style="--hazard:${escapeHtml(hazard.color)};flex-grow:${row.by_hazard[hazard.key]}"></i>`).join("")}</span><b>${number(row.count)} ครั้ง</b></li>`;
      }).join("") : `<li class="dstat-empty">ยังไม่มีข้อมูลภัยพิบัติ</li>`;
    }

    function renderRepeat(rows) {
      const list = root.querySelector("[data-repeat-villages]");
      const max = Math.max(1, ...rows.map(row => row.count));
      list.innerHTML = rows.length ? rows.map(row => `<li><span>${swatch(row.hazard)}${escapeHtml(row.label)}<small>${escapeHtml(hazardByKey[row.hazard]?.label)}</small></span><span class="dstat-hbar" style="width:${percent(row.count, max)}"><i style="--hazard:${escapeHtml(hazardByKey[row.hazard]?.color)}"></i></span><b>${number(row.count)} ครั้ง</b></li>`).join("") : `<li class="dstat-empty">ยังไม่พบหมู่บ้านที่เกิดซ้ำ</li>`;
    }

    // ---------- Outlook ----------
    const outlookBody = root.querySelector("[data-outlook-body]");
    const outlookForm = root.querySelector("[data-outlook-form]");
    let outlook = null;
    let selectedHazard = null;
    let outlookRequest = 0;

    function rainHtml(rain) {
      if (!rain || rain.error) return `<div class="dstat-rain unavailable"><span class="material-symbols-outlined">cloud_off</span><div><b>ไม่มีข้อมูลพยากรณ์ฝน</b><small>${escapeHtml(rain?.error || "")} · ใส่ปริมาณฝนเองเพื่อจำลองสถานการณ์</small></div></div>`;
      const days = (rain.days || []).map(day => `<span>${escapeHtml(String(day.date || "").replace(/\s\d{4}$/, ""))} <b>${number(day.rain_mm, 1)} มม.</b></span>`).join("");
      return `<div class="dstat-rain"><span class="material-symbols-outlined">rainy</span><div><small>ฝนสะสม 3 วันข้างหน้า</small><b>${number(rain.total_mm, 1)} มม.</b><small>${escapeHtml(rain.source || "")}${rain.location ? ` · ${escapeHtml(rain.location)}` : ""}</small>${days ? `<p class="dstat-rain-days">${days}</p>` : ""}</div></div>`;
    }

    function renderOutlook() {
      const data = outlook;
      const hazardRows = data.hazards || [];
      selectedHazard = hazardRows.some(row => row.hazard === selectedHazard) ? selectedHazard : hazardRows[0]?.hazard;
      if (!data.data_from) {
        outlookBody.innerHTML = `<div class="dstat-outlook-top">${rainHtml(data.rain_forecast)}<p class="dstat-empty">ยังไม่มีข้อมูลภัยพิบัติย้อนหลังในพื้นที่ จึงยังคาดการณ์จากสถิติไม่ได้</p></div>`;
        return;
      }
      const summary = data.summary?.length ? `<ul class="dstat-summary">${data.summary.map(line => `<li>${escapeHtml(line)}</li>`).join("")}</ul>` : `<p class="dstat-summary-empty">ช่วงเวลานี้ในอดีตแทบไม่เกิดภัยในพื้นที่</p>`;
      const risks = hazardRows.map(row => {
        const risk = RISKS[row.risk] || RISKS["ต่ำ"];
        const trigger = row.rain_trigger_mm ? `<small>ฝนก่อนเกิดเหตุในอดีต: เฝ้าระวัง ${number(row.rain_trigger_mm.watch_mm)} · ค่ากลาง ${number(row.rain_trigger_mm.median_mm)} มม.</small>` : "";
        return `<button type="button" role="tab" class="dstat-risk" data-outlook-hazard="${escapeHtml(row.hazard)}" aria-selected="${row.hazard === selectedHazard}">
          <span class="dstat-risk-name">${swatch(row.hazard)}${escapeHtml(row.label)}</span>
          <span class="dstat-risk-level ${risk.level}"><span class="material-symbols-outlined">${risk.icon}</span>เสี่ยง${escapeHtml(row.risk)}</span>
          <span class="dstat-risk-trend"><span class="material-symbols-outlined">${TRENDS[row.trend] || "remove"}</span>${escapeHtml(row.trend)}</span>
          <small>สัปดาห์นี้ในอดีต ${number(row.this_week_avg, 1)} ครั้ง · ปีที่แล้ว ${number(row.this_week_last_year)} ครั้ง</small>${trigger}
        </button>`;
      }).join("");
      outlookBody.innerHTML = `<div class="dstat-outlook-top">${rainHtml(data.rain_forecast)}<div><h3>สรุปสถานการณ์ ${escapeHtml(thaiDate(data.date))}</h3>${summary}</div></div>
        <div class="dstat-outlook-grid"><div class="dstat-risks" role="tablist" aria-label="ระดับความเสี่ยงแต่ละภัย">${risks}</div><div class="dstat-weekly" data-weekly role="tabpanel"></div></div>
        ${data.data_from ? `<p class="dstat-footnote">คำนวณจากข้อมูลภัยตั้งแต่ ${escapeHtml(thaiDate(data.data_from))} · ความเสี่ยงสูงขึ้นเมื่อฝนคาดการณ์ถึงระดับฝนก่อนเกิดน้ำท่วม/ดินถล่มในอดีต</p>` : ""}`;
      renderWeekly();
    }

    function renderWeekly() {
      const row = outlook.hazards.find(item => item.hazard === selectedHazard);
      const panel = outlookBody.querySelector("[data-weekly]");
      if (!row) { panel.innerHTML = ""; return; }
      const hazard = hazardByKey[row.hazard];
      const years = Math.max(...row.weeks.map(week => week.years));
      const scale = axis(Math.max(...row.weeks.flatMap(week => [week.average, week.last_year])), 3);
      const hotspots = row.hotspots?.length ? `<p class="dstat-hotspots"><b>หมู่บ้านที่เคยเกิด${escapeHtml(row.label)}ช่วงนี้:</b> ${row.hotspots.map(spot => `${escapeHtml(spot.label)} (${spot.count})`).join(", ")}</p>` : "";
      panel.innerHTML = `<div class="dstat-weekly-head"><h3>${escapeHtml(row.label)} รายสัปดาห์</h3><ul class="dstat-legend compact"><li>${swatch(row.hazard)}<span>เฉลี่ยในอดีต (${years} ปี)</span></li><li><i class="dstat-line-key"></i><span>ปีที่แล้ว</span></li></ul></div>
        <div class="dstat-week-chart">
          <div class="dstat-grid" aria-hidden="true">${scale.ticks.map(tick => `<div style="bottom:${percent(tick, scale.max)}"><span>${number(tick, 1)}</span></div>`).join("")}</div>
          <div class="dstat-columns">${row.weeks.map(week => {
            const tip = `<strong>${escapeHtml(week.label)}</strong><small>${escapeHtml(thaiDate(week.from))} – ${escapeHtml(thaiDate(week.to))}</small>${tipRows([[row.hazard, `เฉลี่ยในอดีต (${week.years} ปี)`, `${number(week.average, 2)} ครั้ง`], [null, "ปีที่แล้ว", `${number(week.last_year)} ครั้ง`]])}`;
            return `<div class="dstat-column${week.offset === 0 ? " current" : ""}" tabindex="0" aria-label="${escapeHtml(week.label)} เฉลี่ย ${week.average} ครั้ง ปีที่แล้ว ${week.last_year} ครั้ง" data-tip="${escapeHtml(tip)}">
              <span class="dstat-stack">
                ${week.average > 0 ? `<b class="dstat-total" style="bottom:${percent(week.average, scale.max)}">${number(week.average, 1)}</b><i style="--hazard:${escapeHtml(hazard.color)};height:${percent(week.average, scale.max)}"></i>` : ""}
                <em class="dstat-last-year" style="bottom:${percent(week.last_year, scale.max)}"></em>
              </span>
              <span class="dstat-axis-label">${week.offset === 0 ? "<small>สัปดาห์นี้</small>" : ""}${week.label.split(/\s?ของ\s/).map(escapeHtml).join("<br>")}</span>
            </div>`;
          }).join("")}</div>
        </div>${hotspots}`;
    }

    async function loadOutlook() {
      const params = new URLSearchParams();
      const form = new FormData(outlookForm);
      if (form.get("date")) params.set("date", form.get("date"));
      if (String(form.get("rain_3d_mm") || "").trim() !== "") params.set("rain_3d_mm", form.get("rain_3d_mm"));
      const request = ++outlookRequest;
      outlookBody.classList.add("refreshing");
      try {
        const data = await getJson(`/api/disaster_events/outlook?${params}`);
        if (request !== outlookRequest) return;
        outlook = data;
        renderOutlook();
      } catch (error) {
        if (request !== outlookRequest) return;
        outlookBody.innerHTML = `<p class="dstat-empty">คำนวณการคาดการณ์ไม่สำเร็จ: ${escapeHtml(error.message)}</p>`;
      } finally {
        if (request === outlookRequest) outlookBody.classList.remove("refreshing");
      }
    }

    outlookForm.addEventListener("submit", event => { event.preventDefault(); loadOutlook(); });
    outlookBody.addEventListener("click", event => {
      const button = event.target.closest("[data-outlook-hazard]");
      if (!button) return;
      selectedHazard = button.dataset.outlookHazard;
      outlookBody.querySelectorAll("[data-outlook-hazard]").forEach(item => item.setAttribute("aria-selected", String(item === button)));
      renderWeekly();
    });

    getJson("/api/disaster_events/statistics").then(renderStats).catch(error => {
      root.querySelector("[data-stats-period]").textContent = `โหลดสถิติไม่สำเร็จ: ${error.message}`;
    });
    loadOutlook();
  });
})();
