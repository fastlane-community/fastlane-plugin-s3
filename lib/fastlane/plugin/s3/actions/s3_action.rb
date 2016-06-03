module Fastlane
  module Actions
    class S3Action < Action
      def self.run(params)
        UI.message("The s3 plugin is working!")
      end

      def self.description
        %q{Upload IPA and APK to S3}
      end

      def self.authors
        [%q{Josh Holtz}]
      end

      def self.available_options
        [
          # FastlaneCore::ConfigItem.new(key: :your_option,
          #                         env_name: "S3_YOUR_OPTION",
          #                      description: "A description of your option",
          #                         optional: false,
          #                             type: String)
        ]
      end

      def self.is_supported?(platform)
        # Adjust this if your plugin only works for a particular platform (iOS vs. Android, for example)
        # See: https://github.com/fastlane/fastlane/blob/master/fastlane/docs/Platforms.md
        #
        # [:ios, :mac, :android].include?(platform)
        true
      end
    end
  end
end
