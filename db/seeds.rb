admin = User.find_or_initialize_by(email: ENV.fetch("ADMIN_EMAIL", "admin@smartcity.local"))
admin.password = ENV.fetch("ADMIN_PASSWORD", "ChangeMe123!")
admin.password_confirmation = admin.password
admin.username = ENV.fetch("ADMIN_USERNAME", "admin")
admin.role = :system_admin
admin.subdistrict = nil
admin.save!

# รหัสจังหวัดตามระบบรหัสภูมิศาสตร์ของประเทศไทย เรียงตามชื่อภาษาไทยตอนนำเข้า
provinces = [
  ["81", "กระบี่", "Krabi"],
  ["10", "กรุงเทพมหานคร", "Bangkok"],
  ["71", "กาญจนบุรี", "Kanchanaburi"],
  ["46", "กาฬสินธุ์", "Kalasin"],
  ["62", "กำแพงเพชร", "Kamphaeng Phet"],
  ["40", "ขอนแก่น", "Khon Kaen"],
  ["22", "จันทบุรี", "Chanthaburi"],
  ["24", "ฉะเชิงเทรา", "Chachoengsao"],
  ["20", "ชลบุรี", "Chon Buri"],
  ["18", "ชัยนาท", "Chai Nat"],
  ["36", "ชัยภูมิ", "Chaiyaphum"],
  ["86", "ชุมพร", "Chumphon"],
  ["92", "ตรัง", "Trang"],
  ["23", "ตราด", "Trat"],
  ["63", "ตาก", "Tak"],
  ["26", "นครนายก", "Nakhon Nayok"],
  ["73", "นครปฐม", "Nakhon Pathom"],
  ["48", "นครพนม", "Nakhon Phanom"],
  ["30", "นครราชสีมา", "Nakhon Ratchasima"],
  ["80", "นครศรีธรรมราช", "Nakhon Si Thammarat"],
  ["60", "นครสวรรค์", "Nakhon Sawan"],
  ["12", "นนทบุรี", "Nonthaburi"],
  ["96", "นราธิวาส", "Narathiwat"],
  ["55", "น่าน", "Nan"],
  ["38", "บึงกาฬ", "Bueng Kan"],
  ["31", "บุรีรัมย์", "Buri Ram"],
  ["13", "ปทุมธานี", "Pathum Thani"],
  ["77", "ประจวบคีรีขันธ์", "Prachuap Khiri Khan"],
  ["25", "ปราจีนบุรี", "Prachin Buri"],
  ["94", "ปัตตานี", "Pattani"],
  ["14", "พระนครศรีอยุธยา", "Phra Nakhon Si Ayutthaya"],
  ["56", "พะเยา", "Phayao"],
  ["82", "พังงา", "Phang Nga"],
  ["93", "พัทลุง", "Phatthalung"],
  ["66", "พิจิตร", "Phichit"],
  ["65", "พิษณุโลก", "Phitsanulok"],
  ["76", "เพชรบุรี", "Phetchaburi"],
  ["67", "เพชรบูรณ์", "Phetchabun"],
  ["54", "แพร่", "Phrae"],
  ["83", "ภูเก็ต", "Phuket"],
  ["44", "มหาสารคาม", "Maha Sarakham"],
  ["49", "มุกดาหาร", "Mukdahan"],
  ["58", "แม่ฮ่องสอน", "Mae Hong Son"],
  ["35", "ยโสธร", "Yasothon"],
  ["95", "ยะลา", "Yala"],
  ["45", "ร้อยเอ็ด", "Roi Et"],
  ["85", "ระนอง", "Ranong"],
  ["21", "ระยอง", "Rayong"],
  ["70", "ราชบุรี", "Ratchaburi"],
  ["16", "ลพบุรี", "Lop Buri"],
  ["52", "ลำปาง", "Lampang"],
  ["51", "ลำพูน", "Lamphun"],
  ["33", "ศรีสะเกษ", "Si Sa Ket"],
  ["47", "สกลนคร", "Sakon Nakhon"],
  ["90", "สงขลา", "Songkhla"],
  ["91", "สตูล", "Satun"],
  ["11", "สมุทรปราการ", "Samut Prakan"],
  ["75", "สมุทรสงคราม", "Samut Songkhram"],
  ["74", "สมุทรสาคร", "Samut Sakhon"],
  ["27", "สระแก้ว", "Sa Kaeo"],
  ["19", "สระบุรี", "Saraburi"],
  ["17", "สิงห์บุรี", "Sing Buri"],
  ["64", "สุโขทัย", "Sukhothai"],
  ["72", "สุพรรณบุรี", "Suphan Buri"],
  ["84", "สุราษฎร์ธานี", "Surat Thani"],
  ["32", "สุรินทร์", "Surin"],
  ["43", "หนองคาย", "Nong Khai"],
  ["39", "หนองบัวลำภู", "Nong Bua Lam Phu"],
  ["15", "อ่างทอง", "Ang Thong"],
  ["37", "อำนาจเจริญ", "Amnat Charoen"],
  ["41", "อุดรธานี", "Udon Thani"],
  ["53", "อุตรดิตถ์", "Uttaradit"],
  ["61", "อุทัยธานี", "Uthai Thani"],
  ["34", "อุบลราชธานี", "Ubon Ratchathani"],
  ["57", "เชียงราย", "Chiang Rai"],
  ["50", "เชียงใหม่", "Chiang Mai"],
  ["42", "เลย", "Loei"]
].sort_by { |(_, name_th, _)| name_th }

provinces.each do |code, name_th, name_en|
  province = Province.find_or_initialize_by(code: code)
  province.update!(name_th: name_th, name_en: name_en)
end

puts "Imported #{Province.count} provinces"
puts "Admin: #{admin.email} / #{ENV.fetch('ADMIN_PASSWORD', 'ChangeMe123!')} (change immediately)"

bangkok = Province.find_by!(code: "10")
sample_password = ENV["SAMPLE_USER_PASSWORD"].presence
raise "Set SAMPLE_USER_PASSWORD before creating Bangkok sample accounts" if sample_password.blank?
created_samples = 0

bangkok.subdistricts.find_each do |subdistrict|
  {
    subdistrict_admin: "admin.#{subdistrict.code}@smartcity.local",
    subdistrict_user: "user.#{subdistrict.code}@smartcity.local"
  }.each do |role, email|
    user = User.find_or_initialize_by(email: email)
    created_samples += 1 if user.new_record?
    user.role = role
    user.subdistrict = subdistrict
    user.username = "#{role == :subdistrict_admin ? 'admin' : 'user'}#{subdistrict.code}"
    if user.new_record?
      user.password = sample_password
      user.password_confirmation = sample_password
    end
    user.save!
  end
end

puts "Created or updated #{bangkok.subdistricts.count * 2} Bangkok sample accounts (#{created_samples} new)"
