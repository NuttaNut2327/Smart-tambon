# เอกสารสรุปโครงการ Smart City

## 1. ภาพรวมโครงการ

Smart City เป็นเว็บแพลตฟอร์มสำหรับแสดงข้อมูลพื้นที่การปกครองของประเทศไทยบนแผนที่ โดยผู้ใช้สามารถเลือกจังหวัดและตำบลจากเมนูแบบ Tree ทางด้านซ้าย ระบบจะแสดงตำแหน่ง ขยายแผนที่ไปยังพื้นที่ที่เลือก และไฮไลต์ polygon ขอบเขตบนแผนที่ด้านขวา

ระบบออกแบบเป็นหน้า Admin Dashboard พร้อมระบบเข้าสู่ระบบ และรองรับแผนที่ถนนจาก OpenStreetMap รวมถึงภาพถ่ายดาวเทียมจาก MapTiler

## 2. วัตถุประสงค์

- แสดงรายชื่อจังหวัดและตำบลทั่วประเทศไทย
- แสดง polygon และขอบเขตพื้นที่การปกครองบนแผนที่
- ค้นหาและเลือกพื้นที่จากเมนูแบบ Tree
- Zoom แผนที่ไปยังจังหวัดหรือตำบลที่เลือก
- รองรับข้อมูลเชิงพื้นที่และการค้นหาเชิงภูมิศาสตร์
- รองรับข้อมูล Dynamic เช่น Sensor, Event หรือข้อมูลเมืองที่เปลี่ยนแปลงบ่อย
- เตรียมโครงสร้างสำหรับพัฒนาเป็นระบบ Smart City ในอนาคต

## 3. เทคโนโลยี

| ส่วนประกอบ | เทคโนโลยี |
| --- | --- |
| Web Application | Ruby on Rails 7.2 |
| ฐานข้อมูลหลัก | PostgreSQL 16 |
| ข้อมูลเชิงพื้นที่ | PostGIS |
| ข้อมูล Dynamic | MongoDB 7 และ Mongoid |
| ระบบ Login | Devise |
| Map Engine | OpenLayers |
| แผนที่ถนน | OpenStreetMap |
| ภาพถ่ายดาวเทียม | MapTiler Satellite |
| Container | Docker และ Docker Compose |

## 4. สถาปัตยกรรมระบบ

ระบบประกอบด้วย Docker services จำนวน 3 ส่วน

1. `web` — Ruby on Rails Application และ API
2. `db` — PostgreSQL พร้อม PostGIS extension
3. `mongo` — MongoDB สำหรับข้อมูล Dynamic

Rails ติดต่อ PostgreSQL ผ่าน ActiveRecord และ `activerecord-postgis-adapter` ส่วน MongoDB ติดต่อผ่าน Mongoid หน้าเว็บใช้ OpenLayers ในการเรียก tile และแสดง GeoJSON ที่ได้รับจาก Rails API

## 5. ฟังก์ชันหลัก

### 5.1 ระบบผู้ใช้งาน

- หน้า Login สำหรับผู้ดูแลระบบ
- ตรวจสอบ session ก่อนเข้า Dashboard
- รองรับการออกจากระบบ
- ใช้ Devise เพื่อรองรับการเพิ่ม Reset Password และการจัดการบัญชีต่อไป

### 5.2 Admin Dashboard

- Sidebar ด้านซ้าย
- รายชื่อจังหวัดเรียงตามตัวอักษรไทย
- Lazy-load รายชื่อตำบลเมื่อเปิดจังหวัด
- ช่องค้นหาพื้นที่
- แสดงบัญชีผู้ใช้ที่เข้าสู่ระบบ
- Responsive layout สำหรับหน้าจอขนาดเล็ก

### 5.3 ระบบแผนที่

- แผนที่ถนน OpenStreetMap
- ภาพถ่ายดาวเทียม MapTiler เมื่อกำหนด API key
- ปุ่มสลับแผนที่ถนนและดาวเทียม
- Zoom และ Fit ไปยัง polygon ที่เลือก
- เลือกจังหวัดแล้วปรับมุมมองให้เห็นขอบเขตทั้งจังหวัด
- เลือกตำบลแล้ว Zoom ใกล้ขึ้นและ Highlight ขอบเขตตำบล
- ใช้จุดกึ่งกลางเป็นตำแหน่งสำรองเมื่อพื้นที่ยังไม่มี polygon
- Highlight polygon ด้วยสีและเส้นขอบ
- แสดงข้อความกรณียังไม่มีข้อมูล polygon

