# frozen_string_literal: true

require 'json'
require 'aws-sdk'

require_relative './lib/constants'
require_relative './lib/aws_asgs'
require_relative './lib/aws_regions'

ENVIRONMENTS = Aws::Constants::ENVIRONMENTS
ASGS_TYPES   = Aws::Constants::ASGS_TYPES

# This may be deployed as an aws lambda
# Arguments needed if run from aws lambda
def auto_scaling_groups(*)
  regions = Aws::Regions.list_used
  json    = JSON.dump(all_asgs(regions))

  puts json unless called_from_aws_lambda?(caller)

  { statusCode: 200, body: json }
end

def collect_asg_types(asgs)
  ASGS_TYPES.each_with_object({}) do |asg_type, memo|
    memo.merge!(asg_type => asgs.send(asg_type))
  end
end

def asgs_by_region(asgs, region)
  { region => collect_asg_types(asgs) }
end

# @param env [String] - set within 'environment' tag
# @param regions [Array] - aws regions to lookup
# @return [Hash]
def environment_asgs(env, regions)
  value = regions.each_with_object({}) do |region, memo|
    asgs = Aws::Asgs.new(region: region, filter_by_tags: { environment: env })
    memo.merge!(asgs_by_region(asgs, region))
  end

  { env => value }
end

def all_asgs(regions)
  ENVIRONMENTS.each_with_object({}) do |env, asgs|
    asgs.merge!(environment_asgs(env, regions))
  end
end

def called_from_aws_lambda?(caller)
  caller.last.include?('/var/runtime/lib/runtime.rb')
end

auto_scaling_groups
