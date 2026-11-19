from __future__ import annotations

import json
import sys
from pathlib import Path


MODULES = {
    "AUTH": ("การยืนยันตัวตนและสิทธิ์", "Critical", "Security / Functional"),
    "REG": ("การลงทะเบียนองค์กร", "High", "Functional / Integration"),
    "DASH": ("ภาพรวมเมือง", "High", "Functional / Data"),
    "GIS": ("แผนที่และ GIS", "Critical", "GIS / API / Functional"),
    "INC": ("เหตุการณ์และภัยพิบัติ", "Critical", "End to End / Functional"),
    "PUB": ("การแจ้งเหตุสาธารณะ", "Critical", "Security / End to End"),
    "DATA": ("การนำเข้าและชุดข้อมูล", "Critical", "Data / Functional"),
    "OPS": ("งานปฏิบัติการ", "High", "Functional / GIS"),
    "SENSOR": ("Sensor และสถานีน้ำ", "High", "API / Integration"),
    "WX": ("บริการสภาพอากาศ", "High", "API / Integration / Data"),
    "RULE": ("กฎทรัพยากร", "High", "Functional / Calculation"),
    "NOTI": ("การแจ้งเตือน", "Critical", "Integration / Security"),
    "SMS": ("SMS และการติดตาม", "High", "Integration / Security"),
    "AI": ("ผู้ช่วย AI", "High", "Security / Functional"),
    "BCAST": ("ข่าวและการเผยแพร่", "High", "End to End / Integration"),
    "TTS": ("การสังเคราะห์เสียง", "Medium", "Integration / Functional"),
    "ANN": ("ประกาศภายใน", "Medium", "Functional"),
    "SET": ("การตั้งค่าระบบ", "High", "Security / Functional"),
    "API": ("API ระบบ", "Critical", "API / Security"),
    "SEC": ("ความมั่นคงปลอดภัย", "Critical", "Security"),
    "PERF": ("ประสิทธิภาพ", "High", "Performance"),
    "REL": ("ความน่าเชื่อถือ", "High", "Resilience / Data"),
    "DATA_NFR": ("คุณภาพและความคงทนข้อมูล", "High", "Data / Recovery"),
    "UX": ("ประสบการณ์ผู้ใช้", "Medium", "Usability / Compatibility"),
    "OPS_NFR": ("การปฏิบัติการระบบ", "High", "Operations / Resilience"),
    "TEST": ("การทดสอบถดถอย", "High", "Regression"),
}


ROLE_BY_MODULE = {
    "AUTH": "system_admin, subdistrict_admin, subdistrict_user และผู้ไม่เข้าสู่ระบบ",
    "REG": "ผู้สมัครองค์กรและ system_admin",
    "DASH": "subdistrict_admin หรือ subdistrict_user ที่มีพื้นที่รับผิดชอบ",
    "GIS": "ผู้ใช้ที่มีพื้นที่รับผิดชอบและ system_admin",
    "INC": "subdistrict_admin และ subdistrict_user ในองค์กรทดสอบ",
    "PUB": "ประชาชนที่ไม่มีบัญชีและเจ้าหน้าที่องค์กร",
    "DATA": "ผู้ใช้องค์กรที่มีสิทธิ์จัดการชุดข้อมูล",
    "OPS": "ผู้ใช้องค์กรและผู้ดูแลข้อมูลพื้นที่",
    "SENSOR": "API client, sensor และผู้ใช้ที่มีสิทธิ์ดูข้อมูล",
    "WX": "Weather API client และผู้ใช้ dashboard",
    "RULE": "ผู้ดูแลกฎและผู้ใช้ประเมินทรัพยากร",
    "NOTI": "ผู้ดูแลองค์กรและช่องทาง sandbox",
    "SMS": "ผู้ดูแลองค์กรและ SMS sandbox",
    "AI": "ผู้ใช้สององค์กรและ system_admin",
    "BCAST": "subdistrict_admin, subdistrict_user และช่องทาง sandbox",
    "TTS": "ผู้ดูแล provider และ TTS sandbox",
    "ANN": "system_admin และผู้ใช้กลุ่มเป้าหมาย",
    "SET": "system_admin และ subdistrict_admin",
    "API": "API client ภายใต้ผู้ใช้แต่ละบทบาท",
}


