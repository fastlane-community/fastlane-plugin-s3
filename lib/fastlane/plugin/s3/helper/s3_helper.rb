module Fastlane
  module Helper
    class S3Helper
      # class methods that you define here become available in your action
      # as `Helper::S3Helper.your_method`
      #
      def self.show_message
        UI.message("Hello from the s3 plugin helper!")
      end
    end
  end
end
