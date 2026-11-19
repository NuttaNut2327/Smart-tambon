from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

from docx import Document
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT, WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


FONT = "TH Sarabun New"
NAVY = "17365D"
PALE = "F5F7F8"
GRAY = "D9D9D9"
WHITE = "FFFFFF"


def set_font(run, size=14, bold=False, color="000000"):
    run.font.name = FONT
    rpr = run._element.get_or_add_rPr()
    for key in ("w:ascii", "w:hAnsi", "w:eastAsia"):
        rpr.rFonts.set(qn(key), FONT)
    run.font.size = Pt(size)
    run.bold = bold
    run.font.color.rgb = RGBColor.from_string(color)


def shade(cell, color):
    pr = cell._tc.get_or_add_tcPr()
    node = pr.find(qn("w:shd")) or OxmlElement("w:shd")
    node.set(qn("w:fill"), color)
    if node.getparent() is None:
        pr.append(node)


def border(cell):
    pr = cell._tc.get_or_add_tcPr()
    borders = pr.first_child_found_in("w:tcBorders")
    if borders is None:
        borders = OxmlElement("w:tcBorders")
        pr.append(borders)
    for edge in ("top", "left", "bottom", "right"):
        node = OxmlElement(f"w:{edge}")
        node.set(qn("w:val"), "single")
        node.set(qn("w:sz"), "6")
        node.set(qn("w:color"), GRAY)
        borders.append(node)


def margins(cell):
    pr = cell._tc.get_or_add_tcPr()
    mar = OxmlElement("w:tcMar")
    for key in ("top", "start", "bottom", "end"):
        node = OxmlElement(f"w:{key}")
        node.set(qn("w:w"), "100")
        node.set(qn("w:type"), "dxa")
        mar.append(node)
    pr.append(mar)


def table(doc, headers, rows, widths=None, small=False):
    t = doc.add_table(rows=1, cols=len(headers))
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    for i, text in enumerate(headers):
        c = t.rows[0].cells[i]
        shade(c, NAVY); border(c); margins(c)
        c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        p = c.paragraphs[0]; p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        set_font(p.add_run(str(text)), 11 if small else 12, True, WHITE)
        if widths: c.width = Inches(widths[i])
    trpr = t.rows[0]._tr.get_or_add_trPr(); trpr.append(OxmlElement("w:tblHeader"))
    for ri, values in enumerate(rows):
        row = t.add_row(); row._tr.get_or_add_trPr().append(OxmlElement("w:cantSplit"))
        for i, text in enumerate(values):
            c = row.cells[i]
            if ri % 2: shade(c, PALE)
            border(c); margins(c); c.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            p = c.paragraphs[0]; p.alignment = WD_ALIGN_PARAGRAPH.LEFT if i else WD_ALIGN_PARAGRAPH.CENTER
            set_font(p.add_run(str(text)), 10.5 if small else 11.5)
            if widths: c.width = Inches(widths[i])
    doc.add_paragraph()
    return t


def heading(doc, text, level=1):
    p = doc.add_heading(text, level=level)
    p.paragraph_format.keep_with_next = True
    return p


def body(doc, text, lead=None):
    p = doc.add_paragraph(); p.paragraph_format.space_after = Pt(5); p.paragraph_format.line_spacing = 1.08
    if lead: set_font(p.add_run(lead), 14, True)
    set_font(p.add_run(text), 14)


def bullets(doc, values):
    for value in values:
        p = doc.add_paragraph(style="List Bullet"); p.paragraph_format.space_after = Pt(2)
        set_font(p.add_run(value), 14)


def configure(doc):
    section = doc.sections[0]
    section.page_width = Inches(8.5); section.page_height = Inches(11)
    section.top_margin = Inches(.7); section.bottom_margin = Inches(.7)
    section.left_margin = Inches(.8); section.right_margin = Inches(.8)
    normal = doc.styles["Normal"]
    normal.font.name = FONT; normal._element.rPr.rFonts.set(qn("w:eastAsia"), FONT); normal.font.size = Pt(14)
    title = doc.styles["Title"]
    title.font.name = FONT; title._element.rPr.rFonts.set(qn("w:eastAsia"), FONT); title.font.size = Pt(28); title.font.bold = True; title.font.color.rgb = RGBColor(0,0,0)
    for level, size in ((1, 21), (2, 18), (3, 16)):
        s = doc.styles[f"Heading {level}"]
        s.font.name = FONT; s._element.rPr.rFonts.set(qn("w:eastAsia"), FONT); s.font.size = Pt(size); s.font.bold = True; s.font.color.rgb = RGBColor(0,0,0)
    p = section.footer.paragraphs[0]; p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    set_font(p.add_run("Smart Tambon Test Plan   |   Version 1.0"), 9.5, False, "666666")