def module_info(req):
    code = req["module_code"]
    if req["type"] == "NFR" and code == "DATA":
        code = "DATA_NFR"
    if req["type"] == "NFR" and code == "OPS":
        code = "OPS_NFR"
    return MODULES.get(code, (req.get("section") or code, "Medium", "Functional"))


def scenario_object(req, index):
    module, priority, test_type = module_info(req)
    return {
        "scenario_id": f"TS-{index:03d}",
        "requirement_id": req["id"],
        "module": module,
        "scenario": f"ตรวจสอบ{req['title']}ให้เป็นไปตามข้อกำหนดและไม่ข้ามสิทธิ์หรือขอบเขตข้อมูล",
        "objective": req["statement"],
        "coverage": "Positive, Negative, Authorization, Boundary" if priority in ("Critical", "High") else "Positive, Negative",
        "priority": priority,
        "test_type": test_type,
        "status": "Not Run",
        "owner": "",
        "notes": "",
    }


def case_common(req, scenario_id, case_id, name, purpose, steps, expected, priority, test_type, test_data):
    role = ROLE_BY_MODULE.get(req["module_code"], "ผู้ใช้ที่มีสิทธิ์และผู้ใช้ที่ไม่มีสิทธิ์")
    return {
        "test_case_id": case_id,
        "scenario_id": scenario_id,
        "requirement_id": req["id"],
        "module": module_info(req)[0],
        "test_case_name": name,
        "purpose": purpose,
        "priority": priority,
        "test_type": test_type,
        "preconditions": f"ระบบ Test พร้อมใช้งาน มีข้อมูลทดสอบ และมีบัญชี {role}",
        "test_data": test_data,
        "steps": "\n".join(f"{i + 1}. {step}" for i, step in enumerate(steps)),
        "expected_result": "\n".join(f"{i + 1}. {item}" for i, item in enumerate(expected)),
        "actual_result": "",
        "status": "Not Run",
        "defect_id": "",
        "tester": "",
        "test_date": "",
        "evidence": "",
        "remarks": "",
    }


def functional_cases(req, scenario_id, seq):
    module, priority, test_type = module_info(req)
    acceptance = req.get("acceptance") or [req["statement"]]
    positive_expected = acceptance + ["ระบบไม่เกิดข้อผิดพลาด 500 และข้อมูลถูกจำกัดตามสิทธิ์"]
    positive = case_common(
        req, scenario_id, f"TC-{seq:04d}", f"{req['title']}ด้วยข้อมูลถูกต้อง",
        f"ยืนยันเส้นทางหลักของ {req['id']}",
        ["เข้าสู่ระบบด้วยบทบาทที่มีสิทธิ์ตามข้อกำหนด", "เตรียมข้อมูลที่ถูกต้องและอยู่ในขอบเขตองค์กรทดสอบ", f"ดำเนินการ {req['title']} ผ่านหน้าจอหรือ API ที่เกี่ยวข้อง", "บันทึกหรือส่งคำขอ", "ตรวจผลบนหน้าจอ API และฐานข้อมูลที่เกี่ยวข้อง"],
        positive_expected, priority, test_type, "ข้อมูลถูกต้องหนึ่งชุดในองค์กร A และพื้นที่ A",
    )
    negative_expected = [
        "ระบบปฏิเสธข้อมูลไม่ครบ ไม่ถูกต้อง หรือการกระทำที่ไม่มีสิทธิ์ด้วยข้อความและ HTTP status ที่เหมาะสม",
        "ไม่สร้างหรือเปลี่ยนข้อมูลปลายทางบางส่วน",
        "ไม่เปิดเผยข้อมูลขององค์กรหรือพื้นที่อื่น",
        "ไม่แสดง stack trace credential หรือข้อมูลภายใน",
    ]
    negative = case_common(
        req, scenario_id, f"TC-{seq + 1:04d}", f"{req['title']}ด้วยข้อมูลผิดหรือไม่มีสิทธิ์",
        f"ยืนยัน validation และ authorization ของ {req['id']}",
        ["เตรียมผู้ใช้ที่ไม่มีสิทธิ์หรือข้อมูลที่ขาดฟิลด์สำคัญ", "เปิดรายการหรือ endpoint ที่เกี่ยวข้อง", f"พยายามดำเนินการ {req['title']} โดยใช้ข้อมูลผิด หรือเปลี่ยน ID ไปยังองค์กร B", "ตรวจ response ข้อความแจ้งเตือน และข้อมูลหลังคำขอ"],
        negative_expected, priority, test_type, "ข้อมูลผิดรูปแบบ ข้อมูลว่าง และ ID ขององค์กร B",
    )
    return [positive, negative]


