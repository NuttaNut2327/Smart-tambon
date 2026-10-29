require "test_helper"

class NotificationsServiceTest < ActiveSupport::TestCase
  test "call delegates event delivery to the dispatcher" do
    dispatcher = Object.new
    received = nil
    dispatcher.define_singleton_method(:dispatch) { |**arguments| received = arguments; [:sent] }

    Notifications::Dispatcher.stub(:new, dispatcher) do
      result = Notifications::Service.call(
        organization_key: "org-1",
        event: "incident.created",
        variables: { "title" => "ไฟไหม้" },
        resource_id: "incident-1"
      )
      assert_equal [:sent], result
    end

    assert_equal "incident.created", received[:tag]
    assert_equal({ "title" => "ไฟไหม้" }, received[:variables])
    assert_equal "incident-1", received[:incident_id]
  end

  test "publish uses the shared provider sender" do
    channel = Struct.new(:kind).new("line")
    sender = Object.new
    received = nil
    sender.define_singleton_method(:deliver) { |text, **arguments| received = [text, arguments]; true }

    Notifications::Senders.stub(:for, sender) do
      assert Notifications::Service.publish(channel: channel, text: "ข้อความ", event: "broadcast", data: { title: "ข่าว" })
    end

    assert_equal ["ข้อความ", { tag: "broadcast", data: { title: "ข่าว" } }], received
  end
end
