module Fastlane
  module Helper
    class S3Helper
      # class methods that you define here become available in your action
      # as `Helper::S3Helper.your_method`
      #
      def self.show_message
        UI.message("Hello from the s3 plugin helper!")
      end

      #
      # Taken from https://github.com/fastlane/fastlane/blob/9c0494ef5e7d71afc51c73fe0b141b02e8991d9c/fastlane/lib/fastlane/erb_template_helper.rb
      # Because I need to load from my plugin gem (not main fastlane gem)
      #
      require "erb"
      def self.load(template_name)
        path = "#{Helper.gem_path('fastlane-plugin-s3')}/lib/assets/#{template_name}.erb"
        load_from_path(path)
      end

      def self.load_from_path(template_filepath)
        unless File.exist?(template_filepath)
          UI.user_error!("Could not find Template at path '#{template_filepath}'")
        end
        File.read(template_filepath)
      end

      def self.render(template, template_vars_hash)
        Fastlane::ErbalT.new(template_vars_hash).render(template)
      end
    end
  end
end
