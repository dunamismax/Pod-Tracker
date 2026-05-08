require "test_helper"

class Smtp2goDeliveryMethodTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body)

  test "posts mail payload to SMTP2GO" do
    http = FakeHttp.new(Response.new("200", {
      email_response: { succeeded: 1, failed: 0 },
      request_id: "request-1"
    }.to_json))
    mail = UserMailer.verify_email(users(:two))

    Smtp2goDeliveryMethod.new(api_key: "api-test", http_adapter: http).deliver!(mail)

    request = http.last_request
    body = JSON.parse(request.body)

    assert_equal "application/json", request["Content-Type"]
    assert_equal "application/json", request["Accept"]
    assert_equal "api-test", request["X-Smtp2go-Api-Key"]
    assert_equal "api-test", body["api_key"]
    assert_equal "Ideal Magic <no-reply@ideal-magic.com>", body["sender"]
    assert_equal [ users(:two).email_address ], body["to"]
    assert_equal "Verify your Ideal Magic email", body["subject"]
    assert_includes body["text_body"], "Welcome to Ideal Magic"
    assert_includes body["html_body"], "Welcome to Ideal Magic"
  end

  test "raises when SMTP2GO returns a failed delivery response" do
    http = FakeHttp.new(Response.new("200", {
      email_response: { succeeded: 0, failed: 1, failures: [ "sender not verified" ] },
      request_id: "request-2"
    }.to_json))
    mail = UserMailer.verify_email(users(:two))

    error = assert_raises(Smtp2goDeliveryMethod::DeliveryError) do
      Smtp2goDeliveryMethod.new(api_key: "api-test", http_adapter: http).deliver!(mail)
    end

    assert_includes error.message, "sender not verified"
    assert_includes error.message, "request-2"
  end

  test "requires an API key" do
    mail = UserMailer.verify_email(users(:two))

    assert_raises(ArgumentError) do
      Smtp2goDeliveryMethod.new.deliver!(mail)
    end
  end

  class FakeHttp
    attr_reader :last_request, :options

    def initialize(response)
      @response = response
    end

    def start(host, port, options)
      @options = { host: host, port: port }.merge(options)
      yield self
    end

    def request(request)
      @last_request = request
      @response
    end
  end
end
