// Live CCTV playback shared by the map popup, the camera list and the camera form.
// window.SmartTambonCctv.mount(container, camera) returns a function that stops the stream.
(() => {
  const escapeHtml = value => String(value ?? "").replace(/[&<>'"]/g, char => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;" })[char]);
  const isHttpUrl = value => /^https?:\/\//i.test(value || "");

  function detectType(url) {
    let path = "";
    try { path = new URL(url).pathname.toLowerCase(); } catch { return "hls"; }
    if (path.endsWith(".m3u8")) return "hls";
    if (/\.(mp4|webm|ogv|ogg)$/.test(path)) return "video";
    if (/\.(mjpg|mjpeg)$/.test(path) || /(mjpe?g|video\.cgi|faststream|nphmotionjpeg)/.test(path)) return "mjpeg";
    return "hls";
  }

  function mount(container, camera) {
    container.innerHTML = "";
    container.classList.add("cctv-stage");
    const status = document.createElement("div");
    status.className = "cctv-stage-status";
    const setStatus = (text, tone = "") => {
      status.className = `cctv-stage-status ${tone}`;
      status.innerHTML = text;
      status.hidden = !text;
    };
    const live = document.createElement("span");
    live.className = "cctv-live-badge";
    live.textContent = "LIVE";
    live.hidden = true;
    const showPlaying = () => { setStatus(""); live.hidden = false; };
    const showError = message => {
      live.hidden = true;
      setStatus(`<span class="material-symbols-outlined">signal_disconnected</span><b>${escapeHtml(message)}</b><button type="button" data-cctv-retry>ลองเชื่อมต่ออีกครั้ง</button>`, "error");
      status.querySelector("[data-cctv-retry]")?.addEventListener("click", () => { stop(); stop = mount(container, camera); });
    };

    let cleanup = () => {};
    let stop = () => { cleanup(); container.innerHTML = ""; };
    const url = camera.stream_url;
    if (!isHttpUrl(url)) {
      container.append(status);
      showError("URL สตรีมไม่ถูกต้อง");
      return () => stop();
    }
    if (camera.status === "inactive") {
      container.append(status);
      setStatus('<span class="material-symbols-outlined">videocam_off</span><b>กล้องปิดใช้งาน</b>');
      return () => stop();
    }
    setStatus('<span class="cctv-spinner"></span><b>กำลังเชื่อมต่อสตรีม…</b>');

    const type = camera.stream_type || detectType(url);
    if (type === "mjpeg") {
      const image = document.createElement("img");
      image.alt = camera.name || "CCTV";
      image.referrerPolicy = "no-referrer";
      image.addEventListener("load", showPlaying, { once: true });
      image.addEventListener("error", () => showError("ไม่สามารถเชื่อมต่อสตรีม MJPEG ได้"));
      image.src = url;
      cleanup = () => { image.removeAttribute("src"); };
      container.append(image, status, live);
    } else if (type === "embed") {
      const frame = document.createElement("iframe");
      frame.src = url;
      frame.title = camera.name || "CCTV";
      frame.allow = "autoplay; fullscreen; picture-in-picture";
      frame.referrerPolicy = "no-referrer";
      frame.setAttribute("sandbox", "allow-scripts allow-same-origin allow-presentation");
      frame.addEventListener("load", showPlaying, { once: true });
      cleanup = () => { frame.src = "about:blank"; };
      container.append(frame, status, live);
    } else {
      const video = document.createElement("video");
      Object.assign(video, { muted: true, autoplay: true, playsInline: true, controls: true });
      video.setAttribute("muted", "");
      video.addEventListener("playing", showPlaying);
      video.addEventListener("waiting", () => setStatus('<span class="cctv-spinner"></span><b>กำลังบัฟเฟอร์…</b>'));
      let hls = null;
      // Prefer hls.js wherever MediaSource exists; some browsers claim native HLS support but fail on real streams.
      if (type === "hls" && window.Hls?.isSupported()) {
        hls = new window.Hls({ lowLatencyMode: true, liveDurationInfinity: true, backBufferLength: 30 });
        hls.on(window.Hls.Events.ERROR, (_event, data) => {
          if (!data.fatal) return;
          if (data.type === window.Hls.ErrorTypes.MEDIA_ERROR) { hls.recoverMediaError(); return; }
          showError(data.type === window.Hls.ErrorTypes.NETWORK_ERROR ? "ไม่สามารถเชื่อมต่อสตรีมได้ (ตรวจสอบ URL หรือ CORS)" : "ไม่สามารถเล่นสตรีมนี้ได้");
        });
        hls.loadSource(url);
        hls.attachMedia(video);
      } else if (type === "hls" && !video.canPlayType("application/vnd.apple.mpegurl")) {
        container.append(status);
        showError("เบราว์เซอร์นี้ไม่รองรับ HLS");
        return () => stop();
      } else {
        video.src = url;
        video.addEventListener("error", () => showError("ไม่สามารถเล่นสตรีมนี้ได้"));
      }
      video.play?.().catch(() => {});
      cleanup = () => { hls?.destroy(); video.pause(); video.removeAttribute("src"); video.load(); };
      container.append(video, status, live);
    }
    return () => stop();
  }

  let viewer, stopViewer;
  function ensureViewer() {
    if (viewer) return viewer;
    viewer = document.createElement("dialog");
    viewer.className = "cctv-viewer";
    viewer.innerHTML = `
      <header><div><p data-cctv-viewer-meta></p><h2 data-cctv-viewer-title></h2></div>
        <div class="cctv-viewer-tools">
          <button type="button" data-cctv-fullscreen title="เต็มหน้าจอ"><span class="material-symbols-outlined">fullscreen</span>เต็มหน้าจอ</button>
          <a data-cctv-open-source target="_blank" rel="noopener noreferrer" title="เปิดสตรีมในแท็บใหม่"><span class="material-symbols-outlined">open_in_new</span></a>
          <button type="button" data-cctv-close aria-label="ปิด"><span class="material-symbols-outlined">close</span></button>
        </div></header>
      <div class="cctv-viewer-stage" data-cctv-viewer-stage></div>
      <footer data-cctv-viewer-footer></footer>`;
    document.body.append(viewer);
    const close = () => viewer.close();
    viewer.querySelector("[data-cctv-close]").addEventListener("click", close);
    viewer.addEventListener("click", event => { if (event.target === viewer) close(); });
    viewer.addEventListener("close", () => { stopViewer?.(); stopViewer = null; if (document.fullscreenElement) document.exitFullscreen?.(); });
    viewer.querySelector("[data-cctv-fullscreen]").addEventListener("click", () => {
      const stage = viewer.querySelector("[data-cctv-viewer-stage]");
      if (document.fullscreenElement) document.exitFullscreen?.();
      else (stage.requestFullscreen || stage.webkitRequestFullscreen)?.call(stage);
    });
    return viewer;
  }

  function openViewer(camera) {
    const dialog = ensureViewer();
    stopViewer?.();
    dialog.querySelector("[data-cctv-viewer-title]").textContent = camera.name || "กล้องวงจรปิด";
    dialog.querySelector("[data-cctv-viewer-meta]").textContent = [camera.code, camera.status_label, camera.stream_type_label].filter(Boolean).join(" · ");
    const place = [camera.location_name, camera.subdistrict_name && `ต.${camera.subdistrict_name}`, camera.district_name && `อ.${camera.district_name}`].filter(Boolean).join(" ");
    dialog.querySelector("[data-cctv-viewer-footer]").textContent = [place, camera.description].filter(Boolean).join(" — ");
    const source = dialog.querySelector("[data-cctv-open-source]");
    source.hidden = !isHttpUrl(camera.stream_url);
    if (isHttpUrl(camera.stream_url)) source.href = camera.stream_url;
    if (!dialog.open) dialog.showModal();
    stopViewer = mount(dialog.querySelector("[data-cctv-viewer-stage]"), camera);
  }

  const markerColors = { active: "#2f6fb0", maintenance: "#c98a1b", inactive: "#8a8f98" };
  const markerStyles = {};
  function markerStyle(status) {
    if (!window.ol) return undefined;
    const color = markerColors[status] || markerColors.active;
    markerStyles[color] ||= new ol.style.Style({
      image: new ol.style.Icon({
        anchor: [0.5, 1],
        src: "data:image/svg+xml;charset=utf-8," + encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="34" height="42" viewBox="0 0 34 42"><path d="M17 41s15-14.2 15-24A15 15 0 0 0 2 17c0 9.8 15 24 15 24z" fill="${color}" stroke="#fff" stroke-width="2"/><rect x="8" y="12" width="13" height="10" rx="2" fill="#fff"/><path d="M21 15.5l5-3v9l-5-3z" fill="#fff"/></svg>`)
      })
    });
    return markerStyles[color];
  }

  window.SmartTambonCctv = { mount, openViewer, detectType, markerStyle, escapeHtml };
})();
