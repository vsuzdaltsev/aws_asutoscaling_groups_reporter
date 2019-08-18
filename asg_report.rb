# frozen_string_literal: true

require 'json'
require 'aws-sdk'

require_relative './lib/constants'
require_relative './lib/aws_asgs'
require_relative './lib/aws_regions'

# This may be deployed as an aws lambda
def auto_scaling_groups(*)
  regions = Aws::Regions.list_used
  json    = JSON.dump(all_asgs(regions))

  puts json unless called_from_aws_lambda?(caller)

  { statusCode: 200, body: json }
end

def environment_asgs(env, regions)
  value = regions.map do |region|
    { region => Aws::Asgs.new(region: region, filter_by_tags: { environment: env }).running_asgs }
  end

  { env => value }
end

def all_asgs(regions)
  {}.tap do |asgs|
    Aws::Constants::ENVIRONMENTS.each do |env|
      asgs.merge!(environment_asgs(env, regions))
    end
  end
end

def called_from_aws_lambda?(caller)
  caller.last.include?('/var/runtime/lib/runtime.rb')
end

auto_scaling_groups
