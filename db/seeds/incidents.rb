user = User.find_by(email: ENV.fetch("INCIDENT_SAMPLE_USER", "admin550513@smartcity.local"))
raise "Sample incident user not found" unless user
raise "Sample incident user must have a subdistrict" unless user.subdistrict_id

now = Time.current
area_name = "ต.#{user.subdistrict.name_th} จ.#{user.subdistrict.province.name_th}"

samples = [
  {
    reference_code: "INC-2569-001",
    category: "disaster",
    incident_type: "น้ำท่วม",
    title: "น้ำป่าไหลหลากเข้าพื้นที่ชุมชน",
    description: "ประชาชนแจ้งน้ำป่าไหลหลากจากพื้นที่สูงเข้าท่วมถนนและบ้านเรือน ระดับน้ำเพิ่มขึ้นอย่างต่อเนื่อง",
    severity: "critical",
    status: "in_progress",
    reporter_name: "นายสมชาย ใจดี",
    reporter_contact: "08X-XXX-2481",
    location_name: "หมู่ 5 #{area_name}",
    latitude: 19.4028,
    longitude: 100.9246,
    affected_people: 86,
    affected_households: 24,
    assigned_to: "ทีมป้องกันและบรรเทาสาธารณภัย",
    created_at: now - 2.hours,
    histories: [
      { "title" => "รับแจ้งเหตุเข้าสู่ระบบ", "description" => "ตรวจสอบข้อมูลผู้แจ้งและพิกัดเบื้องต้น", "occurred_at" => (now - 2.hours).strftime("%d/%m/%Y %H:%M"), "actor" => "ศูนย์รับแจ้งเหตุ", "resources" => [] },
      { "title" => "ส่งเจ้าหน้าที่เข้าพื้นที่", "description" => "สำรวจระดับน้ำและช่วยเคลื่อนย้ายประชาชนกลุ่มเปราะบาง", "occurred_at" => (now - 55.minutes).strftime("%d/%m/%Y %H:%M"), "actor" => "ทีมป้องกันฯ", "resources" => [{ "name" => "เรือท้องแบน", "quantity" => 2, "unit" => "ลำ" }, { "name" => "เสื้อชูชีพ", "quantity" => 20, "unit" => "ตัว" }] }
    ],
    resources_used: [
      { "name" => "เรือท้องแบน", "quantity" => 2, "unit" => "ลำ", "note" => "ลำเลียงประชาชน" },
      { "name" => "เสื้อชูชีพ", "quantity" => 20, "unit" => "ตัว", "note" => "แจกเจ้าหน้าที่และประชาชน" },
      { "name" => "กำลังเจ้าหน้าที่", "quantity" => 12, "unit" => "คน", "note" => "ปฏิบัติงานในพื้นที่" }
    ],
    active_plan_version: 2,
    response_plan_versions: [
      { "version" => 1, "title" => "แผนรับมือเบื้องต้น", "affected_people" => 60, "budget" => 180_000, "assessed_at" => "วันนี้ 14:30 น.", "resources" => [{ "name" => "เรือท้องแบน", "required" => 2, "available" => 3, "unit" => "ลำ" }, { "name" => "เสื้อชูชีพ", "required" => 20, "available" => 40, "unit" => "ตัว" }] },
      { "version" => 2, "title" => "ปรับตามระดับน้ำล่าสุด", "affected_people" => 86, "budget" => 285_000, "assessed_at" => "วันนี้ 16:05 น.", "resources" => [{ "name" => "เรือท้องแบน", "required" => 4, "available" => 3, "unit" => "ลำ" }, { "name" => "เครื่องสูบน้ำ", "required" => 6, "available" => 5, "unit" => "เครื่อง" }, { "name" => "กำลังเจ้าหน้าที่", "required" => 18, "available" => 30, "unit" => "คน" }] }
    ]
  },
  {
    reference_code: "INC-2569-002", category: "general", incident_type: "ต้นไม้ล้ม", title: "ต้นไม้ใหญ่ล้มขวางสายไฟ",
    description: "ต้นไม้ขนาดใหญ่ล้มพาดสายไฟและกีดขวางเส้นทางเข้าออกหมู่บ้าน", severity: "urgent", status: "acknowledged",
    reporter_name: "นางมาลี คำดี", reporter_contact: "09X-XXX-6152", location_name: "หมู่ 7 #{area_name}", latitude: 19.3954, longitude: 100.9132,
    affected_people: 18, affected_households: 6, assigned_to: "งานป้องกันฯ และการไฟฟ้า", created_at: now - 5.hours,
    histories: [{ "title" => "รับแจ้งเหตุเข้าสู่ระบบ", "description" => "ประสานงานเจ้าหน้าที่และการไฟฟ้าเข้าตรวจสอบ", "occurred_at" => (now - 5.hours).strftime("%d/%m/%Y %H:%M"), "actor" => "ศูนย์รับแจ้งเหตุ", "resources" => [] }]
  },
  {
    reference_code: "INC-2569-003", category: "disaster", incident_type: "ดินถล่ม", title: "พบดินสไลด์บริเวณไหล่ทาง",
    description: "ฝนตกต่อเนื่องทำให้ดินบนเนินเขาไหลลงมาปิดช่องทางจราจรหนึ่งช่องทาง", severity: "watch", status: "assessing",
    reporter_name: "นายคำปัน แสนสุข", reporter_contact: "08X-XXX-9704", location_name: "ถนนเชื่อมหมู่ 3–4 #{area_name}", latitude: 19.4181, longitude: 100.9391,
    affected_people: 0, affected_households: 0, assigned_to: "ทีมสำรวจพื้นที่", created_at: now - 1.day,
    histories: [{ "title" => "กำลังประเมินพื้นที่", "description" => "เจ้าหน้าที่อยู่ระหว่างตรวจสอบความมั่นคงของลาดดิน", "occurred_at" => (now - 22.hours).strftime("%d/%m/%Y %H:%M"), "actor" => "ทีมสำรวจพื้นที่", "resources" => [] }]
  },
  {
    reference_code: "INC-2569-004", category: "general", incident_type: "ถนนชำรุด", title: "ถนนชำรุดเป็นหลุมลึก",
    description: "ผิวถนนทรุดตัวเป็นหลุมลึก เสี่ยงต่อการเกิดอุบัติเหตุโดยเฉพาะช่วงกลางคืน", severity: "urgent", status: "completed",
    reporter_name: "นางสาวกัญญา เมืองดี", reporter_contact: "06X-XXX-1148", location_name: "หน้าโรงเรียนชุมชน #{area_name}", latitude: 19.4063, longitude: 100.9187,
    affected_people: 0, affected_households: 0, assigned_to: "กองช่าง", created_at: now - 2.days,
    histories: [{ "title" => "ซ่อมแซมผิวถนนแล้ว", "description" => "ปิดหลุมและติดตั้งป้ายเตือนเรียบร้อย", "occurred_at" => (now - 1.day).strftime("%d/%m/%Y %H:%M"), "actor" => "กองช่าง", "resources" => [{ "name" => "ยางมะตอยสำเร็จรูป", "quantity" => 8, "unit" => "ถุง" }] }],
    resources_used: [{ "name" => "ยางมะตอยสำเร็จรูป", "quantity" => 8, "unit" => "ถุง", "note" => "ซ่อมผิวถนน" }]
  },
  {
    reference_code: "INC-2569-005", category: "disaster", incident_type: "ไฟป่า", title: "พบกลุ่มควันใกล้พื้นที่ป่าชุมชน",
    description: "ประชาชนพบกลุ่มควันและกลิ่นไหม้บริเวณแนวป่าชุมชน ยังไม่พบเปลวไฟขนาดใหญ่", severity: "watch", status: "pending",
    reporter_name: "ไม่ประสงค์ออกนาม", reporter_contact: "", location_name: "แนวป่าด้านทิศเหนือ #{area_name}", latitude: 19.4315, longitude: 100.9028,
    affected_people: 0, affected_households: 0, created_at: now - 3.days
  },
  {
    reference_code: "INC-2569-006", category: "general", incident_type: "ไฟส่องสว่าง", title: "ไฟส่องสว่างสาธารณะดับหลายจุด",
    description: "ไฟส่องสว่างริมถนนดับต่อเนื่อง 4 จุด ทำให้บริเวณทางโค้งมืดและเสี่ยงอุบัติเหตุ", severity: "watch", status: "completed",
    reporter_name: "นายอนันต์ ปัญญา", reporter_contact: "08X-XXX-3319", location_name: "ถนนสายหลักหมู่ 2 #{area_name}", latitude: 19.3892, longitude: 100.9298,
    affected_people: 0, affected_households: 0, assigned_to: "กองช่างไฟฟ้า", created_at: now - 4.days,
    histories: [{ "title" => "เปลี่ยนหลอดไฟเรียบร้อย", "description" => "ตรวจสอบระบบและเปลี่ยนหลอดไฟครบทั้ง 4 จุด", "occurred_at" => (now - 3.days).strftime("%d/%m/%Y %H:%M"), "actor" => "กองช่างไฟฟ้า", "resources" => [] }]
  }
]

samples.each do |attributes|
  incident = Incident.find_or_initialize_by(reference_code: attributes[:reference_code])
  incident.assign_attributes(attributes.merge(user_id: user.id, subdistrict_id: user.subdistrict_id))
  incident.save!
end

puts "Created or updated #{samples.size} sample incidents for #{user.email}"
