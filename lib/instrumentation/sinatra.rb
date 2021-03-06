# frozen_string_literal: true

require 'opentelemetry'

require_relative '../util'
require_relative '../epsagon_constants'

# Sinatra middleware for epsagon instrumentation
class EpsagonTracerMiddleware
  def initialize(app)
    @app = app
  end

  def config
    EpsagonSinatraInstrumentation.instance.config
  end

  def call(env)
    request = Rack::Request.new(env)
    path, path_params = request.path.split(';')
    request_headers = JSON.generate(Hash[*env.select { |k, _v| k.start_with? 'HTTP_' }
      .collect { |k, v| [k.sub(/^HTTP_/, ''), v] }
      .collect { |k, v| [k.split('_').collect(&:capitalize).join('-'), v] }
      .sort
      .flatten])

    attributes = {
      'operation' => env['REQUEST_METHOD'],
      'type' => 'http',
      'http.scheme' => env['rack.url_scheme'],
      'http.request.path' => path,
      'http.request.headers' => request_headers
    }

    unless config[:epsagon][:metadata_only]
      request.body.rewind
      request_body = request.body.read
      request.body.rewind

      attributes.merge!(Util.epsagon_query_attributes(request.query_string))

      attributes.merge!({
                          'http.request.body' => request_body,
                          'http.request.path_params' => path_params,
                          'http.request.headers.User-Agent' => env['HTTP_USER_AGENT']
                        })
    end

    tracer.in_span(
      env['HTTP_HOST'],
      attributes: attributes,
      kind: :server,
      with_parent: parent_context(env)
    ) do |http_span|
      tracer.in_span(
        env['HTTP_HOST'],
        kind: :server,
        attributes: { type: 'sinatra' }
      ) do |framework_span|
        app.call(env).tap { |resp| trace_response(http_span, framework_span, env, resp) }
      end
    end
  end

  private

  attr_reader :app

  def parent_context(env)
    OpenTelemetry.propagation.http.extract(env)
  end

  def tracer
    EpsagonSinatraInstrumentation.instance.tracer
  end

  def trace_response(http_span, framework_span, env, resp)
    status, headers, response_body = resp

    unless config[:epsagon][:metadata_only]
      http_span.set_attribute('http.response.headers', JSON.generate(headers))
      http_span.set_attribute('http.response.body', response_body.join)
    end

    http_span.set_attribute('http.status_code', status)
    http_span.set_attribute('http.route', env['sinatra.route'].split.last) if env['sinatra.route']
    http_span.status = OpenTelemetry::Trace::Status.http_to_status(status)
  end
end

# Sinatra extension for epsagon instrumentation
module EpsagonTracerExtension
  # Sinatra hook after extension is registered
  def self.registered(app)
    # Create tracing `render` method
    ::Sinatra::Base.module_eval do
      def render(_engine, data, *)
        template_name = data.is_a?(Symbol) ? data : :literal

        Sinatra::Instrumentation.instance.tracer.in_span(
          'sinatra.render_template',
          attributes: { 'sinatra.template_name' => template_name.to_s }
        ) do
          super
        end
      end
    end

    app.use EpsagonTracerMiddleware
  end
end

# Sinatra epsagon instrumentation
class EpsagonSinatraInstrumentation < OpenTelemetry::Instrumentation::Base
  VERSION = EpsagonConstants::VERSION

  install do |_|
    ::Sinatra::Base.register EpsagonTracerExtension
  end

  present do
    defined?(::Sinatra)
  end
end
