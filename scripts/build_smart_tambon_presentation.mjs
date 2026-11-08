import fs from 'node:fs/promises';
import path from 'node:path';
import { Presentation, PresentationFile } from '@oai/artifact-tool';

const OUT = path.resolve('presentation_output');
const SHOT = 'F:/ESM_doc/SmartCity/Smart Tambon/Screenshot';
const W = 1280, H = 720;
const C = { navy:'#0B2942', blue:'#1479C9', cyan:'#3BB8D8', ink:'#173042', muted:'#557181', pale:'#EDF6FA', white:'#FFFFFF', green:'#2C8A69', gold:'#E0A23A', red:'#D85B52' };
const FONT = 'Sarabun';

async function bytes(p){ const b=await fs.readFile(p); return b.buffer.slice(b.byteOffset,b.byteOffset+b.byteLength); }
async function writeBlob(p,b){ await fs.writeFile(p,new Uint8Array(await b.arrayBuffer())); }
function addText(slide,text,x,y,w,h,size=24,color=C.ink,bold=false,align='left'){
  const s=slide.shapes.add({geometry:'textbox',position:{left:x,top:y,width:w,height:h},fill:'none',line:{fill:'none',width:0}});
  s.text=text; s.text.style={fontFamily:FONT,fontSize:size,color,bold,alignment:align,verticalAlignment:'middle'}; return s;
}
function rect(slide,x,y,w,h,fill=C.white,r='rounded-xl',line='none',shadow){
  return slide.shapes.add({geometry:r==='none'?'rect':'roundRect',position:{left:x,top:y,width:w,height:h},fill,line:{style:'solid',fill:line,width:line==='none'?0:1},borderRadius:r==='none'?undefined:r,shadow});
}
function line(slide,x1,y1,x2,y2,color=C.blue,width=3){ return slide.shapes.add({geometry:'line',position:{left:x1,top:y1,width:x2-x1,height:y2-y1},fill:'none',line:{style:'solid',fill:color,width}}); }
async function image(slide,rel,x,y,w,h,fit='cover',radius='rounded-xl'){
  const opts={blob:await bytes(`${SHOT}/${rel}`),contentType:'image/jpeg',alt:`ภาพหน้าจอระบบ Smart Tambon: ${rel}`,fit,position:{left:x,top:y,width:w,height:h},geometry:radius==='none'?'rect':'roundRect'};
  if(radius!=='none') opts.borderRadius=radius;
  return slide.images.add(opts);
}
function header(slide,no,title,subtitle=''){
  addText(slide,String(no).padStart(2,'0'),54,34,58,28,14,C.blue,true);
  addText(slide,title,54,66,1172,58,31,C.navy,true);
  if(subtitle) addText(slide,subtitle,54,124,1172,35,16,C.muted,false);
  rect(slide,54,166,1172,2,C.blue,'none');
}
function pill(slide,text,x,y,w,color=C.blue){ rect(slide,x,y,w,36,color,'rounded-full'); addText(slide,text,x+10,y,w-20,36,15,C.white,true,'center'); }
function bulletCard(slide,title,body,x,y,w,h,accent=C.blue){ rect(slide,x,y,w,h,C.white,'rounded-xl','#D7E6EE','shadow-sm'); rect(slide,x,y,7,h,accent,'rounded-xl'); addText(slide,title,x+24,y+14,w-44,30,20,C.navy,true); addText(slide,body,x+24,y+48,w-44,h-60,15,C.muted,false); }
function footer(slide,no){ addText(slide,'SMART TAMBON SAFETY THAILAND',54,686,320,18,10,'#76909E',true); addText(slide,String(no),1185,686,40,18,10,'#76909E',true,'right'); }
function base(){ return Presentation.create({slideSize:{width:W,height:H}}); }

