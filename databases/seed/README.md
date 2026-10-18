# Seed data (database dumps)

ข้อมูลตั้งต้นของสภาพแวดล้อม development ทั้งสองฐานข้อมูล ณ วันที่ 18 ต.ค. 2569

| ไฟล์ | ฐานข้อมูล | รูปแบบ |
|---|---|---|
| `postgres_smart_city_development.dump` | PostgreSQL/PostGIS `smart_city_development` (ขอบเขตจังหวัด/ตำบล, สถานีน้ำ, ผู้ใช้ ฯลฯ) | `pg_dump -Fc` |
| `mongo_smart_city_development.archive.gz` | MongoDB `smart_city_development` (DynamicLayer, เหตุการณ์, โครงการ, กล้อง, ข่าว, ตั้งค่า ฯลฯ) | `mongodump --archive --gzip` |

ไม่รวมฐาน `*_test` (ชุดทดสอบสร้างใหม่เอง)

## กู้คืน

```bash
docker compose up -d db mongo
databases/seed/restore.sh
```

สคริปต์จะลบข้อมูล development เดิมทั้งหมดแล้วแทนที่ด้วยไฟล์ในโฟลเดอร์นี้

## สร้างไฟล์ใหม่

```bash
databases/seed/dump.sh
```

## ข้อควรระวัง

- ไฟล์มีบัญชีผู้ใช้ (รหัสผ่านแบบ hash) และค่าตั้งค่าที่เข้ารหัส เช่น API key ของผู้ให้บริการ AI/TTS — อย่าเผยแพร่ใน repository สาธารณะ
- ค่าที่เข้ารหัสจะถอดได้เฉพาะเครื่องที่ใช้ `secret_key_base` / master key เดียวกัน เครื่องอื่นต้องกรอก API key ใหม่
- `postgres_smart_city_development.dump` ใหญ่ประมาณ 107 MB เกินขีดจำกัดไฟล์ละ 100 MB ของ GitHub — ถ้าจะ commit ให้ใช้ Git LFS
