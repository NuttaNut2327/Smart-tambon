document.addEventListener("DOMContentLoaded", () => {
  const rulesList = document.querySelector("[data-rules-list]");
  if (rulesList) {
    const search = document.querySelector("[data-rule-search]");
    const filters = [...document.querySelectorAll("[data-rule-filter]")];
    const count = document.querySelector("[data-rule-count]");
    let activeType = "all";
    const applyRuleFilters = () => {
      const query = search.value.trim().toLowerCase();
      let visible = 0;
      rulesList.querySelectorAll("[data-rule-card]").forEach(card => {
        card.hidden = (activeType !== "all" && card.dataset.ruleType !== activeType) || !card.dataset.ruleSearch.includes(query);
        if (!card.hidden) visible += 1;
      });
      count.textContent = `แสดง ${visible} กฎ`;
    };
    search.addEventListener("input", applyRuleFilters);
    filters.forEach(button => button.addEventListener("click", () => {
      filters.forEach(item => item.classList.toggle("active", item === button));
      activeType = button.dataset.ruleFilter;
      applyRuleFilters();
    }));
  }
});

document.addEventListener("DOMContentLoaded", () => {
  if (!document.querySelector("#map") || !window.ol) return;
  const key = document.querySelector(".shell").dataset.maptilerKey;
  const street = new ol.layer.Tile({ source: new ol.source.OSM() });
  const satellite = new ol.layer.Tile({ visible: false, source: new ol.source.XYZ({
    url: key ? `https://api.maptiler.com/tiles/satellite/{z}/{x}/{y}.jpg?key=${key}` : "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
    attributions: key ? "© MapTiler © OpenStreetMap contributors" : "© OpenStreetMap contributors",
    maxZoom: key ? 19 : 18,
    wrapX: false
  })});
  const highlight = new ol.layer.Vector({ source: new ol.source.Vector(), style: new ol.style.Style({
    stroke: new ol.style.Stroke({color:"#5ac5a9",width:5}), fill:new ol.style.Fill({color:"rgba(0,0,0,0)"}),
    image:new ol.style.Circle({radius:8,fill:new ol.style.Fill({color:"#00a98f"}),stroke:new ol.style.Stroke({color:"white",width:3})})
  })});
  const siblingBoundaryStyle=new ol.style.Style({
      stroke:new ol.style.Stroke({color:"rgba(13,27,42,.9)",width:1.5}),
      fill:new ol.style.Fill({color:"rgba(13,27,42,.25)"})
    });
  const districtSubdistrictStyle=new ol.style.Style({stroke:new ol.style.Stroke({color:"rgba(13,27,42,.88)",width:1.25}),fill:new ol.style.Fill({color:"rgba(0,0,0,0)"})});
  const siblingBoundaries = new ol.layer.Vector({
    source:new ol.source.Vector(),
    style:feature=>feature.get("districtOnly") ? districtSubdistrictStyle : siblingBoundaryStyle
  });
  const districtBoundaryStyle=new ol.style.Style({stroke:new ol.style.Stroke({color:"rgba(13,27,42,.9)",width:2}),fill:new ol.style.Fill({color:"rgba(0,0,0,0)"})});
  const dimmedDistrictStyle=new ol.style.Style({stroke:new ol.style.Stroke({color:"rgba(13,27,42,.9)",width:1.5}),fill:new ol.style.Fill({color:"rgba(13,27,42,.22)"})});
  const districtBoundaries = new ol.layer.Vector({
    source:new ol.source.Vector(),
    style:feature=>selectedFeatureData?.properties?.level==="district" && String(feature.getId())!==String(selectedDistrictCode) ? dimmedDistrictStyle : districtBoundaryStyle
  });
  const overviewBoundaryStyle=new ol.style.Style({stroke:new ol.style.Stroke({color:"rgba(90,197,169,.8)",width:1.2}),fill:new ol.style.Fill({color:"rgba(90,197,169,.05)"})});
  const selectedProvinceOverviewStyle=new ol.style.Style({stroke:new ol.style.Stroke({color:"rgba(90,197,169,.8)",width:1.2}),fill:new ol.style.Fill({color:"rgba(0,0,0,0)"})});
  const dimmedProvinceStyle=new ol.style.Style({stroke:new ol.style.Stroke({color:"rgba(13,27,42,.78)",width:1.1}),fill:new ol.style.Fill({color:"rgba(13,27,42,.26)"})});
  const overviewBoundaries = new ol.layer.Vector({
    source:new ol.source.Vector(),
    style:feature=>{
      if(String(feature.getId())===String(selectedProvinceId)) return selectedProvinceOverviewStyle;
      return selectedFeatureData?.properties?.level==="province" ? dimmedProvinceStyle : overviewBoundaryStyle;
    }
  });
  // This only represents the temporary, user-drawn selection tool.  It is
  // intentionally separate from the selected province/district/subdistrict.
  let areaSelectionFilterGeometry=null;
  const placeConfig = {
    government:{color:"#2563eb",glyph:"building",icon:"account_balance"}, education:{color:"#f59e0b",glyph:"ส",icon:"school"}, health:{color:"#e11d48",glyph:"+",icon:"heart_plus"}, culture:{color:"#8b5cf6",glyph:"♜",icon:"folded_hands"}, tourism:{color:"#f97316",glyph:"★",icon:"star"}, transport:{color:"#0ea5a4",glyph:"↔",icon:"directions_car"}, service:{color:"#ec4899",glyph:"●",icon:"local_mall"}, emergency:{color:"#dc2626",glyph:"!",icon:"emergency_home"}
  };
  const placeCategoryTags={government:["government","municipality"],education:["school","university","library"],health:["hospital","clinic","pharmacy"],culture:["temple","mosque","church","museum"],tourism:["tourist attraction","hotel","park","viewpoint"],transport:["bus station","train station","pier","parking"],service:["restaurant","cafe","shopping","convenience"],emergency:["police","fire_station","rescue"]};
  const placeMarkerIcon = (color, glyph) => {
    const symbol = glyph === "building"
      ? '<path d="M13 27V14h16v13h-4v-5h-3v5h-3v-5h-3v5zm3-10h2v2h-2zm4 0h2v2h-2zm4 0h2v2h-2z" fill="#fff"/>'
      : `<text x="21" y="25" fill="#fff" font-family="Arial,sans-serif" font-size="15" font-weight="700" text-anchor="middle">${glyph}</text>`;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="36" height="44" viewBox="0 0 42 52"><path d="M21 1C10 1 2 9.5 2 20c0 14.2 19 30.4 19 30.4S40 34.2 40 20C40 9.5 32 1 21 1z" fill="${color}" stroke="#fff" stroke-width="3"/>${symbol}</svg>`;
    return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
  };
  const isPlaceInsideManualSelection = feature => !areaSelectionFilterGeometry || areaSelectionFilterGeometry.intersectsCoordinate(feature.getGeometry().getCoordinates());
  const placeMarkerStyle = config => {
    const selectedStyle=new ol.style.Style({image:new ol.style.Icon({src:placeMarkerIcon(config.color,""),anchor:[0.5,1],anchorXUnits:"fraction",anchorYUnits:"fraction"}),text:new ol.style.Text({text:config.icon,font:'20px "Material Symbols Outlined"',fill:new ol.style.Fill({color:"#fff"}),offsetY:-25})});
    const mutedStyle=new ol.style.Style({image:new ol.style.Icon({src:placeMarkerIcon("#94a3b8",""),anchor:[0.5,1],anchorXUnits:"fraction",anchorYUnits:"fraction"}),text:new ol.style.Text({text:config.icon,font:'20px "Material Symbols Outlined"',fill:new ol.style.Fill({color:"#fff"}),offsetY:-25})});
    return feature=>isPlaceInsideManualSelection(feature) ? selectedStyle : mutedStyle;
  };
  const placeLayers = {};
  Object.entries(placeConfig).forEach(([category, config]) => {
    placeLayers[category] = new ol.layer.Vector({
      source:new ol.source.Vector(),
      style:placeMarkerStyle(config)
    });
  });
  const importedSelectedStyle=new ol.style.Style({image:new ol.style.Icon({src:placeMarkerIcon("#5ac5a9","+"),anchor:[0.5,1],anchorXUnits:"fraction",anchorYUnits:"fraction"})});
  const importedMutedStyle=new ol.style.Style({image:new ol.style.Icon({src:placeMarkerIcon("#94a3b8","+"),anchor:[0.5,1],anchorXUnits:"fraction",anchorYUnits:"fraction"})});
  const importedPlacesLayer = new ol.layer.Vector({
    source:new ol.source.Vector(),
    style:feature=>isPlaceInsideManualSelection(feature) ? importedSelectedStyle : importedMutedStyle
  });
  const importedDatasetLayer = new ol.layer.Vector({
    source:new ol.source.Vector(),
    style:new ol.style.Style({
      image:new ol.style.Circle({radius:8,fill:new ol.style.Fill({color:"#7c3aed"}),stroke:new ol.style.Stroke({color:"#fff",width:2})})
    })
  });
  const waterStationLayer = new ol.layer.Vector({
    source:new ol.source.Vector(),
    style:new ol.style.Style({
      image:new ol.style.Circle({radius:7,fill:new ol.style.Fill({color:"#1677c8"}),stroke:new ol.style.Stroke({color:"#fff",width:2})})
    })
  });
  const areaSelectionLayer = new ol.layer.Vector({
    source:new ol.source.Vector(),
    style:new ol.style.Style({
      stroke:new ol.style.Stroke({color:"#0b6b57",width:3,lineDash:[8,5]}),
      fill:new ol.style.Fill({color:"rgba(90,197,169,.16)"}),
      image:new ol.style.Circle({radius:7,fill:new ol.style.Fill({color:"#0b6b57"}),stroke:new ol.style.Stroke({color:"white",width:2})})
    })
  });
  const areaSelectionDimLayer = new ol.layer.Vector({
    source:new ol.source.Vector(),
    style:new ol.style.Style({fill:new ol.style.Fill({color:"rgba(9,35,59,.48)"})})
  });
  const areaSelectionEndpointsLayer = new ol.layer.Vector({
    source:new ol.source.Vector(),
    style:new ol.style.Style({image:new ol.style.Circle({radius:7,fill:new ol.style.Fill({color:"#237d69"}),stroke:new ol.style.Stroke({color:"white",width:3})})})
  });
  const map = new ol.Map({ target:"map", layers:[street,satellite,overviewBoundaries,districtBoundaries,siblingBoundaries,highlight,...Object.values(placeLayers),importedPlacesLayer,importedDatasetLayer,waterStationLayer,areaSelectionDimLayer,areaSelectionLayer,areaSelectionEndpointsLayer], view:new ol.View({center:ol.proj.fromLonLat([100.5018,13.7563]),zoom:6,minZoom:5,maxZoom:19,extent:ol.proj.get("EPSG:3857").getExtent()}) });
  window.smartCityMap=map;
  fetch("/api/imported_datasets",{headers:{Accept:"application/json"}}).then(response=>response.ok?response.json():null).then(data=>{
    if(!data)return;
    importedDatasetLayer.getSource().addFeatures(new ol.format.GeoJSON().readFeatures(data,{featureProjection:"EPSG:3857"}));
  }).catch(error=>console.warn("Unable to load imported dataset layers",error));
  const disasterWorkspace=document.querySelector(".disaster-workspace");
  if(disasterWorkspace){
    const disasterEventList=disasterWorkspace.querySelector(".disaster-event-list");
    document.querySelector("#overview")?.remove();
    const disasterMapSection=document.querySelector("#map-section");
    if(disasterEventList && disasterMapSection){
      disasterMapSection.append(disasterEventList);
      disasterMapSection.classList.add("disaster-map-with-events");
    }
    const [lon,lat]=disasterWorkspace.dataset.disasterCenter.split(",").map(Number);
    const events={flood:{title:"น้ำเอ่อล้นตลิ่ง ชุมชนริมแม่น้ำ",location:"พื้นที่ริมน้ำ · วันนี้ 13:42",severity:"เร่งด่วน",point:[lon+.008,lat+.004],people:"1,840 คน",households:"612 หลัง",places:"8 แห่ง",shelters:"3 แห่ง",pumps:"12 เครื่อง",staff:"48 คน",water:"5,520 ลิตร",food:"5,520 มื้อ",kits:"612 ชุด",note:"เตรียมรองรับการอพยพและการช่วยเหลือภายใน 24 ชั่วโมง"},rain:{title:"ฝนตกหนักต่อเนื่อง",location:"เขตพื้นที่ลุ่มต่ำ · วันนี้ 11:15",severity:"เฝ้าระวัง",point:[lon-.01,lat+.006],people:"760 คน",households:"248 หลัง",places:"4 แห่ง",shelters:"1 แห่ง",pumps:"6 เครื่อง",staff:"24 คน",water:"2,280 ลิตร",food:"2,280 มื้อ",kits:"248 ชุด",note:"ติดตามฝนสะสมและเปิดเครื่องสูบน้ำในจุดเสี่ยง"},fire:{title:"ไฟไหม้หญ้าพื้นที่ว่าง",location:"แนวชุมชน · 2 ก.ย. 18:40",severity:"ติดตาม",point:[lon+.006,lat-.008],people:"120 คน",households:"36 หลัง",places:"1 แห่ง",shelters:"-",pumps:"-",staff:"18 คน",water:"1,000 ลิตร",food:"360 มื้อ",kits:"36 ชุด",note:"กันแนวไฟและเตรียมหน่วยสนับสนุนใกล้เคียง"}};
    const source=new ol.source.Vector(), layer=new ol.layer.Vector({source,style:new ol.style.Style({image:new ol.style.Circle({radius:15,fill:new ol.style.Fill({color:"#ef4444"}),stroke:new ol.style.Stroke({color:"#fff",width:3})}),text:new ol.style.Text({text:"!",font:"700 16px sans-serif",fill:new ol.style.Fill({color:"#fff"})})})});map.addLayer(layer);
    Object.entries(events).forEach(([id,event])=>source.addFeature(new ol.Feature({geometry:new ol.geom.Point(ol.proj.fromLonLat(event.point)),event:id})));
    const set=(id)=>{const event=events[id];document.querySelectorAll(".disaster-event").forEach(button=>button.classList.toggle("active",button.dataset.event===id));[["disaster-title",event.title],["disaster-location",event.location],["disaster-severity",event.severity],["impact-people",event.people],["impact-households",event.households],["impact-places",event.places],["resource-shelters",event.shelters],["resource-pumps",event.pumps],["resource-staff",event.staff],["resource-water",event.water],["resource-food",event.food],["resource-kits",event.kits],["preparedness-note",event.note],["disaster-map-note",`กำลังโฟกัส: ${event.location}`]].forEach(([key,value])=>{const node=document.querySelector(`#${key}`);if(node)node.textContent=value});map.getView().animate({center:ol.proj.fromLonLat(event.point),zoom:15,duration:500});};
    document.querySelectorAll(".disaster-event").forEach(button=>button.addEventListener("click",()=>set(button.dataset.event)));set("flood");
  }
  const overviewPage=document.querySelector(".page-overview");
  if(overviewPage){
    const taskItems=[
      {level:"urgent",title:"น้ำท่วมขังในซอยหมู่ที่ 5",place:"ม.5 บ้านเนิน · ซอยโพธิ์",time:"แจ้งเมื่อ 15:45 น.",reporter:"นายสมชาย ใจดี · 08X-XXX-2481",team:"ทีมป้องกันและบรรเทาสาธารณภัย ชุด A",impact:"ประชาชนประมาณ 86 คน · 24 ครัวเรือน · ถนนชุมชน 1 สาย",detail:"พบปัญหาน้ำขังในพื้นที่ ส่งผลต่อการเดินทางและบ้านเรือนใกล้เคียง ต้องส่งเจ้าหน้าที่เข้าตรวจสอบและกั้นพื้นที่โดยเร็ว",next:"ตรวจสอบระดับน้ำของเขตต้นเหตุ, ช่วยเหลือประชาชนกลุ่มเปราะบางก่อน, จัดรถสูบน้ำและวางแนวกั้นน้ำ"},
      {level:"urgent",title:"ต้นไม้ใหญ่โค่นขวางทางสัญจร",place:"ม.7 บ้านโคก · ถนนสายเก่า",time:"แจ้งเมื่อ 09:20 น.",reporter:"นางสาวจิราภา แก้วคำ · 08X-XXX-5762",team:"ทีมช่างโยธาและงานป้องกันฯ",impact:"ประชาชน 42 คน · ถนนชุมชน 1 สาย",detail:"ต้นไม้โค่นกีดขวางเส้นทางหลักของชุมชน ต้องตัดกิ่งและเปิดเส้นทางเพื่อให้รถฉุกเฉินผ่านได้",next:"กั้นจุดเสี่ยง, ประสานรถกระเช้า, ตรวจสอบสายไฟบริเวณใกล้เคียง"},
      {level:"watch",title:"ไฟฟ้าขัดข้องบริเวณสี่แยกหมู่ที่ 3",place:"ม.3 ตำบลบางพลี",time:"แจ้งเมื่อ 11:05 น.",reporter:"ศูนย์รับแจ้งเหตุเทศบาล · 191",team:"ประสานการไฟฟ้าส่วนภูมิภาค",impact:"ไฟส่องสว่างสาธารณะ 12 จุด",detail:"ระบบไฟส่องสว่างริมถนนขัดข้องในช่วงฝนตก กำลังรอเจ้าหน้าที่เข้าตรวจสอบตู้ควบคุม",next:"ประสานผู้รับผิดชอบ, ตั้งป้ายเตือนผู้ใช้ถนน, ติดตามการแก้ไข"},
      {level:"normal",title:"ตรวจสอบฝนสะสมพื้นที่ลุ่มต่ำ",place:"ม.2 บ้านริมน้ำ",time:"อัปเดตเมื่อ 13:10 น.",reporter:"สถานีวัดน้ำและฝนในพื้นที่",team:"ทีมเฝ้าระวังน้ำท่วม",impact:"พื้นที่เฝ้าระวัง 3 จุด",detail:"ปริมาณฝนสะสมสูงกว่าค่าเฉลี่ยเล็กน้อย ยังไม่พบผลกระทบต่อชุมชน",next:"ติดตามระดับน้ำทุก 30 นาที, แจ้งเตือนผู้นำชุมชนหากระดับสูงขึ้น"},
      {level:"watch",title:"ตรวจสอบท่อระบายน้ำอุดตัน",place:"ม.4 บ้านตลาด · ถนนสายหลัก",time:"แจ้งเมื่อ 12:35 น.",reporter:"นายธนพล ศรีสุข · 08X-XXX-9124",team:"ทีมช่างโยธา",impact:"เสี่ยงน้ำขังบริเวณตลาดและทางแยก",detail:"พบเศษวัสดุอุดตันบริเวณตะแกรงรับน้ำ ต้องเร่งทำความสะอาดก่อนฝนตกช่วงเย็น",next:"ส่งทีมตรวจสอบพื้นที่, นำเครื่องมือทำความสะอาด, รายงานผลหลังดำเนินการ"},
      {level:"normal",title:"ติดตามการจัดส่งน้ำดื่มชุมชน",place:"ม.6 บ้านคลอง · ศูนย์ชุมชน",time:"อัปเดตเมื่อ 10:40 น.",reporter:"เจ้าหน้าที่ศูนย์ประสานงาน",team:"ทีมสาธารณสุขและอาสาสมัคร",impact:"ครัวเรือนกลุ่มเปราะบาง 18 ครัวเรือน",detail:"เตรียมจัดส่งน้ำดื่มสำหรับผู้สูงอายุและผู้ป่วยติดเตียงตามแผนช่วยเหลือประจำวัน",next:"ยืนยันรายการรับน้ำดื่ม, ประสานอาสาสมัคร, บันทึกผลการส่งมอบ"}
    ];
    const mapSection=document.querySelector("#map-section");
    if(mapSection){
      const taskPanel=document.createElement("section");
      taskPanel.className="overview-task-panel";
      taskPanel.innerHTML=`<div class="overview-panel-heading"><div><h2>งานที่ต้องดำเนินการ</h2><p>เรียงตามระดับความเร่งด่วน</p></div><b>${taskItems.length} งาน</b></div><div class="overview-task-filters"><button class="active" data-task-filter="all">ทั้งหมด</button><button data-task-filter="urgent">ฉุกเฉิน</button><button data-task-filter="watch">ด่วน</button><button data-task-filter="normal">เฝ้าระวัง</button></div><div class="overview-task-list">${taskItems.map((task,index)=>`<button type="button" class="overview-task ${task.level}" data-task-index="${index}"><span class="task-status-dot"></span><span><b>${task.title}</b><small>⌖ ${task.place}</small><small>${task.time}</small></span><em>${task.level==="urgent"?"ฉุกเฉิน":task.level==="watch"?"ด่วน":"เฝ้าระวัง"}</em></button>`).join("")}</div>`;
      mapSection.prepend(taskPanel);
      taskPanel.classList.toggle("has-scroll",taskItems.length>4);
      if(taskItems.length>4){
        const mapCard=mapSection.querySelector(".map-card");
        const mapWrap=mapCard?.querySelector(".map-wrap");
        const syncTaskPanelHeight=()=>{
          if(!mapCard || !mapWrap) return;
          const toolbarHeight=mapCard.querySelector(".map-toolbar")?.getBoundingClientRect().height || 0;
          taskPanel.style.height=`${Math.ceil(mapWrap.getBoundingClientRect().height+toolbarHeight)}px`;
        };
        requestAnimationFrame(syncTaskPanelHeight);
        window.ResizeObserver && mapWrap && new ResizeObserver(syncTaskPanelHeight).observe(mapWrap);
      }
      const taskStates=[
        {name:"emergency",label:"ฉุกเฉิน"},
        {name:"priority",label:"เร่งด่วน"},
        {name:"watch",label:"เฝ้าระวัง"},
        {name:"normal",label:"รอได้"},
        {name:"priority",label:"เร่งด่วน"},
        {name:"normal",label:"รอได้"}
      ];
      taskPanel.querySelector(".overview-task-filters").innerHTML='<button class="active" data-task-filter="all">ทั้งหมด</button><button data-task-filter="emergency">ฉุกเฉิน</button><button data-task-filter="priority">เร่งด่วน</button><button data-task-filter="watch">เฝ้าระวัง</button><button data-task-filter="normal">รอได้</button>';
      taskPanel.querySelectorAll(".overview-task").forEach((button,index)=>{
        const state=taskStates[index];
        button.classList.remove("urgent","watch","normal");
        button.classList.add(state.name);
        button.dataset.taskState=state.name;
        button.querySelector("em").textContent=state.label;
        const taskContent=button.querySelector(".task-status-dot + span");
        const taskDetails=taskContent?.querySelectorAll("small");
        if(taskDetails?.length===2){
          taskDetails[0].classList.add("task-location");
          taskDetails[0].textContent=`สถานที่: ${taskItems[index].place}`;
          taskDetails[1].classList.add("task-time");
          const taskMeta=document.createElement("span");
          taskMeta.className="task-meta";
          const taskLevel=button.querySelector("em");
          taskLevel.classList.add("task-level");
          taskMeta.append(taskDetails[1]);
          button.append(taskMeta,taskLevel);
        }
      });
      mapSection.classList.add("overview-map-workspace");
      const baseline=document.createElement("section");
      baseline.className="overview-baseline";
      baseline.innerHTML=`<div class="overview-baseline-heading"><div><h2>ข้อมูลพื้นฐานของตำบล</h2><p>ข้อมูลสำหรับวางแผนและจัดสรรกำลัง</p></div><span>ข้อมูลสาธิต</span></div><div class="overview-baseline-grid"><article class="area-facts"><h3>ข้อมูลทั่วไปของตำบลบางนาค</h3><div class="fact-kpis"><div><b>48.7</b><small>ตร.กม.</small></div><div><b>18</b><small>หมู่บ้าน</small></div><div><b>2,310</b><small>ครัวเรือน</small></div></div><dl><div><dt>ประเภทพื้นที่</dt><dd>องค์การบริหารส่วนตำบล</dd></div><div><dt>อำเภอ</dt><dd>อำเภอเมืองนราธิวาส</dd></div></dl></article><article class="population-facts"><h3>ประชาชนและกลุ่มเปราะบาง</h3><strong>8,420 <small>คน</small></strong><div><span>ผู้สูงอายุ <b>1,245 คน</b></span><i class="amber" style="--value:74%"></i><span>ผู้ป่วยติดเตียง <b>92 คน</b></span><i class="red" style="--value:20%"></i><span>ผู้พิการ <b>134 คน</b></span><i class="purple" style="--value:32%"></i></div></article><article class="resource-facts"><h3>ทรัพยากรในตำบล</h3><div class="resource-status-grid"><div><span>💧 เครื่องสูบน้ำ</span><b>10 <small>/ 12 พร้อม</small></b><em>ไม่พร้อม 2</em></div><div><span>🚜 รถบรรทุกน้ำ</span><b>3 <small>/ 4 พร้อม</small></b><em>ไม่พร้อม 1</em></div><div><span>🚑 รถพยาบาล</span><b>2 <small>/ 3 พร้อม</small></b><em>ไม่พร้อม 1</em></div><div><span>⚡ เครื่องปั่นไฟ</span><b>5 <small>/ 6 พร้อม</small></b><em>ไม่พร้อม 1</em></div></div></article><article class="team-facts"><h3>ทีมงานในพื้นที่</h3><ul><li><span>ทีมกู้ภัย</span><b>42 <small>พร้อม 38 · ไม่พร้อม 4</small></b></li><li><span>ทีมสาธารณสุข</span><b>28 <small>พร้อม 26 · ไม่พร้อม 2</small></b></li><li><span>อาสาสมัคร อปพร.</span><b>36 <small>พร้อม 31 · ไม่พร้อม 5</small></b></li></ul></article></div>`;
      baseline.querySelector(".resource-facts").innerHTML='<h3>ทรัพยากรในตำบล</h3><div class="resource-status-grid"><div><span>💧 เครื่องสูบน้ำ</span><b>พร้อมใช้งาน 10 เครื่อง</b><em>ไม่พร้อมใช้งาน 2 เครื่อง</em></div><div><span>🚜 รถบรรทุกน้ำ</span><b>พร้อมใช้งาน 3 คัน</b><em>ไม่พร้อมใช้งาน 1 คัน</em></div><div><span>🚑 รถพยาบาล</span><b>พร้อมใช้งาน 2 คัน</b><em>ไม่พร้อมใช้งาน 1 คัน</em></div><div><span>⚡ เครื่องปั่นไฟ</span><b>พร้อมใช้งาน 5 เครื่อง</b><em>ไม่พร้อมใช้งาน 1 เครื่อง</em></div></div>';
      baseline.querySelector(".team-facts").innerHTML='<h3>ทีมงานในพื้นที่</h3><ul><li><span>ทีมกู้ภัย</span><b>พร้อมทำงาน 38 คน<small>ไม่พร้อมทำงาน 4 คน · รวม 42 คน</small></b></li><li><span>ทีมสาธารณสุข</span><b>พร้อมทำงาน 26 คน<small>ไม่พร้อมทำงาน 2 คน · รวม 28 คน</small></b></li><li><span>อาสาสมัคร อปพร.</span><b>พร้อมทำงาน 31 คน<small>ไม่พร้อมทำงาน 5 คน · รวม 36 คน</small></b></li></ul>';
      baseline.querySelector(".resource-facts").innerHTML='<h3>ทรัพยากรในตำบล</h3><ul><li><span>💧 เครื่องสูบน้ำ</span><b><strong>10 พร้อม</strong><small>2 ไม่พร้อม</small></b></li><li><span>🚜 รถบรรทุกน้ำ</span><b><strong>3 พร้อม</strong><small>1 ไม่พร้อม</small></b></li><li><span>🚑 รถพยาบาล</span><b><strong>2 พร้อม</strong><small>1 ไม่พร้อม</small></b></li><li><span>⚡ เครื่องปั่นไฟ</span><b><strong>5 พร้อม</strong><small>1 ไม่พร้อม</small></b></li></ul>';
      [12,4,3,6].forEach((total,index)=>{
        const summary=baseline.querySelectorAll(".resource-facts li b")[index];
        if(summary){ const totalLabel=document.createElement("span"); totalLabel.className="resource-total"; totalLabel.textContent=`ทั้งหมด ${total}`; summary.prepend(totalLabel); }
      });
      baseline.querySelector(".team-facts").innerHTML='<h3>ทีมงานในพื้นที่</h3><ul><li><span>ทีมกู้ภัย</span><b><span class="team-total">ทั้งหมด 42</span><strong>38 พร้อม</strong><small>4 ไม่พร้อม</small></b></li><li><span>ทีมสาธารณสุข</span><b><span class="team-total">ทั้งหมด 28</span><strong>26 พร้อม</strong><small>2 ไม่พร้อม</small></b></li><li><span>อาสาสมัคร อปพร.</span><b><span class="team-total">ทั้งหมด 36</span><strong>31 พร้อม</strong><small>5 ไม่พร้อม</small></b></li></ul>';
      const dailyStatus=document.createElement("section");
      dailyStatus.className="daily-status-card";
      dailyStatus.innerHTML='<div class="daily-status-heading"><div><h2>สถานะภัยในพื้นที่ตอนนี้</h2><p>สรุปภาพรวมภัยที่ต้องติดตามในเขตรับผิดชอบ</p></div><button type="button">ดูรายละเอียดทั้งหมด →</button></div><div class="daily-status-list"><article class="danger"><i>≋</i><div><b>น้ำท่วม</b><small>2 จุดต้องเฝ้าระวัง</small><em>มีเหตุการณ์</em></div></article><article class="safe"><i>♨</i><div><b>ไฟป่า</b><small>ไม่มีรายงานเหตุ</small><em>ปกติ</em></div></article><article class="watch"><i>≋</i><div><b>วาตภัย</b><small>1 จุดกำลังเฝ้าระวัง</small><em>มีเหตุการณ์</em></div></article><article class="safe"><i>△</i><div><b>ดินถล่ม</b><small>ไม่มีพื้นที่เสี่ยง</small><em>ปกติ</em></div></article><article class="safe"><i>☀</i><div><b>อากาศร้อน</b><small>อุณหภูมิ 34°C</small><em>ปกติ</em></div></article><article class="watch"><i>♬</i><div><b>ฝนตกหนัก</b><small>ฝนสะสม 68.5 มม.</small><em>เฝ้าระวัง</em></div></article></div>';
      mapSection.after(dailyStatus);
      dailyStatus.after(baseline);
      const dialog=document.createElement("dialog");
      dialog.className="overview-task-dialog";
      document.body.append(dialog);
      const showTask=(task)=>{dialog.innerHTML=`<button type="button" class="overview-dialog-close" aria-label="ปิด">×</button><header><span class="${task.level}">${task.level==="urgent"?"ฉุกเฉิน":task.level==="watch"?"ด่วน":"เฝ้าระวัง"}</span><small>รหัสเหตุการณ์ INC-2569-${String(taskItems.indexOf(task)+1).padStart(3,"0")}</small><h2>${task.title}</h2><p>⌖ ${task.place} · ${task.time}</p></header><div class="overview-dialog-grid"><section><h3>รายละเอียดเหตุที่ได้รับแจ้ง</h3><dl><div><dt>ผู้แจ้งเหตุ</dt><dd>${task.reporter}</dd></div><div><dt>ช่องทางรับแจ้ง</dt><dd>สายด่วน อบต. / เจ้าหน้าที่บันทึกเข้าระบบ</dd></div><div><dt>รายละเอียด</dt><dd>${task.detail}</dd></div><div><dt>ผลกระทบเบื้องต้น</dt><dd>${task.impact}</dd></div></dl></section><section><h3>การดำเนินงาน</h3><dl><div><dt>สถานะ</dt><dd>รอรับเรื่อง</dd></div><div><dt>ผู้รับผิดชอบหลัก</dt><dd>${task.team}</dd></div></dl><h4>สิ่งที่ต้องทำต่อ</h4><ul>${task.next.split(", ").map(item=>`<li>${item}</li>`).join("")}</ul></section></div>`;dialog.showModal();dialog.querySelector(".overview-dialog-close")?.addEventListener("click",()=>dialog.close())};
      taskPanel.querySelectorAll(".overview-task").forEach(button=>button.addEventListener("click",()=>showTask(taskItems[Number(button.dataset.taskIndex)])));
      taskPanel.addEventListener("click",event=>{
        const button=event.target.closest(".overview-task");
        if(!button) return;
        const state=taskStates[Number(button.dataset.taskIndex)];
        window.setTimeout(()=>{
          const status=dialog.querySelector("header>span");
          if(status){ status.className=state.name; status.textContent=state.label; }
        });
      });
      taskPanel.querySelectorAll("[data-task-filter]").forEach(button=>button.addEventListener("click",()=>{taskPanel.querySelectorAll("[data-task-filter]").forEach(item=>item.classList.toggle("active",item===button));taskPanel.querySelectorAll(".overview-task").forEach(task=>task.hidden=button.dataset.taskFilter!=="all"&&task.classList.contains(button.dataset.taskFilter)===false)}));
    }
  }
  const terrainSourceNotice=document.createElement("a");
  terrainSourceNotice.id="terrain-source-notice";
  terrainSourceNotice.href="https://registry.opendata.aws/terrain-tiles/";
  terrainSourceNotice.target="_blank";
  terrainSourceNotice.rel="noopener";
  terrainSourceNotice.textContent="แผนที่ฐาน: OpenStreetMap · ความสูงภูมิประเทศ: AWS Open Data Terrain Tiles";
  document.querySelector(".map-wrap").appendChild(terrainSourceNotice);
  const terrainElevationLegend=document.createElement("section");
  terrainElevationLegend.id="terrain-elevation-legend";
  terrainElevationLegend.innerHTML='<div class="terrain-legend-heading"><b>สีและเงาตามระดับความสูง</b><button type="button" id="terrain-color-toggle" class="terrain-switch is-on" role="switch" aria-checked="true" aria-label="เปิดหรือปิดสีแสดงระดับความสูง"><span></span></button></div><span class="terrain-gradient"></span><div><small>0 ม.</small><small>100</small><small>250</small><small>500</small><small>1,000+ ม.</small></div>';
  document.querySelector(".map-wrap").appendChild(terrainElevationLegend);
  let cesiumViewer, cesiumBoundaryDataSource, cesiumSiblingBoundaryDataSource, cesiumProvinceBoundaryDataSource, cesiumPickHandler, terrainColorLayer, floodDataSource, floodStartEntity, floodStart, floodPicking=false, cesiumMode=false, terrainColorEnabled=true, selectedFeatureData, lastFloodAnalysis=null, cesiumPlaceVersion=0, cesiumBoundaryVersion=0;
  const cesiumPlaceEntities=[];
  const cesiumBoundaryPayloadCache=new Map();
  const selectedAreaPayloadCache=new Map();
  const administrativeBoundaryPayloadCache=new Map();
  const terrainTileCache=new Map();
  try {
    Object.keys(sessionStorage)
      .filter(key=>key.startsWith("smart-tambon:selected-area:"))
      .forEach(key=>sessionStorage.removeItem(key));
  } catch (_) { /* Browser storage may be unavailable. */ }
  const terrainTileUrl=(x,y,level)=>`/api/terrain_tiles/${level}/${x}/${y}`;
  async function terrainHeightmapFromSource(x,y,level,sourceLevel) {
    const divisor=2**(level-sourceLevel);
    const sourceX=Math.floor(x/divisor), sourceY=Math.floor(y/divisor);
    const localX=x%divisor, localY=y%divisor;
    const response=await fetch(terrainTileUrl(sourceX,sourceY,sourceLevel));
    if(!response.ok) throw new Error(`Terrain tile ${response.status}`);
    const image=await createImageBitmap(await response.blob());
    const canvas=document.createElement("canvas"); canvas.width=257; canvas.height=257;
    const context=canvas.getContext("2d",{willReadFrequently:true});
    const cropSize=image.width/divisor;
    context.drawImage(image,localX*cropSize,localY*cropSize,cropSize,cropSize,0,0,257,257);
    image.close?.();
    const pixels=context.getImageData(0,0,257,257).data;
    const heights=new Float32Array(257*257);
    for(let index=0;index<heights.length;index+=1){const offset=index*4;heights[index]=pixels[offset]*256+pixels[offset+1]+pixels[offset+2]/256-32768;}
    return heights;
  }
  async function awsTerrainHeightmap(x,y,level) {
    const cacheKey=`${level}/${x}/${y}`;
    if (terrainTileCache.has(cacheKey)) return terrainTileCache.get(cacheKey);
    const request=(async()=>{
      for(let sourceLevel=Math.min(level,15);sourceLevel>=0;sourceLevel-=1){
        try{return await terrainHeightmapFromSource(x,y,level,sourceLevel);}
        catch(error){console.warn(`Terrain tile level ${sourceLevel} unavailable; using the next parent tile`,error);}
      }
      return new Float32Array(257*257);
    })();
    terrainTileCache.set(cacheKey,request);
    if(terrainTileCache.size>160) terrainTileCache.delete(terrainTileCache.keys().next().value);
    return request;
  }
  function initializeCesium() {
    if(cesiumViewer) return cesiumViewer;
    if(!window.Cesium) throw new Error("ไม่สามารถโหลด CesiumJS ได้");
    const Cesium=window.Cesium;
    const terrainProvider=new Cesium.CustomHeightmapTerrainProvider({
      width:257,height:257,tilingScheme:new Cesium.WebMercatorTilingScheme(),
      callback:(x,y,level)=>awsTerrainHeightmap(x,y,level)
    });
    cesiumViewer=new Cesium.Viewer("cesium-map",{
      terrainProvider,
      baseLayer:new Cesium.ImageryLayer(new Cesium.OpenStreetMapImageryProvider({url:"https://tile.openstreetmap.org/",credit:new Cesium.Credit("© OpenStreetMap contributors")})),
      animation:false,baseLayerPicker:false,fullscreenButton:false,geocoder:false,homeButton:true,infoBox:true,sceneModePicker:false,selectionIndicator:false,timeline:false,navigationHelpButton:false,
      requestRenderMode:true,maximumRenderTimeChange:Number.POSITIVE_INFINITY
    });
    cesiumViewer.scene.globe.depthTestAgainstTerrain=true;
    cesiumViewer.scene.verticalExaggeration=2.8;
    cesiumViewer.scene.verticalExaggerationRelativeHeight=0;
    cesiumViewer.scene.globe.maximumScreenSpaceError=3;
    cesiumViewer.scene.globe.tileCacheSize=240;
    cesiumViewer.scene.globe.preloadAncestors=false;
    cesiumViewer.scene.globe.preloadSiblings=false;
    cesiumViewer.scene.globe.enableLighting=false;
    cesiumViewer.scene.globe.dynamicAtmosphereLighting=false;
    cesiumViewer.scene.screenSpaceCameraController.enableCollisionDetection=true;
    cesiumViewer.scene.screenSpaceCameraController.minimumZoomDistance=1_200;
    cesiumViewer.scene.screenSpaceCameraController.maximumZoomDistance=4_000_000;
    cesiumViewer.scene.globe.baseColor=Cesium.Color.fromCssColorString("#d9e2e8");
    cesiumViewer.scene.backgroundColor=Cesium.Color.fromCssColorString("#d9e2e8");
    const terrainColorProvider=new Cesium.UrlTemplateImageryProvider({url:"/api/terrain_color_tiles/{z}/{x}/{y}?palette=green-v7",tilingScheme:new Cesium.WebMercatorTilingScheme(),maximumLevel:12,credit:new Cesium.Credit("Elevation colors: AWS Open Data Terrain Tiles")});
    terrainColorLayer=new Cesium.ImageryLayer(terrainColorProvider,{alpha:0.58,show:terrainColorEnabled});
    cesiumViewer.imageryLayers.add(terrainColorLayer);
    bindCesiumSubdistrictSelection();
    return cesiumViewer;
  }
  function syncCesiumPlaces() {
    if(!cesiumViewer) return;
    const Cesium=window.Cesium;
    ++cesiumPlaceVersion;
    cesiumPlaceEntities.splice(0).forEach(entity=>cesiumViewer.entities.remove(entity));
    const colors=Object.fromEntries(Object.entries(placeConfig).map(([category,config])=>[category,Cesium.Color.fromCssColorString(config.color)]));
    Object.values(placesByCategory).flat().forEach(place=>{
      if(!Number.isFinite(Number(place.lon)) || !Number.isFinite(Number(place.lat))) return;
      const longitude=Number(place.lon), latitude=Number(place.lat);
      const entity=cesiumViewer.entities.add({
        name:place.name,
        position:Cesium.Cartesian3.fromDegrees(longitude,latitude,3),
        point:{
          pixelSize:10,color:colors[place.category] || Cesium.Color.fromCssColorString("#5ac5a9"),
          outlineColor:Cesium.Color.WHITE,outlineWidth:2,
          heightReference:Cesium.HeightReference.RELATIVE_TO_GROUND,
          disableDepthTestDistance:Number.POSITIVE_INFINITY
        }
      });
      cesiumPlaceEntities.push(entity);
    });
  }
  async function fetchCesiumBoundary(url) {
    if(cesiumBoundaryPayloadCache.has(url)) return cesiumBoundaryPayloadCache.get(url);
    const request=fetch(url,{headers:{Accept:"application/json"}}).then(response=>{
      if(!response.ok) throw new Error(response.status);
      return response.json();
    });
    cesiumBoundaryPayloadCache.set(url,request);
    try{return await request;}catch(error){cesiumBoundaryPayloadCache.delete(url);throw error;}
  }
  async function fetchSelectedArea(url) {
    if(selectedAreaPayloadCache.has(url)) return selectedAreaPayloadCache.get(url);
    const request=fetch(url,{headers:{Accept:"application/json"}}).then(response=>{
      if(!response.ok) throw new Error(response.status);
      return response.json();
    });
    selectedAreaPayloadCache.set(url,request);
    try{return await request;}catch(error){selectedAreaPayloadCache.delete(url);throw error;}
  }
  async function fetchAdministrativeBoundary(url) {
    if(administrativeBoundaryPayloadCache.has(url)) return administrativeBoundaryPayloadCache.get(url);
    const request=fetch(url,{headers:{Accept:"application/json"}}).then(response=>{
      if(!response.ok) throw new Error(response.status);
      return response.json();
    });
    administrativeBoundaryPayloadCache.set(url,request);
    try{return await request;}catch(error){administrativeBoundaryPayloadCache.delete(url);throw error;}
  }
  async function syncCesiumBoundary() {
    const version=++cesiumBoundaryVersion;
    if(!cesiumViewer || !selectedFeatureData?.geometry) return;
    const Cesium=window.Cesium;
    if(cesiumBoundaryDataSource) cesiumViewer.dataSources.remove(cesiumBoundaryDataSource,true);
    if(cesiumSiblingBoundaryDataSource) cesiumViewer.dataSources.remove(cesiumSiblingBoundaryDataSource,true);
    if(cesiumProvinceBoundaryDataSource) cesiumViewer.dataSources.remove(cesiumProvinceBoundaryDataSource,true);
    const selectedIsProvince=selectedFeatureData.properties?.level==="province";
    const selectedColor=Cesium.Color.fromCssColorString("#5ac5a9");
    cesiumBoundaryDataSource=await Cesium.GeoJsonDataSource.load(selectedFeatureData,{clampToGround:true,stroke:selectedColor,fill:Cesium.Color.TRANSPARENT,strokeWidth:selectedIsProvince ? 5 : 4});
    drapeBoundaryOnTerrain(cesiumBoundaryDataSource);
    appendTerrainOutlines(cesiumBoundaryDataSource,selectedFeatureData,selectedColor,selectedIsProvince ? 5 : 4);
    if(version!==cesiumBoundaryVersion) return;
    cesiumViewer.dataSources.add(cesiumBoundaryDataSource);
    cesiumViewer.scene.requestRender();
    await new Promise(resolve=>window.setTimeout(resolve,120));
    if(version!==cesiumBoundaryVersion) return;
    if(selectedIsProvince){
      try{
        const [provinces,districts]=await Promise.all([
          fetchCesiumBoundary("/api/provinces?geometry=1&simplified=3d"),
          fetchCesiumBoundary(`/api/provinces/${selectedProvinceId}/districts?geometry=1&simplified=3d`)
        ]);
        if(version!==cesiumBoundaryVersion) return;
        cesiumProvinceBoundaryDataSource=await Cesium.GeoJsonDataSource.load(districts,{clampToGround:true,stroke:Cesium.Color.fromCssColorString("#0d1b2a").withAlpha(.9),fill:Cesium.Color.TRANSPARENT,strokeWidth:2});
        drapeBoundaryOnTerrain(cesiumProvinceBoundaryDataSource);
        appendTerrainOutlines(cesiumProvinceBoundaryDataSource,districts,Cesium.Color.fromCssColorString("#0d1b2a").withAlpha(.9),2);
        if(version!==cesiumBoundaryVersion) return;
        cesiumViewer.dataSources.add(cesiumProvinceBoundaryDataSource);
        const otherProvinces={...provinces,features:provinces.features.filter(feature=>String(feature.id)!==String(selectedProvinceId))};
        cesiumSiblingBoundaryDataSource=await Cesium.GeoJsonDataSource.load(otherProvinces,{clampToGround:true,stroke:Cesium.Color.fromCssColorString("#0d1b2a").withAlpha(.78),fill:Cesium.Color.fromCssColorString("#0d1b2a").withAlpha(.26),strokeWidth:1.1});
        drapeBoundaryOnTerrain(cesiumSiblingBoundaryDataSource);
        if(version!==cesiumBoundaryVersion) return;
        cesiumViewer.dataSources.add(cesiumSiblingBoundaryDataSource);
      }catch(error){console.warn("Unable to load other province boundaries in 3D",error);}
      return;
    }
    if(selectedFeatureData.properties?.level==="district"){
      try{
        const [districts,subdistrictFeatures]=await Promise.all([
          fetchCesiumBoundary(`/api/provinces/${selectedProvinceId}/districts?geometry=1&simplified=3d`),
          fetchCesiumBoundary(`/api/provinces/${selectedProvinceId}/subdistricts?geometry=1&district_code=${encodeURIComponent(selectedDistrictCode)}&simplified=3d`)
        ]);
        if(version!==cesiumBoundaryVersion) return;
        const otherDistricts={...districts,features:districts.features.filter(feature=>String(feature.id)!==String(selectedDistrictCode))};
        cesiumSiblingBoundaryDataSource=await Cesium.GeoJsonDataSource.load(otherDistricts,{clampToGround:true,stroke:Cesium.Color.fromCssColorString("#0d1b2a").withAlpha(.9),fill:Cesium.Color.fromCssColorString("#0d1b2a").withAlpha(.22),strokeWidth:1.5});
        drapeBoundaryOnTerrain(cesiumSiblingBoundaryDataSource);
        if(version!==cesiumBoundaryVersion) return;
        cesiumViewer.dataSources.add(cesiumSiblingBoundaryDataSource);
        const districtSubdistricts={...subdistrictFeatures,features:subdistrictFeatures.features.map(feature=>({...feature,properties:{...feature.properties,subdistrict_id:feature.id}}))};
        cesiumProvinceBoundaryDataSource=await Cesium.GeoJsonDataSource.load(districtSubdistricts,{clampToGround:true,stroke:Cesium.Color.fromCssColorString("#0d1b2a").withAlpha(.9),fill:Cesium.Color.TRANSPARENT,strokeWidth:1.5});
        drapeBoundaryOnTerrain(cesiumProvinceBoundaryDataSource);
        appendTerrainOutlines(cesiumProvinceBoundaryDataSource,districtSubdistricts,Cesium.Color.fromCssColorString("#0d1b2a").withAlpha(.9),1.5);
        if(version!==cesiumBoundaryVersion) return;
        cesiumViewer.dataSources.add(cesiumProvinceBoundaryDataSource);
      }catch(error){console.warn("Unable to load district boundaries in 3D",error);}
      return;
    }
    if(!selectedProvinceId || !selectedSubdistrictId) return;
    try{
      const [provinceFeature,subdistrictFeatures]=await Promise.all([
        fetchCesiumBoundary(`/api/provinces/${selectedProvinceId}?simplified=3d`),
        fetchCesiumBoundary(`/api/provinces/${selectedProvinceId}/subdistricts?geometry=1&district_code=${encodeURIComponent(selectedDistrictCode)}&simplified=3d`)
      ]);
      if(version!==cesiumBoundaryVersion) return;
      cesiumProvinceBoundaryDataSource=await Cesium.GeoJsonDataSource.load(provinceFeature,{clampToGround:true,stroke:Cesium.Color.fromCssColorString("#173f56").withAlpha(.9),fill:Cesium.Color.TRANSPARENT,strokeWidth:2.5});
      drapeBoundaryOnTerrain(cesiumProvinceBoundaryDataSource);
      if(version!==cesiumBoundaryVersion) return;
      cesiumViewer.dataSources.add(cesiumProvinceBoundaryDataSource);
      const siblings={...subdistrictFeatures,features:subdistrictFeatures.features.filter(feature=>String(feature.id)!==String(selectedSubdistrictId)).map(feature=>({...feature,properties:{...feature.properties,subdistrict_id:feature.id}}))};
      cesiumSiblingBoundaryDataSource=await Cesium.GeoJsonDataSource.load(siblings,{clampToGround:true,stroke:Cesium.Color.fromCssColorString("#0d1b2a").withAlpha(.9),fill:Cesium.Color.fromCssColorString("#0d1b2a").withAlpha(.24),strokeWidth:1.5});
      drapeBoundaryOnTerrain(cesiumSiblingBoundaryDataSource);
      appendTerrainOutlines(cesiumSiblingBoundaryDataSource,siblings,Cesium.Color.fromCssColorString("#0d1b2a").withAlpha(.9),1.5);
      if(version!==cesiumBoundaryVersion) return;
      cesiumViewer.dataSources.add(cesiumSiblingBoundaryDataSource);
    }catch(error){console.warn("Unable to load province and sibling boundaries in 3D",error);}
  }
  function cesiumPropertyValue(entity,key) {
    const value=entity?.properties?.[key];
    return value?.getValue ? value.getValue() : value;
  }
  async function selectCesiumSubdistrict(id,name,districtCode,provinceId) {
    if(!id || String(id)===String(selectedSubdistrictId) || !selectedProvinceId) return;
    if(districtCode && provinceId) return selectNextLayerAtLocation({id,name_th:name,province_id:provinceId,district_code:districtCode});
    const directButton=document.querySelector(`.direct-subdistrict[data-id="${id}"]`);
    if(directButton) return selectFeature(`/api/subdistricts/${id}`,name || directButton.dataset.name || directButton.textContent.trim(),directButton,{provinceId:selectedProvinceId,selectedId:id});
    const provinceButton=document.querySelector(`.province-button[data-id="${selectedProvinceId}"]`);
    if(!provinceButton) return;
    const children=await ensureProvinceChildren(provinceButton,true);
    const button=children.querySelector(`[data-subdistrict-id="${id}"]`);
    if(button) selectFeature(`/api/subdistricts/${id}`,name || button.textContent.trim(),button,{provinceId:selectedProvinceId,selectedId:id});
  }
  function bindCesiumSubdistrictSelection() {
    if(cesiumPickHandler) return;
    const Cesium=window.Cesium;
    cesiumPickHandler=new Cesium.ScreenSpaceEventHandler(cesiumViewer.scene.canvas);
    cesiumPickHandler.setInputAction(event=>{
      if(floodPicking){pickFloodStart(event.position);return;}
      const entity=cesiumViewer.scene.pick(event.position)?.id;
      if(cesiumPropertyValue(entity,"level")!=="subdistrict") return;
      selectCesiumSubdistrict(cesiumPropertyValue(entity,"subdistrict_id"),cesiumPropertyValue(entity,"name_th"),cesiumPropertyValue(entity,"district_code"),cesiumPropertyValue(entity,"province_id"));
    },Cesium.ScreenSpaceEventType.LEFT_CLICK);
  }
  function drapeBoundaryOnTerrain(dataSource) {
    const Cesium=window.Cesium;
    dataSource.entities.values.forEach(entity=>{
      if(entity.polygon){
        entity.polygon.heightReference=Cesium.HeightReference.CLAMP_TO_GROUND;
        entity.polygon.perPositionHeight=false;
      }
      if(entity.polyline){
        entity.polyline.clampToGround=true;
        entity.polyline.arcType=Cesium.ArcType.GEODESIC;
      }
    });
  }
  function appendTerrainOutlines(dataSource,geoJson,color,width) {
    const Cesium=window.Cesium;
    const features=geoJson.type==="FeatureCollection" ? geoJson.features : [geoJson];
    features.forEach(feature=>{
      if(!feature?.geometry) return;
      const polygons=feature.geometry.type==="Polygon" ? [feature.geometry.coordinates] : feature.geometry.type==="MultiPolygon" ? feature.geometry.coordinates : [];
      polygons.forEach(polygon=>polygon.forEach(ring=>{
        if(!Array.isArray(ring) || ring.length<2) return;
        const coordinates=ring.flatMap(position=>[position[0],position[1]]);
        dataSource.entities.add({properties:feature.properties,polyline:{positions:Cesium.Cartesian3.fromDegreesArray(coordinates),width,material:color,clampToGround:true,arcType:Cesium.ArcType.GEODESIC}});
      }));
    });
  }
  function focusCesiumArea() {
    if(!cesiumViewer || !selectedAreaCenter) return;
    const Cesium=window.Cesium;
    const bounds=selectedGeometryBounds();
    if(bounds){
      const [west,south,east,north]=bounds;
      const sphere=Cesium.BoundingSphere.fromPoints([
        Cesium.Cartesian3.fromDegrees(west,south),Cesium.Cartesian3.fromDegrees(west,north),
        Cesium.Cartesian3.fromDegrees(east,south),Cesium.Cartesian3.fromDegrees(east,north)
      ]);
      cesiumViewer.camera.flyToBoundingSphere(sphere,{offset:new Cesium.HeadingPitchRange(0,Cesium.Math.toRadians(-54),0),duration:1.2});
      return;
    }
    cesiumViewer.camera.flyTo({destination:Cesium.Cartesian3.fromDegrees(selectedAreaCenter[0],selectedAreaCenter[1],500000),orientation:{heading:0,pitch:Cesium.Math.toRadians(-54),roll:0},duration:1.2});
  }
  function focusCesiumCurrentLocation(location) {
    if(!cesiumViewer || !location || selectedAreaCenter || !cesiumMode) return;
    const Cesium=window.Cesium;
    cesiumViewer.camera.flyTo({
      destination:Cesium.Cartesian3.fromDegrees(location[0],location[1],18_000),
      orientation:{heading:0,pitch:Cesium.Math.toRadians(-54),roll:0},duration:1.1
    });
  }

  function selectedGeometryBounds() {
    const coordinates=[];
    const collect=value=>Array.isArray(value) && typeof value[0]==="number" ? coordinates.push(value) : Array.isArray(value) ? value.forEach(collect) : null;
    collect(selectedFeatureData?.geometry?.coordinates);
    if(!coordinates.length) return null;
    return [
      Math.min(...coordinates.map(position=>position[0])),Math.min(...coordinates.map(position=>position[1])),
      Math.max(...coordinates.map(position=>position[0])),Math.max(...coordinates.map(position=>position[1]))
    ];
  }
  function setMapMode(is3d) {
    if(is3d && typeof setAreaSelectionTool === "function") setAreaSelectionTool(false);
    cesiumMode=is3d;
    const cesiumContainer=document.querySelector("#cesium-map"), mapContainer=document.querySelector("#map");
    cesiumContainer.classList.toggle("active",is3d); mapContainer.classList.toggle("map-hidden",is3d);
    terrainSourceNotice.classList.toggle("active",is3d);
    terrainElevationLegend.classList.toggle("active",is3d);
    document.querySelectorAll("[data-map-mode]").forEach(button=>button.classList.toggle("active",is3d && button.dataset.mapMode==="3d"));
    updateFloodControls();
    if(!is3d){requestAnimationFrame(()=>map.updateSize());return;}
    try{initializeCesium();updateFloodControls();cesiumViewer.resize();syncCesiumPlaces();syncCesiumBoundary();if(selectedAreaCenter){focusCesiumArea();}else{placeSearchLocation().then(focusCesiumCurrentLocation);}}catch(error){setMapMode(false);document.querySelector("#map-message").textContent=error.message;document.querySelector("#map-message").classList.add("error");}
  }
  function setTerrainColorVisible(visible) {
    terrainColorEnabled=visible;
    if(terrainColorLayer) terrainColorLayer.show=visible;
    const toggle=document.querySelector("#terrain-color-toggle");
    if(toggle){toggle.setAttribute("aria-checked",String(visible));toggle.classList.toggle("is-on",visible);}
  }
  document.querySelector("#terrain-color-toggle")?.addEventListener("click",event=>setTerrainColorVisible(event.currentTarget.getAttribute("aria-checked")!=="true"));
  const floodPickButton=document.querySelector("#flood-pick-point"), floodRunButton=document.querySelector("#flood-run"), floodClearButton=document.querySelector("#flood-clear"), floodRiseInput=document.querySelector("#flood-rise"), floodStatus=document.querySelector("#flood-point-status"), floodSummary=document.querySelector("#flood-summary");
  function updateFloodControls() {
    const active=cesiumMode && Boolean(cesiumViewer);
    floodPickButton.disabled=!active;
    floodRiseInput.disabled=!active || !floodStart;
    floodRunButton.disabled=!active || !floodStart;
    floodClearButton.disabled=!active || (!floodStart && !floodDataSource);
    if(!active) floodStatus.textContent="เปิดโหมด 3D เพื่อเริ่มจำลอง";
    else if(!floodStart) floodStatus.textContent="เลือกจุดเริ่มต้นของระดับน้ำบนพื้นผิว";
  }
  function pickFloodStart(position) {
    const Cesium=window.Cesium;
    const ray=cesiumViewer.camera.getPickRay(position);
    const point=ray && cesiumViewer.scene.globe.pick(ray,cesiumViewer.scene);
    if(!point) return;
    floodPicking=false;
    Cesium.sampleTerrain(cesiumViewer.terrainProvider,13,[Cesium.Cartographic.fromCartesian(point)]).then(samples=>{
      const sample=samples[0];
      if(!Number.isFinite(sample.height)) throw new Error("ไม่พบข้อมูลความสูง");
      floodStart={longitude:sample.longitude,latitude:sample.latitude,height:sample.height};
      if(floodStartEntity) cesiumViewer.entities.remove(floodStartEntity);
      // Keep the marker attached just above the rendered terrain.  The terrain is
      // vertically exaggerated for readability, so an absolute, raw elevation
      // would otherwise be hidden inside the visible ground surface.
      floodStartEntity=cesiumViewer.entities.add({name:"จุดเริ่มต้นระดับน้ำ",position:Cesium.Cartesian3.fromRadians(sample.longitude,sample.latitude,14),point:{pixelSize:16,color:Cesium.Color.fromCssColorString("#1377c9"),outlineColor:Cesium.Color.WHITE,outlineWidth:3,heightReference:Cesium.HeightReference.RELATIVE_TO_GROUND,disableDepthTestDistance:Number.POSITIVE_INFINITY},label:{text:"จุดเริ่มต้นน้ำ",font:"600 12px Noto Sans Thai",fillColor:Cesium.Color.WHITE,outlineColor:Cesium.Color.fromCssColorString("#0b3556"),outlineWidth:3,style:Cesium.LabelStyle.FILL_AND_OUTLINE,pixelOffset:new Cesium.Cartesian2(0,-22),heightReference:Cesium.HeightReference.RELATIVE_TO_GROUND,disableDepthTestDistance:Number.POSITIVE_INFINITY}});
      floodStatus.textContent=`จุดเริ่มต้นสูง ${sample.height.toFixed(1)} ม. จากระดับน้ำทะเล`;
      updateFloodControls();
    }).catch(error=>{floodStatus.textContent=error.message;updateFloodControls();});
  }
  function floodExtent() {
    const values=[];
    const collect=value=>Array.isArray(value) ? (typeof value[0]==="number" ? values.push(value) : value.forEach(collect)) : null;
    if(selectedFeatureData?.geometry?.coordinates) collect(selectedFeatureData.geometry.coordinates);
    if(!values.length){const lon=floodStart.longitude*180/Math.PI,lat=floodStart.latitude*180/Math.PI;return [lon-.03,lat-.03,lon+.03,lat+.03];}
    return [Math.min(...values.map(value=>value[0])),Math.min(...values.map(value=>value[1])),Math.max(...values.map(value=>value[0])),Math.max(...values.map(value=>value[1]))];
  }
  function clearFloodSimulation() {
    floodPicking=false;
    if(floodDataSource) cesiumViewer?.dataSources.remove(floodDataSource,true);
    floodDataSource=null;
    if(floodStartEntity) cesiumViewer?.entities.remove(floodStartEntity);
    floodStartEntity=null; floodStart=null; lastFloodAnalysis=null;
    floodSummary.hidden=true; floodSummary.replaceChildren();
    updateFloodControls();
    updateAnalysisSaveAction();
  }
  async function runFloodSimulation() {
    if(!cesiumViewer || !floodStart) return;
    const Cesium=window.Cesium, rise=Math.max(0,Number(floodRiseInput.value)||0), waterLevel=floodStart.height+rise;
    const [west,south,east,north]=floodExtent(), size=26, dx=(east-west)/size, dy=(north-south)/size;
    const cells=[];
    for(let row=0;row<size;row+=1)for(let column=0;column<size;column+=1){
      const lon=west+(column+.5)*dx,lat=south+(row+.5)*dy;
      if(selectedAreaGeometry && !selectedAreaGeometry.intersectsCoordinate(ol.proj.fromLonLat([lon,lat]))) continue;
      cells.push({row,column,lon,lat,cartographic:Cesium.Cartographic.fromDegrees(lon,lat)});
    }
    floodRunButton.disabled=true; floodStatus.textContent="กำลังวิเคราะห์ระดับความสูงของพื้นที่…";
    try{
      const samples=await Cesium.sampleTerrain(cesiumViewer.terrainProvider,13,cells.map(cell=>cell.cartographic));
      samples.forEach((sample,index)=>cells[index].height=sample.height);
      const byGrid=new Map(cells.filter(cell=>Number.isFinite(cell.height)).map(cell=>[`${cell.row}/${cell.column}`,cell]));
      const seed=[...byGrid.values()].reduce((nearest,cell)=>!nearest || (cell.lon-floodStart.longitude*180/Math.PI)**2+(cell.lat-floodStart.latitude*180/Math.PI)**2<(nearest.lon-floodStart.longitude*180/Math.PI)**2+(nearest.lat-floodStart.latitude*180/Math.PI)**2 ? cell : nearest,null);
      const flooded=new Set(), queue=seed && seed.height<=waterLevel ? [seed] : [];
      while(queue.length){const cell=queue.shift(),key=`${cell.row}/${cell.column}`;if(flooded.has(key))continue;flooded.add(key);[[1,0],[-1,0],[0,1],[0,-1]].forEach(([row,column])=>{const next=byGrid.get(`${cell.row+row}/${cell.column+column}`);if(next && next.height<=waterLevel && !flooded.has(`${next.row}/${next.column}`))queue.push(next);});}
      if(floodDataSource) cesiumViewer.dataSources.remove(floodDataSource,true);
      floodDataSource=new Cesium.CustomDataSource("flood-simulation"); cesiumViewer.dataSources.add(floodDataSource);
      const cellArea=Math.abs(dx*dy)*111320*111320*Math.cos(((south+north)/2)*Math.PI/180);
      let volume=0;
      // Cesium exaggerates the globe but not absolute polygon heights.  Render
      // water at the same visual height as the exaggerated terrain while all
      // flood decisions above remain based on the real metres above sea level.
      const displayWaterLevel=waterLevel*(cesiumViewer.scene.verticalExaggeration || 1)+1;
      flooded.forEach(key=>{const cell=byGrid.get(key),w=west+cell.column*dx,e=w+dx,s=south+cell.row*dy,n=s+dy;volume+=(waterLevel-cell.height)*cellArea;floodDataSource.entities.add({polygon:{hierarchy:Cesium.Cartesian3.fromDegreesArrayHeights([w,s,displayWaterLevel,e,s,displayWaterLevel,e,n,displayWaterLevel,w,n,displayWaterLevel]),perPositionHeight:true,material:Cesium.Color.fromCssColorString("#1677c8").withAlpha(.68),outline:true,outlineColor:Cesium.Color.fromCssColorString("#8fd3ff").withAlpha(.9)}});});
      const total=cells.filter(cell=>Number.isFinite(cell.height)).length,wet=flooded.size;
      floodStatus.textContent=`ระดับน้ำ ${waterLevel.toFixed(1)} ม. (เพิ่ม ${rise.toFixed(1)} ม.)`;
      floodSummary.innerHTML=`<span>พื้นที่ท่วมโดยประมาณ<b>${(wet*cellArea/1e6).toFixed(2)} ตร.กม.</b></span><span>ปริมาตรน้ำโดยประมาณ<b>${(volume/1e6).toFixed(2)} ล้าน ลบ.ม.</b></span><span>เซลล์ที่ท่วม<b>${wet.toLocaleString()}</b></span><span>พื้นที่ไม่ท่วม<b>${Math.max(0,total-wet).toLocaleString()} เซลล์</b></span>`;floodSummary.hidden=false;
      lastFloodAnalysis={geometry:{type:"Point",coordinates:[floodStart.longitude*180/Math.PI,floodStart.latitude*180/Math.PI]},summary:{rise_m:rise,water_level_m:waterLevel,flooded_area_sq_km:Number((wet*cellArea/1e6).toFixed(2)),water_volume_million_cubic_m:Number((volume/1e6).toFixed(2)),flooded_cells:wet,total_cells:total}};
      updateAnalysisSaveAction();
    }catch(error){floodStatus.textContent=`จำลองไม่สำเร็จ: ${error.message}`;}finally{updateFloodControls();}
  }
  floodPickButton?.addEventListener("click",()=>{if(!cesiumMode)return;floodPicking=true;floodStatus.textContent="คลิกตำแหน่งเริ่มต้นบนแผนที่ 3D";});
  floodRunButton?.addEventListener("click",runFloodSimulation);
  floodClearButton?.addEventListener("click",clearFloodSimulation);
  const popupElement = document.querySelector("#place-popup");
  const popup = new ol.Overlay({element:popupElement,positioning:"bottom-center",stopEvent:true});
  map.addOverlay(popup);
  requestAnimationFrame(() => map.updateSize());
  window.addEventListener("resize", () => map.updateSize());

  async function loadNationalOverview() {
    if (document.querySelector(".direct-subdistrict")) return;
    try {
      const data=await fetchAdministrativeBoundary("/api/provinces?geometry=1");
      const features=new ol.format.GeoJSON().readFeatures(data,{featureProjection:"EPSG:3857"});
      overviewBoundaries.getSource().addFeatures(features);
      if(document.querySelector(".dashboard-shell")?.dataset.userRole==="system_admin" && features.length){
        map.getView().fit(overviewBoundaries.getSource().getExtent(),{padding:[48,48,48,48],maxZoom:6,duration:0});
        document.querySelector("#map-message").hidden=true;
      }
    } catch (error) {
      console.warn("Unable to load national boundaries",error);
    }
  }
  loadNationalOverview();

  const placeRequests = {};
  const placeContinuationQueue = [];
  const queuedPlaceContinuations = new Set();
  const placeLoadVersions = {};
  let isProcessingPlaceContinuation = false;
  const hasAssignedSubdistrict = Boolean(document.querySelector(".direct-subdistrict, .direct-access-area"));
  const currentUserRole=document.querySelector(".dashboard-shell")?.dataset.userRole;
  const placesByCategory = {};
  const allProvincePlacesByCategory = {};
  const categoryLabels = {government:"สถานที่ราชการ",education:"การศึกษา",health:"สาธารณสุข",culture:"ศาสนา/วัฒนธรรม",tourism:"ท่องเที่ยว",transport:"คมนาคม",service:"ร้านค้า/บริการ",emergency:"ความปลอดภัย/ฉุกเฉิน",imported:"สถานที่เพิ่มเติม"};
  const fallbackPopulation = {government:150,education:500,health:120,culture:200,tourism:300,transport:250,service:100,emergency:80};
  let selectedAreaGeometry=null, selectedAreaCode=null, selectedAreaCenter=null, selectedProvinceId=null, selectedDistrictCode=null, selectedSubdistrictId=null;
  let currentLocation, currentLocationPromise;
  const escapeHtml = value => String(value || "").replace(/[&<>'"]/g, char => ({"&":"&amp;","<":"&lt;",">":"&gt;","'":"&#39;",'"':"&quot;"})[char]);
  const areaSelectToggle=document.querySelector("#area-select-toggle");
  const areaSelectCard=document.querySelector("#area-select-card");
  const areaSelectDistance=document.querySelector("#area-select-distance");
  const areaSelectDistanceLabel=document.querySelector("#area-select-distance-label");
  const areaSelectHint=document.querySelector("#area-select-hint");
  const areaSelectResult=document.querySelector("#area-select-result");
  const areaSelectClear=document.querySelector("#area-select-clear");
  if(areaSelectDistanceLabel?.firstChild) areaSelectDistanceLabel.firstChild.textContent="ระยะขยาย";
  let areaSelectDistanceField;
  const areaSelectionSettings=document.createElement("section");
  areaSelectionSettings.id="area-selection-settings";
  areaSelectionSettings.className="summary-card area-selection-settings";
  areaSelectionSettings.hidden=true;
  areaSelectionSettings.innerHTML='<div class="area-selection-settings-heading"><div><h2>เลือกพื้นที่</h2><p class="card-caption">กำหนดระยะและเลือกขอบเขตบนแผนที่</p></div></div><p id="area-select-status" class="area-select-status">ยังไม่ได้เลือกพื้นที่</p><div id="area-select-place-result" class="area-select-place-result"></div>';
  const analysisSaveButton=document.createElement("button");
  analysisSaveButton.type="button"; analysisSaveButton.className="analysis-save-button"; analysisSaveButton.textContent="บันทึกข้อมูลการวิเคราะห์"; analysisSaveButton.disabled=true;
  const analysisActionBar=document.createElement("div");
  analysisActionBar.className="analysis-action-bar";
  analysisActionBar.append(analysisSaveButton);
  document.querySelector("#overview")?.prepend(areaSelectionSettings);
  const areaSelectStatus=areaSelectionSettings.querySelector("#area-select-status");
  const areaSelectDistanceValue=document.createElement("output");
  areaSelectDistanceValue.id="area-select-distance-value";
  areaSelectResult?.remove();
  if(areaSelectDistance){
    areaSelectDistance.type="range";
    areaSelectDistance.min="0";
    areaSelectDistance.max="10000";
    areaSelectDistance.step="10";
    areaSelectDistance.value="1000";
    areaSelectDistanceValue.textContent=`${Number(areaSelectDistance.value).toLocaleString()} เมตร`;
    const rangeControl=document.createElement("span");
    rangeControl.className="area-select-range-control";
    const rangeMinimum=document.createElement("span");
    rangeMinimum.className="area-select-range-minimum";
    const rangeTrack=document.createElement("span");
    rangeTrack.className="area-select-range-track";
    const rangeFill=document.createElement("i");
    rangeFill.className="area-select-range-fill";
    rangeTrack.append(rangeFill);
    const rangeHandle=document.createElement("i");
    rangeHandle.className="area-select-range-handle";
    rangeControl.append(rangeMinimum,rangeTrack,rangeHandle,areaSelectDistance,areaSelectDistanceValue);
    areaSelectDistanceLabel?.append(rangeControl);
  }
  if(areaSelectDistanceLabel){
    const rangeControl=areaSelectDistance.closest(".area-select-range-control");
    areaSelectDistanceField=document.createElement("div");
    areaSelectDistanceField.className="area-select-distance-field";
    areaSelectDistanceField.innerHTML="<b>ระยะขยาย</b>";
    if(rangeControl) areaSelectDistanceField.append(rangeControl);
    areaSelectDistanceLabel.remove();
    areaSelectionSettings.querySelector(".area-selection-settings-heading")?.after(areaSelectDistanceField);
    areaSelectDistanceField.hidden=true;
  }
  areaSelectHint?.remove();
  if(areaSelectClear) areaSelectionSettings.insertBefore(areaSelectClear,areaSelectionSettings.querySelector("#area-select-place-result"));
  if(areaSelectToggle){
    areaSelectToggle.className="area-select-floating";
    areaSelectToggle.title="เลือกพื้นที่";
    areaSelectToggle.innerHTML='<span class="material-symbols-outlined">near_me</span>';
    document.querySelector(".map-wrap")?.append(areaSelectToggle);
  }
  if(document.querySelector(".page-analysis")){
    const mapWrap=document.querySelector(".map-wrap"), panel=document.querySelector("#overview"), layerHeading=panel?.querySelector(".layer-panel-heading"), layerList=panel?.querySelector(".layer-list"), floodPanel=document.querySelector("#flood-simulator");
    const layerOverlay=document.createElement("section"); layerOverlay.className="map-layer-overlay"; layerOverlay.innerHTML="<button type=\"button\">ชั้นข้อมูลบนแผนที่</button><div></div>";
    layerOverlay.querySelector("div").append(layerHeading,layerList); mapWrap?.append(layerOverlay);
    const tabs=document.createElement("nav"); tabs.className="analysis-workspace-tabs";tabs.innerHTML="<button class=\"active\" data-analysis-tab=\"analysis\">วิเคราะห์พื้นที่</button><button data-analysis-tab=\"flood\">จำลองน้ำท่วม</button>";panel?.prepend(tabs);
    const analysisContent=document.createElement("div");analysisContent.className="analysis-tab-content active";if(areaSelectCard){areaSelectCard.hidden=false;areaSelectCard.classList.add("analysis-draw-tools");areaSelectionSettings.prepend(areaSelectCard);}analysisContent.append(areaSelectionSettings,analysisActionBar); const floodContent=document.createElement("div");floodContent.className="analysis-tab-content";floodContent.append(floodPanel);panel?.append(analysisContent,floodContent);
    tabs.querySelectorAll("button").forEach(button=>button.addEventListener("click",()=>{const flood=button.dataset.analysisTab==="flood";activeAnalysisTab=flood ? "flood" : "analysis";if(flood) floodContent.append(analysisActionBar); else analysisContent.append(analysisActionBar);tabs.querySelectorAll("button").forEach(x=>x.classList.toggle("active",x===button));analysisContent.classList.toggle("active",!flood);floodContent.classList.toggle("active",flood);updateAnalysisSaveAction()}));
  }
  let activeAnalysisTab="analysis";
  let areaSelectionToolActive=false, areaSelectionMode=null, areaSelectionGeometry=null, areaSelectionAnchor=null, areaSelectionLine=null, areaSelectionDraw;
  document.querySelectorAll("[data-area-select-mode]").forEach(button=>button.classList.remove("active"));

  function areaSelectionDistance() {
    const minimum=Math.max(0,Number(areaSelectDistance?.min) || 0);
    const maximum=Math.max(minimum,Number(areaSelectDistance?.max) || 10000);
    return Math.max(minimum,Math.min(maximum,Number(areaSelectDistance?.value) || minimum));
  }
  function updateAreaSelectionRangeVisual() {
    const minimum=Number(areaSelectDistance.min), maximum=Number(areaSelectDistance.max), current=areaSelectionDistance();
    const percentage=maximum===minimum ? 0 : ((current-minimum)/(maximum-minimum))*100;
    const rangeControl=areaSelectDistance.closest(".area-select-range-control");
    const rangeMinimum=rangeControl?.querySelector(".area-select-range-minimum");
    const rangeFill=rangeControl?.querySelector(".area-select-range-fill");
    const rangeHandle=rangeControl?.querySelector(".area-select-range-handle");
    if(rangeMinimum) rangeMinimum.textContent=`${minimum.toLocaleString()} ม.`;
    rangeControl?.style.setProperty("--area-select-progress",`${percentage}%`);
    if(rangeFill) rangeFill.style.width=`${percentage}%`;
    if(rangeHandle) rangeHandle.style.left=`${percentage}%`;
    areaSelectDistanceValue.style.left=`${percentage}%`;
  }
  function bufferedLineGeometry(line,distance) {
    const coordinates=line.getCoordinates();
    if(coordinates.length<2) return null;
    const left=[], right=[];
    coordinates.forEach((coordinate,index)=>{
      const previous=coordinates[Math.max(0,index-1)], next=coordinates[Math.min(coordinates.length-1,index+1)];
      const dx=next[0]-previous[0], dy=next[1]-previous[1], length=Math.hypot(dx,dy) || 1;
      const x=-dy/length*distance, y=dx/length*distance;
      left.push([coordinate[0]+x,coordinate[1]+y]); right.push([coordinate[0]-x,coordinate[1]-y]);
    });
    return new ol.geom.Polygon([[...left,...right.reverse(),left[0]]]);
  }
  function expandedLineSelectionGeometry(line,distance) {
    const coordinates=line.getCoordinates(), parts=[];
    coordinates.forEach(coordinate=>parts.push(new ol.geom.Circle(coordinate,distance)));
    for(let index=1;index<coordinates.length;index+=1) {
      const segment=bufferedLineGeometry(new ol.geom.LineString([coordinates[index-1],coordinates[index]]),distance);
      if(segment) parts.push(segment);
    }
    return new ol.geom.GeometryCollection(parts);
  }
  function selectedPlacesInArea() {
    if(!areaSelectionFilterGeometry) return [];
    const seen=new Set();
    return Object.values(allProvincePlacesByCategory).flat().filter(place=>{
      const key=`${place.category || "place"}:${place.id || `${place.lon}/${place.lat}/${place.name}`}`;
      if(seen.has(key) || !Number.isFinite(Number(place.lon)) || !Number.isFinite(Number(place.lat))) return false;
      seen.add(key);
      return areaSelectionFilterGeometry.intersectsCoordinate(ol.proj.fromLonLat([Number(place.lon),Number(place.lat)]));
    });
  }
  function renderAreaSelectionResult() {
    const result=areaSelectionSettings.querySelector("#area-select-place-result");
    if(!areaSelectionGeometry) { areaSelectStatus.textContent="ยังไม่ได้เลือกพื้นที่"; updateAnalysisSaveAction(); if(result) result.replaceChildren(); return; }
    const places=selectedPlacesInArea();
    areaSelectStatus.textContent=`เลือกพื้นที่แล้ว · พบ ${places.length.toLocaleString()} สถานที่จากหมวดที่เปิดแสดง`;
    const byCategory=places.reduce((groups,place)=>{(groups[place.category] ||= []).push(place);return groups;},{});
    if(result) result.innerHTML=places.length ? Object.entries(byCategory).map(([category,items])=>`<details><summary><span><i class="material-symbols-outlined">${escapeHtml(placeConfig[category]?.icon || "location_on")}</i>${escapeHtml(categoryLabels[category] || category)}</span><b>${items.length} แห่ง</b></summary>${items.map(place=>`<p>${escapeHtml(place.name)}</p>`).join("")}</details>`).join("") : '<p>ไม่พบสถานที่จากหมวดที่เปิดแสดงภายในพื้นที่นี้</p>';
    updateAnalysisSaveAction();
  }
  function updateAnalysisSaveAction() {
    const floodTab=activeAnalysisTab==="flood";
    analysisSaveButton.textContent=floodTab ? "บันทึกข้อมูลการจำลองน้ำท่วม" : "บันทึกข้อมูลการวิเคราะห์";
    analysisSaveButton.disabled=floodTab ? !lastFloodAnalysis : !areaSelectionGeometry;
  }
  analysisSaveButton.addEventListener("click",async()=>{
    const floodTab=activeAnalysisTab==="flood";
    if(floodTab && !lastFloodAnalysis) return;
    if(!floodTab && !areaSelectionGeometry) return;
    const places=floodTab ? [] : selectedPlacesInArea();
    const summary=floodTab ? lastFloodAnalysis.summary : {place_count:places.length,by_category:places.reduce((groups,place)=>{groups[place.category]=(groups[place.category]||0)+1;return groups;},{})};
    const geometry=floodTab ? lastFloodAnalysis.geometry : new ol.format.GeoJSON().writeGeometryObject(areaSelectionGeometry,{featureProjection:"EPSG:3857",dataProjection:"EPSG:4326"});
    analysisSaveButton.disabled=true; analysisSaveButton.textContent="กำลังบันทึก…";
    try{
      const response=await fetch("/api/analysis_records",{method:"POST",headers:{"Content-Type":"application/json","X-CSRF-Token":document.querySelector('meta[name="csrf-token"]')?.content,Accept:"application/json"},body:JSON.stringify({analysis_record:{name:`${floodTab ? "จำลองน้ำท่วม" : "วิเคราะห์พื้นที่"} ${new Date().toLocaleString("th-TH",{timeZone:"Asia/Bangkok"})}`,selection_type:floodTab ? "flood" : (areaSelectionMode||"point"),geometry,summary,places:places.map(({id,name,category,lon,lat,address})=>({id,name,category,lon,lat,address}))}})});
      if(!response.ok) throw new Error("ไม่สามารถบันทึกข้อมูลได้");
      analysisSaveButton.textContent="บันทึกแล้ว";
      window.setTimeout(updateAnalysisSaveAction,1500);
    }catch(error){analysisSaveButton.textContent="บันทึกไม่สำเร็จ";window.setTimeout(updateAnalysisSaveAction,1500);}
  });
  function areaSelectionMaskGeometry(geometry) {
    if(!geometry) return null;
    const selection=geometry.getType()==="Circle" ? ol.geom.Polygon.fromCircle(geometry,96) : geometry;
    if(selection.getType()!=="Polygon") return null;
    const inner=selection.getCoordinates()[0];
    if(!inner?.length) return null;
    const edge=20037508.34;
    const outer=[[-edge,-edge],[-edge,edge],[edge,edge],[edge,-edge],[-edge,-edge]];
    return new ol.geom.Polygon([outer,[...inner].reverse()]);
  }
  function setAreaSelection(geometry,anchor=null,endpoints=[],filterGeometry=geometry) {
    areaSelectionGeometry=geometry; areaSelectionFilterGeometry=filterGeometry; areaSelectionAnchor=anchor;
    const source=areaSelectionLayer.getSource(); source.clear();
    const dimSource=areaSelectionDimLayer.getSource(); dimSource.clear();
    const endpointSource=areaSelectionEndpointsLayer.getSource(); endpointSource.clear();
    if(geometry) source.addFeature(new ol.Feature({geometry}));
    endpoints.forEach(coordinate=>endpointSource.addFeature(new ol.Feature({geometry:new ol.geom.Point(coordinate)})));
    Object.values(placeLayers).forEach(layer=>layer.changed());
    importedPlacesLayer.changed();
    areaSelectClear.disabled=!geometry;
    renderImportantPlaces();
  }
  function removeAreaSelectionDraw() {
    if(areaSelectionDraw) { map.removeInteraction(areaSelectionDraw); areaSelectionDraw=null; }
  }
  function beginAreaSelectionDraw() {
    removeAreaSelectionDraw();
    if(!areaSelectionToolActive || areaSelectionMode==="point") return;
    areaSelectionDraw=new ol.interaction.Draw({source:new ol.source.Vector(),type:areaSelectionMode==="line" ? "LineString" : "Polygon"});
    areaSelectionDraw.on("drawstart",()=>{areaSelectionLayer.getSource().clear();});
    areaSelectionDraw.on("drawend",event=>{
      areaSelectionLine=areaSelectionMode==="line" ? event.feature.getGeometry() : null;
      const geometry=areaSelectionMode==="line" ? bufferedLineGeometry(areaSelectionLine,areaSelectionDistance()) : event.feature.getGeometry();
      const filterGeometry=areaSelectionMode==="line" ? expandedLineSelectionGeometry(areaSelectionLine,areaSelectionDistance()) : geometry;
      const lineCoordinates=areaSelectionLine?.getCoordinates();
      if(geometry) setAreaSelection(geometry,null,lineCoordinates ? [lineCoordinates[0],lineCoordinates.at(-1)] : [],filterGeometry);
      beginAreaSelectionDraw();
    });
    map.addInteraction(areaSelectionDraw);
  }
  function updateAreaSelectionMode(mode) {
    areaSelectionMode=mode;
    document.querySelectorAll("[data-area-select-mode]").forEach(button=>button.classList.toggle("active",button.dataset.areaSelectMode===mode));
    const needsDistance=mode!=="polygon";
    if(areaSelectDistanceField) areaSelectDistanceField.hidden=!needsDistance;
    areaSelectionLine=null; setAreaSelection(null); beginAreaSelectionDraw();
  }
  function setAreaSelectionTool(active) {
    areaSelectionToolActive=active;
    areaSelectToggle?.setAttribute("aria-pressed",String(active));
    areaSelectToggle?.classList.toggle("active",active);
    if(areaSelectCard) areaSelectCard.hidden=!active;
    if(!active) { areaSelectionSettings.hidden=true; areaSelectionLine=null; setAreaSelection(null); removeAreaSelectionDraw(); map.getTargetElement().style.cursor=""; }
    else { areaSelectionSettings.hidden=false; updateAreaSelectionRangeVisual(); }
  }
  areaSelectToggle?.addEventListener("click",()=>{
    if(cesiumMode) { document.querySelector("#map-message").textContent="เครื่องมือเลือกพื้นที่ใช้งานบนแผนที่ 2D"; return; }
    if(areaSelectionToolActive) { setAreaSelectionTool(false); return; }
    setAreaSelectionTool(true);
  });
  document.querySelector("#area-select-close")?.remove();
  document.querySelector("#area-select-close")?.addEventListener("click",()=>setAreaSelectionTool(false));
  document.querySelectorAll("[data-area-select-mode]").forEach(button=>button.addEventListener("click",()=>{
    if(cesiumMode) { document.querySelector("#map-message").textContent="เครื่องมือเลือกพื้นที่ใช้งานบนแผนที่ 2D"; return; }
    setAreaSelectionTool(true);
    updateAreaSelectionMode(button.dataset.areaSelectMode);
    areaSelectCard.hidden=false;
    areaSelectionSettings.hidden=false;
  }));
  areaSelectDistance?.addEventListener("input",()=>{
    areaSelectDistanceValue.textContent=`${areaSelectionDistance().toLocaleString()} เมตร`;
    updateAreaSelectionRangeVisual();
    if(areaSelectionMode==="point" && areaSelectionAnchor) setAreaSelection(new ol.geom.Circle(areaSelectionAnchor,areaSelectionDistance()),areaSelectionAnchor);
    if(areaSelectionMode==="line" && areaSelectionLine){const coordinates=areaSelectionLine.getCoordinates();setAreaSelection(bufferedLineGeometry(areaSelectionLine,areaSelectionDistance()),null,[coordinates[0],coordinates.at(-1)],expandedLineSelectionGeometry(areaSelectionLine,areaSelectionDistance()));}
  });
  areaSelectClear?.addEventListener("click",()=>{areaSelectionLine=null;setAreaSelection(null);});
  const placeControls=document.querySelector(".place-controls"), overviewPanel=document.querySelector("#overview");
  placeControls?.querySelector('[data-place-category="utility"]')?.remove();
  const mapToolbar=document.querySelector(".map-toolbar");
  const toolbarActions=mapToolbar?.querySelector(".map-toolbar-actions");
  if(placeControls && mapToolbar) mapToolbar.insertBefore(placeControls,toolbarActions || null);
  let fullPlaceControlsWidth=0;
  const updatePlaceControlDensity=()=>{
    if(!placeControls) return;
    if(!fullPlaceControlsWidth){
      const buttons=[...placeControls.querySelectorAll("button")];
      const gap=Number.parseFloat(getComputedStyle(placeControls).gap) || 0;
      fullPlaceControlsWidth=buttons.reduce((total,button)=>total+button.getBoundingClientRect().width,0)+Math.max(0,buttons.length-1)*gap;
    }
    const availableWidth=placeControls.clientWidth;
    const isIconsOnly=placeControls.classList.contains("icons-only");
    // Keep a small buffer before restoring labels.  Without it, a toolbar
    // sitting exactly on its breakpoint can alternate between two widths.
    if(isIconsOnly){
      if(availableWidth >= fullPlaceControlsWidth + 40) placeControls.classList.remove("icons-only");
    }else if(fullPlaceControlsWidth > availableWidth){
      placeControls.classList.add("icons-only");
    }
    requestAnimationFrame(()=>placeControls.classList.toggle("is-scrollable",placeControls.scrollWidth > placeControls.clientWidth + 1));
  };
  if(placeControls && mapToolbar){
    requestAnimationFrame(updatePlaceControlDensity);
    if(window.ResizeObserver) new ResizeObserver(updatePlaceControlDensity).observe(mapToolbar);
    let dragStartX=0, dragStartScroll=0, pointerIsDown=false, isDraggingControls=false, suppressPlaceControlClick=false;
    placeControls.addEventListener("pointerdown",event=>{
      if(event.pointerType !== "mouse" || !placeControls.classList.contains("is-scrollable")) return;
      pointerIsDown=true;
      isDraggingControls=false;
      dragStartX=event.clientX;
      dragStartScroll=placeControls.scrollLeft;
      placeControls.setPointerCapture?.(event.pointerId);
    });
    placeControls.addEventListener("pointermove",event=>{
      if(!pointerIsDown) return;
      if(!isDraggingControls && Math.abs(event.clientX-dragStartX)<5) return;
      isDraggingControls=true;
      placeControls.classList.add("is-dragging");
      placeControls.scrollLeft=dragStartScroll-(event.clientX-dragStartX);
    });
    const stopPlaceControlDrag=()=>{
      suppressPlaceControlClick=isDraggingControls;
      pointerIsDown=false;
      isDraggingControls=false;
      placeControls.classList.remove("is-dragging");
      if(suppressPlaceControlClick) window.setTimeout(()=>{suppressPlaceControlClick=false;},0);
    };
    placeControls.addEventListener("pointerup",stopPlaceControlDrag);
    placeControls.addEventListener("pointercancel",stopPlaceControlDrag);
    placeControls.addEventListener("click",event=>{
      if(!suppressPlaceControlClick) return;
      event.preventDefault();
      event.stopPropagation();
      suppressPlaceControlClick=false;
    },true);
  }
  overviewPanel?.querySelector(".place-category-summary")?.remove();
  overviewPanel?.querySelectorAll(".legacy-overview-card").forEach(card=>card.remove());
  const analysisTabContent=document.querySelector(".page-analysis .analysis-tab-content");
  if(analysisTabContent) {
    analysisTabContent.append(areaSelectionSettings);
    areaSelectionSettings.after(analysisActionBar);
  }
  else overviewPanel?.prepend(areaSelectionSettings);
  document.querySelectorAll("[data-place-category]").forEach(button=>{const label=categoryLabels?.[button.dataset.placeCategory] || button.textContent.trim();button.setAttribute("aria-label",label);button.setAttribute("title",label);});
  function updatePlaceCategorySummary() {
    const areaSummary=document.querySelector(".area-summary");
    if(areaSummary){
      const scopeName=areaSummary.dataset.scopeName || areaSummary.querySelector(".card-caption")?.textContent?.trim() || "พื้นที่ที่ดูแล";
      areaSummary.dataset.scopeName=scopeName;
      const rows=Object.keys(placeConfig).map(category=>`<div class="summary-row"><span>${escapeHtml(categoryLabels[category] || category)}</span><b id="place-summary-${category}">${(placesByCategory[category] || []).length.toLocaleString()} แห่ง</b></div>`).join("");
      const total=Object.values(placesByCategory).flat().length;
      areaSummary.innerHTML=`<h2>สรุปข้อมูลจาก Longdo Map</h2><p class="card-caption">สถานที่ภายในขอบเขต <b>${escapeHtml(scopeName)}</b></p><div class="summary-row place-total"><span>สถานที่ทั้งหมด</span><b id="place-summary-total">${total.toLocaleString()} แห่ง</b></div>${rows}`;
    }
    Object.keys(placeConfig).forEach(category => {
      const element=document.querySelector(`#place-summary-${category}`);
      if (element) element.textContent=`${(placesByCategory[category] || []).length.toLocaleString()} แห่ง`;
    });
    const totalElement=document.querySelector("#place-summary-total");
    if (totalElement) totalElement.textContent=`${Object.values(placesByCategory).flat().length.toLocaleString()} แห่ง`;
  }
  function renderProvincePlaceTree() {
    const tree=document.querySelector("#place-detail-tree");
    if(!tree) return;
    const activeCategories=Object.keys(placeConfig).filter(category=>document.querySelector(`[data-place-category="${category}"]`)?.getAttribute("aria-pressed")==="true");
    tree.innerHTML=activeCategories.length ? activeCategories.map(category=>{
      const categoryPlaces=allProvincePlacesByCategory[category] || [];
      return `<details class="place-tree-category"><summary><span>${escapeHtml(categoryLabels[category])}</span><b>${categoryPlaces.length} แห่ง</b></summary>${categoryPlaces.length ? categoryPlaces.map(place=>`<article class="place-tree-item"><strong>${escapeHtml(place.name)}</strong><small>${escapeHtml(place.address || "ไม่ระบุที่อยู่")}</small></article>`).join("") : '<p class="place-tree-empty">ไม่พบสถานที่ในหมวดนี้</p>'}</details>`;
    }).join("") : '<p>เลือกไอคอนหมวดหมู่เพื่อดูรายละเอียดสถานที่</p>';
  }
  function renderImportantPlaces() {
    updatePlaceCategorySummary();
    const wrap = document.querySelector(".place-table-wrap");
    const body = document.querySelector("#important-places-body");
    const places = Object.values(placesByCategory).flat().sort((a,b) => String(a.name).localeCompare(String(b.name),"th"));
    if (wrap && body) {
      wrap.hidden = places.length === 0;
      body.innerHTML = places.map(place => {
        const estimate = Number(place.estimated_population || fallbackPopulation[place.category] || 0);
        const people = estimate > 0 ? `ประมาณ ${estimate.toLocaleString()} คน` : "ไม่ระบุ";
        return `<tr><td><b>${escapeHtml(place.name)}</b>${place.address ? `<small>${escapeHtml(place.address)}</small>` : ""}</td><td><span class="place-category-tag ${escapeHtml(place.category)}">${escapeHtml(categoryLabels[place.category] || place.category)}</span></td><td>${people}</td></tr>`;
      }).join("");
    }
    const tree=document.querySelector("#place-detail-tree");
    if(tree){const activeCategories=Object.keys(placeConfig).filter(category=>document.querySelector(`[data-place-category="${category}"]`)?.getAttribute("aria-pressed")==="true");tree.innerHTML=activeCategories.length ? activeCategories.map(category=>{const categoryPlaces=placesByCategory[category]||[];return `<details class="place-tree-category"><summary><span>${escapeHtml(categoryLabels[category])}</span><b>${categoryPlaces.length} แห่ง</b></summary>${categoryPlaces.length ? categoryPlaces.map(place=>`<article class="place-tree-item"><strong>${escapeHtml(place.name)}</strong><small>${escapeHtml(place.address || "ไม่ระบุที่อยู่")}</small><small>ประมาณ ${Number(place.estimated_population||0).toLocaleString()} คน${place.tel ? ` · ${escapeHtml(place.tel)}` : ""}</small></article>`).join("") : '<p class="place-tree-empty">ไม่พบสถานที่ในหมวดนี้</p>'}</details>`}).join("") : '<p>เลือกไอคอนหมวดหมู่เพื่อดูรายละเอียดสถานที่</p>';}
    renderProvincePlaceTree();
    renderAreaSelectionResult();
    syncCesiumPlaces();
  }
  const waterStationsToggle=document.querySelector(".layer-dot.water")?.closest("label")?.querySelector("input");
  const waterStationsRow=waterStationsToggle?.closest("label");
  const waterStationsCount=waterStationsRow?.querySelector("small");
  if(waterStationsToggle){
    waterStationsToggle.disabled=false;
    waterStationsToggle.checked=true;
    waterStationsRow.querySelector("b").textContent="สถานีวัดน้ำและฝน";
    waterStationsToggle.addEventListener("change",()=>waterStationLayer.setVisible(waterStationsToggle.checked));
  }
  async function loadWaterStations() {
    if(!waterStationsToggle) return;
    waterStationsCount.textContent="กำลังโหลด…";
    try {
      const response=await fetch("/api/water_stations",{headers:{Accept:"application/json"}});
      if(!response.ok) throw new Error(response.status);
      const stations=await response.json();
      const visibleStations=stations.filter(station=>!selectedAreaGeometry || selectedAreaGeometry.intersectsCoordinate(ol.proj.fromLonLat([Number(station.lon),Number(station.lat)])));
      const source=waterStationLayer.getSource();
      source.clear();
      visibleStations.forEach(station=>source.addFeature(new ol.Feature({geometry:new ol.geom.Point(ol.proj.fromLonLat([station.lon,station.lat])),water_station:station})));
      waterStationLayer.setVisible(waterStationsToggle.checked);
      waterStationsCount.textContent=`${visibleStations.length.toLocaleString()} สถานี`;
    } catch (error) {
      waterStationsCount.textContent="โหลดไม่สำเร็จ";
      console.warn("Unable to load DWR water stations",error);
    }
  }
  loadWaterStations();
  async function loadImportedPlaces() {
    try {
      const response=await fetch("/api/dynamic_layers?layer_key=important_place",{headers:{Accept:"application/json"}});
      if(!response.ok)throw new Error(response.status);
      const records=await response.json();
      const places=records.filter(record=>Array.isArray(record.location) && record.location.length>=2).map(record=>({
        id:record._id,name:record.name,lon:Number(record.location[0]),lat:Number(record.location[1]),
        category:record.payload?.category || "สถานที่เพิ่มเติม",estimated_population:record.payload?.estimated_population,
        address:record.payload?.category ? `ประเภท: ${record.payload.category}` : ""
      })).filter(place=>Number.isFinite(place.lon) && Number.isFinite(place.lat) && (!selectedAreaGeometry || selectedAreaGeometry.intersectsCoordinate(ol.proj.fromLonLat([place.lon,place.lat]))));
      importedPlacesLayer.getSource().clear();
      places.forEach(place=>importedPlacesLayer.getSource().addFeature(new ol.Feature({geometry:new ol.geom.Point(ol.proj.fromLonLat([place.lon,place.lat])),place})));
      placesByCategory.imported=places;
      renderImportantPlaces();
    } catch (error) {
      console.warn("Unable to load imported places",error);
    }
  }
  const searchSpan = () => {
    const zoom = map.getView().getZoom() || 6;
    if (zoom < 7) return "300km";
    if (zoom < 9) return "120km";
    if (zoom < 11) return "50km";
    if (zoom < 13) return "20km";
    return "8km";
  };

  async function loadLongdoUsage() {
    const element=document.querySelector("#longdo-usage");
    try {
      const stats=await fetch("/api/places/usage",{headers:{Accept:"application/json"}}).then(response=>{if(!response.ok)throw new Error(response.status);return response.json()});
      element.innerHTML=`<b>Longdo API</b><span>เรียกจริง ${stats.longdo_requests.toLocaleString()} ครั้ง · Cache ${stats.cache_hits.toLocaleString()} ครั้ง</span>`;
    } catch (_) {
      element.innerHTML="<b>Longdo API</b><span>ไม่สามารถโหลดสถิติ</span>";
    }
  }
  loadLongdoUsage();

  async function placeSearchLocation(focusZoom=13) {
    if(selectedAreaCenter)return selectedAreaCenter;
    // Local accounts are always scoped to their assigned subdistrict.  Do not
    // start a competing browser-geolocation request while its boundary loads.
    if(hasAssignedSubdistrict && currentUserRole !== "system_admin") return ol.proj.toLonLat(map.getView().getCenter());
    if(currentLocation)return currentLocation;
    if(!currentLocationPromise){
      currentLocationPromise=new Promise(resolve=>{
        if(!navigator.geolocation){resolve(null);return;}
        navigator.geolocation.getCurrentPosition(
          position=>resolve([position.coords.longitude,position.coords.latitude]),
          ()=>resolve(null),
          {enableHighAccuracy:true,timeout:8000,maximumAge:300000}
        );
      }).then(location=>{
        currentLocation=location;
        if(location)map.getView().animate({center:ol.proj.fromLonLat(location),zoom:Math.max(map.getView().getZoom(),focusZoom),duration:600});
        return location;
      });
    }
    return (await currentLocationPromise) || ol.proj.toLonLat(map.getView().getCenter());
  }

  async function loadPlaces(category) {
    const button = document.querySelector(`[data-place-category="${category}"]`);
    const count = document.querySelector(`[data-place-count="${category}"]`);
    const source = placeLayers[category].getSource();
    const loadVersion=(placeLoadVersions[category] || 0) + 1;
    placeLoadVersions[category]=loadVersion;
    if (button.getAttribute("aria-pressed") !== "true") return;

    placeRequests[category]?.abort();
    placeRequests[category] = new AbortController();
    count.textContent="กำลังโหลด…";
    const [lon,lat] = await placeSearchLocation();
    try {
      const query = new URLSearchParams({category,lon:lon.toFixed(6),lat:lat.toFixed(6),span:searchSpan()});
      if(selectedProvinceId) query.set("province_id",selectedProvinceId);
      if(selectedAreaCode)query.set("area",selectedAreaCode);
      const response = await fetch(`/api/places?${query}`,{headers:{Accept:"application/json"},signal:placeRequests[category].signal});
      const responseText = await response.text();
      let payload;
      try { payload = JSON.parse(responseText); }
      catch (_) { throw new Error(response.ok ? "ข้อมูลสถานที่จากเซิร์ฟเวอร์ไม่ถูกต้อง" : `โหลดสถานที่ไม่สำเร็จ (HTTP ${response.status})`); }
      if (!response.ok) throw new Error(payload.error || `HTTP ${response.status}`);
      if(button.getAttribute("aria-pressed") !== "true" || placeLoadVersions[category] !== loadVersion) return;
      updateCategoryPlaces(category,payload.data);
      count.textContent=placeLoadStatus(payload,(placesByCategory[category] || []).length);
      if(placeLoadIsIncomplete(payload)) queuePlaceContinuation(category,query,loadVersion,placeRetryDelay(payload));
      loadLongdoUsage();
      document.querySelector("#map-message").classList.remove("error");
    } catch (error) {
      if (error.name === "AbortError") return;
      source.clear(); delete placesByCategory[category]; delete allProvincePlacesByCategory[category]; renderImportantPlaces(); count.textContent="โหลดไม่สำเร็จ";
      const message = document.querySelector("#map-message");
      message.textContent=error.message; message.classList.add("error");
    }
  }

  function setPlaceCategoryVisibility(category, visible) {
    const button=document.querySelector(`[data-place-category="${category}"]`);
    const count=document.querySelector(`[data-place-count="${category}"]`);
    const layer=placeLayers[category];
    if(!button || !layer) return;

    button.setAttribute("aria-pressed",String(visible));
    const label=categoryLabels[category] || category;
    button.setAttribute("aria-label",`${label} · ${visible ? "กำลังแสดง" : "ไม่แสดง"}`);
    button.title=`${label} · ${visible ? "กำลังแสดง" : "ไม่แสดง"}`;

    if(visible) {
      layer.setVisible(true);
      loadPlaces(category);
      return;
    }

    placeLoadVersions[category]=(placeLoadVersions[category] || 0)+1;
    placeRequests[category]?.abort();
    queuedPlaceContinuations.delete(category);
    layer.getSource().clear();
    layer.setVisible(false);
    delete placesByCategory[category];
    delete allProvincePlacesByCategory[category];
    if(count) count.textContent="ไม่แสดง";
    renderImportantPlaces();
  }

  function placeLoadIsIncomplete(payload) {
    return payload.meta?.pagination?.complete === false;
  }

  function placeRetryDelay(payload) {
    const retrySeconds=Number(payload.meta?.pagination?.retry_after_seconds || 0);
    return retrySeconds > 0 ? retrySeconds * 1000 : 2000;
  }

  function placeLoadStatus(payload, count) {
    return payload.meta?.pagination?.retry_after_seconds
      ? `${count} แห่ง · กำลังรอเชื่อมต่อ Longdo…`
      : (placeLoadIsIncomplete(payload) ? `${count} แห่ง · กำลังทยอยโหลด…` : `${count} แห่ง`);
  }

  function updateCategoryPlaces(category, places) {
    const source=placeLayers[category].getSource();
    const visiblePlaces=places.filter(place=>{
      if(!selectedAreaGeometry)return true;
      return selectedAreaGeometry.intersectsCoordinate(ol.proj.fromLonLat([Number(place.lon),Number(place.lat)]));
    });
    source.clear();
    visiblePlaces.forEach(place=>source.addFeature(new ol.Feature({geometry:new ol.geom.Point(ol.proj.fromLonLat([Number(place.lon),Number(place.lat)])),place})));
    allProvincePlacesByCategory[category]=places;
    placesByCategory[category]=visiblePlaces;
    renderImportantPlaces();
  }

  function queuePlaceContinuation(category, baseQuery, loadVersion, delay=2000) {
    if(queuedPlaceContinuations.has(category)) return;
    queuedPlaceContinuations.add(category);
    placeContinuationQueue.push({category,query:new URLSearchParams(baseQuery),loadVersion,delay});
    processPlaceContinuationQueue();
  }

  function processPlaceContinuationQueue() {
    if(isProcessingPlaceContinuation || !placeContinuationQueue.length) return;
    isProcessingPlaceContinuation=true;
    const next=placeContinuationQueue.shift();
    queuedPlaceContinuations.delete(next.category);
    window.setTimeout(async()=>{
      const button=document.querySelector(`[data-place-category="${next.category}"]`);
      const count=document.querySelector(`[data-place-count="${next.category}"]`);
      if(!button || button.getAttribute("aria-pressed") !== "true" || placeLoadVersions[next.category] !== next.loadVersion) {
        isProcessingPlaceContinuation=false;
        processPlaceContinuationQueue();
        return;
      }
      const controller=new AbortController();
      placeRequests[next.category]=controller;
      next.query.set("load_more","1");
      try {
        const response=await fetch(`/api/places?${next.query}`,{headers:{Accept:"application/json"},signal:controller.signal});
        const responseText=await response.text();
        let payload;
        try { payload=JSON.parse(responseText); }
        catch (_) { throw new Error(response.ok ? "ข้อมูลสถานที่จากเซิร์ฟเวอร์ไม่ถูกต้อง" : `โหลดสถานที่ไม่สำเร็จ (HTTP ${response.status})`); }
        if(!response.ok) throw new Error(payload.error || `HTTP ${response.status}`);
        if(button.getAttribute("aria-pressed") !== "true" || placeLoadVersions[next.category] !== next.loadVersion) return;
        updateCategoryPlaces(next.category,payload.data);
        count.textContent=placeLoadStatus(payload,(placesByCategory[next.category] || []).length);
        if(placeLoadIsIncomplete(payload)) queuePlaceContinuation(next.category,next.query,next.loadVersion,placeRetryDelay(payload));
        loadLongdoUsage();
      } catch(error) {
        if(error.name !== "AbortError") console.warn("Unable to load more Longdo places",error);
      } finally {
        isProcessingPlaceContinuation=false;
        processPlaceContinuationQueue();
      }
    },next.delay);
  }

  document.querySelectorAll("[data-place-category]").forEach(button => button.addEventListener("click",() => {
    const category=button.dataset.placeCategory;
    setPlaceCategoryVisibility(category,button.getAttribute("aria-pressed") !== "true");
  }));
  document.querySelectorAll("[data-place-category]").forEach(button => {
    button.setAttribute("aria-pressed","true");
    button.setAttribute("aria-label",`${categoryLabels[button.dataset.placeCategory] || button.textContent.trim()} · กำลังแสดง`);
  });
  let initialPlaceLoadStarted=false;
  const loadInitialPlaceCategories=()=>{
    if(!document.querySelector(".page-overview, .page-map, .page-analysis")) return;
    if(initialPlaceLoadStarted) return;
    initialPlaceLoadStarted=true;
    loadImportedPlaces();
    document.querySelectorAll("[data-place-category]").forEach((button,index) => {
      window.setTimeout(()=>loadPlaces(button.dataset.placeCategory),index*250);
    });
  };
  async function selectCurrentProvinceForSystemAdmin() {
    // Focus immediately at the same maximum zoom used for a province boundary.
    // The province lookup and GeoJSON boundary can continue in the background.
    const location=await placeSearchLocation(10);
    if(!location) {
      document.querySelector("#map-message").textContent="อนุญาตการเข้าถึงตำแหน่งเพื่อแสดงข้อมูลสถานที่ภายในจังหวัดปัจจุบัน";
      return;
    }
    try {
      const query=new URLSearchParams({lon:location[0].toFixed(7),lat:location[1].toFixed(7)});
      const response=await fetch(`/api/subdistricts/locate?${query}`,{headers:{Accept:"application/json"}});
      const result=await response.json();
      if(!response.ok) throw new Error(result.error || `HTTP ${response.status}`);
      const provinceButton=document.querySelector(`.province-button[data-id="${result.province_id}"]`);
      if(!provinceButton) throw new Error("ไม่พบจังหวัดในรายการ");
      await selectFeature(`/api/provinces/${result.province_id}`,result.province_name_th,provinceButton,{initialFocus:true,loadPlaces:false});
      loadImportedPlaces();
      loadInitialPlaceCategories();
    } catch(error) {
      console.warn("Unable to select current province",error);
      document.querySelector("#map-message").textContent="ไม่สามารถระบุจังหวัดจากตำแหน่งปัจจุบันได้";
    }
  }
  if(!hasAssignedSubdistrict) {
    if(currentUserRole !== "system_admin") loadInitialPlaceCategories();
  }
  map.on("singleclick", event => {
    if(areaSelectionToolActive && areaSelectionMode==="point") {
      setAreaSelection(new ol.geom.Circle(event.coordinate,areaSelectionDistance()),event.coordinate);
      return;
    }
    if(areaSelectionToolActive) return;
    const feature = map.forEachFeatureAtPixel(event.pixel, item => (item.get("place") || item.get("water_station")) ? item : null);
    const place = feature?.get("place");
    const waterStation=feature?.get("water_station");
    if(waterStation){
      const waterLevel=waterStation.water_level_m_msl == null ? "ไม่มีข้อมูล" : `${Number(waterStation.water_level_m_msl).toFixed(2)} ม.รทก.`;
      const rainfall=waterStation.rainfall_value == null ? "ไม่มีข้อมูล" : `${Number(waterStation.rainfall_value).toFixed(1)} มม.`;
      popupElement.innerHTML=`<strong>${escapeHtml(waterStation.name)}</strong><p>ระดับน้ำ: ${waterLevel}</p><p>ปริมาณฝน: ${rainfall}</p>${waterStation.code ? `<p>รหัสสถานี: ${escapeHtml(waterStation.code)}</p>` : ""}`;
      popupElement.hidden=false; popup.setPosition(feature.getGeometry().getCoordinates());
      return;
    }
    if (!place) {
      popupElement.hidden=true; popup.setPosition(undefined);
      if (currentUserRole === "subdistrict_admin") return;
      const subdistrict = map.forEachFeatureAtPixel(event.pixel,item => item,{
        layerFilter:layer => layer === siblingBoundaries
      });
      selectSubdistrictAtCoordinate(event.coordinate);
      return;
    }
    const safeUrl = /^https?:\/\//i.test(place.url || "") ? place.url : null;
    popupElement.innerHTML=`<strong>${escapeHtml(place.name)}</strong>${place.address ? `<p>${escapeHtml(place.address)}</p>` : ""}${place.tel ? `<p>โทร. ${escapeHtml(place.tel)}</p>` : ""}${safeUrl ? `<a href="${escapeHtml(safeUrl)}" target="_blank" rel="noopener">ดูข้อมูลเพิ่มเติม</a>` : ""}`;
    popupElement.hidden=false; popup.setPosition(feature.getGeometry().getCoordinates());
  });
  map.on("pointermove", event => { map.getTargetElement().style.cursor=areaSelectionToolActive ? "crosshair" : (map.hasFeatureAtPixel(event.pixel) ? "pointer" : ""); });

  let boundaryLoadVersion=0, districtBoundaryLoadVersion=0;
  let locateRequest;
  async function selectNextLayerAtLocation(result) {
    const province=document.querySelector(`.province-button[data-id="${result.province_id}"]`);
    if(!province) throw new Error("ไม่พบจังหวัดในรายการด้านซ้าย");
    const level=selectedFeatureData?.properties?.level;
    if(!selectedProvinceId || String(selectedProvinceId)!==String(result.province_id)){
      await ensureProvinceChildren(province,true);
      await selectFeature(`/api/provinces/${result.province_id}`,result.province_name_th || province.textContent.trim(),province);
      province.scrollIntoView({behavior:"smooth",block:"center"});
      return;
    }
    const children=await ensureProvinceChildren(province,true);
    const district=children.querySelector(`.district-button[data-code="${result.district_code}"]`);
    if(!district) throw new Error("ไม่พบอำเภอในรายการด้านซ้าย");
    if(level==="province" || !selectedDistrictCode || String(selectedDistrictCode)!==String(result.district_code)){
      const box=district.closest(".district"); box?.classList.add("open"); const rows=box?.querySelector(".district-children"); if(rows) rows.hidden=false;
      await selectFeature(`/api/provinces/${result.province_id}/districts/${encodeURIComponent(result.district_code)}`,result.district_name_th || district.textContent.trim(),district,{provinceId:result.province_id,districtCode:result.district_code});
      district.scrollIntoView({behavior:"smooth",block:"center"});
      return;
    }
    const subdistrict=children.querySelector(`[data-subdistrict-id="${result.id}"]`);
    if(!subdistrict) throw new Error("ไม่พบตำบลในรายการด้านซ้าย");
    await selectFeature(`/api/subdistricts/${result.id}`,result.name_th,subdistrict,{provinceId:result.province_id,districtCode:result.district_code,selectedId:result.id});
    subdistrict.scrollIntoView({behavior:"smooth",block:"center"});
  }
  const pauseForLayer=()=>new Promise(resolve=>window.setTimeout(resolve,380));
  async function selectHierarchyAtLocation(result) {
    const direct=document.querySelector(`.direct-subdistrict[data-id="${result.id}"]`);
    if(direct) return selectFeature(`/api/subdistricts/${result.id}`,result.name_th,direct,{provinceId:result.province_id,districtCode:result.district_code,selectedId:result.id});
    const province=document.querySelector(`.province-button[data-id="${result.province_id}"]`);
    if(!province) throw new Error("ไม่พบจังหวัดในรายการด้านซ้าย");
    const children=await ensureProvinceChildren(province,true);
    await selectFeature(`/api/provinces/${result.province_id}`,result.province_name_th || province.textContent.trim(),province);
    province.scrollIntoView({behavior:"smooth",block:"center"}); await pauseForLayer();
    const district=children.querySelector(`.district-button[data-code="${result.district_code}"]`);
    if(!district) throw new Error("ไม่พบอำเภอในรายการด้านซ้าย");
    const box=district.closest(".district"); box?.classList.add("open"); const rows=box?.querySelector(".district-children"); if(rows) rows.hidden=false;
    await selectFeature(`/api/provinces/${result.province_id}/districts/${encodeURIComponent(result.district_code)}`,result.district_name_th || district.textContent.trim(),district,{provinceId:result.province_id,districtCode:result.district_code});
    district.scrollIntoView({behavior:"smooth",block:"center"}); await pauseForLayer();
    const subdistrict=children.querySelector(`[data-subdistrict-id="${result.id}"]`);
    if(!subdistrict) throw new Error("ไม่พบตำบลในรายการด้านซ้าย");
    await selectFeature(`/api/subdistricts/${result.id}`,result.name_th,subdistrict,{provinceId:result.province_id,districtCode:result.district_code,selectedId:result.id});
    subdistrict.scrollIntoView({behavior:"smooth",block:"center"});
  }
  async function selectSubdistrictAtCoordinate(coordinate) {
    locateRequest?.abort();
    locateRequest = new AbortController();
    const [lon,lat] = ol.proj.toLonLat(coordinate);
    const message = document.querySelector("#map-message");
    message.textContent="กำลังค้นหาตำบลจากตำแหน่งที่คลิก…";
    try {
      const query = new URLSearchParams({lon:lon.toFixed(7),lat:lat.toFixed(7)});
      const response = await fetch(`/api/subdistricts/locate?${query}`,{
        headers:{Accept:"application/json"},signal:locateRequest.signal
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || `HTTP ${response.status}`);
      return selectNextLayerAtLocation(result);
      const directButton = document.querySelector(`.direct-subdistrict[data-id="${result.id}"]`);
      if (directButton) {
        return selectFeature(`/api/subdistricts/${result.id}`,result.name_th,directButton,{
          provinceId:result.province_id,selectedId:result.id
        });
      }
      const provinceButton = document.querySelector(`.province-button[data-id="${result.province_id}"]`);
      if (!provinceButton) throw new Error("ไม่พบจังหวัดในรายการด้านซ้าย");
      const children = await ensureProvinceChildren(provinceButton,true);
      const button = children.querySelector(`[data-subdistrict-id="${result.id}"]`);
      if (!button) throw new Error("ไม่พบตำบลในรายการด้านซ้าย");
      selectFeature(`/api/subdistricts/${result.id}`,result.name_th,button,{
        provinceId:result.province_id,selectedId:result.id
      });
    } catch (error) {
      if (error.name === "AbortError") return;
      message.textContent=error.message;
      message.classList.add("error");
    }
  }

  async function loadSiblingBoundaries(provinceId, selectedId, districtCode) {
    const source = siblingBoundaries.getSource();
    const loadVersion=++boundaryLoadVersion;
    source.clear();
    if (!provinceId || (!selectedId && !districtCode)) return;
    try {
      const query=new URLSearchParams({geometry:"1"});
      if(districtCode) query.set("district_code",districtCode);
      const data = await fetchAdministrativeBoundary(`/api/provinces/${provinceId}/subdistricts?${query}`);
      if(loadVersion!==boundaryLoadVersion) return;
      const features = new ol.format.GeoJSON().readFeatures(data,{featureProjection:"EPSG:3857"})
        .filter(feature => (!districtCode || String(feature.get("district_code"))===String(districtCode)) && String(feature.getId()) !== String(selectedId));
      features.forEach(feature => {feature.set("provinceId",String(provinceId));feature.set("districtOnly",!selectedId);});
      source.addFeatures(features);
    } catch (error) {
      console.warn("Unable to load nearby subdistrict boundaries",error);
    }
  }

  async function loadDistrictBoundaries(provinceId) {
    const source=districtBoundaries.getSource(); source.clear();
    if(!provinceId) return;
    const loadVersion=++districtBoundaryLoadVersion;
    try{
      const data=await fetchAdministrativeBoundary(`/api/provinces/${provinceId}/districts?geometry=1`);
      if(loadVersion!==districtBoundaryLoadVersion) return;
      source.addFeatures(new ol.format.GeoJSON().readFeatures(data,{featureProjection:"EPSG:3857"}));
    }catch(error){console.warn("Unable to load district boundaries",error);}
  }

  async function ensureProvinceChildren(button,open=false) {
    const box=button.closest(".province"), children=box.querySelector(".children");
    if(!children.dataset.loaded){
      const rows=await fetch(`/api/provinces/${button.dataset.id}/subdistricts`,{headers:{Accept:"application/json"}})
        .then(response=>{if(!response.ok)throw new Error(response.status);return response.json()});
      const districts=new Map();
      rows.forEach(row=>{const code=row.district_code || "unknown",name=row.district_name_th || "ไม่ระบุอำเภอ";if(!districts.has(code))districts.set(code,{name,rows:[]});districts.get(code).rows.push(row);});
      districts.forEach((district,code)=>{const box=document.createElement("div");box.className="district";const districtButton=document.createElement("button");districtButton.className="tree-row district-button";districtButton.dataset.code=code;districtButton.innerHTML=`<span class="chevron">›</span><span>▱</span>${district.name}`;const districtChildren=document.createElement("div");districtChildren.className="children district-children";districtChildren.hidden=true;district.rows.forEach(x=>{const b=document.createElement("button");b.className="tree-row";b.dataset.subdistrictId=x.id;b.innerHTML=`<span aria-hidden="true">⌖</span>${x.name_th}`;b.onclick=()=>selectFeature(`/api/subdistricts/${x.id}`,x.name_th,b,{provinceId:button.dataset.id,districtCode:code,selectedId:x.id});districtChildren.appendChild(b)});districtButton.onclick=()=>{box.classList.toggle("open");districtChildren.hidden=!districtChildren.hidden;selectFeature(`/api/provinces/${button.dataset.id}/districts/${encodeURIComponent(code)}`,district.name,districtButton,{provinceId:button.dataset.id,districtCode:code,preserveTreeCollapsed:districtChildren.hidden});};districtButton.querySelector(".chevron")?.addEventListener("click",event=>{if(currentUserRole!=="system_admin")return;event.stopPropagation();box.classList.toggle("open");districtChildren.hidden=!districtChildren.hidden;});box.append(districtButton,districtChildren);children.appendChild(box)});
      children.dataset.loaded="true";
    }
    if(open){box.classList.add("open");children.hidden=false;}
    return children;
  }

  function syncSystemAdminTree({preserveCollapsed=false,previousProvinceId=null,previousDistrictCode=null}={}) {
    if(currentUserRole !== "system_admin" || !selectedProvinceId) return;

    const provinceButton=document.querySelector(`.province-button[data-id="${String(selectedProvinceId)}"]`);
    const province=provinceButton?.closest(".province");
    if(!province) return;

    // When the selection moves to another province, collapse only the branch
    // that was previously selected. Other branches remain under the user's control.
    if(previousProvinceId && String(previousProvinceId)!==String(selectedProvinceId)){
      const previousProvince=document.querySelector(`.province-button[data-id="${String(previousProvinceId)}"]`)?.closest(".province");
      const previousChildren=previousProvince?.querySelector(":scope > .children");
      previousProvince?.classList.remove("open");
      if(previousChildren) previousChildren.hidden=true;
    }

    if(previousDistrictCode && selectedDistrictCode && String(previousProvinceId)===String(selectedProvinceId) && String(previousDistrictCode)!==String(selectedDistrictCode)){
      const previousDistrict=province.querySelector(`.district-button[data-code="${String(previousDistrictCode)}"]`)?.closest(".district");
      const previousDistrictChildren=previousDistrict?.querySelector(".district-children");
      previousDistrict?.classList.remove("open");
      if(previousDistrictChildren) previousDistrictChildren.hidden=true;
    }

    // Keep the complete national tree available.  Only reveal and scroll to the
    // selected branch; never remove other provinces, districts, or subdistricts.
    if(!preserveCollapsed && selectedDistrictCode){
      const provinceChildren=province.querySelector(":scope > .children");
      province.classList.add("open");
      if(provinceChildren) provinceChildren.hidden=false;
    }

    let selectedRow=provinceButton;
    if(selectedDistrictCode){
      const districtButton=province.querySelector(`.district-button[data-code="${String(selectedDistrictCode)}"]`);
      if(districtButton){
        selectedRow=districtButton;
        if(!preserveCollapsed && selectedSubdistrictId){
          const district=districtButton.closest(".district");
          const districtChildren=district?.querySelector(".district-children");
          district?.classList.add("open");
          if(districtChildren) districtChildren.hidden=false;
        }
      }
    }

    if(selectedSubdistrictId){
      const subdistrictRow=province.querySelector(`.tree-row[data-subdistrict-id="${String(selectedSubdistrictId)}"]`);
      if(subdistrictRow) selectedRow=subdistrictRow;
    }

    selectedRow.scrollIntoView({block:"nearest",behavior:"smooth"});
  }

  async function selectFeature(url, name, button, options={}) {
    const previousProvinceId=selectedProvinceId;
    const previousDistrictCode=selectedDistrictCode;
    const wasSameSelection=String(selectedProvinceId || "")===String(options.provinceId || (button.dataset.id || "")) && String(selectedDistrictCode || "")===String(options.districtCode || "") && String(selectedSubdistrictId || "")===String(options.selectedId || "");
    document.querySelectorAll(".tree-row.active").forEach(x=>x.classList.remove("active")); button.classList.add("active");
    const parentDistrict=button.closest(".district");
    if(parentDistrict){parentDistrict.classList.add("open");const districtChildren=parentDistrict.querySelector(".district-children");if(districtChildren)districtChildren.hidden=false;}
    const featureData = await fetchSelectedArea(url);
    selectedFeatureData=featureData;
    selectedProvinceId=options.provinceId || (featureData.properties?.level==="province" ? button.dataset.id : null);
    selectedDistrictCode=options.districtCode || featureData.properties?.district_code || null;
    selectedSubdistrictId=options.selectedId || null;
    syncSystemAdminTree({preserveCollapsed:options.preserveTreeCollapsed || wasSameSelection,previousProvinceId,previousDistrictCode});
    if(!options.accessArea){
      loadSiblingBoundaries(selectedProvinceId,selectedSubdistrictId,selectedDistrictCode);
      overviewBoundaries.changed();
      districtBoundaries.changed();
      loadDistrictBoundaries(selectedProvinceId);
    }
    const source = highlight.getSource(); source.clear();
    if(featureData.geometry){
      const feature = new ol.format.GeoJSON().readFeature(featureData,{featureProjection:"EPSG:3857"}); source.addFeature(feature);
      const isProvince = featureData.properties?.level === "province";
      const isDistrict = featureData.properties?.level === "district";
      selectedAreaGeometry=feature.getGeometry();
      selectedAreaCode=featureData.properties?.code;
      selectedAreaCenter=featureData.properties?.center || ol.proj.toLonLat(ol.extent.getCenter(feature.getGeometry().getExtent()));
      if(isDistrict){
        const view=map.getView(), extent=source.getExtent(), size=map.getSize() || [900,600];
        const paddedSize=[Math.max(1,size[0]-160),Math.max(1,size[1]-160)];
        const fitZoom=view.getZoomForResolution(view.getResolutionForExtent(extent,paddedSize));
        const targetZoom=Math.max(view.getZoom() || 6,Math.min(fitZoom,14));
        view.animate({center:ol.extent.getCenter(extent),zoom:targetZoom,duration:700});
      }else{
        map.getView().fit(source.getExtent(),{
          padding:[80,80,80,80], duration:options.initialFocus ? 0 : 700,
          maxZoom:isProvince ? 10 : 15
        });
      }
      document.querySelector("#map-message").textContent=`แสดงขอบเขต: ${name}`;
    } else if(featureData.properties?.center){
      const isProvince = featureData.properties.level === "province";
      selectedAreaGeometry=null;
      selectedAreaCode=featureData.properties?.code;
      selectedAreaCenter=featureData.properties.center;
      map.getView().animate({
        center:ol.proj.fromLonLat(featureData.properties.center),
        zoom:isProvince ? 9 : 14,
        duration:700
      });
      document.querySelector("#map-message").textContent=`โฟกัสพื้นที่: ${name} (ยังไม่มี polygon)`;
    } else {
      selectedAreaGeometry=null;selectedAreaCode=null;selectedAreaCenter=null;
      document.querySelector("#map-message").textContent=`${name}: ยังไม่มีข้อมูลขอบเขต polygon`;
    }
    document.querySelector("#selection-label").textContent=name;
    const dashboardTitle = document.querySelector("#dashboard-area-title");
    const mapAreaLabel = document.querySelector("#map-area-label");
    if (dashboardTitle) dashboardTitle.textContent=name;
    if (mapAreaLabel) mapAreaLabel.textContent=name;
    syncCesiumBoundary();
    focusCesiumArea();
    Object.values(placeLayers).forEach(layer => layer.getSource().clear());
    importedPlacesLayer.getSource().clear();
    Object.keys(placesByCategory).forEach(category => delete placesByCategory[category]);
    Object.keys(allProvincePlacesByCategory).forEach(category => delete allProvincePlacesByCategory[category]);
    renderImportantPlaces();
    loadWaterStations();
    if(options.loadPlaces!==false){
      loadImportedPlaces();
      document.querySelectorAll('[data-place-category][aria-pressed="true"]').forEach(placeButton=>loadPlaces(placeButton.dataset.placeCategory));
    }
    document.querySelector("#map-message").classList.remove("error");
  }
  document.querySelectorAll(".province-button").forEach(button=>{
    button.querySelector(".chevron")?.addEventListener("click",event=>{
      if(currentUserRole!=="system_admin") return;
      event.stopPropagation();
      const box=button.closest(".province"), children=box.querySelector(".children");
      box.classList.toggle("open");children.hidden=!children.hidden;
    });
    button.addEventListener("click",async()=>{
      const box=button.closest(".province"), children=box.querySelector(".children"), name=box.dataset.name;
      box.classList.toggle("open");children.hidden=!children.hidden;
      await ensureProvinceChildren(button);
      selectFeature(`/api/provinces/${button.dataset.id}`,name,button,{preserveTreeCollapsed:children.hidden});
    });
  });
  document.querySelectorAll(".direct-subdistrict").forEach(button=>{
    let initialSelection=true;
    const selectAssignedSubdistrict=async()=>{
      const isInitialSelection=initialSelection;
      await selectFeature(`/api/subdistricts/${button.dataset.id}`,button.dataset.name || button.textContent.trim(),button,{provinceId:button.dataset.provinceId,selectedId:button.dataset.id,loadPlaces:!isInitialSelection,initialFocus:isInitialSelection});
      initialSelection=false;
      if(isInitialSelection) loadInitialPlaceCategories();
    };
    button.addEventListener("click",selectAssignedSubdistrict);
    selectAssignedSubdistrict();
  });
  document.querySelectorAll(".direct-access-area").forEach(button=>{
    let initialSelection=true;
    const selectAccessArea=async()=>{
      const isInitialSelection=initialSelection;
      await selectFeature("/api/access_area",button.dataset.name || button.textContent.trim(),button,{accessArea:true,loadPlaces:!isInitialSelection,initialFocus:isInitialSelection});
      initialSelection=false;
      if(isInitialSelection) loadInitialPlaceCategories();
    };
    button.addEventListener("click",selectAccessArea);
    selectAccessArea();
  });
  document.querySelectorAll("[data-basemap]").forEach(b=>b.onclick=()=>{setMapMode(false);const sat=b.dataset.basemap==="satellite";street.setVisible(!sat);satellite.setVisible(sat);document.querySelectorAll("[data-basemap]").forEach(x=>x.classList.toggle("active",x===b));if(sat&&!key)document.querySelector("#map-message").textContent="กำหนด MAPTILER_KEY เพื่อเปิดภาพดาวเทียม"});
  document.querySelectorAll("[data-map-mode]").forEach(button=>button.addEventListener("click",()=>setMapMode(button.dataset.mapMode==="3d")));
  const areaSearch = document.querySelector("#area-search");
  const searchResults = document.querySelector("#area-search-results");
  if (areaSearch && searchResults) {
  let searchTimer, searchRequest, currentSearchRows=[];
  async function activateSearchResult(row) {
    const provinceButton=document.querySelector(`.province-button[data-id="${row.province_id}"]`);
    if(row.result_type==="province"){
      const provinceResultButton=document.querySelector(`.province-button[data-id="${row.id}"]`);
      if(!provinceResultButton)return;
      await ensureProvinceChildren(provinceResultButton,true);
      areaSearch.value=row.name_th;
      searchResults.hidden=true;
      areaSearch.setAttribute("aria-expanded","false");
      await selectFeature(`/api/provinces/${row.id}`,row.name_th,provinceResultButton);
      return;
    }
    const directButton=document.querySelector(`.direct-subdistrict[data-id="${row.id}"]`);
    if(directButton){
      areaSearch.value=row.name_th;
      searchResults.hidden=true;
      areaSearch.setAttribute("aria-expanded","false");
      return selectFeature(`/api/subdistricts/${row.id}`,row.name_th,directButton,{provinceId:row.province_id,selectedId:row.id});
    }
    if(!provinceButton)return;
    const children=await ensureProvinceChildren(provinceButton,true);
    const subdistrictButton=children.querySelector(`[data-subdistrict-id="${row.id}"]`);
    if(!subdistrictButton)return;
    areaSearch.value=row.name_th;
    searchResults.hidden=true;
    areaSearch.setAttribute("aria-expanded","false");
    await selectFeature(`/api/subdistricts/${row.id}`,row.name_th,subdistrictButton,{provinceId:row.province_id,selectedId:row.id});
  }
  areaSearch.addEventListener("keydown",event=>{
    if(event.key==="Enter" && currentSearchRows.length){
      event.preventDefault();
      activateSearchResult(currentSearchRows[0]);
    }
  });
  areaSearch.addEventListener("input",event => {
    clearTimeout(searchTimer);
    searchRequest?.abort();
    const query=event.target.value.trim();
    document.querySelectorAll(".province").forEach(province => province.hidden=false);
    if(!query){currentSearchRows=[];searchResults.hidden=true;searchResults.replaceChildren();areaSearch.setAttribute("aria-expanded","false");return;}
    searchTimer=setTimeout(async()=>{
      searchRequest=new AbortController();
      searchResults.hidden=false;
      areaSearch.setAttribute("aria-expanded","true");
      searchResults.innerHTML='<div class="search-result-status">กำลังค้นหา…</div>';
      try{
        const response=await fetch(`/api/subdistricts/search?${new URLSearchParams({query})}`,{
          headers:{Accept:"application/json"},signal:searchRequest.signal
        });
        if(!response.ok)throw new Error(response.status);
        const rows=await response.json();
        currentSearchRows=rows;
        searchResults.replaceChildren();
        searchResults.hidden=false;
        if(!rows.length){searchResults.innerHTML='<div class="search-result-status">ไม่พบจังหวัดหรือ ตำบล</div>';return;}
        rows.forEach(row=>{
          const result=document.createElement("button");
          result.type="button";
          const detail=row.result_type==="province" ? "จังหวัด" : ["ตำบล",row.district_name_th,row.province_name_th].filter(Boolean).join(" · ");
          result.innerHTML=`<strong>${escapeHtml(row.name_th)}</strong><small>${escapeHtml(detail)}</small>`;
          result.onclick=()=>activateSearchResult(row);
          searchResults.appendChild(result);
        });
      }catch(error){
        if(error.name!=="AbortError")searchResults.innerHTML='<div class="search-result-status">ค้นหาไม่สำเร็จ</div>';
      }
    },250);
  });
  }

  const importDialog = document.querySelector("#place-import-dialog");
  const importForm = document.querySelector("#place-import-form");
  const importStatus = document.querySelector("#place-import-status");
  document.querySelectorAll("[data-open-place-import]").forEach(button => button.addEventListener("click", () => importDialog?.showModal()));
  document.querySelectorAll("[data-close-place-import]").forEach(button => button.addEventListener("click", () => importDialog?.close()));
  if (importForm) {
    importForm.addEventListener("submit", async event => {
      event.preventDefault();
      const submit = importForm.querySelector("[type=submit]");
      const token = document.querySelector('meta[name="csrf-token"]')?.content;
      submit.disabled = true;
      importStatus.classList.remove("error");
      importStatus.textContent = "กำลังนำเข้าข้อมูล…";
      try {
        const response = await fetch("/place_imports", {
          method: "POST",
          headers: { "X-CSRF-Token": token, Accept: "application/json" },
          body: new FormData(importForm)
        });
        const payload = await response.json();
        if (!response.ok) throw new Error(payload.error || "ไม่สามารถนำเข้าข้อมูลได้");
        importStatus.textContent = `เพิ่มสถานที่สำคัญ ${payload.imported.toLocaleString()} แห่งแล้ว`;
        importForm.reset();
        loadImportedPlaces();
      } catch (error) {
        importStatus.classList.add("error");
        importStatus.textContent = error.message;
      } finally {
        submit.disabled = false;
      }
    });
  }
});