async function main(){
  await fs.mkdir(OUT,{recursive:true});
  const p=base();

  // 1 Cover
  { const s=p.slides.add(); s.background.fill=C.navy; await image(s,'1_ภาพรวมเมือง/1_ภาพรวม.JPG',540,0,740,720,'cover','none'); rect(s,0,0,720,720,C.navy,'none'); rect(s,520,0,260,720,{color:C.navy,transparency:18},'none'); pill(s,'ระบบบริหารจัดการเมืองและความปลอดภัย',64,62,318,C.blue); addText(s,'Smart Tambon\nSafety Thailand',64,126,550,142,44,C.white,true); addText(s,'ระบบบริหารจัดการความปลอดภัยอัจฉริยะ\nสำหรับองค์การบริหารส่วนตำบล',64,292,530,90,25,'#D7EEF8',true); addText(s,'รวมข้อมูลพื้นที่ เหตุการณ์ ทรัพยากร และการสื่อสาร\nไว้ในศูนย์กลางเดียว เพื่อการตัดสินใจที่รวดเร็วและตรวจสอบได้',64,414,500,88,18,'#B9D4E1'); rect(s,64,572,430,2,C.cyan,'none'); addText(s,'เอกสารนำเสนอระบบและสาธิตการใช้งาน',64,590,420,28,14,C.white,true); }

  // 2 Pain points
  { const s=p.slides.add(); s.background.fill=C.pale; header(s,2,'เมื่อข้อมูลแยกส่วน การตัดสินใจก็ช้าลง','ปัญหาที่หน่วยงานท้องถิ่นพบในงานประจำและภาวะฉุกเฉิน'); const cards=[['ข้อมูลกระจายหลายช่องทาง','เอกสาร แชต โทรศัพท์ และไฟล์หลายชุด ทำให้ค้นหาและตรวจสอบยาก'],['มองภาพพื้นที่ไม่ครบ','ขาดมุมมองเดียวที่เชื่อมเหตุการณ์ ประชากร ทรัพยากร และตำแหน่งบนแผนที่'],['ประสานงานล่าช้า','การรับเรื่อง มอบหมาย ติดตาม และแจ้งเตือนยังไม่อยู่ในกระบวนการเดียว'],['รายงานใช้เวลานาน','ต้องรวบรวมข้อมูลซ้ำก่อนสรุปให้ผู้บริหารและประชาชน']]; cards.forEach((c,i)=>bulletCard(s,c[0],c[1],54+(i%2)*586,210+Math.floor(i/2)*190,552,154,[C.red,C.gold,C.blue,C.green][i])); addText(s,'Smart Tambon เปลี่ยนข้อมูลกระจัดกระจายให้เป็นการปฏิบัติงานที่เห็นภาพเดียวกันทั้งองค์กร',145,613,990,44,21,C.navy,true,'center'); footer(s,2); }

  // 3 Solution
  { const s=p.slides.add(); s.background.fill=C.white; header(s,3,'แพลตฟอร์มเดียว เชื่อมทุกภารกิจของตำบล','จากการเฝ้าระวัง ไปจนถึงการสรุปผลเพื่อวางแผนเชิงรุก'); await image(s,'1_ภาพรวมเมือง/2_ภาพรวม(ต่อ).JPG',610,205,570,344,'contain'); const items=[['รู้ทันสถานการณ์','แดชบอร์ดและข้อมูลสิ่งแวดล้อม'],['ประชาชนมีส่วนร่วม','รับแจ้งเหตุผ่านลิงก์หรือคิวอาร์โค้ด'],['จัดการรับมือ','มอบหมายทีมและทรัพยากรเป็นระบบ'],['สรุปข้อมูลอัจฉริยะ','ผู้ช่วย AI ช่วยสรุปและสร้างรายงาน']]; items.forEach((c,i)=>bulletCard(s,c[0],c[1],54,205+i*93,500,76,[C.blue,C.cyan,C.green,C.gold][i])); addText(s,'ข้อมูลศูนย์กลางเดียว',758,572,280,30,19,C.navy,true,'center'); addText(s,'ลดขั้นตอนซ้ำ • เห็นสถานะล่าสุด • ตรวจสอบย้อนหลังได้',650,607,490,28,15,C.muted,false,'center'); footer(s,3); }

  // 4 Dashboard
  { const s=p.slides.add(); s.background.fill=C.pale; header(s,4,'ศูนย์สั่งการอัจฉริยะ เห็นสถานการณ์ในหน้าจอเดียว','ติดตามตัวชี้วัดสำคัญและเหตุการณ์ที่ต้องดำเนินการ'); await image(s,'1_ภาพรวมเมือง/1_ภาพรวม.JPG',54,204,770,435,'contain'); const ys=[214,333,452]; [['ภาพรวมเหตุการณ์','เห็นงานรอรับเรื่อง กำลังดำเนินการ และเสร็จสิ้น'],['ข้อมูลสิ่งแวดล้อม','ติดตามสภาพอากาศ ฝุ่น และข้อมูลจากเซนเซอร์'],['ข้อมูลพื้นที่','เชื่อมจำนวนประชากร ครัวเรือน และข้อมูลที่เกี่ยวข้อง']].forEach((c,i)=>bulletCard(s,c[0],c[1],860,ys[i],320,94,[C.blue,C.cyan,C.green][i])); footer(s,4); }

  // 5 Map
  { const s=p.slides.add(); s.background.fill=C.white; header(s,5,'แผนที่อัจฉริยะ วิเคราะห์ผลกระทบจากพื้นที่จริง','เชื่อมตำแหน่งเหตุการณ์ ขอบเขตพื้นที่สำคัญ ประชากร และกล้องวงจรปิด'); await image(s,'2_แผนที่เมือง/3_วิเคราะห์พื้นที่.JPG',54,204,566,350,'contain'); await image(s,'2_แผนที่เมือง/4_ผลการประเมินและพื้นที่สำคัญ.JPG',660,204,566,350,'contain'); [['ปักหมุดเหตุการณ์','แสดงพิกัดและรายละเอียดบนแผนที่'],['วาดขอบเขตได้เอง','กำหนดหมู่บ้านหรือพื้นที่เสี่ยงได้ตรงจุด'],['ประเมินผลกระทบ','คำนวณประชากรและครัวเรือนในพื้นที่'],['เชื่อมกล้องวงจรปิด','เปิดดูจุดกล้องจากบริบทของพื้นที่']].forEach((c,i)=>{ const x=54+i*293; rect(s,x,583,270,64,C.pale,'rounded-lg'); addText(s,c[0],x+15,590,240,22,16,C.navy,true,'center'); addText(s,c[1],x+12,614,246,24,12,C.muted,false,'center'); }); footer(s,5); }

  // 6 Public report
  { const s=p.slides.add(); s.background.fill=C.pale; header(s,6,'ประชาชนแจ้งเหตุได้ง่าย เจ้าหน้าที่รับเรื่องได้ทันที','ไม่ต้องติดตั้งแอปพลิเคชัน ใช้งานผ่านลิงก์หรือคิวอาร์โค้ด'); await image(s,'3_เหตุการณ์ทั่วไป/10_แชร์แบบฟอร์ม.JPG',54,210,500,315,'contain'); await image(s,'3_เหตุการณ์ทั่วไป/11_แบบฟอร์มประชาชนกรอก.JPG',700,210,470,315,'contain'); const steps=['พบเหตุการณ์','สแกนคิวอาร์โค้ด','กรอกข้อมูลและแนบภาพ','เรื่องเข้าสู่ระบบ']; steps.forEach((t,i)=>{ const x=76+i*292; rect(s,x,565,230,52,i===3?C.green:C.white,'rounded-full','#CEE0E9'); addText(s,`${i+1}  ${t}`,x+10,565,210,52,15,i===3?C.white:C.navy,true,'center'); if(i<3) addText(s,'→',x+238,570,42,40,24,C.blue,true,'center'); }); footer(s,6); }

  // 7 Workflow
  { const s=p.slides.add(); s.background.fill=C.white; header(s,7,'บริหารเหตุการณ์แบบครบวงจร ตั้งแต่รับเรื่องจนปิดงาน','ทุกฝ่ายเห็นสถานะเดียวกัน พร้อมประวัติการดำเนินงาน'); const imgs=['3_เหตุการณ์ทั่วไป/1_เหตุการทั่วไป-รอรับเรื่อง.JPG','3_เหตุการณ์ทั่วไป/4_เหตุการทั่วไป-กำลังดำเนินการ.JPG','3_เหตุการณ์ทั่วไป/5_เหตุการทั่วไป-เสร็จสิ้น.JPG']; const labels=[['รอรับเรื่อง','ตรวจสอบความถูกต้องและลำดับความสำคัญ'],['กำลังดำเนินการ','มอบหมายทีม อุปกรณ์ และบันทึกความคืบหน้า'],['เสร็จสิ้น','บันทึกผลการดำเนินงานและปิดงาน']]; for(let i=0;i<3;i++){ const x=54+i*398; await image(s,imgs[i],x,215,360,232,'contain'); pill(s,labels[i][0],x+70,470,220,[C.blue,C.gold,C.green][i]); addText(s,labels[i][1],x+28,518,304,58,14,C.muted,false,'center'); if(i<2) addText(s,'→',x+362,305,36,38,28,C.blue,true,'center'); } addText(s,'ผลลัพธ์: ติดตามงานได้ชัดเจน ลดงานตกหล่น และตรวจสอบย้อนหลังได้',220,615,840,34,19,C.navy,true,'center'); footer(s,7); }

  // 8 Disaster
  { const s=p.slides.add(); s.background.fill=C.pale; header(s,8,'จากการตั้งรับ สู่การเตรียมพร้อมรับมือภัยพิบัติ','ประเมินสถานการณ์ วางแผน และจัดสรรทรัพยากรก่อนเกิดเหตุจริง'); await image(s,'4_ภัยพิบัติ/3_ประเมินสถานการณ์.JPG',54,205,550,300,'contain'); await image(s,'4_ภัยพิบัติ/6_แผนรับมือภัยพิบัติ.JPG',676,205,550,300,'contain'); const flow=['ยกระดับเหตุ','ประเมินพื้นที่','คำนวณทรัพยากร','สร้างแผนรับมือ']; flow.forEach((t,i)=>{const x=70+i*300; rect(s,x,560,240,56,[C.red,C.gold,C.blue,C.green][i],'rounded-full'); addText(s,t,x+10,560,220,56,17,C.white,true,'center'); if(i<3)addText(s,'→',x+246,567,42,40,24,C.navy,true,'center');}); footer(s,8); }

  // 9 Communication
  { const s=p.slides.add(); s.background.fill=C.white; header(s,9,'แจ้งเตือนอัตโนมัติ ให้ข้อมูลถึงผู้รับผิดชอบตรงเวลา','เชื่อม LINE OA และช่องทางที่หน่วยงานกำหนด'); await image(s,'12_ตั้งค่าระบบ/5_เทมเพลตข้อความ.JPG',54,205,560,330,'contain'); await image(s,'12_ตั้งค่าระบบ/8_ทดสอบแจ้งเตือน - ส่งเทมเพลต.JPG',666,205,560,330,'contain'); [['เทมเพลตข้อความ','ดึงข้อมูลสถานที่ ประเภทเหตุ และเวลา มาใส่ข้อความอัตโนมัติ'],['แจ้งเตือนแบบกลุ่ม','ส่งถึงทีมงานหรือผู้บริหารเมื่อเกิดเหตุใหม่'],['ทดสอบก่อนใช้งาน','ตรวจสอบรูปแบบและช่องทางส่งได้จากหน้าตั้งค่า']].forEach((c,i)=>bulletCard(s,c[0],c[1],54+i*390,572,364,70,[C.blue,C.cyan,C.green][i])); footer(s,9); }

  // 10 AI news PA
  { const s=p.slides.add(); s.background.fill=C.pale; header(s,10,'AI สรุปข่าวและสร้างเสียงตามสาย ภายในขั้นตอนเดียว','เปลี่ยนข้อมูลในชุมชนให้พร้อมสื่อสารได้รวดเร็วและสม่ำเสมอ'); await image(s,'7_ข่าว/1_ข่าวประชาสัมพันธ์.JPG',54,205,600,380,'contain'); const x=715; const steps=[['รวบรวมข้อมูล','เหตุการณ์ กิจกรรม โครงการ และประกาศ'],['AI เรียบเรียงข่าว','สรุปสาระสำคัญและจัดทำสคริปต์'],['เจ้าหน้าที่ตรวจสอบ','แก้ไข อนุมัติ และทดลองฟัง'],['กระจายเสียง','สร้างไฟล์เสียงและส่งสู่ระบบเสียงตามสาย']]; steps.forEach((c,i)=>{ bulletCard(s,c[0],c[1],x,205+i*100,465,82,[C.blue,C.cyan,C.gold,C.green][i]); if(i<3) line(s,x+230,287+i*100,x+230,303+i*100,C.blue,2); }); addText(s,'ช่วยลดเวลาจัดทำข่าว และคงสิทธิ์การตรวจสอบไว้กับเจ้าหน้าที่ก่อนเผยแพร่',170,620,940,30,17,C.navy,true,'center'); footer(s,10); }

  // 11 Data
  { const s=p.slides.add(); s.background.fill=C.white; header(s,11,'นำเข้าข้อมูลอย่างเป็นระบบ พร้อมประวัติที่ตรวจสอบได้','รองรับไฟล์ CSV, Excel และ PDF รวมถึงการสร้างชุดข้อมูลเฉพาะหน่วยงาน'); await image(s,'10_นำเข้าข้อมูล/2_นำเข้าด้วยไฟล์.JPG',54,205,350,220,'contain'); await image(s,'10_นำเข้าข้อมูล/3_จับคู่ข้อมูล.JPG',465,205,350,220,'contain'); await image(s,'10_นำเข้าข้อมูล/33_คลังข้อมูลไฟล์.JPG',876,205,350,220,'contain'); const steps=[['1','อัปโหลดไฟล์'],['2','จับคู่คอลัมน์'],['3','ตรวจสอบตัวอย่าง'],['4','บันทึกเป็นรุ่นข้อมูล'],['5','ค้นจากคลังไฟล์']]; steps.forEach((c,i)=>{const x=65+i*240; rect(s,x,475,205,60,i===4?C.green:C.pale,'rounded-full','#D4E4EC'); addText(s,c[0],x+12,485,34,40,18,i===4?C.white:C.blue,true,'center'); addText(s,c[1],x+48,482,145,44,15,i===4?C.white:C.navy,true);}); addText(s,'ทุกการนำเข้าและแก้ไขมีประวัติ ช่วยย้อนดูแหล่งที่มาและรุ่นข้อมูลได้อย่างโปร่งใส',155,590,970,44,18,C.navy,true,'center'); footer(s,11); }

  // 12 AI assistant
  { const s=p.slides.add(); s.background.fill=C.pale; header(s,12,'ผู้ช่วย AI เปลี่ยนข้อมูลให้เป็นข้อสรุปที่พร้อมใช้','ถามข้อมูล สรุปเหตุการณ์ สร้างกราฟ และจัดทำรายงานได้จากระบบ'); await image(s,'11_ผู้ช่วย AI/1_ผู้ช่วย AI.JPG',54,205,750,405,'contain'); const items=[['สรุปสถานการณ์','สรุปรายสัปดาห์หรือรายเดือนเป็นภาษาที่เข้าใจง่าย'],['สร้างกราฟและตาราง','ช่วยมองแนวโน้มและสัดส่วนของข้อมูล'],['จัดทำรายงาน','สร้างไฟล์รายงานเพื่อเสนอผู้บริหาร'],['เก็บผลลัพธ์','บันทึกงานสำคัญไว้เรียกใช้ภายหลัง']]; items.forEach((c,i)=>bulletCard(s,c[0],c[1],840,205+i*102,340,84,[C.blue,C.cyan,C.gold,C.green][i])); footer(s,12); }

  // 13 Use case
  { const s=p.slides.add(); s.background.fill=C.white; header(s,13,'ตัวอย่างการใช้งาน: รับมือเหตุอุทกภัยแบบเชื่อมโยงทั้งระบบ','ทุกขั้นตอนใช้ข้อมูลชุดเดียวกัน ตั้งแต่รับแจ้งจนสรุปบทเรียน'); const steps=[['1','ประชาชนแจ้งเหตุ','แนบภาพและตำแหน่ง'],['2','ศูนย์สั่งการตรวจสอบ','เห็นเหตุบนแผนที่'],['3','ประเมินผลกระทบ','จำนวนประชาชนและพื้นที่เสี่ยง'],['4','มอบหมายและแจ้งเตือน','ทีม อุปกรณ์ และ LINE OA'],['5','ติดตามและสรุปผล','ปิดงานและสร้างรายงาน']]; steps.forEach((c,i)=>{const x=54+i*238; rect(s,x,225,210,235,C.pale,'rounded-xl','#D2E5EE'); rect(s,x,225,210,12,[C.blue,C.cyan,C.gold,C.green,C.navy][i],'rounded-xl'); addText(s,c[0],x+20,252,52,52,28,[C.blue,C.cyan,C.gold,C.green,C.navy][i],true,'center'); addText(s,c[1],x+18,322,174,48,17,C.navy,true,'center'); addText(s,c[2],x+20,378,170,48,14,C.muted,false,'center'); if(i<4)addText(s,'→',x+208,310,30,40,23,C.blue,true,'center');}); addText(s,'จากข้อมูลพื้นที่ → การปฏิบัติ → หลักฐานและรายงาน',270,505,740,44,24,C.navy,true,'center'); addText(s,'ช่วยให้ผู้บริหารตัดสินใจจากข้อมูลจริง เจ้าหน้าที่ทำงานต่อเนื่อง และประชาชนรับรู้ความคืบหน้าได้เร็วขึ้น',175,562,930,62,17,C.muted,false,'center'); footer(s,13); }

  // 14 Benefits
  { const s=p.slides.add(); s.background.fill=C.pale; header(s,14,'คุณค่าที่หน่วยงานได้รับตั้งแต่วันแรกที่ใช้งาน','ออกแบบให้รองรับทั้งงานประจำ เหตุฉุกเฉิน และการวางแผนระยะยาว'); const benefits=[['ข้อมูลรวมศูนย์','ค้นง่าย เชื่อมโยง และมีแหล่งอ้างอิง'],['เห็นพื้นที่จริง','แผนที่ช่วยประเมินผลกระทบได้ตรงบริบท'],['ประสานงานเป็นระบบ','สถานะ ทีม และทรัพยากรอยู่ในกระบวนการเดียว'],['สื่อสารรวดเร็ว','แจ้งเตือนและประชาสัมพันธ์ผ่านช่องทางที่คุ้นเคย'],['ตรวจสอบย้อนหลัง','มีประวัติรุ่นข้อมูลและการดำเนินงาน'],['ต่อยอดได้','เพิ่มชุดข้อมูล ผู้ใช้ และการเชื่อมต่อได้ตามบริบท']]; benefits.forEach((c,i)=>bulletCard(s,c[0],c[1],54+(i%3)*390,210+Math.floor(i/3)*165,364,132,[C.blue,C.cyan,C.green,C.gold,C.red,C.navy][i])); rect(s,170,572,940,60,C.navy,'rounded-full'); addText(s,'Smart Tambon ไม่ได้เพียงเก็บข้อมูล แต่ทำให้ข้อมูลขับเคลื่อนการทำงานของทั้งองค์กร',190,572,900,60,20,C.white,true,'center'); footer(s,14); }

  // 15 Closing
  { const s=p.slides.add(); s.background.fill=C.navy; await image(s,'2_แผนที่เมือง/1_แผนที่เมือง.JPG',650,0,630,720,'cover','none'); rect(s,0,0,780,720,C.navy,'none'); addText(s,'พร้อมยกระดับตำบลให้ปลอดภัย\nและบริหารจัดการได้ดียิ่งขึ้น',64,105,620,140,36,C.white,true); addText(s,'เริ่มจากข้อมูลที่มี เชื่อมกระบวนการที่สำคัญ\nและขยายสู่เมืองอัจฉริยะที่ตอบโจทย์ประชาชนจริง',64,282,560,90,21,'#CDE7F2'); rect(s,64,424,488,76,C.blue,'rounded-full'); addText(s,'นัดสาธิตระบบตามบริบทของหน่วยงาน',84,424,448,76,21,C.white,true,'center'); addText(s,'Smart Tambon Safety Thailand',64,582,430,32,18,C.white,true); addText(s,'ระบบเดียว • ข้อมูลเดียว • การตัดสินใจที่มั่นใจขึ้น',64,620,470,28,15,'#9FC7D9'); }

  for(const [i,s] of p.slides.items.entries()) await writeBlob(path.join(OUT,`slide-${String(i+1).padStart(2,'0')}.png`),await p.export({slide:s,format:'png',scale:1}));
  await writeBlob(path.join(OUT,'deck-montage.webp'),await p.export({format:'webp',montage:true}));
  const pptx=await PresentationFile.exportPptx(p); await pptx.save(path.join(OUT,'System_Product_Presentation.pptx'));
  console.log(`Created ${p.slides.items.length} slides`);
}
main().catch(e=>{console.error(e);process.exitCode=1});
