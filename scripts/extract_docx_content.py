from pathlib import Path
import sys

from docx import Document


def main() -> None:
    source = Path(sys.argv[1])
    document = Document(source)

    print("# PARAGRAPHS")
    for index, paragraph in enumerate(document.paragraphs, start=1):
        text = paragraph.text.strip()
        if text:
            print(f"P{index:04d}\t[{paragraph.style.name}]\t{text}")

    print("\n# TABLES")
    for table_index, table in enumerate(document.tables, start=1):
        print(f"\n## TABLE {table_index}")
        for row_index, row in enumerate(table.rows, start=1):
            values = [cell.text.replace("\n", " / ").strip() for cell in row.cells]
            print(f"R{row_index:03d}\t" + "\t".join(values))


if __name__ == "__main__":
    main()