### 5.4 ข้อมูลพื้นที่การปกครอง

- จังหวัดครบ 77 จังหวัด
- รหัสจังหวัดและชื่อไทย–อังกฤษ
- รหัสและชื่ออำเภอที่ตำบลสังกัด
- รหัสและชื่อตำบลไทย–อังกฤษ
- ข้อมูลประชากรเมื่อชุดข้อมูลต้นทางระบุ
- Polygon จังหวัดและตำบลแบบ MultiPolygon
- จุดภายในพื้นที่สำหรับการ Zoom
- Spatial index แบบ GiST

## 6. โครงสร้างข้อมูล PostgreSQL/PostGIS

### ตาราง `provinces`

| Field | รายละเอียด |
| --- | --- |
| `code` | รหัสจังหวัด 2 หลัก |
| `name_th` | ชื่อจังหวัดภาษาไทย |
| `name_en` | ชื่อจังหวัดภาษาอังกฤษ |
| `boundary` | ขอบเขตจังหวัดชนิด MultiPolygon, SRID 4326 |
| `center` | จุดภายในจังหวัดสำหรับ Zoom |

### ตาราง `subdistricts`

| Field | รายละเอียด |
| --- | --- |
| `province_id` | จังหวัดที่ตำบลสังกัด |
| `code` | รหัสตำบล |
| `name_th` | ชื่อตำบลภาษาไทย |
| `name_en` | ชื่อตำบลภาษาอังกฤษ |
| `district_code` | รหัสอำเภอ |
| `district_name_th` | ชื่ออำเภอภาษาไทย |
| `district_name_en` | ชื่ออำเภอภาษาอังกฤษ |
| `population` | จำนวนประชากรจากชุดข้อมูลต้นทาง |
| `source_name` | ชื่อแหล่งข้อมูล |
| `source_date` | วันที่ของข้อมูลต้นทาง |
| `boundary` | ขอบเขตตำบลชนิด MultiPolygon, SRID 4326 |
| `center` | จุดภายในตำบลสำหรับ Zoom |

### ตาราง `users`

เก็บบัญชีผู้ใช้งาน รหัสผ่านแบบเข้ารหัส และข้อมูลที่ Devise ใช้สำหรับ session และการกู้คืนรหัสผ่าน

## 7. ข้อมูล Dynamic ใน MongoDB

Model `DynamicLayer` ใช้เก็บข้อมูลที่โครงสร้างเปลี่ยนแปลงได้ เช่น

- Sensor และค่าตรวจวัด
- เหตุการณ์ในพื้นที่
- จุดแจ้งเตือน
- ข้อมูลจราจร
- Metadata ของชั้นข้อมูล

Document ประกอบด้วย `layer_key`, `name`, `payload`, `location`, `active` และ timestamps พร้อม 2dsphere index สำหรับข้อมูลตำแหน่ง

## 8. API

| Endpoint | รายละเอียด |
| --- | --- |
| `GET /api/provinces` | รายชื่อจังหวัดทั้งหมด |
| `GET /api/provinces/:id` | GeoJSON ของจังหวัด |
| `GET /api/provinces/:province_id/subdistricts` | รายชื่อตำบลในจังหวัด |
| `GET /api/subdistricts/:id` | GeoJSON และข้อมูลตำบล |
| `GET /api/dynamic_layers` | ข้อมูล Dynamic จาก MongoDB |

API ถูกป้องกันด้วยระบบ Login และส่ง polygon ในรูปแบบ GeoJSON เพื่อให้ OpenLayers นำไปแสดงผล

## 9. แหล่งข้อมูลขอบเขต

ตัวนำเข้าเตรียมไว้สำหรับ Feature Layer “ขอบเขตตำบล” ของ GISTDA ArcGIS REST Service โดยร้องขอข้อมูลเป็น GeoJSON และแปลงระบบพิกัดเป็น EPSG:4326

ขั้นตอนนำเข้าจะดำเนินการดังนี้

