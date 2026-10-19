// Broadcast page: poll the worker's progress, show script length, and draw/upload the square news card image.
document.addEventListener("DOMContentLoaded", () => {
  const page = document.querySelector("[data-broadcast]");
  if (!page) return;

  // Reload once queued work (generate / synthesize / publish) has finished.
  if (page.dataset.busy === "true") {
    const label = page.querySelector("[data-broadcast-status]");
    const poll = async () => {
      try {
        const response = await fetch(page.dataset.statusUrl, { headers: { Accept: "application/json" } });
        const state = await response.json();
        if (label) label.textContent = state.status_label;
        if (!state.busy) { window.location.reload(); return; }
      } catch (_error) { /* keep polling */ }
      setTimeout(poll, 3000);
    };
    setTimeout(poll, 3000);
  }

  // Thai is read at roughly 12 characters per second over a PA system.
  const script = page.querySelector("[data-broadcast-script]");
  const stats = page.querySelector("[data-script-stats]");
  const updateStats = () => {
    if (!script || !stats) return;
    const length = script.value.replace(/\s+/g, "").length;
    const seconds = Math.round(length / 12);
    stats.textContent = length ? `${length.toLocaleString()} ตัวอักษร · อ่านประมาณ ${Math.floor(seconds / 60)} นาที ${seconds % 60} วินาที` : "";
  };
  script?.addEventListener("input", updateStats);
  updateStats();

  const canvas = page.querySelector("[data-news-card]");
  if (!canvas) return;
  const segmenter = window.Intl?.Segmenter ? new Intl.Segmenter("th", { granularity: "word" }) : null;
  const words = text => segmenter ? [...segmenter.segment(text)].map(part => part.segment) : text.split(/(\s+)/);
  const wrap = (ctx, text, maxWidth) => {
    const lines = [];
    let line = "";
    words(text).forEach(word => {
      const next = line + word;
      if (ctx.measureText(next).width > maxWidth && line.trim()) { lines.push(line.trim()); line = word.trimStart(); } else { line = next; }
    });
    if (line.trim()) lines.push(line.trim());
    return lines;
  };

  const draw = () => {
    const ctx = canvas.getContext("2d");
    const width = canvas.width, height = canvas.height, pad = 80;
    const title = page.querySelector('[name="broadcast[title]"]')?.value.trim() || "ข่าวประชาสัมพันธ์";
    const bullets = (page.querySelector("[data-broadcast-bullets]")?.value || "").split("\n").map(line => line.trim()).filter(Boolean);
    const font = '"Google Sans", "Noto Sans Thai", "Sarabun", sans-serif';
    const gradient = ctx.createLinearGradient(0, 0, width, height);
    gradient.addColorStop(0, "#2c3930");
    gradient.addColorStop(1, "#3f6b52");
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, width, height);
    ctx.fillStyle = "rgba(255,255,255,.08)";
    ctx.beginPath(); ctx.arc(width - 60, 120, 260, 0, Math.PI * 2); ctx.fill();

    ctx.fillStyle = "#f2c94c";
    ctx.font = `700 34px ${font}`;
    ctx.fillText("ข่าวประชาสัมพันธ์", pad, pad + 20);
    ctx.fillStyle = "rgba(255,255,255,.75)";
    ctx.font = `500 30px ${font}`;
    ctx.fillText(`${canvas.dataset.org} · ${canvas.dataset.date}`, pad, pad + 70);

    ctx.fillStyle = "#ffffff";
    ctx.font = `700 64px ${font}`;
    let y = pad + 190;
    wrap(ctx, title, width - pad * 2).slice(0, 3).forEach(line => { ctx.fillText(line, pad, y); y += 82; });

    y += 20;
    ctx.font = `500 38px ${font}`;
    const bottomLimit = height - pad - 90;
    for (const bullet of bullets.slice(0, 6)) {
      const lines = wrap(ctx, bullet, width - pad * 2 - 50);
      if (y + lines.length * 52 > bottomLimit) break;
      ctx.fillStyle = "#f2c94c";
      ctx.beginPath(); ctx.arc(pad + 12, y - 13, 9, 0, Math.PI * 2); ctx.fill();
      ctx.fillStyle = "#ffffff";
      lines.forEach(line => { ctx.fillText(line, pad + 50, y); y += 52; });
      y += 18;
    }

    ctx.fillStyle = "rgba(255,255,255,.6)";
    ctx.font = `500 26px ${font}`;
    ctx.fillText(canvas.dataset.system || "", pad, height - pad);
  };
  // Draw once fonts are ready so Thai glyphs and measurements are correct.
  (document.fonts?.ready || Promise.resolve()).then(draw);
  page.querySelectorAll('[name="broadcast[title]"], [data-broadcast-bullets]').forEach(input => input.addEventListener("input", draw));

  const save = page.querySelector("[data-news-card-save]");
  const saveStatus = page.querySelector("[data-news-card-status]");
  save?.addEventListener("click", () => {
    draw();
    save.disabled = true;
    if (saveStatus) saveStatus.textContent = "กำลังบันทึกภาพ…";
    canvas.toBlob(async blob => {
      try {
        const body = new FormData();
        body.append("image", blob, "news-card.png");
        body.append("authenticity_token", document.querySelector('meta[name="csrf-token"]').content);
        const response = await fetch(save.dataset.url, { method: "POST", body, headers: { Accept: "application/json" } });
        const result = await response.json();
        if (!response.ok) throw new Error(result.error || `HTTP ${response.status}`);
        if (saveStatus) saveStatus.textContent = "บันทึกภาพข่าวแล้ว";
      } catch (error) {
        if (saveStatus) saveStatus.textContent = `บันทึกไม่สำเร็จ: ${error.message}`;
      } finally {
        save.disabled = false;
      }
    }, "image/png");
  });
});