def main():
    qa = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    output = Path(sys.argv[2])
    counts = qa["summary"]
    module_counts = Counter(item["module"] for item in qa["scenarios"])
    priority_counts = Counter(item["priority"] for item in qa["test_cases"])

    doc = Document(); configure(doc)
    logo = Path(__file__).resolve().parents[1] / "app/assets/images/logo-smart-tambon.png"
    if logo.exists():
        p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER; p.paragraph_format.space_before = Pt(45)
        p.add_run().add_picture(str(logo), width=Inches(1.1))
    p = doc.add_paragraph(style="Title"); p.alignment = WD_ALIGN_PARAGRAPH.CENTER; p.paragraph_format.space_before = Pt(24)
    set_font(p.add_run("แผนการทดสอบระบบ Smart Tambon"), 28, True)
    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    set_font(p.add_run("System Test Plan"), 18, True)
    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER; p.paragraph_format.space_before = Pt(36)
    set_font(p.add_run("อ้างอิง BRD SRS As Built ฉบับวันที่ 18 พฤศจิกายน 2569"), 14)
    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    set_font(p.add_run("เวอร์ชัน 1.0   สถานะ Draft for Review"), 14, True, NAVY)
    doc.add_page_break()

    heading(doc, "การควบคุมเอกสาร", 1)
    table(doc, ["รายการ", "รายละเอียด"], [
        ("ชื่อเอกสาร", "แผนการทดสอบระบบ Smart Tambon"),
        ("เวอร์ชัน", "1.0"),
        ("สถานะ", "Draft for Review"),
        ("วันที่", "18 พฤศจิกายน 2569"),
        ("เอกสารอ้างอิง", "Smart Tambon BRD SRS As Built 2026 11 18"),
        ("ขอบเขต Requirement", f"{counts['requirements']} ข้อ Functional {counts['functional']} และ Non Functional {counts['nonfunctional']}"),
        ("Test Assets", f"Test Scenario {counts['scenarios']} รายการ และ Test Case {counts['test_cases']} รายการ"),
    ], widths=[1.7, 5.2])
    heading(doc, "ผู้ทบทวนและอนุมัติ", 2)
    table(doc, ["บทบาท", "ชื่อ", "ผล", "วันที่"], [
        ("Test Lead", "", "รอพิจารณา", ""), ("Product Owner", "", "รอพิจารณา", ""),
        ("Development Lead", "", "รอพิจารณา", ""), ("Security หรือ Infrastructure", "", "รอพิจารณา", ""),
    ], widths=[2.0, 1.8, 1.8, 1.3], small=True)

    heading(doc, "1 วัตถุประสงค์", 1)
    body(doc, "แผนนี้กำหนดแนวทาง ทรัพยากร สภาพแวดล้อม เกณฑ์ และหลักฐานสำหรับตรวจสอบว่าระบบ Smart Tambon ทำงานตรงตาม BRD SRS As Built โดยเน้นความถูกต้องของข้อมูล การแยกองค์กรและพื้นที่ วงจรเหตุการณ์ GIS การนำเข้า Integration และความมั่นคงปลอดภัย")

    heading(doc, "2 ขอบเขตการทดสอบ", 1)
    heading(doc, "2.1 อยู่ในขอบเขต", 2)
    module_rows = [(module, count, "ตาม BRD และ RTM") for module, count in sorted(module_counts.items())]
    table(doc, ["โมดูล", "Scenario", "หลักอ้างอิง"], module_rows, widths=[3.3, 1.1, 2.5], small=True)
    heading(doc, "2.2 นอกขอบเขต", 2)
    bullets(doc, [
        "บริการหรือ provider ที่ BRD ระบุว่าเป็น stub หรือยังไม่ implement",
        "Penetration Test โดยบุคคลที่สามและการรับรองมาตรฐาน เว้นแต่มีการว่าจ้างแยก",
        "ข้อมูล Production จริง การส่ง SMS LINE หรือประกาศจริง โดยไม่มี sandbox และหนังสืออนุญาต",
        "SLA RTO RPO retention browser matrix และ load target ที่ยังเป็น TBD จนกว่าเจ้าของระบบจะอนุมัติ",
    ])

    heading(doc, "3 กลยุทธ์การทดสอบ", 1)
    table(doc, ["ประเภท", "เป้าหมาย", "หลักฐาน"], [
        ("Smoke", "ยืนยัน service login dashboard map API และฐานข้อมูลหลัง deploy", "Checklist และ screenshot"),
        ("Functional", "ตรวจ Positive Negative Boundary ของทุก FR", "ผล Test Case"),
        ("Authorization", "ตรวจ role organization area และ IDOR", "Request response และ account matrix"),
        ("API", "ตรวจ status schema validation pagination และ error handling", "API collection และ response"),
        ("GIS", "ตรวจ SRID geometry locate overlap layer และ tile", "GeoJSON screenshot และ query result"),
        ("Integration", "ตรวจ Weather GISTDA FIRMS Water LINE SMS AI TTS MQTT", "Stub sandbox log และ delivery record"),
        ("Data", "ตรวจ import export version restore duplicate และ integrity", "Input output และ reconciliation"),
        ("Security", "ตรวจ XSS injection CSRF upload token secret และ access control", "Security test evidence"),
        ("Performance", "ตรวจ response map file import และ concurrent workload ตามเป้าที่อนุมัติ", "Metric และรายงานผล"),
        ("Resilience", "หยุด upstream worker หรือ data store แบบควบคุม", "Log recovery และ data check"),
        ("Compatibility", "ตรวจ browser device และ responsive ตาม matrix ที่อนุมัติ", "Compatibility matrix"),
        ("Regression", "รัน Rails และ Weather automated tests รวม critical manual regression", "Test log และ report"),
    ], widths=[1.25, 3.75, 1.9], small=True)

    heading(doc, "4 ระดับความสำคัญและความเสี่ยง", 1)
    table(doc, ["Priority", "จำนวน Test Case", "แนวทาง"], [
        ("Critical", priority_counts.get("Critical", 0), "รันทุก build สำหรับ flow สำคัญและก่อน UAT"),
        ("High", priority_counts.get("High", 0), "รันใน System Test และ Regression ที่กระทบ"),
        ("Medium", priority_counts.get("Medium", 0), "รันครบก่อน release และเมื่อ module เปลี่ยน"),
        ("Low", priority_counts.get("Low", 0), "รันตามเวลาหรือ risk assessment"),
    ], widths=[1.2, 1.4, 4.3])
    heading(doc, "4.1 ความเสี่ยงสำคัญ", 2)
    bullets(doc, [
        "ข้อมูลรั่วข้าม organization_key หรือพื้นที่จากหน้าเว็บ API export worker หรือ AI",
        "Geometry หรือพิกัดผิดทำให้แสดงพื้นที่และประเมินผลกระทบคลาดเคลื่อน",
        "Import หรือ restore ล้มเหลวกลางทางและทิ้งข้อมูลครึ่งชุด",
        "Webhook schedule และ retry สร้างเหตุหรือส่งข้อความซ้ำ",
        "ค่าที่ไม่มีจาก upstream ถูกแสดงเป็นศูนย์และทำให้ผู้ใช้ตัดสินใจผิด",
        "Secret ปรากฏใน HTML log API response หรือไฟล์ export",
        "การทดสอบ Integration ส่งข้อความหรือเผยแพร่ไปยังปลายทางจริงโดยไม่ตั้งใจ",
    ])

    heading(doc, "5 สภาพแวดล้อมทดสอบ", 1)
    table(doc, ["องค์ประกอบ", "ข้อกำหนดขั้นต่ำ", "การตรวจสอบก่อนรัน"], [
        ("Rails Web", "Build หรือ commit ที่ระบุได้", "health page login และ log ไม่มี startup error"),
        ("PostgreSQL PostGIS", "Migration ล่าสุดและ test data", "extension schema index และ connection"),
        ("MongoDB", "Indexes และ test database", "connection และ collection ที่จำเป็น"),
        ("MinIO", "Bucket แยกจาก production", "upload download delete test object"),
        ("MQTT", "Test broker และ credential", "publish subscribe test topic"),
        ("Weather service", "Test database และ stub provider", "health locations และ forecast endpoint"),
        ("External services", "Stub sandbox หรือ disabled", "ยืนยันปลายทางและ key ไม่ใช่ production"),
        ("Browser", "ตาม compatibility matrix", "cache clear timezone Asia Bangkok"),
    ], widths=[1.5, 3.0, 2.4], small=True)

    heading(doc, "6 ข้อมูลทดสอบ", 1)
    bullets(doc, [
        "บัญชี system_admin และองค์กร A กับ B โดยแต่ละองค์กรมี subdistrict_admin และ subdistrict_user",
        "พื้นที่ A และ B ที่ไม่ทับกัน รวมพิกัดในพื้นที่ นอกพื้นที่ บนแนวเขต และพิกัดผิด",
        "เหตุการณ์ทุกสถานะและประเภท รวมเหตุซ้ำ เหตุมีรูป และเหตุที่ยกระดับเป็นภัยพิบัติ",
        "ไฟล์ import ถูกต้อง ผิด schema encoding ไทย แถวซ้ำ ไฟล์ใหญ่ และพิกัดผิด",
        "Sensor payload ปัจจุบัน เก่า อนาคต ซ้ำ ขาดฟิลด์ และค่าผิดช่วง",
        "ช่องทาง LINE SMS Telegram Signal AI และ TTS แบบ stub หรือ sandbox เท่านั้น",
        "ห้ามใช้ข้อมูลส่วนบุคคล เบอร์โทร token รูปภาพ หรือ credential ของ production",
    ])

    heading(doc, "7 Entry Criteria", 1)
    bullets(doc, [
        "BRD SRS และ Test Plan ได้รับการทบทวนในระดับที่ใช้ตัดสิน Pass Fail ได้",
        "Build ถูก deploy และระบุ commit image tag migration และ configuration ได้",
        "Test Environment และ Test Data พร้อมและแยกจาก production",
        "Critical dependency พร้อมหรือมี stub ที่ได้รับอนุมัติ",
        "Known issue และส่วนเปลี่ยนแปลงของ build ถูกส่งให้ทีมทดสอบ",
        "Automated smoke หรือ test ขั้นต้นผ่านโดยไม่มี blocker",
    ])
    heading(doc, "8 Exit Criteria", 1)
    bullets(doc, [
        "Test Case ในขอบเขตถูก Execute ครบ หรือรายการ Blocked มีผู้รับผิดชอบและมติ",
        "Critical และ High requirement มี coverage ครบ",
        "ไม่มี defect ระดับ Critical เปิดอยู่",
        "Defect High ที่ยังเปิดต้องมี risk acceptance จาก Product Owner",
        "Authorization isolation import restore notification และ critical E2E ผ่าน",
        "Regression ที่เกี่ยวข้องผ่านและไม่มีข้อมูลสูญหาย",
        "Test Summary Report และ RTM อัปเดตผลล่าสุดแล้ว",
    ])

    heading(doc, "9 เกณฑ์ Pass Fail Blocked", 1)
    table(doc, ["ผล", "นิยาม"], [
        ("Pass", "Actual Result ตรง Expected Result ทุกข้อและไม่มี side effect ที่ไม่อนุญาต"),
        ("Fail", "ผลต่างจาก Expected Result มีข้อผิดพลาด หรือเกิดข้อมูลรั่วหรือข้อมูลเสียหาย"),
        ("Blocked", "ไม่สามารถรันได้จาก environment dependency data หรือ decision ที่ขาด โดยต้องมีหลักฐาน"),
        ("Not Run", "ยังไม่ได้เริ่มทดสอบ"),
        ("N A", "ไม่ใช้กับ build หรือ configuration นี้และได้รับการอนุมัติพร้อมเหตุผล"),
    ], widths=[1.2, 5.7])

    heading(doc, "10 การจัดการ Defect", 1)
    table(doc, ["Severity", "ตัวอย่าง", "เป้าหมายการจัดการ"], [
        ("Critical", "ระบบล่ม ข้อมูลสูญหาย ข้ามสิทธิ์ secret รั่ว ส่งจริงผิดปลายทาง", "หยุดทดสอบส่วนที่เสี่ยงและแก้ก่อนดำเนินต่อ"),
        ("High", "Flow หลักใช้ไม่ได้ ข้อมูลสำคัญผิด ไม่มี workaround", "แก้ในรอบทดสอบปัจจุบัน"),
        ("Medium", "มีผลกระทบและมี workaround", "วางแผนแก้และ retest"),
        ("Low", "ข้อความ UI layout หรือข้อผิดพลาดเล็กน้อย", "จัดลำดับตาม release"),
    ], widths=[1.2, 3.8, 1.9], small=True)
    body(doc, "Defect ทุกใบต้องมี Build Environment Preconditions Steps Expected Actual Severity Priority Evidence Test Data และลิงก์ Test Case พร้อมระบุผล Retest และ Regression")

    heading(doc, "11 การทดสอบซ้ำและ Regression", 1)
    bullets(doc, [
        "Retest เฉพาะ defect ด้วยข้อมูลเดิมและตรวจกรณีใกล้เคียง",
        "รัน regression ของ module ต้นทางและ downstream ที่ใช้ข้อมูลร่วมกัน",
        "การเปลี่ยน authorization ต้องรัน role organization area matrix",
        "การเปลี่ยน model migration import หรือ storage ต้องรัน data integrity และ restore",
        "การเปลี่ยน integration หรือ worker ต้องรัน duplicate retry timeout และ secret test",
    ])

    heading(doc, "12 บทบาทและความรับผิดชอบ", 1)
    table(doc, ["บทบาท", "ความรับผิดชอบ"], [
        ("Product Owner", "ยืนยัน requirement TBD acceptance และ risk acceptance"),
        ("Test Lead", "วางแผน มอบหมาย ควบคุม coverage และรายงานผล"),
        ("Tester", "เตรียมข้อมูล รัน Test Case เก็บหลักฐาน และรายงาน defect"),
        ("Developer", "วิเคราะห์ defect แก้ไข เพิ่ม automated test และแจ้งผลกระทบ"),
        ("Infrastructure", "เตรียม environment log backup monitoring และ sandbox"),
        ("Security Reviewer", "ทบทวน access control secret upload token และ finding สำคัญ"),
    ], widths=[1.7, 5.2])

    heading(doc, "13 แผนดำเนินงาน", 1)
    table(doc, ["ระยะ", "กิจกรรม", "ผู้รับผิดชอบ", "กำหนด"], [
        ("Preparation", "ทบทวน BRD RTM Scenario Case Environment และ Data", "Test Lead", "TBD"),
        ("Cycle 1", "Smoke Functional API GIS และ Integration", "Tester", "TBD"),
        ("Cycle 2", "Retest Regression Security และ Resilience", "Tester Dev Infra", "TBD"),
        ("UAT", "Business flow และ acceptance โดยผู้ใช้", "Product Owner Users", "TBD"),
        ("Closure", "สรุปผล RTM defect risk และ sign off", "Test Lead", "TBD"),
    ], widths=[1.1, 3.3, 1.6, 0.9], small=True)

    heading(doc, "14 ผลส่งมอบ", 1)
    bullets(doc, [
        "Test Plan ฉบับอนุมัติ",
        "RTM ที่เชื่อม Requirement Scenario Test Case ผลและ Defect",
        "Test Scenario และ Test Case ที่ระบุ Priority Preconditions Data Steps Expected Result",
        "Test Execution Evidence และ Defect Report",
        "Test Summary Report และ Release Recommendation",
    ])
    heading(doc, "15 ประเด็นที่ต้องตัดสินใจก่อน UAT", 1)
    bullets(doc, [
        "SLA response time concurrent users และขนาดไฟล์สูงสุด",
        "RTO RPO retention และขอบเขต backup restore",
        "Browser device และ accessibility target",
        "Password lockout session timeout MFA และ rate limit",
        "เกณฑ์ความแม่นยำของ simulation forecast geocode และ AI",
        "ผู้อนุมัติการส่งจริงและ auto publish",
    ])

    output.parent.mkdir(parents=True, exist_ok=True)
    doc.save(output)
    print(output)


if __name__ == "__main__":
    main()
