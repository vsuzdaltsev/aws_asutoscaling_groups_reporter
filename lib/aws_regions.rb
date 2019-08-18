# frozen_string_literal: true

module Aws
  class Regions
    # List all available aws regions
    def self.list_all
      Aws::EC2::Client.new.describe_regions.to_h[:regions].map do |reg|
        reg[:region_name]
      end
    end

    # List only those aws regions that are set in constants
    def self.list_used
      Aws::Constants::USED_REGIONS
    end
  end
end
