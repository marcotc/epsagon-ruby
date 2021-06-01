# frozen_string_literal: true

require 'httparty'
# require 'epsagon'
require 'opentelemetry/sdk'
require_relative '../lib/instrumentation/httparty'

EXPORTER = OpenTelemetry::SDK::Trace::Export::InMemorySpanExporter.new
span_processor = OpenTelemetry::SDK::Trace::Export::SimpleSpanProcessor.new(EXPORTER)

RSpec.shared_examples 'HTTP Metadata Only' do |scheme, method, path|
  span_name = URI.parse(path).host.downcase

  it 'has the correct span name' do
    expect(span.name).to eq span_name
  end

  it 'has the correct type' do
    expect(span.attributes['type']).to eq 'http'
  end

  it 'has the correct method' do
    expect(span.attributes['operation']).to eq method
  end

  it 'has the correct scheme' do
    expect(span.attributes['http.scheme']).to eq scheme
  end

  it 'has the correct status_code' do
    expect(span.attributes['http.status_code']).to eq 200
  end

  it 'has the correct http.request.path' do
    expect(span.attributes['http.request.path']).to eq path
  end
end

RSpec.shared_examples 'HTTP With Additional Data' do
  it 'has accept-encoding header' do
    expect(span_headers['Accept-Encoding']).to eq 'gzip, deflate'
  end

  it 'has Content-Type header' do
    expect(span_headers['Content-type']).to eq 'text/html'
  end

  it 'has User Agent' do
    expect(span_headers['User-Agent']).to eq 'Mozilla/5.0'
  end
end

RSpec.describe 'HTTParty Instrumentation' do
  let(:exporter)          { EXPORTER }
  let(:span)              { exporter.finished_spans.first }
  let(:instrumentation)   { EpsagonHTTPartyInstrumentation.instance }
  let(:metadata_only) { true }
  let(:config) do
    {
      epsagon: {
        metadata_only: metadata_only
      }
    }
  end
  let(:request_headers) do
    {
      'Content-type': 'text/html',
      'Accept-Encoding': 'gzip, deflate',
      'User-Agent': 'Mozilla/5.0'
    }
  end

  before(:each) do
    instrumentation.instance_variable_set(:@installed, false)
    instrumentation.instance_variable_set(:@config, nil)
    exporter.reset

    OpenTelemetry::SDK.configure do |c|
      c.add_span_processor span_processor
    end

    instrumentation.install(config)
    instrumentation.instance_variable_set(:@config, config)
  end

  it "doesn't have spans before request" do
    expect(exporter.finished_spans.size).to eq 0
  end

  describe 'GET' do
    describe 'GET HTTPS with metadata only' do
      let(:metadata_only) { true }

      before do
        HTTParty.get('https://www.google.com')
      end

      it_behaves_like 'HTTP Metadata Only', 'https', 'GET', 'https://www.google.com/'

      [
        'http.request.path_params',
        'http.request.query',
        'http.request.query_params',
        'http.request.body',
        'http.request.body',
        'http.request.headers',
        'http.request.headers.User-Agent',
        'http.response.headers'
      ].each do |attribute|
        it "does not have #{attribute}" do
          expect(span.attributes[attribute]).to eq nil
        end
      end
    end

    describe 'GET HTTPS with additional data' do

      let(:metadata_only) { false }
      let(:span_headers) { JSON.parse(span.attributes['http.request.headers']) }

      before(:each) do
        HTTParty.get('https://www.google.com/search?q=Test', headers: request_headers)
      end

      it_behaves_like 'HTTP Metadata Only', 'https', 'GET', 'https://www.google.com/search'

      it 'has empty request body' do
        expect(span.attributes['http.request.body']).to eq nil
      end

      it_behaves_like 'HTTP With Additional Data'
    end

    skip describe 'GET HTTPS with Params' do
      let(:metadata_only) { false }

      before do
        OpenTelemetry::SDK.configure do |c|
          c.add_span_processor span_processor
        end

        instrumentation.install(config)
        instrumentation.instance_variable_set(:@config, config)
        HTTParty.get('https://www.google.com/search?q=Test')
      end

      it 'has the correct http.request.query' do
        # expect(span.attributes['http.banana.query']).to eq 'q'
        p span.attributes['http.request.query']
        expect(span.attributes['http.request.query']).to eq 'q=Test'
      end

      it 'has http.request.query_params' do
        expect(JSON.parse(span.attributes['http.request.query_params'])).to eq 'q=Test'
      end

      it 'has empty request body' do
        expect(span.attributes['http.request.body']).to eq nil
      end
    end
  end

  describe 'POST' do
    context 'with metadata_only = true' do
      let(:metadata_only) { true }
      before do
        HTTParty.post('http://localhost/post')
      end

      it_behaves_like 'HTTP Metadata Only', 'http', 'POST', 'http://localhost/post'
    end
  end
end
