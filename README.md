# Smart Tambon Geo Admin

ต้นแบบ Rails สำหรับแผนที่จังหวัด/ตำบล: PostgreSQL + PostGIS เก็บขอบเขตที่ต้อง query เชิงพื้นที่, MongoDB เก็บข้อมูล dynamic, OpenLayers แสดง OSM และ MapTiler satellite, Devise ดูแล login

## เริ่มใช้งานด้วย Docker

1. คัดลอก `.env.example` เป็น `.env` แล้วใส่ `LONGDO_MAP_KEY` สำหรับหมุดสถานที่ และ MapTiler key สำหรับภาพดาวเทียม (หากไม่ใส่ MapTiler ระบบยังใช้แผนที่ถนน OSM ได้)
2. รัน:

```bash
docker compose build
docker compose up
```

3. เปิด `http://localhost:3000` และ login ด้วย `admin@smartcity.local` / `ChangeMe123!`
4. เปลี่ยนรหัสผ่านและค่าจากตัวอย่างก่อน deploy

Seed เริ่มต้นนำเข้ารายชื่อจังหวัดครบ 77 จังหวัด พร้อมรหัสจังหวัดและชื่อภาษาอังกฤษ โดย sidebar และ API เรียงชื่อตามตัวอักษรไทย ส่วนข้อมูลตำบลที่นำเข้าเพิ่มเติมจะเรียงตามชื่อไทยอัตโนมัติเช่นกัน

คำสั่งที่ใช้บ่อย:

```bash
docker compose run --rm web bin/rails db:seed
docker compose run --rm web bin/rails console
docker compose run --rm web bin/rails db:migrate
docker compose run --rm web bin/rails db:mongoid:create_indexes
docker compose down
```

## นำเข้าตำบลและขอบเขตจริงทั่วประเทศ

ตัวนำเข้าใช้ Feature Layer “ขอบเขตตำบล” ของ GISTDA ซึ่งมี polygon, รหัสและชื่อจังหวัด/อำเภอ/ตำบล ชื่ออังกฤษ ประชากร และข้อมูลแหล่งที่มา โดยร้องขอ GeoJSON เป็น EPSG:4326 แล้วรวม polygon ตำบลเป็นขอบเขตจังหวัด

หลังเปิดระบบครั้งแรกแล้ว รัน:

```bash
docker compose exec web sh bin/import-gistda-boundaries
```

หากดาวน์โหลด GeoJSON ไว้แล้ว ให้วางที่ `tmp/data/tambons.geojson` และรันเฉพาะตัวนำเข้า:

```bash
docker compose exec web bundle exec rails geo:import_tambons FILE=tmp/data/tambons.geojson
```

ตัวนำเข้าเป็นแบบ upsert จึงรันซ้ำเพื่ออัปเดตได้ พร้อมซ่อม geometry ด้วย `ST_MakeValid`, แปลงเป็น MultiPolygon, คำนวณจุดภายในพื้นที่ด้วย `ST_PointOnSurface` และบันทึกรายการที่ผิดพลาดไว้ใน `tmp/data/rejected-tambons.json`

ตัวดาวน์โหลดจะขอ Object ID ก่อน แล้วดาวน์โหลดเป็นชุดย่อยชุดละ 250 features เพื่อป้องกัน HTTP 500 จากการขอ polygon ทั้งประเทศใน request เดียว หากเซิร์ฟเวอร์ไม่เสถียร สามารถลดขนาดชุดได้:

```bash
docker compose exec -e GISTDA_BATCH_SIZE=100 web sh bin/import-gistda-boundaries
```

ชื่อพื้นที่จากแหล่งข้อมูลจะถูก normalize โดยตัดคำนำหน้า `จังหวัด`, `อำเภอ`, `เขต`, `ตำบล`, `แขวง` และคำนำหน้าภาษาอังกฤษก่อนบันทึก เพื่อให้ค้นหาและเรียงตามตัวอักษรได้ถูกต้อง

## โครงสร้างสำคัญ

- `Province`, `Subdistrict`: ActiveRecord/PostGIS พร้อม GiST index
- `DynamicLayer`: Mongoid document สำหรับ sensor/event/metadata ที่ schema เปลี่ยนได้
- `/api/provinces/:id` และ `/api/subdistricts/:id`: ส่ง GeoJSON ให้ OpenLayers
- หน้า dashboard: lazy-load tree, zoom/fit polygon, highlight และสลับ base map
- `/api/places`: ดึง POI จาก Longdo Map โดยเก็บ API key ไว้ฝั่งเซิร์ฟเวอร์ และ cache ผลลัพธ์ใน MongoDB ตามหมวด/พื้นที่/รัศมีเป็นเวลา 24 ชั่วโมง (`LONGDO_CACHE_TTL`); หน้า dashboard เปิด/ปิดหมุดสถานที่ราชการ โรงเรียน โรงพยาบาล และสถานที่ท่องเที่ยวได้
- Satellite ต้องมี `MAPTILER_KEY`; attribution ถูกกำหนดใน source

## สิทธิ์ผู้ใช้

ผู้ดูแลระบบจัดการบัญชีได้ที่ `/users` และกำหนดได้ 3 role:

- `system_admin`: เข้าถึงแผนที่และข้อมูลทุกตำบล
- `subdistrict_admin`: เข้าถึงเฉพาะตำบลที่กำหนด พร้อมข้อมูล DynamicLayer ฉบับเต็มของตำบลนั้น และเห็นเส้นขอบตำบลอื่นในจังหวัดเดียวกันแบบไม่มีรายละเอียด
- `subdistrict_user`: ดูแผนที่และข้อมูลทุกตำบลได้เหมือนผู้ดูแลระบบ แต่ไม่มีสิทธิ์เข้าหน้าหรือ API จัดการบัญชีผู้ใช้

ผู้ใช้ระดับตำบลต้องกำหนดตำบลที่รับผิดชอบเสมอ การตรวจสิทธิ์ทำที่ API ด้วย จึงไม่สามารถข้ามขอบเขตด้วยการเรียก URL โดยตรงได้

การรัน `bin/rails db:seed` จะสร้างบัญชีตัวอย่างสำหรับทุกตำบลในกรุงเทพฯ 2 บัญชีต่อตำบล:

- `admin.<รหัสตำบล>@smartcity.local` สำหรับผู้ดูแลประจำตำบล
- `user.<รหัสตำบล>@smartcity.local` สำหรับผู้ใช้งานประจำตำบล

ต้องกำหนด `SAMPLE_USER_PASSWORD` เป็นรหัสผ่านที่รัดกุมก่อนรัน seed และควรเปลี่ยนรหัสผ่านทั้งหมดก่อนใช้งานจริง

## ก่อนขึ้น production

กำหนด secrets ผ่าน secret manager, บังคับ HTTPS, จำกัด CORS/CSP ให้ครอบคลุม tile domains, เพิ่ม authorization ตาม role, pagination/cache สำหรับข้อมูล dynamic, simplify polygon ตาม zoom level และใช้ background job ในการ import/validate geometry (`ST_MakeValid`) ไม่ควรส่ง polygon รายละเอียดสูงทั้งหมดในครั้งเดียว
