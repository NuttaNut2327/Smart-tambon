import fs from "node:fs/promises";
import path from "node:path";
import { spawn } from "node:child_process";

const projectRoot = path.resolve(import.meta.dirname, "..");
const outputDir = path.join(projectRoot, "docs", "screenshots", "system_flows");
const completeOutputDir = path.join(outputDir, "complete_flows");
const chromePath = "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe";
const debugPort = 9333;
const baseUrl = "http://localhost:3000";
const googleSansData = await fs.readFile(path.join(projectRoot, "tmp", "google-sans-400.ttf"), "base64");
const materialSymbolsData = await fs.readFile(path.join(projectRoot, "tmp", "material-symbols-400.ttf"), "base64");

const envText = await fs.readFile(path.join(projectRoot, ".env"), "utf8");
const env = Object.fromEntries(envText.split(/\r?\n/).filter((line) => line && !line.trimStart().startsWith("#") && line.includes("=")).map((line) => {
  const separator = line.indexOf("=");
  return [line.slice(0, separator).trim(), line.slice(separator + 1).trim().replace(/^['"]|['"]$/g, "")];
}));
const username = env.CAPTURE_USERNAME || "admin550513";
const password = env.CAPTURE_PASSWORD || env.SAMPLE_USER_PASSWORD;
if (!password) throw new Error("CAPTURE_PASSWORD or SAMPLE_USER_PASSWORD is required in .env");

await fs.mkdir(outputDir, { recursive: true });
await fs.mkdir(completeOutputDir, { recursive: true });
const profileDir = path.join(projectRoot, "tmp", "flow-capture-profile");
await fs.rm(profileDir, { recursive: true, force: true });

const chrome = spawn(chromePath, [
  "--headless=new",
  "--no-sandbox",
  "--enable-gpu",
  "--enable-webgl",
  "--ignore-gpu-blocklist",
  "--use-angle=swiftshader",
  "--hide-scrollbars",
  "--no-first-run",
  "--disable-extensions",
  `--remote-debugging-port=${debugPort}`,
  "--remote-allow-origins=*",
  `--user-data-dir=${profileDir}`,
  "--window-size=1600,1000",
  "about:blank"
], { stdio: ["ignore", "pipe", "pipe"] });
let chromeError = "";
chrome.stderr.on("data", (data) => { chromeError += data.toString(); });

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
let pageTarget;
for (let attempt = 0; attempt < 50; attempt += 1) {
  try {
    const targets = await fetch(`http://127.0.0.1:${debugPort}/json/list`).then((response) => response.json());
    pageTarget = targets.find((target) => target.type === "page");
    if (pageTarget) break;
  } catch (_) { /* Chrome is still starting. */ }
  await sleep(200);
}
if (!pageTarget) throw new Error("Unable to connect to screenshot browser");

const socket = new WebSocket(pageTarget.webSocketDebuggerUrl);
await new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error(`Timed out opening DevTools socket. ${chromeError}`)), 10_000);
  socket.addEventListener("open", () => { clearTimeout(timer); resolve(); }, { once: true });
  socket.addEventListener("error", (error) => { clearTimeout(timer); reject(error); }, { once: true });
  socket.addEventListener("close", () => { clearTimeout(timer); reject(new Error(`DevTools socket closed. ${chromeError}`)); }, { once: true });
});

