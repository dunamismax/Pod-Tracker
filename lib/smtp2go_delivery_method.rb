require "json"
require "net/http"
require "uri"

class Smtp2goDeliveryMethod
  class DeliveryError < StandardError; end

  DEFAULT_ENDPOINT = "https://api.smtp2go.com/v3/email/send"

  attr_reader :settings

  def initialize(settings = {})
    @settings = {
      endpoint: DEFAULT_ENDPOINT,
      http_adapter: Net::HTTP,
      open_timeout: 5,
      read_timeout: 5
    }.merge(settings)
  end

  def deliver!(mail)
    api_key = required_setting(:api_key)
    uri = URI(settings.fetch(:endpoint))
    request = Net::HTTP::Post.new(uri)
    request["Accept"] = "application/json"
    request["Content-Type"] = "application/json"
    request["X-Smtp2go-Api-Key"] = api_key
    request.body = JSON.generate(payload_for(mail, api_key: api_key))

    response = settings.fetch(:http_adapter).start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: settings.fetch(:open_timeout).to_i,
      read_timeout: settings.fetch(:read_timeout).to_i
    ) { |http| http.request(request) }

    parsed = parse_response(response)
    raise DeliveryError, failure_message(response, parsed) unless successful?(response, parsed)

    response
  end

  private
    def required_setting(name)
      value = settings[name].to_s
      return value unless value.empty?

      raise ArgumentError, "SMTP2GO #{name} is required"
    end

    def payload_for(mail, api_key:)
      payload = {
        api_key: api_key,
        sender: sender_for(mail),
        to: Array(mail.to),
        cc: Array(mail.cc),
        bcc: Array(mail.bcc),
        subject: mail.subject.to_s
      }.compact_blank

      if mail.multipart?
        payload[:text_body] = decoded_part(mail.text_part)
        payload[:html_body] = decoded_part(mail.html_part)
      elsif mail.mime_type == "text/html"
        payload[:html_body] = mail.body.decoded
      else
        payload[:text_body] = mail.body.decoded
      end

      payload.compact_blank
    end

    def sender_for(mail)
      mail[:from]&.decoded.presence || Array(mail.from).first.to_s
    end

    def decoded_part(part)
      part&.body&.decoded
    end

    def parse_response(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      raise DeliveryError, "SMTP2GO returned invalid JSON (HTTP #{response.code})."
    end

    def successful?(response, parsed)
      return false unless response.code.to_i.between?(200, 299)

      email_response = parsed["email_response"]
      return true unless email_response.is_a?(Hash)

      email_response.fetch("failed", 0).to_i.zero? && email_response.fetch("succeeded", 1).to_i.positive?
    end

    def failure_message(response, parsed)
      data = parsed["data"].is_a?(Hash) ? parsed["data"] : {}
      email_response = parsed["email_response"].is_a?(Hash) ? parsed["email_response"] : {}
      detail = data["error"].presence || Array(email_response["failures"]).first.presence
      request_id = parsed["request_id"].presence

      message = +"SMTP2GO delivery failed (HTTP #{response.code})"
      message << ": #{detail}" if detail
      message << " [request_id=#{request_id}]" if request_id
      message
    end
end
