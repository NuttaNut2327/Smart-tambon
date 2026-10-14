require "test_helper"
require "minitest/mock"

# AI assistant: data scoping of the query engine, session privacy, and kept snippets re-running with the viewer's scope.
class AiAssistantTest < ActionDispatch::IntegrationTest
  # Scripted stand-in for an LLM: first asks for a chart, then answers with its marker.
  class FakeLlm
    attr_reader :calls

    def initialize(chart_input)
      @chart_input = chart_input
      @calls = []
    end

    def format = "fake"
    def user_message(text) = { "role" => "user", "content" => text }
    def assistant_text(text) = { "role" => "assistant", "content" => text }
    def tool_results(results) = results.map { |result| { "role" => "tool", "tool_call_id" => result[:id], "content" => result[:content] } }

    def chat(system:, tools:, messages:)
      @calls << { system: system, tools: tools.map { |tool| tool[:name] }, messages: messages }
      if @calls.size == 1
        call = Ai::Llm::ToolCall.new(id: "call-1", name: "show_chart", input: @chart_input)
        Ai::Llm::Response.new(text: "", tool_calls: [call], stop_reason: "tool_calls", assistant_message: { "role" => "assistant", "tool_calls" => [{ "id" => "call-1" }] }, usage: {}, model: "fake-model")
      else
        Ai::Llm::Response.new(text: "## สรุป\nงบประมาณตามปี\n\n[[artifact:1]]", tool_calls: [], stop_reason: "stop", assistant_message: { "role" => "assistant", "content" => "done" }, usage: {}, model: "fake-model")
      end
    end
  end

  CHART = { "title" => "งบตามปี", "kind" => "bar", "x" => "fiscal_year", "y" => ["งบรวม"],
            "query" => { "source" => "projects", "group_by" => [{ "field" => "fiscal_year" }],
                         "measures" => [{ "agg" => "sum", "field" => "budget", "label" => "งบรวม" }] } }.freeze

  setup do
    @province = Province.create!(code: "A97", name_th: "จังหวัดทดสอบ AI")
    @first = create_subdistrict("A9701", "ตำบลเอไอหนึ่ง", 100.0)
    @second = create_subdistrict("A9702", "ตำบลเอไอสอง", 101.0)
    @admin = User.create!(username: "ai_admin_one", password: "Password123!", role: :subdistrict_admin, subdistrict: @first)
    @staff = User.create!(username: "ai_staff_one", password: "Password123!", role: :subdistrict_user, subdistrict: @first)
    @other = User.create!(username: "ai_admin_two", password: "Password123!", role: :subdistrict_admin, subdistrict: @second)
    Project.create!(user_id: @admin.id, subdistrict_id: @first.id, name: "ถนนหมู่ 1", group: "infrastructure", project_type: "ถนน", agency: "กองช่าง", budget: 100_000, fiscal_year: 2569)
    Project.create!(user_id: @admin.id, subdistrict_id: @first.id, name: "ฝายหมู่ 2", group: "water", project_type: "ฝาย", agency: "กองช่าง", budget: 50_000, fiscal_year: 2570)
    Project.create!(user_id: @other.id, subdistrict_id: @second.id, name: "โครงการตำบลอื่น", group: "water", project_type: "ฝาย", agency: "กองช่าง", budget: 9_999_999, fiscal_year: 2570)
    @provider = AiProvider.create!(name: "ทดสอบ", api_format: "openai", base_url: "http://llm.test/v1", model: "fake-model", is_default: true)
    sign_in @admin
  end

  teardown do
    AiSnippet.delete_all
    AiChatMessage.delete_all
    AiChatSession.delete_all
    AiProvider.delete_all
    Project.where(:user_id.in => [@admin&.id, @other&.id]).delete_all
    [@admin, @staff, @other].compact.each(&:destroy)
    @province&.subdistricts&.destroy_all
    @province&.destroy
  end

  test "query engine only sees the account's own organisation" do
    result = Ai::QueryEngine.new(Ai::DataCatalog.new(@admin)).run(CHART["query"])

    assert_equal [{ "fiscal_year" => 2569, "งบรวม" => 100_000.0 }, { "fiscal_year" => 2570, "งบรวม" => 50_000.0 }],
                 result.rows.sort_by { |row| row["fiscal_year"] }
    assert_equal 2, result.total
  end

  test "query engine hints at real values when a text filter matches nothing" do
    result = Ai::QueryEngine.new(Ai::DataCatalog.new(@admin))
                            .run({ "source" => "projects", "filters" => [{ "field" => "subdistrict", "op" => "eq", "value" => "ต.ตำบลเอไอหนึ่ง" }] })

    assert_equal 0, result.total
    assert_includes result.hints["subdistrict"], "ตำบลเอไอหนึ่ง"
  end

  test "query engine rejects unknown fields with the list of valid ones" do
    error = assert_raises(Ai::QueryEngine::InvalidSpec) do
      Ai::QueryEngine.new(Ai::DataCatalog.new(@admin)).run({ "source" => "projects", "columns" => ["secret"] })
    end
    assert_includes error.message, "fiscal_year"
  end

  test "chat answer stores the chart artifact and the queries behind it" do
    post ai_sessions_path, as: :json
    session_id = response.parsed_body["id"]
    fake = FakeLlm.new(CHART)

    Ai::Llm.stub(:for, fake) do
      post ai_session_messages_path(session_id), params: { content: "งบโครงการแต่ละปี" }, as: :json
    end

    assert_response :success
    assistant = response.parsed_body["messages"].last
    assert_equal "assistant", assistant["role"]
    assert_includes assistant["content"], "[[artifact:1]]"
    assert_equal "งบตามปี", assistant["artifacts"].first["title"]
    assert_equal [2569, 2570], assistant["artifacts"].first["rows"].map { |row| row["fiscal_year"] }.sort
    assert_equal 1, assistant["queries"].size
    assert_equal "งบโครงการแต่ละปี", response.parsed_body["title"]
    assert_includes fake.calls.first[:tools], "query_data"
  end

  test "sessions are private to their owner" do
    session = AiChatSession.create!(user_id: @other.id, organization_key: @other.organization_key)

    get ai_session_path(session), as: :json
    assert_response :not_found

    post ai_session_messages_path(session), params: { content: "สวัสดี" }, as: :json
    assert_response :not_found
  end

  test "snippet re-runs with the viewer's scope and sharing stays inside the organisation" do
    session = AiChatSession.create!(user_id: @admin.id, organization_key: @admin.organization_key)
    session.messages.create!(seq: 1, role: "user", content: "งบโครงการแต่ละปี")
    message = session.messages.create!(seq: 2, role: "assistant", content: "[[artifact:1]]",
                                       artifacts: [CHART.merge("key" => 1, "spec" => CHART["query"], "rows" => [{ "stale" => true }])])

    post ai_snippets_path, params: { session_id: session.id, message_id: message.id }, as: :json
    assert_response :created
    snippet_id = response.parsed_body["id"]
    assert_nil AiSnippet.find(snippet_id).artifacts.first["rows"], "kept snippets store specs, not rows"

    post run_ai_snippet_path(snippet_id), params: { from: "2026-01-01" }, as: :json
    assert_response :success
    assert_equal 2, response.parsed_body["artifacts"].first["rows"].size

    patch ai_snippet_path(snippet_id), params: { shared: true }, as: :json
    assert_response :success

    sign_in @staff
    get ai_snippets_path, as: :json
    assert_equal [snippet_id], response.parsed_body.map { |item| item["id"] }
    patch ai_snippet_path(snippet_id), params: { title: "แก้ชื่อ" }, as: :json
    assert_response :forbidden

    sign_in @other
    get ai_snippets_path, as: :json
    assert_empty response.parsed_body
    post run_ai_snippet_path(snippet_id), as: :json
    assert_response :not_found
  end

  test "only the system admin manages AI providers and keys are never rendered" do
    @provider.assign_api_key("sk-test-secret-1234")
    @provider.save!

    get ai_providers_path
    assert_redirected_to root_path

    admin = User.create!(username: "ai_system_admin", password: "Password123!", role: :system_admin)
    sign_in admin
    get ai_providers_path
    assert_response :success
    assert_not_includes response.body, "sk-test-secret"
    assert_includes response.body, "1234"
  ensure
    admin&.destroy
  end

  private

  def create_subdistrict(code, name, longitude)
    factory = RGeo::Cartesian.preferred_factory(srid: 4326)
    points = [[longitude, 14.0], [longitude + 0.1, 14.0], [longitude + 0.1, 14.1],
              [longitude, 14.1], [longitude, 14.0]].map { |lon, lat| factory.point(lon, lat) }
    boundary = factory.multi_polygon([factory.polygon(factory.linear_ring(points))])
    @province.subdistricts.create!(code: code, name_th: name, boundary: boundary)
  end
end
