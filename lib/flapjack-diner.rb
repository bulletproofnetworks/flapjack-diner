require 'httparty'
require 'json'
require 'uri'
require 'cgi'

require "flapjack-diner/version"
require "flapjack-diner/argument_validator"

module Flapjack
  module Diner
    SUCCESS_STATUS_CODES = [200, 204]

    include HTTParty
    extend ArgumentValidator::Helper

    format :json

    validate_all :path => :entity, :as => :required
    validate_all :query => [:start_time, :end_time], :as => :time

    class << self

      attr_accessor :logger

      # NB: clients will need to handle any exceptions caused by,
      # e.g., network failures or non-parseable JSON data.

      def entities
        path = '/entities'
        response = perform_get_simple(path)
        parsed(response)
      end

      def checks(entity)
        perform_get_request('checks', :path => {:entity => entity})
      end

      def status(entity, options = {})
        args = {:entity => entity, :check => options.delete(:check)}
        perform_get_request('status', :path => args)
      end

      def acknowledge!(entity, check, options = {})
        args = {:entity => entity, :check => check}
        perform_post_request('acknowledgements', :path => args, :query => options)
      end

      def test_notifications!(entity, check, options = {})
        args = {:entity => entity, :check => check}
        perform_post_request('test_notifications', :path => args, :query => options)
      end

      def create_scheduled_maintenance!(entity, check, options = {})
        args = {:entity => entity, :check => check}

        perform_post_request('scheduled_maintenances', :path => args, :query => options) do
          validate :path  => [:entity, :check], :as => :required
          validate :query => :start_time, :as => :required
          validate :query => :duration, :as => [:required, :integer]
        end
      end

      def scheduled_maintenances(entity, options = {})
        args = {:entity => entity, :check => options.delete(:check)}
        perform_get_request('scheduled_maintenances', :path => args, :query => options)
      end

      def unscheduled_maintenances(entity, options = {})
        args = {:entity => entity, :check => options.delete(:check)}
        perform_get_request('unscheduled_maintenances', :path => args, :query => options)
      end

      def outages(entity, options = {})
        args = {:entity => entity, :check => options.delete(:check)}
        perform_get_request('outages', :path => args, :query => options)
      end

      def downtime(entity, options = {})
        args = {:entity => entity, :check => options.delete(:check)}
        perform_get_request('downtime', :path => args, :query => options)
      end

      def contacts(options = {})
        path = '/contacts'
        response = perform_get_simple(path)
        parsed(response)
      end

      def contact_timezone(contact_id, options = {})
        path = "/contacts/#{contact_id}/timezone"
        response = perform_get_simple(path)
        parsed(response)
      end

      def contact_set_timezone(contact_id, options = {})
        path = "/contacts/#{contact_id}/timezone"
        body = { :timezone => options[:timezone] }.to_json
        perform_put_json(path, body)
      end

      private

      def perform_put_json(path, body)
        response = put(path, :body => body, :headers => {'Content-Type' => 'application/json'})
        response_body = response.body ? response.body[0..300] : nil
        logger.info "PUT #{path}"
        logger.info "  " + body
        logger.info "  Response Code: #{response.code} #{response.message}"
        logger.info "  Response Body: " + response_body
        SUCCESS_STATUS_CODES.include?(response.code)
      end

      def perform_post_json(path, body)
        response = post(path, :body => body, :headers => {'Content-Type' => 'application/json'})
        response_body = response.body ? response.body[0..300] : nil
        logger.info "POST #{path}"
        logger.info "  " + body
        logger.info "  Response Code: #{response.code} #{response.message}"
        logger.info "  Response Body: " + response_body
        SUCCESS_STATUS_CODES.include?(response.code)
      end

      def perform_get_simple(uri)
        response = get(uri)
        response_body = response.body ? response.body[0..300] : nil
        logger.info "GET #{uri}"
        logger.info "  Response Code: #{response.code} #{response.message}"
        logger.info "  Response Body: " + response_body
        response
      end

      def perform_delete(uri)
        response = delete(uri)
        response_body = response.body ? response.body[0..300] : nil
        logger.info "DELETE #{uri}"
        logger.info "  Response Code: #{response.code} #{response.message}"
        SUCCESS_STATUS_CODES.include?(response.code)
      end

      def perform_get_request(action, options, &validation)
        path, params = prepare_request(action, options, &validation)
        req_uri = build_uri(path, params)
        logger.info "GET #{req_uri}" if logger
        response = get(req_uri.request_uri)
        logger.info "  Response: #{response.body.inspect}" if logger
        parsed(responce)
      end

      def perform_post_request(action, options, &validation)
        path, params = prepare_request(action, options, &validation)
        req_uri = build_uri(path)
        logger.info "POST #{req_uri}\n  Params: #{params.inspect}" if logger
        code = post(path, :body => params).code
        logger.info "  Response code: #{code}" if logger
        SUCCESS_STATUS_CODES.include?(code)
      end

      def prepare_request(action, options, &validation)
        args = options[:path]
        query = options[:query]

        (block_given? ? [validation] : @validations).each do |validation|
          ArgumentValidator.new(args, query).instance_eval(&validation)
        end

        [prepare_path(action, args), prepare_query(query)]
      end

      def protocol_host_port
        self.base_uri =~ /^(?:(https?):\/\/)?([a-zA-Z0-9][a-zA-Z0-9\.\-]*[a-zA-Z0-9])(:(\d+))?/i
        protocol = ($1 || 'http').downcase
        host = $2
        port = $4.to_i || ('https'.eql?(protocol) ? 443 : 80)

        [protocol, host, port]
      end

      def build_uri(path, params = nil)
        pr, ho, po = protocol_host_port
        URI::HTTP.build(:protocol => pr, :host => ho, :port => po,
          :path => path, :query => (params && params.empty? ? nil : params))
      end

      def prepare_value(value)
        value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
      end

      def prepare_path(action, args)
        ["/#{action}", args[:entity], args[:check]].compact.map do |value|
          prepare_value(value)
        end.join('/')
      end

      def prepare_query(query)
        query.collect do |key, value|
          [CGI.escape(key.to_s), CGI.escape(prepare_value(value))].join('=')
        end.join('&') if query
      end

      def parsed(response)
        return unless response && response.respond_to?(:parsed_response)
        response.parsed_response
      end
    end
  end
end
