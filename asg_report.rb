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

# @param env [String] - set within 'environment' tag
# @param regions [Array] - aws regions to lookup
# @param asgs_type [String] - 'running_asgs' or 'sleeping_asgs'.
#   Running asg has at least one EC2 running or desired
# @return [Hash]
def environment_asgs(env, regions, asgs_type)
  value = regions.map do |region|
    { region => Aws::Asgs.new(region: region, filter_by_tags: { environment: env }).send(asgs_type) }
  end

  { env => value }
end

def all_asgs(regions)
  {}.tap do |asgs|
    ENVIRONMENTS.each do |env|
      ASGS_TYPES.each do |asgs_type|
        asgs[asgs_type] = environment_asgs(env, regions, asgs_type)
      end
    end
  end
end

def called_from_aws_lambda?(caller)
  caller.last.include?('/var/runtime/lib/runtime.rb')
end

auto_scaling_groups
