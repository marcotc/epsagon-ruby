# frozen_string_literal: true

require_relative '../util'

# AWS SDK plugin for epsagon instrumentation
class EpsagonAwsPlugin < Seahorse::Client::Plugin
  def add_handlers(handlers, _)
    handlers.add(EpsagonAwsHandler, step: :validate)
  end
end

# Generates Spans for all uses of AWS SDK
class EpsagonAwsHandler < Seahorse::Client::Handler
  def call(context)
    span_name = "AWS #{context[:service_name]}"
    tracer.in_span(span_name) do |span|
      @handler.call(context).tap do
        span.set_attribute('aws.command', context[:command])
        span.set_attribute('aws.status_code', context[:status_code])
      end
    end
  end

  def tracer
    EpsagonAwsSdkInstrumentation.instance.tracer
  end
end

# AWS SDK epsagon instrumentation
class EpsagonAwsSdkInstrumentation < OpenTelemetry::Instrumentation::Base
  VERSION = '0.0.0'
  SERVICES = %w[
    ACM
    APIGateway
    AppStream
    ApplicationAutoScaling
    ApplicationDiscoveryService
    Athena
    AutoScaling
    Batch
    Budgets
    CloudDirectory
    CloudFormation
    CloudFront
    CloudHSM
    CloudHSMV2
    CloudSearch
    CloudSearchDomain
    CloudTrail
    CloudWatch
    CloudWatchEvents
    CloudWatchLogs
    CodeBuild
    CodeCommit
    CodeDeploy
    CodePipeline
    CodeStar
    CognitoIdentity
    CognitoIdentityProvider
    CognitoSync
    ConfigService
    CostandUsageReportService
    DAX
    DataPipeline
    DatabaseMigrationService
    DeviceFarm
    DirectConnect
    DirectoryService
    DynamoDB
    DynamoDBStreams
    EC2
    ECR
    ECS
    EFS
    EMR
    ElastiCache
    ElasticBeanstalk
    ElasticLoadBalancing
    ElasticLoadBalancingV2
    ElasticTranscoder
    ElasticsearchService
    EventBridge
    Firehose
    GameLift
    Glacier
    Glue
    Greengrass
    Health
    IAM
    ImportExport
    Inspector
    IoT
    IoTDataPlane
    KMS
    Kinesis
    KinesisAnalytics
    Lambda
    LambdaPreview
    Lex
    LexModelBuildingService
    Lightsail
    MTurk
    MachineLearning
    MarketplaceCommerceAnalytics
    MarketplaceEntitlementService
    MarketplaceMetering
    MigrationHub
    Mobile
    OpsWorks
    OpsWorksCM
    Organizations
    Pinpoint
    Polly
    RDS
    Redshift
    Rekognition
    ResourceGroupsTaggingAPI
    Route53
    Route53Domains
    S3
    SES
    SMS
    SNS
    SQS
    SSM
    STS
    SWF
    ServiceCatalog
    Shield
    SimpleDB
    Snowball
    States
    StorageGateway
    Support
    Textract
    WAF
    WAFRegional
    WorkDocs
    WorkSpaces
    XRay
  ].freeze

  install do |_|
    ::Seahorse::Client::Base.add_plugin(EpsagonAwsPlugin)
    loaded_constants.each { |klass| klass.add_plugin(EpsagonAwsPlugin) }
  end

  present do
    defined?(::Seahorse::Client::Base)
  end

  private

  def loaded_constants
    # Cross-check services against loaded AWS constants
    # Module#const_get can return a constant from ancestors when there's a miss.
    # If this conincidentally matches another constant, it will attempt to patch
    # the wrong constant, resulting in patch failure.
    available_services = ::Aws.constants & SERVICES.map(&:to_sym)

    available_services.each_with_object([]) do |service, constants|
      next if ::Aws.autoload?(service)

      begin
        constants << ::Aws.const_get(service, false).const_get(:Client, false)
      rescue StandardError
        next
      end
    end
  end
end