let messageId = 0;
const pending = new Map();
const eventWaiters = new Map();
socket.addEventListener("message", ({ data }) => {
  const message = JSON.parse(data);
  if (message.id && pending.has(message.id)) {
    const { resolve, reject } = pending.get(message.id);
    pending.delete(message.id);
    if (message.error) reject(new Error(message.error.message)); else resolve(message.result);
    return;
  }
  const waiters = eventWaiters.get(message.method) || [];
  eventWaiters.delete(message.method);
  waiters.forEach((resolve) => resolve(message.params));
});
const command = (method, params = {}) => new Promise((resolve, reject) => {
  const id = ++messageId;
  pending.set(id, { resolve, reject });
  socket.send(JSON.stringify({ id, method, params }));
});
const waitForEvent = (method, timeout = 15_000) => new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error(`Timed out waiting for ${method}`)), timeout);
  const wrapped = (value) => { clearTimeout(timer); resolve(value); };
  eventWaiters.set(method, [...(eventWaiters.get(method) || []), wrapped]);
});
const evaluate = async (expression) => {
  const result = await command("Runtime.evaluate", { expression, awaitPromise: true, returnByValue: true });
  if (result.exceptionDetails) throw new Error(result.exceptionDetails.text || "Evaluation failed");
  return result.result?.value;
};
const waitForVisuals = async () => {
  await evaluate(`(async () => {
    await (document.fonts?.ready || Promise.resolve());
    await Promise.all([...document.images].map((image) => image.complete ? Promise.resolve() : new Promise((resolve) => {
      image.addEventListener("load", resolve, { once: true });
      image.addEventListener("error", resolve, { once: true });
      setTimeout(resolve, 12000);
    })));
    let previous = -1;
    let stable = 0;
    for (let attempt = 0; attempt < 30 && stable < 3; attempt += 1) {
      const current = performance.getEntriesByType("resource").length;
      stable = current === previous ? stable + 1 : 0;
      previous = current;
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  })()`);
  if (await evaluate(`Boolean(document.querySelector(".ol-viewport, .maplibregl-map, [data-map], #map"))`)) await sleep(3500);
};
const navigate = async (route) => {
  const loaded = waitForEvent("Page.loadEventFired").catch(() => null);
  await command("Page.navigate", { url: `${baseUrl}${route}` });
  await loaded;
  await evaluate(`new Promise(resolve => {
    const done = () => requestAnimationFrame(() => requestAnimationFrame(resolve));
    if (document.readyState === "complete") done(); else addEventListener("load", done, { once: true });
  })`);
  await waitForVisuals();
  await evaluate(`(() => {
    const style = document.createElement("style");
    style.textContent = "[data-city-incident-toast]{display:none!important} html{scroll-behavior:auto!important}";
    document.head.appendChild(style);
    window.scrollTo(0, 0);
  })()`);
};
const clickText = async (text) => evaluate(`(() => {
  const wanted = ${JSON.stringify(text)};
  const element = [...document.querySelectorAll("button,a,[role=tab]")].find((item) => item.textContent.replace(/\\s+/g," ").trim().includes(wanted) && !item.disabled && item.offsetParent !== null);
  if (!element) return false;
  element.click();
  return true;
})()`);
const capture = async (filename) => {
  await waitForVisuals();
  const { data } = await command("Page.captureScreenshot", { format: "png", captureBeyondViewport: false, fromSurface: true });
  await fs.writeFile(path.join(outputDir, filename), Buffer.from(data, "base64"));
  console.log(filename);
};
const capturePage = async (route, filename) => { await navigate(route); await capture(filename); };
const captureAfterClick = async (text, filename) => {
  if (!await clickText(text)) return false;
  await sleep(900);
  await evaluate("window.scrollTo(0, 0)");
  await capture(filename);
  return true;
};
const safeSlug = (value) => value.toLowerCase().replace(/^\/+|\/+$/g, "").replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 90) || "home";
const routeSignature = (urlString) => {
  const url = new URL(urlString, baseUrl);
  const normalizedPath = url.pathname
    .replace(/[0-9a-f]{20,}/gi, ":id")
    .replace(/\/[0-9]+(?=\/|$)/g, "/:id");
  const retained = [...url.searchParams.entries()]
    .filter(([key]) => ["view", "incident_id", "plan_id", "plan_version"].includes(key))
    .map(([key, value]) => `${key}=${key.endsWith("_id") ? ":id" : value}`)
    .sort()
    .join("&");
  return `${normalizedPath}${retained ? `?${retained}` : ""}`;
};
const completeManifest = [];
let completeSequence = 0;
const captureComplete = async (label, suffix = "") => {
  completeSequence += 1;
  const filename = `${String(completeSequence).padStart(3, "0")}_${safeSlug(label)}${suffix ? `_${safeSlug(suffix)}` : ""}.png`;
  await capture(path.join("complete_flows", filename));
  completeManifest.push({ step: completeSequence, filename, title: await evaluate(`document.querySelector("h1,h2")?.textContent?.trim() || document.title`), url: await evaluate("location.href") });
};
const discoverSafeLinks = () => evaluate(`(() => [...document.querySelectorAll("a[href]")].map((anchor) => ({
  href: anchor.href,
  text: anchor.textContent.replace(/\\s+/g, " ").trim(),
  method: anchor.dataset.turboMethod || anchor.getAttribute("data-method") || "get",
  download: anchor.hasAttribute("download")
})).filter((item) => {
  try {
    const url = new URL(item.href);
    return url.origin === location.origin && item.method.toLowerCase() === "get" && !item.download &&
      !url.pathname.match(/sign_out|download|audio|image|photo|attachment|export|destroy|delete/i) &&
      !url.pathname.startsWith("/rails/") && !url.pathname.startsWith("/assets/");
  } catch (_) { return false; }
}))()`);
const captureInteractiveStates = async (pageLabel) => {
  const dialogOpeners = await evaluate(`[...document.querySelectorAll("[data-open-incident-dialog], [data-open-rule-wizard], [data-open-plan-save]")].filter((el) => el.offsetParent !== null && !el.disabled).map((el, index) => ({ index, label: el.textContent.replace(/\\s+/g," ").trim() || el.getAttribute("aria-label") || "dialog" }))`);
  for (const opener of dialogOpeners.slice(0, 12)) {
    const opened = await evaluate(`(() => { const items=[...document.querySelectorAll("[data-open-incident-dialog], [data-open-rule-wizard], [data-open-plan-save]")].filter(el=>el.offsetParent!==null&&!el.disabled); items[${opener.index}]?.click(); return Boolean(items[${opener.index}]); })()`);
    if (!opened) continue;
    await sleep(700);
    await waitForVisuals();
    await captureComplete(pageLabel, opener.label);
    await evaluate(`(() => { const dialog=[...document.querySelectorAll("dialog")].find(item=>item.open); if(dialog) dialog.close(); document.querySelectorAll("[data-close-incident-dialog],[data-rule-wizard-close],[data-close-plan-save]").forEach(button=>{ if(button.offsetParent!==null) button.click(); }); })()`);
    await sleep(250);
  }
  const tabs = await evaluate(`[...document.querySelectorAll('[role="tab"], .incident-status-tags button, [data-version-tab], [data-method]')].filter((el)=>el.offsetParent!==null&&!el.disabled).map((el,index)=>({index,label:el.textContent.replace(/\\s+/g," ").trim()||"tab",active:el.classList.contains("active")||el.getAttribute("aria-selected")==="true"}))`);
  for (const tab of tabs.filter((item) => !item.active).slice(0, 10)) {
    const clicked = await evaluate(`(() => { const items=[...document.querySelectorAll('[role="tab"], .incident-status-tags button, [data-version-tab], [data-method]')].filter(el=>el.offsetParent!==null&&!el.disabled); items[${tab.index}]?.click(); return Boolean(items[${tab.index}]); })()`);
    if (!clicked) continue;
    await sleep(1000);
    await waitForVisuals();
    await captureComplete(pageLabel, tab.label);
  }
  const closedDetails = await evaluate(`[...document.querySelectorAll("details:not([open])")].filter(el=>el.offsetParent!==null).map((el,index)=>({index,label:el.querySelector("summary")?.textContent.replace(/\\s+/g," ").trim()||"details"}))`);
  for (const detail of closedDetails.slice(0, 4)) {
    await evaluate(`[...document.querySelectorAll("details:not([open])")].filter(el=>el.offsetParent!==null)[0]?.setAttribute("open","")`);
    await sleep(400);
    await captureComplete(pageLabel, detail.label);
  }
};
const captureAllReachableFlows = async () => {
  const queue = ["/", "/situation_assessment", "/general_incidents", "/disasters", "/disaster_statistics"];
  const queued = new Set(queue.map((route) => routeSignature(route)));
  const visited = new Set();
  while (queue.length && visited.size < 120) {
    const route = queue.shift();
    const signature = routeSignature(route);
    if (visited.has(signature)) continue;
    visited.add(signature);
    await navigate(route.startsWith("http") ? new URL(route).pathname + new URL(route).search : route);
    const pageLabel = signature.replace(/:id/g, "detail");
    await captureComplete(pageLabel);
    await captureInteractiveStates(pageLabel);
    const links = await discoverSafeLinks();
    for (const link of links) {
      const signatureOfLink = routeSignature(link.href);
      if (!visited.has(signatureOfLink) && !queued.has(signatureOfLink)) {
        queued.add(signatureOfLink);
        queue.push(link.href);
      }
    }
  }
  const lines = ["# Complete system flow screenshots", "", `Captured with ${username}.`, "", ...completeManifest.map((item) => `${item.step}. \`${item.filename}\` — ${item.title} — ${item.url}`), ""];
  await fs.writeFile(path.join(completeOutputDir, "README.md"), lines.join("\n"), "utf8");
};

