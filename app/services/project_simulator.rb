# Builds realistic-looking simulated projects for demos and chart testing; see `rake projects:simulate`.
class ProjectSimulator
  CODE_PATTERN = /\ASIM-/

  # Name templates and budget ranges (baht) for each suggested project type.
  TEMPLATES = {
    "infrastructure" => [
      ["ถนน", "ก่อสร้างถนนคอนกรีตเสริมเหล็ก สายบ้าน%{village} หมู่ที่ %{moo}", 350_000..2_500_000],
      ["ถนน", "ซ่อมแซมถนนลูกรัง หมู่ที่ %{moo}", 80_000..450_000],
      ["ท่อระบายน้ำ", "วางท่อระบายน้ำ คสล. พร้อมบ่อพัก หมู่ที่ %{moo}", 200_000..1_200_000],
      ["ไฟฟ้าส่องสว่าง", "ติดตั้งไฟฟ้าส่องสว่างพลังงานแสงอาทิตย์ หมู่ที่ %{moo}", 150_000..900_000],
      ["ประปา", "ปรับปรุงระบบประปาหมู่บ้าน หมู่ที่ %{moo}", 250_000..1_500_000],
      ["สะพาน", "ก่อสร้างสะพาน คสล. ข้ามลำห้วย%{stream}", 600_000..3_500_000]
    ],
    "water" => [
      ["ขุดลอกคลอง", "ขุดลอกลำห้วย%{stream} หมู่ที่ %{moo}", 150_000..800_000],
      ["ฝาย", "ก่อสร้างฝายชะลอน้ำลำห้วย%{stream}", 200_000..1_200_000],
      ["สระเก็บน้ำ", "ขุดสระเก็บน้ำสาธารณะ หมู่ที่ %{moo}", 300_000..1_800_000],
      ["ส่งเสริมการเกษตร", "ส่งเสริมการปลูกพืชหลังนาและเกษตรปลอดภัย", 30_000..150_000]
    ],
    "economy" => [
      ["ฝึกอาชีพ", "ฝึกอบรมอาชีพเสริมการจักสานและแปรรูปผลผลิต", 20_000..120_000],
      ["วิสาหกิจชุมชน", "สนับสนุนวิสาหกิจชุมชนผ้าทอบ้าน%{village}", 50_000..300_000],
      ["ท่องเที่ยวชุมชน", "พัฒนาแหล่งท่องเที่ยวชุมชนและจุดชมวิว", 100_000..600_000]
    ],
    "social" => [
      ["ผู้สูงอายุ", "ส่งเสริมคุณภาพชีวิตผู้สูงอายุ (โรงเรียนผู้สูงอายุ)", 30_000..150_000],
      ["ผู้พิการ", "ปรับปรุงที่อยู่อาศัยผู้พิการและผู้ด้อยโอกาส", 40_000..200_000],
      ["เด็กและเยาวชน", "จัดงานวันเด็กแห่งชาติ", 30_000..100_000],
      ["กีฬาและนันทนาการ", "แข่งขันกีฬาต้านยาเสพติด ป่ากลางเกมส์", 50_000..200_000],
      ["ศาสนาและวัฒนธรรม", "สืบสานประเพณีสงกรานต์และรดน้ำดำหัวผู้สูงอายุ", 30_000..150_000]
    ],
    "health" => [
      ["ป้องกันโรค", "ป้องกันและควบคุมโรคไข้เลือดออก", 30_000..120_000],
      ["ควบคุมโรคติดต่อ", "ป้องกันโรคพิษสุนัขบ้า (สัตว์ปลอดโรค คนปลอดภัย)", 20_000..80_000],
      ["ส่งเสริมสุขภาพ", "อุดหนุน อสม. ดำเนินงานสาธารณสุขมูลฐาน หมู่ที่ %{moo}", 20_000..60_000]
    ],
    "education" => [
      ["อาหารกลางวัน/อาหารเสริม", "สนับสนุนอาหารเสริม (นม) โรงเรียนในพื้นที่", 400_000..1_200_000],
      ["อาหารกลางวัน/อาหารเสริม", "อุดหนุนอาหารกลางวันโรงเรียนบ้าน%{village}", 300_000..900_000],
      ["ศูนย์พัฒนาเด็กเล็ก", "ปรับปรุงศูนย์พัฒนาเด็กเล็ก อบต.ป่ากลาง", 150_000..800_000],
      ["ห้องสมุด/แหล่งเรียนรู้", "จัดตั้งแหล่งเรียนรู้ชุมชนและห้องสมุดประชาชน", 50_000..250_000]
    ],
    "environment" => [
      ["จัดการขยะ", "บริหารจัดการขยะมูลฝอยชุมชนต้นทาง", 50_000..300_000],
      ["ปลูกป่า", "ปลูกป่าเฉลิมพระเกียรติและสร้างแนวกันไฟ", 30_000..150_000],
      ["พลังงานทดแทน", "ติดตั้งโซลาร์เซลล์อาคารสำนักงาน", 300_000..1_500_000]
    ],
    "safety" => [
      ["ป้องกันและบรรเทาสาธารณภัย", "ฝึกอบรม อปพร. และซ้อมแผนป้องกันอุทกภัย", 50_000..250_000],
      ["ป้องกันและบรรเทาสาธารณภัย", "ป้องกันและแก้ไขปัญหาไฟป่าและหมอกควัน", 50_000..200_000],
      ["กล้องวงจรปิด", "ติดตั้งกล้องวงจรปิด CCTV จุดเสี่ยงในชุมชน", 300_000..1_200_000],
      ["ความปลอดภัยทางถนน", "ตั้งจุดบริการประชาชนช่วงเทศกาลปีใหม่และสงกรานต์", 20_000..80_000]
    ],
    "administration" => [
      ["ครุภัณฑ์", "จัดซื้อครุภัณฑ์คอมพิวเตอร์สำนักงาน", 50_000..300_000],
      ["ครุภัณฑ์", "จัดซื้อรถบรรทุกน้ำอเนกประสงค์", 2_000_000..2_800_000],
      ["ระบบสารสนเทศ", "พัฒนาระบบแผนที่ภาษีและทะเบียนทรัพย์สิน", 100_000..500_000],
      ["พัฒนาบุคลากร", "ฝึกอบรมและศึกษาดูงานเพิ่มประสิทธิภาพบุคลากร", 100_000..400_000]
    ]
  }.freeze
  # How often each group appears; infrastructure dominates local budgets.
  GROUP_WEIGHTS = { "infrastructure" => 30, "water" => 12, "economy" => 6, "social" => 12, "health" => 8, "education" => 12, "environment" => 6, "safety" => 8, "administration" => 6 }.freeze
  AGENCIES = {
    "infrastructure" => "กองช่าง", "water" => "กองช่าง", "economy" => "สำนักปลัด", "social" => "กองสวัสดิการสังคม",
    "health" => "กองสาธารณสุขและสิ่งแวดล้อม", "education" => "กองการศึกษา ศาสนาและวัฒนธรรม",
    "environment" => "กองสาธารณสุขและสิ่งแวดล้อม", "safety" => "สำนักปลัด (งานป้องกันฯ)", "administration" => "กองคลัง"
  }.freeze
  BUDGET_SOURCES = { "ข้อบัญญัติงบประมาณรายจ่ายประจำปี" => 70, "เงินอุดหนุนเฉพาะกิจ" => 15, "เงินสะสม" => 10, "เงินอุดหนุนทั่วไป" => 5 }.freeze
  VILLAGES = %w[ป่ากลาง ห้วยขาบ ดอนแก้ว ทุ่งรวงทอง น้ำฮาว สบปัว ค้างฮ่อ ร่มเย็น].freeze
  STREAMS = %w[น้ำปัว ห้วยขาบ ห้วยยื่น ห้วยแก้ว น้ำยาว].freeze
  LOCATED_GROUPS = %w[infrastructure water environment safety education].freeze

  def initialize(subdistrict_id:, years:, per_year:, seed:)
    @subdistrict = subdistrict_id.present? ? Subdistrict.find(subdistrict_id) : User.where.not(subdistrict_id: nil).order(:id).first&.subdistrict
    raise ArgumentError, "No subdistrict found; pass SUBDISTRICT_ID" unless @subdistrict

    @owner = User.where(subdistrict_id: @subdistrict.id).order(:id).first || User.order(:id).first
    @years = years
    @per_year = per_year
    @random = Random.new(seed)
  end

  def run
    removed = Project.where(code: CODE_PATTERN).delete_all
    current_year = Project.current_fiscal_year
    fiscal_years = ((current_year - @years + 1)..current_year).to_a
    points = random_points(fiscal_years.size * @per_year)
    sequence = 0

    created = fiscal_years.flat_map do |fiscal_year|
      count = (@per_year * (0.8 + @random.rand * 0.4)).round
      Array.new(count) do
        sequence += 1
        build(fiscal_year, current_year, sequence, points)
      end
    end
    Project.collection.insert_many(created.map(&:as_document))
    puts "Removed #{removed} old simulated projects; created #{created.size} in ต.#{@subdistrict.name_th} for FY #{fiscal_years.first}-#{fiscal_years.last}"
    fiscal_years.each do |year|
      rows = created.select { |project| project.fiscal_year == year }
      by_approval = rows.group_by(&:approval_status).transform_values { |list| list.sum(&:budget).round }
      puts "  #{year}: #{rows.size} projects, #{by_approval}"
    end
  end

  private

  def build(fiscal_year, current_year, sequence, points)
    group = weighted(GROUP_WEIGHTS)
    type, template, budget_range = TEMPLATES.fetch(group).sample(random: @random)
    moo = @random.rand(1..12)
    name = format(template, moo:, village: VILLAGES.sample(random: @random), stream: STREAMS.sample(random: @random))
    approval_status, status, progress = lifecycle(current_year - fiscal_year)
    budget = (@random.rand(budget_range) / 1000.0).round * 1000
    point = LOCATED_GROUPS.include?(group) || @random.rand < 0.3 ? points.pop : nil
    started = Date.new(fiscal_year - 544, 10, 1) + @random.rand(0..300)

    Project.new(
      code: format("SIM-%d-%03d", fiscal_year, sequence), name:, group:, project_type: type,
      budget:, budget_source: weighted(BUDGET_SOURCES), agency: AGENCIES.fetch(group), fiscal_year:,
      approval_status:, status:, progress_percent: progress,
      location_name: point && "หมู่ที่ #{moo} บ้าน#{VILLAGES.sample(random: @random)}",
      description: "ข้อมูลจำลองสำหรับทดสอบระบบ — #{name}",
      latitude: point&.y, longitude: point&.x, subdistrict_id: @subdistrict.id, user_id: @owner.id,
      created_at: started.to_time, updated_at: started.to_time
    )
  end

  # Older years are settled (mostly approved and completed); the current year is still in play.
  def lifecycle(age)
    roll = @random.rand
    if age.zero?
      return ["rejected", "suspended", 0] if roll < 0.08
      return ["pending", "planned", 0] if roll < 0.45

      [["approved", "procurement", @random.rand(0..10)], ["approved", "in_progress", @random.rand(15..85)], ["approved", "planned", 0]].sample(random: @random)
    elsif age == 1
      return ["rejected", "suspended", 0] if roll < 0.12
      return ["pending", "planned", 0] if roll < 0.18

      roll < 0.55 ? ["approved", "in_progress", @random.rand(50..95)] : ["approved", "completed", 100]
    else
      return ["rejected", "suspended", 0] if roll < 0.15
      return ["approved", "suspended", @random.rand(0..40)] if roll < 0.20

      ["approved", "completed", 100]
    end
  end

  def weighted(weights)
    pick = @random.rand(weights.values.sum)
    weights.each { |key, weight| return key if (pick -= weight).negative? }
  end

  # Random points inside the subdistrict boundary so simulated projects land in the right area.
  def random_points(count)
    sql = Subdistrict.where(id: @subdistrict.id)
      .select("(ST_Dump(ST_GeneratePoints(boundary::geometry, #{count.to_i}, #{@random.rand(1..1_000_000)}))).geom AS point").to_sql
    Subdistrict.connection.select_values("SELECT ST_AsText(point) FROM (#{sql}) points")
      .map { |wkt| RGeo::Cartesian.preferred_factory(srid: 4326).parse_wkt(wkt) }
  end
end
