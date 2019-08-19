# frozen_string_literal: true

require 'json'
require 'aws-sdk'

# Report Autoscaling groups by tags/running vms
module Aws
  # call AWS API
  class AsgApiCall
    # @param region [String, NilClass] - AWS region
    # @raise [ArgumentError] - if region kwarg nil
    # @raise [StandardError] - ff can't parse AWS API response
    # @return [Array] - array of Hashes that contains info about each ASG in the region
    def self.auto_scaling_groups(region: nil)
      raise ArgumentError, ">> #{self}.#{__method__}: mandatory <region> kwarg missing" unless region

      Aws::AutoScaling::Client.new(region: region).describe_auto_scaling_groups.map do |response|
        response.to_h[:auto_scaling_groups]
      end.flatten
    rescue StandardError => e
      puts "Can't get info about existing ASGs. Error is: #{e}"
    end
  end

  # Tags existing in the pointed region
  class AsgAvailableTags
    attr_reader :available_tags

    # @param region [String, NilClass] - AWS region
    # @param all_asgs [String, NilClass] - array of Hashes that contains info about each ASG in the region
    # @raise [ArgumentError] - if region kwarg nil
    def initialize(region: nil, all_asgs: nil)
      raise ArgumentError, ">> #{self}.#{__method__}: mandatory <region> kwarg missing" unless region

      @asgs           = all_asgs
      @available_tags = parse_available_tags
    end

    # All tags from api call response to array of tag names
    def parse_available_tags
      array_of_tags.each_with_object({}) do |tag_name, memo|
        memo.merge!(tag_name)
      end.keys
    end

    private

    def array_of_tags
      @asgs.map do |asg|
        asg[:tags]
      end.map { |tags| tags.map { |tag| { tag[:key] => tag[:value] } } }.flatten.uniq
    end
  end

  # ASG reports
  class Asgs
    attr_reader :timestamp,
                :running_asgs,
                :sleeping_asgs

    # Methods that allow get ASG names with 'names' alias
    CREATE_NAMES = lambda { |asgs|
      asgs.instance_eval do
        def names
          keys
        end
      end
    }

    # @param region [String, NilClass] - AWS region
    # @param filter_by_tags [Hash] filter by tag values. Example: { environment: 'production' }
    # @param to_json [Boolean] - report in json format
    # @raise [ArgumentError] - if region kwarg nil
    def initialize(region: nil, filter_by_tags: {}, to_json: false)
      raise ArgumentError, ">> #{self}.#{__method__}: mandatory <region> kwarg missing" unless region

      @timestamp      = Time.now
      @region         = region
      @to_json        = to_json
      @asgs           = AsgApiCall.auto_scaling_groups(region: @region)
      @available_tags = AsgAvailableTags.new(region: @region, all_asgs: @asgs).available_tags
      @tags           = symbolize(filter_by_tags)

      create_check_tags_aliases

      @all_asg_normalized = all_asgs
      @running_asgs       = running
      @sleeping_asgs      = sleeping
    end

    private

    def create_check_tags_aliases
      @available_tags.each do |method_name|
        self.class.send(:alias_method, method_name, :check_tag)
      end
    end

    def running
      asgs = all_asgs.select do |name, parameters|
        !empty_asg?(parameters) && tags_filtered?(parameters) ? { name => parameters } : nil
      end

      CREATE_NAMES.call(asgs)
      return asgs.to_json if @to_json

      asgs
    end

    def sleeping
      asgs = all_asgs.select do |name, parameters|
        empty_asg?(parameters) && tags_filtered?(parameters) ? { name => parameters } : nil
      end

      CREATE_NAMES.call(asgs)
      return asgs.to_json if @to_json

      asgs
    end

    def symbolize(tags)
      tags.each_with_object({}) do |(key, value), memo|
        memo[key.to_s] = value
      end
    end

    def all_asgs
      @asgs.each_with_object({}) do |asg, memo|
        memo.merge!(
          asg[:auto_scaling_group_name] => all_asgs_values(asg)
        )
      end
    end

    def all_asgs_values(asg)
      {
        min_size:         asg[:min_size],
        max_size:         asg[:max_size],
        desired_capacity: asg[:desired_capacity],
        tags:             tags(asg),
        instances:        asg[:instances].size
      }
    end

    def tags_filtered?(parameters)
      @tags.keys.map do |tag_name|
        tag_filtered?(parameters, tag_name)
      end.all?(true)
    end

    def tag_filtered?(parameters, tag_name)
      return true if @tags[tag_name].nil? || @tags[tag_name].empty?

      @tags[tag_name].eql?(parameters[:tags][tag_name])
    end

    def tags(asg)
      @tags.each_key.each_with_object({}) do |tag_name, memo|
        memo.merge!(tag_name => send(tag_name, asg))
      end
    end

    def tag(asg, tag_name)
      asg[:tags].map do |tag|
        tag[:value] if tag[:key].eql?(tag_name)
      end.compact.join
    rescue StandardError => e
      puts ">> Can't determine #{tag_name} by tags. They may be absent. Error is: #{e}"
      '_default'
    end

    def check_tag(asg)
      tag(asg, __callee__.to_s)
    end

    def empty_asg?(parameters)
      parameters[:instances].zero? && parameters[:desired_capacity].zero?
    end
  end
end
