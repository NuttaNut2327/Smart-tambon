from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from docx import Document


REQ_RE = re.compile(r"^(FR-[A-Z]+-\d{3})\s+(.+)$")
NFR_RE = re.compile(r"^NFR-[A-Z]+-\d{3}$")
BR_RE = re.compile(r"^BR-\d{3}$")
RULE_RE = re.compile(r"^RULE-\d{3}$")


def clean(value: str) -> str:
    return " ".join(value.replace("\xa0", " ").split())


def main() -> None:
    source = Path(sys.argv[1])
    target = Path(sys.argv[2])
    document = Document(source)
    paragraphs = document.paragraphs
    requirements = []
    index = 0
    current_section = ""
    while index < len(paragraphs):
        paragraph = paragraphs[index]
        text = clean(paragraph.text)
        style = paragraph.style.name if paragraph.style else ""
        if style.startswith("Heading") and text:
            current_section = text
        match = REQ_RE.match(text)
        if not match:
            index += 1
            continue
        requirement_id, title = match.groups()
        statement = ""
        acceptance = []
        source_note = "Repository"
        cursor = index + 1
        collecting_acceptance = False
        while cursor < len(paragraphs):
            item = paragraphs[cursor]
            item_text = clean(item.text)
            if REQ_RE.match(item_text) or (item.style and item.style.name.startswith("Heading")):
                break
            if item_text.startswith("ข้อกำหนด"):
                statement = clean(item_text.removeprefix("ข้อกำหนด"))
            elif item_text == "เกณฑ์ยอมรับ":
                collecting_acceptance = True
            elif item_text.startswith("หลักฐาน As Built"):
                source_note = clean(item_text.removeprefix("หลักฐาน As Built")) or "Repository"
                collecting_acceptance = False
            elif collecting_acceptance and item_text:
                acceptance.append(item_text)
            cursor += 1
        requirements.append({
            "id": requirement_id,
            "type": "FR",
            "module_code": requirement_id.split("-")[1],
            "section": current_section,
            "title": title,
            "statement": statement,
            "acceptance": acceptance,
            "source": source_note,
        })
        index = cursor

    table_requirements = []
    business_requirements = []
    rules = []
    for table in document.tables:
        for row in table.rows[1:]:
            cells = [clean(cell.text) for cell in row.cells]
            if not cells:
                continue
            if NFR_RE.match(cells[0]):
                table_requirements.append({
                    "id": cells[0], "type": "NFR", "module_code": cells[0].split("-")[1],
                    "section": "ข้อกำหนดที่ไม่ใช่หน้าที่", "title": cells[1] if len(cells) > 1 else "",
                    "statement": cells[2] if len(cells) > 2 else "", "acceptance": [], "source": "BRD",
                })
            elif BR_RE.match(cells[0]):
                business_requirements.append({"id": cells[0], "statement": cells[1] if len(cells) > 1 else ""})
            elif RULE_RE.match(cells[0]):
                rules.append({"id": cells[0], "statement": cells[1] if len(cells) > 1 else ""})

    payload = {
        "source": str(source),
        "functional_requirements": requirements,
        "nonfunctional_requirements": table_requirements,
        "business_requirements": business_requirements,
        "business_rules": rules,
    }
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({
        "functional": len(requirements),
        "nonfunctional": len(table_requirements),
        "business": len(business_requirements),
        "rules": len(rules),
        "output": str(target),
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()
