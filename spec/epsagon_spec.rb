# frozen_string_literal: true

require 'epsagon'
require 'opentelemetry/proto/collector/trace/v1/trace_service_pb'

RSpec.describe do
  pids = {}

  before(:all) do
    Dir.mkdir('tmp') unless File.exist?('tmp')
    File.delete('tmp/body.pb') if File.exist?('tmp/body.pb')
    pids[:backend] = spawn 'ruby mock_backend.rb'
    pids[:traced_app] = spawn 'ruby traced_sinatra.rb'
    pids[:untraced_app] = spawn 'ruby untraced_sinatra.rb'
    sleep 3
  end

  describe 'trace' do
    it 'gets request data correctly' do
      `curl -X POST http://localhost:4567/foo/bar -d "amir=asdasd"`
      received_message = File.open('tmp/body.pb', &:read)
      decoded_message = Opentelemetry::Proto::Collector::Trace::V1::ExportTraceServiceRequest.decode(
        received_message
      ).to_h
      attributes = decoded_message[:resource_spans][0][:instrumentation_library_spans][0][:spans][0][:attributes]
      attr_hash = Hash[attributes.collect { |a| [a[:key], a[:value]] }]

      expect(attr_hash['http.request.path'][:string_value]).to eq('/foo/bar')
      expect(attr_hash['http.request.body'][:string_value]).to eq('amir=asdasd')
    end
  end

  describe 'data integrity' do
    it 'doesn\'t change request data' do
      expect(`curl -X POST http://localhost:4567/foo/bar -d "amir=asdasd"`).to eq(
        `curl -X POST http://localhost:4566/foo/bar -d "amir=asdasd"`
      )
    end
  end

  after(:all) do
    Process.kill('SIGHUP', pids[:backend])
    Process.detach(pids[:backend])
    Process.kill('SIGHUP', pids[:traced_app])
    Process.detach(pids[:traced_app])
    Process.kill('SIGHUP', pids[:untraced_app])
    Process.detach(pids[:untraced_app])
    File.delete('tmp/body.pb') if File.exist?('tmp/body.pb')
    sleep 5
  end
end