try {
  await command("Page.enable");
  await command("Runtime.enable");
  await command("Page.addScriptToEvaluateOnNewDocument", { source: `(() => {
    const install = () => {
      if (!document.head || document.getElementById("capture-fonts")) return false;
      const style = document.createElement("style");
      style.id = "capture-fonts";
      style.textContent = \`@font-face{font-family:'Google Sans';font-style:normal;font-weight:100 900;font-display:block;src:url(data:font/ttf;base64,${googleSansData}) format('truetype')}@font-face{font-family:'Material Symbols Outlined';font-style:normal;font-weight:100 700;font-display:block;src:url(data:font/ttf;base64,${materialSymbolsData}) format('truetype')}\`;
      document.head.appendChild(style);
      return true;
    };
    if (!install()) addEventListener("DOMContentLoaded", install, { once: true });
  })();` });
  await command("Emulation.setDeviceMetricsOverride", { width: 1600, height: 1000, deviceScaleFactor: 1, mobile: false });

  await capturePage("/users/sign_in", "00_login_01_sign_in.png");
  await evaluate(`(() => {
    const username = document.querySelector('input[name="user[username]"]');
    const password = document.querySelector('input[name="user[password]"]');
    if (!username || !password) throw new Error("Login form not found");
    username.value = ${JSON.stringify(username)};
    password.value = ${JSON.stringify(password)};
    username.dispatchEvent(new Event("input", { bubbles: true }));
    password.dispatchEvent(new Event("input", { bubbles: true }));
    document.querySelector("form").requestSubmit();
  })()`);
  await waitForEvent("Page.loadEventFired").catch(() => null);
  await sleep(1200);
  const loginState = await evaluate(`({
    url: location.pathname,
    hasPasswordField: Boolean(document.querySelector('input[name="user[password]"]')),
    hasUsername: document.body.innerText.includes(${JSON.stringify(username)})
  })`);
  if (loginState.url.includes("sign_in") || loginState.hasPasswordField || !loginState.hasUsername) {
    throw new Error(`Unable to sign in as ${username}`);
  }

  if (process.env.COMPLETE_ONLY !== "1") {
  await capturePage("/", "01_overview_01_city_overview.png");

  await capturePage("/situation_assessment", "02_city_map_01_map.png");
  await captureAfterClick("วิเคราะห์พื้นที่", "02_city_map_02_area_analysis.png");
  await captureAfterClick("จำลองสถานการณ์", "02_city_map_03_simulation.png");

  await capturePage("/general_incidents", "03_incidents_01_incident_list.png");
  await captureAfterClick("บันทึกเหตุการณ์ใหม่", "03_incidents_02_new_incident_form.png");

  await capturePage("/disasters", "04_disasters_01_disaster_list.png");
  await captureAfterClick("แผนรับมือในอนาคต", "04_disasters_02_contingency_plans.png");
  await captureAfterClick("สร้างแผนรับมือ", "04_disasters_03_new_contingency_plan.png");

  await capturePage("/disaster_statistics", "05_statistics_01_disaster_statistics.png");

  await capturePage("/resource_rules", "06_resource_rules_01_rule_list.png");
  await captureAfterClick("สร้างกฎ", "06_resource_rules_02_new_rule.png") || await captureAfterClick("เพิ่มกฎ", "06_resource_rules_02_new_rule.png");

  await capturePage("/activities", "07_activities_01_activity_list.png");
  await captureAfterClick("เพิ่มกิจกรรม", "07_activities_02_new_activity.png");

  await capturePage("/broadcasts", "08_broadcasts_01_broadcast_list.png");
  await captureAfterClick("เพิ่มรายการข่าว", "08_broadcasts_02_new_broadcast.png") || await captureAfterClick("สร้างข่าว", "08_broadcasts_02_new_broadcast.png");

  await capturePage("/cctv_cameras", "09_cctv_01_camera_list.png");
  await captureAfterClick("เพิ่มกล้อง", "09_cctv_02_new_camera.png");

  await capturePage("/projects", "10_projects_01_project_list.png");
  await captureAfterClick("เพิ่มโครงการ", "10_projects_02_new_project.png");

  await capturePage("/data_layers", "11_data_import_01_dataset_categories.png");
  await captureAfterClick("หน่วยงาน", "11_data_import_02_agency_dataset.png");
  await captureAfterClick("นำเข้าจากไฟล์", "11_data_import_03_file_import.png") || await captureAfterClick("นำเข้าไฟล์ใหม่", "11_data_import_03_file_import.png") || await captureAfterClick("นำเข้าไฟล์", "11_data_import_03_file_import.png");

  await capturePage("/ai", "12_ai_01_assistant.png");

  await capturePage("/users", "13_users_01_user_list.png");
  await captureAfterClick("เพิ่มผู้ใช้", "13_users_02_new_user.png");

  await capturePage("/settings", "14_settings_01_settings_home.png");
  await capturePage("/system_settings", "14_settings_02_system_settings.png");
  await capturePage("/organization_settings", "14_settings_03_organization_settings.png");
  await capturePage("/notification_channels", "14_settings_04_notification_channels.png");
  await capturePage("/notification_templates", "14_settings_05_notification_templates.png");
  await capturePage("/notification_tests", "14_settings_06_notification_test.png");
  }
  await captureAllReachableFlows();
} finally {
  socket.close();
  chrome.kill();
}

