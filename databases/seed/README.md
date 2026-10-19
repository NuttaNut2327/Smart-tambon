# Seed data (database dumps)

ข้อมูลตั้งต้นของสภาพแวดล้อม development ทั้งสองฐานข้อมูล

**Snapshot ใน git:** โฟลเดอร์ `2026-10-18/` (ข้อมูล ณ วันที่ 18 ต.ค. 2569) เก็บไว้ชุดเดียว
ไฟล์ PostgreSQL ถูกแบ่งเป็น `.part-aa`, `.part-ab`, ... ส่วนละไม่เกิน 45 MB เพราะ GitHub ไม่รับไฟล์เกิน 100 MB
(ต่อกลับเป็นไฟล์เดียวได้ด้วย `cat postgres_smart_city_development.dump.part-* > postgres_smart_city_development.dump`)

**Dump ในเครื่อง:** ไฟล์ที่ `dump.sh` สร้างไว้ตรงโฟลเดอร์นี้ ถูก ignore — ไม่เข้า git

| ไฟล์ | ฐานข้อมูล | รูปแบบ |
|---|---|---|
| `postgres_smart_city_development.dump` (หรือ `.part-*`) | PostgreSQL/PostGIS `smart_city_development` (ขอบเขตจังหวัด/ตำบล, สถานีน้ำ, ผู้ใช้ ฯลฯ) | `pg_dump -Fc` |
| `mongo_smart_city_development.archive.gz` | MongoDB `smart_city_development` (DynamicLayer, เหตุการณ์, โครงการ, กล้อง, ข่าว, ตั้งค่า ฯลฯ) | `mongodump --archive --gzip` |

ไม่รวมฐาน `*_test` (ชุดทดสอบสร้างใหม่เอง)

## กู้คืน

```bash
docker compose up -d db mongo
databases/seed/restore.sh
```

สคริปต์จะลบข้อมูล development เดิมทั้งหมดแล้วแทนที่ — ใช้ dump ในเครื่องถ้ามี ไม่เช่นนั้นใช้ snapshot `2026-10-18/`
ระบุโฟลเดอร์เองได้: `databases/seed/restore.sh databases/seed/2026-10-18`

## สร้างไฟล์ใหม่

```bash
databases/seed/dump.sh
```

## ข้อควรระวัง

- ไฟล์มีบัญชีผู้ใช้ (รหัสผ่านแบบ hash) และค่าตั้งค่าที่เข้ารหัส เช่น API key ของผู้ให้บริการ AI/TTS — อย่าเผยแพร่ใน repository สาธารณะ
- ค่าที่เข้ารหัสจะถอดได้เฉพาะเครื่องที่ใช้ `secret_key_base` / master key เดียวกัน เครื่องอื่นต้องกรอก API key ใหม่
- ไม่ต้อง commit dump ชุดใหม่ ถ้าจำเป็นต้องเก็บ ให้แบ่งไฟล์ (`split -b 45m`) แบบเดียวกับ snapshot