def nonfunctional_case(req, scenario_id, seq):
    module, priority, test_type = module_info(req)
    return case_common(
        req, scenario_id, f"TC-{seq:04d}", f"ตรวจสอบ {req['title']}",
        f"พิสูจน์ข้อกำหนด {req['id']} ภายใต้สภาวะปกติและสภาวะผิดพลาด",
        ["เตรียมสภาพแวดล้อมและข้อมูลตามข้อกำหนด", "บันทึกค่าเริ่มต้นและหลักฐานก่อนทดสอบ", "ดำเนิน workload หรือ security/resilience condition ที่เกี่ยวข้อง", "ตรวจผลระหว่างทดสอบ", "ตรวจข้อมูล log และความสมบูรณ์ของข้อมูลหลังทดสอบ"],
        [req["statement"], "ไม่เกิดข้อมูลเสียหายหรือข้อมูลรั่วไหล", "มีหลักฐาน log metric หรือผลตรวจสอบที่ทำซ้ำได้"],
        priority, test_type, "ชุดข้อมูลทดสอบ มาตรวัด และเครื่องมือทดสอบตามประเภท NFR",
    )


def main():
    source = Path(sys.argv[1])
    target = Path(sys.argv[2])
    payload = json.loads(source.read_text(encoding="utf-8"))
    reqs = payload["functional_requirements"] + payload["nonfunctional_requirements"]
    scenarios = []
    cases = []
    case_seq = 1
    for index, requirement in enumerate(reqs, start=1):
        scenario = scenario_object(requirement, index)
        scenarios.append(scenario)
        if requirement["type"] == "FR":
            new_cases = functional_cases(requirement, scenario["scenario_id"], case_seq)
            case_seq += 2
        else:
            new_cases = [nonfunctional_case(requirement, scenario["scenario_id"], case_seq)]
            case_seq += 1
        cases.extend(new_cases)

    rtm = []
    for requirement in reqs:
        matching_scenarios = [s for s in scenarios if s["requirement_id"] == requirement["id"]]
        matching_cases = [c for c in cases if c["requirement_id"] == requirement["id"]]
        module, priority, test_type = module_info(requirement)
        rtm.append({
            "requirement_id": requirement["id"],
            "requirement_type": requirement["type"],
            "module": module,
            "title": requirement["title"],
            "requirement": requirement["statement"],
            "acceptance_criteria": "\n".join(requirement.get("acceptance") or []),
            "priority": priority,
            "scenario_ids": ", ".join(s["scenario_id"] for s in matching_scenarios),
            "test_case_ids": ", ".join(c["test_case_id"] for c in matching_cases),
            "coverage_status": "Covered" if matching_cases else "Not Covered",
            "execution_status": "Not Run",
            "defect_ids": "",
            "notes": "",
        })

    result = {
        "source": payload["source"],
        "business_requirements": payload["business_requirements"],
        "business_rules": payload["business_rules"],
        "requirements": reqs,
        "rtm": rtm,
        "scenarios": scenarios,
        "test_cases": cases,
        "summary": {
            "requirements": len(reqs),
            "functional": len(payload["functional_requirements"]),
            "nonfunctional": len(payload["nonfunctional_requirements"]),
            "scenarios": len(scenarios),
            "test_cases": len(cases),
        },
    }
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result["summary"], ensure_ascii=False))


if __name__ == "__main__":
    main()