1. ดาวน์โหลด GeoJSON ขอบเขตตำบล
2. จับคู่จังหวัดด้วยรหัสจังหวัด
3. Upsert ข้อมูลตำบลด้วยรหัสพื้นที่
4. แปลง Polygon เป็น MultiPolygon
5. ซ่อม geometry ด้วย `ST_MakeValid`
6. คำนวณจุดภายในพื้นที่ด้วย `ST_PointOnSurface`
7. รวม polygon ตำบลเป็นขอบเขตจังหวัดด้วย `ST_UnaryUnion`
8. บันทึกรายการที่นำเข้าไม่สำเร็จไว้สำหรับตรวจสอบ

## 10. การติดตั้งด้วย Docker Compose

### เตรียมค่า Environment

คัดลอก `.env.example` เป็น `.env` แล้วกำหนดค่าที่ต้องการ

```env
MAPTILER_KEY=your_maptiler_key
ADMIN_EMAIL=admin@smartcity.local
ADMIN_PASSWORD=ChangeMe123!
```

### Build และเปิดระบบ

```bash
docker compose build
docker compose up -d
```

เปิดระบบที่ `http://localhost:3000`

### นำเข้าข้อมูลจังหวัด

```bash
docker compose exec web bundle exec rails db:seed
```

### นำเข้าตำบลและขอบเขตทั่วประเทศ

```bash
docker compose exec web sh bin/import-gistda-boundaries
```

### ตรวจสอบสถานะ

```bash
docker compose ps
docker compose logs -f web
```

### หยุดระบบ

```bash
docker compose down
```

## 11. โครงสร้างไฟล์สำคัญ

```text
smart-city/
├── app/
│   ├── controllers/        Rails controllers และ API
│   ├── models/             PostgreSQL และ MongoDB models
│   ├── views/              หน้า Login และ Dashboard
│   ├── javascript/         OpenLayers และการควบคุม Tree
│   └── assets/             CSS ของ Admin Dashboard
├── bin/
│   └── import-gistda-boundaries
├── config/
│   ├── database.yml        PostgreSQL/PostGIS
│   ├── mongoid.yml         MongoDB
│   └── routes.rb           Web และ API routes
├── db/
│   ├── migrate/            Database schema
│   └── seeds.rb            จังหวัด 77 จังหวัดและ Admin
├── lib/tasks/
│   └── administrative_boundaries.rake
├── compose.yaml
├── Dockerfile
└── README.md
```

## 12. สถานะปัจจุบัน

- จัดทำโครงสร้าง Rails Application แล้ว
- จัดทำ Docker Compose แล้ว
- จัดทำ schema PostgreSQL/PostGIS และ MongoDB แล้ว
- เพิ่มรายชื่อจังหวัดครบ 77 จังหวัดใน seed แล้ว
- จัดทำตัวนำเข้าข้อมูลตำบลและ polygon แล้ว
- จัดทำหน้า Admin Dashboard และระบบ Login แล้ว
- จัดทำ OpenLayers map และการเลือกพื้นที่แล้ว
- ตรวจสอบรูปแบบ Docker Compose ผ่านแล้ว

ชุดข้อมูลตำบลและ polygon ขนาดเต็มจะถูกดาวน์โหลดและบันทึกลงฐานข้อมูลเมื่อรันคำสั่งนำเข้าใน container ที่สามารถเชื่อมต่ออินเทอร์เน็ตได้

## 13. งานที่ควรพัฒนาต่อก่อน Production

- เปลี่ยนรหัสผ่าน Admin เริ่มต้น
- จัดเก็บ secrets ใน secret manager
- เพิ่ม Role และ Permission
- บังคับ HTTPS
- กำหนด Content Security Policy และ CORS
- เพิ่ม pagination และ caching ของ API
- ทำ polygon simplification ตามระดับ Zoom
- แยกงานนำเข้าข้อมูลไปทำใน Background Job
- เพิ่มหน้าแสดงสถานะและประวัติการนำเข้าข้อมูล
- เพิ่มระบบสำรอง PostgreSQL และ MongoDB
- เพิ่ม automated tests และ deployment pipeline
- ตรวจสอบเงื่อนไขการใช้งานและวันที่ปรับปรุงของข้อมูลต้นทางก่อนใช้งานจริง
