# rubocop:disable Metrics/AbcSize
require 'fastlane/erb_template_helper'
require 'ostruct'

module Fastlane
  module Actions
    module SharedValues
      S3_APK_OUTPUT_PATH ||= :S3_APK_OUTPUT_PATH
      S3_IPA_OUTPUT_PATH ||= :S3_IPA_OUTPUT_PATH
      S3_DSYM_OUTPUT_PATH ||= :S3_DSYM_OUTPUT_PATH
      S3_PLIST_OUTPUT_PATH ||= :S3_PLIST_OUTPUT_PATH
      S3_HTML_OUTPUT_PATH ||= :S3_HTML_OUTPUT_PATH
      S3_VERSION_OUTPUT_PATH ||= :S3_VERSION_OUTPUT_PATH
    end

    class AwsS3Action < Action
      def self.run(config)
        # Calling fetch on config so that default values will be used
        params = {}
        params[:apk] = config[:apk]
        params[:ipa] = config[:ipa]
        params[:dsym] = config[:dsym]
        params[:access_key] = config[:access_key]
        params[:secret_access_key] = config[:secret_access_key]
        params[:bucket] = config[:bucket]
        params[:region] = config[:region]
        params[:expires_in] = config[:expires_in]
        params[:app_directory] = config[:app_directory]
        params[:acl] = config[:acl]
        params[:source] = config[:source]
        params[:path] = config[:path]
        params[:upload_metadata] = config[:upload_metadata]
        params[:plist_template_path] = config[:plist_template_path]
        params[:html_template_path] = config[:html_template_path]
        params[:html_file_name] = config[:html_file_name]
        params[:version_template_path] = config[:version_template_path]
        params[:version_file_name] = config[:version_file_name]

        # Pulling parameters for other uses
        s3_region = params[:region]
        s3_access_key = params[:access_key]
        s3_secret_access_key = params[:secret_access_key]
        s3_bucket = params[:bucket]
        apk_file = params[:apk]
        ipa_file = params[:ipa]
        dsym_file = params[:dsym]
        s3_path = params[:path]
        acl     = params[:acl].to_sym

        UI.user_error!("No S3 access key given, pass using `access_key: 'key'`") unless s3_access_key.to_s.length > 0
        UI.user_error!("No S3 secret access key given, pass using `secret_access_key: 'secret key'`") unless s3_secret_access_key.to_s.length > 0
        UI.user_error!("No S3 bucket given, pass using `bucket: 'bucket'`") unless s3_bucket.to_s.length > 0
        UI.user_error!("No IPA or APK file path given, pass using `ipa: 'ipa path'` or `apk: 'apk path'`") if ipa_file.to_s.length == 0 && apk_file.to_s.length == 0
        UI.user_error!("Please only give IPA path or APK path (not both)") if ipa_file.to_s.length > 0 && apk_file.to_s.length > 0

        require 'aws-sdk'
        Aws.config.update({
          region: s3_region,
          credentials: Aws::Credentials.new(s3_access_key, s3_secret_access_key)
        })

        s3_client = Aws::S3::Client.new

        upload_ipa(s3_client, params, s3_region, s3_access_key, s3_secret_access_key, s3_bucket, ipa_file, dsym_file, s3_path, acl) if ipa_file.to_s.length > 0
        upload_apk(s3_client, params, s3_region, s3_access_key, s3_secret_access_key, s3_bucket, apk_file, s3_path, acl) if apk_file.to_s.length > 0

        return true
      end

      def self.upload_ipa(s3_client, params, s3_region, s3_access_key, s3_secret_access_key, s3_bucket, ipa_file, dsym_file, s3_path, acl)

        s3_path = "v{CFBundleShortVersionString}_b{CFBundleVersion}/" unless s3_path

        expires_in = params[:expires_in]
        app_directory = params[:app_directory]

        plist_template_path = params[:plist_template_path]
        html_template_path = params[:html_template_path]
        html_file_name = params[:html_file_name]
        version_template_path = params[:version_template_path]
        version_file_name = params[:version_file_name]

        url_part = self.expand_path_with_substitutions_from_ipa_plist(ipa_file, s3_path)

        ipa_file_basename = File.basename(ipa_file)
        ipa_file_name = "#{url_part}#{ipa_file_basename}"
        ipa_file_data = File.open(ipa_file, 'rb')

        ipa_url = self.upload_file(s3_client, s3_bucket, app_directory, ipa_file_name, ipa_file_data, acl, expires_in)

        # Setting action and environment variables
        Actions.lane_context[SharedValues::S3_IPA_OUTPUT_PATH] = ipa_url
        ENV[SharedValues::S3_IPA_OUTPUT_PATH.to_s] = ipa_url

        if dsym_file
          dsym_file_basename = File.basename(dsym_file)
          dsym_file_name = "#{url_part}#{dsym_file_basename}"
          dsym_file_data = File.open(dsym_file, 'rb')

          dsym_url = self.upload_file(s3_client, s3_bucket, app_directory, dsym_file_name, dsym_file_data, acl, expires_in)

          # Setting action and environment variables
          Actions.lane_context[SharedValues::S3_DSYM_OUTPUT_PATH] = dsym_url
          ENV[SharedValues::S3_DSYM_OUTPUT_PATH.to_s] = dsym_url

        end

        if params[:upload_metadata] == false
          return true
        end

        #####################################
        #
        # html and plist building
        #
        #####################################

        # Gets info used for the plist
        info = FastlaneCore::IpaFileAnalyser.fetch_info_plist_file(ipa_file)

        build_num = info['CFBundleVersion']
        bundle_id = info['CFBundleIdentifier']
        bundle_version = info['CFBundleShortVersionString']
        title = info['CFBundleName']
        full_version = "#{bundle_version}.#{build_num}"

        # Creating plist and html names
        plist_file_name = "#{url_part}#{title.delete(' ')}.plist"

        html_file_name ||= "index.html"

        version_file_name ||= "version.json"

        # grabs module
        eth = Fastlane::Helper::AwsS3Helper

        # Creates plist from template
        if plist_template_path && File.exist?(plist_template_path)
          puts "1 - #{plist_template_path}"
          plist_template = eth.load_from_path(plist_template_path)
        else
          puts "2 - #{Helper.gem_path('fastlane-plugin-aws_s3')}"
          plist_template = eth.load("s3_ios_plist_template")
        end
        plist_render = eth.render(plist_template, {
          url: ipa_url,
          ipa_url: ipa_url,
          build_num: build_num,
          bundle_id: bundle_id,
          bundle_version: bundle_version,
          title: title
        })

        #####################################
        #
        # plist uploading
        #
        #####################################
        plist_url = self.upload_file(s3_client, s3_bucket, app_directory, plist_file_name, plist_render, acl, expires_in)

        # Creates html from template
        if html_template_path && File.exist?(html_template_path)
          html_template = eth.load_from_path(html_template_path)
        else
          html_template = eth.load("s3_ios_html_template")
        end
        html_render = eth.render(html_template, {
          url: plist_url,
          plist_url: plist_url,
          ipa_url: ipa_url,
          build_num: build_num,
          bundle_id: bundle_id,
          bundle_version: bundle_version,
          title: title
        })

        # Creates version from template
        if version_template_path && File.exist?(version_template_path)
          version_template = eth.load_from_path(version_template_path)
        else
          version_template = eth.load("s3_ios_version_template")
        end
        version_render = eth.render(version_template, {
          url: plist_url,
          plist_url: plist_url,
          ipa_url: ipa_url,
          build_num: build_num,
          bundle_version: bundle_version,
          full_version: full_version
        })

        #####################################
        #
        # html uploading
        #
        #####################################
        html_url = self.upload_file(s3_client, s3_bucket, app_directory, html_file_name, html_render, acl, expires_in)
        version_url = self.upload_file(s3_client, s3_bucket, app_directory, version_file_name, version_render, acl, expires_in)

        # Setting action and environment variables
        Actions.lane_context[SharedValues::S3_PLIST_OUTPUT_PATH] = plist_url
        ENV[SharedValues::S3_PLIST_OUTPUT_PATH.to_s] = plist_url

        Actions.lane_context[SharedValues::S3_HTML_OUTPUT_PATH] = html_url
        ENV[SharedValues::S3_HTML_OUTPUT_PATH.to_s] = html_url

        Actions.lane_context[SharedValues::S3_VERSION_OUTPUT_PATH] = version_url
        ENV[SharedValues::S3_VERSION_OUTPUT_PATH.to_s] = version_url

        UI.success("Successfully uploaded ipa file to '#{Actions.lane_context[SharedValues::S3_IPA_OUTPUT_PATH]}'")
        UI.success("iOS app can be downloaded at '#{Actions.lane_context[SharedValues::S3_HTML_OUTPUT_PATH]}'")
      end

      def self.upload_apk(s3_client, params, s3_region, s3_access_key, s3_secret_access_key, s3_bucket, apk_file, s3_path, acl)
        version = get_apk_version(apk_file)

        version_code = version[0]
        version_name = version[1]
        title = version[2]

        s3_path = "#{version_code}_#{version_name}/" unless s3_path

        expires_in = params[:expires_in]
        app_directory = params[:app_directory]

        html_template_path = params[:html_template_path]
        html_file_name = params[:html_file_name]
        version_template_path = params[:version_template_path]
        version_file_name = params[:version_file_name]

        url_part = s3_path

        apk_file_basename = File.basename(apk_file)
        apk_file_name = "#{url_part}#{apk_file_basename}"
        apk_file_data = File.open(apk_file, 'rb')

        apk_url = self.upload_file(s3_client, s3_bucket, app_directory, apk_file_name, apk_file_data, acl, expires_in)

        # Setting action and environment variables
        Actions.lane_context[SharedValues::S3_APK_OUTPUT_PATH] = apk_url
        ENV[SharedValues::S3_APK_OUTPUT_PATH.to_s] = apk_url

        if params[:upload_metadata] == false
          return true
        end

        #####################################
        #
        # html and plist building
        #
        #####################################

        html_file_name ||= "index.html"

        version_file_name ||= "version.json"

        # grabs module
        eth = Fastlane::Helper::AwsS3Helper

        # Creates html from template
        if html_template_path && File.exist?(html_template_path)
          html_template = eth.load_from_path(html_template_path)
        else
          html_template = eth.load("s3_android_html_template")
        end
        html_render = eth.render(html_template, {
          apk_url: apk_url,
          version_code: version_code,
          version_name: version_name,
          title: title
        })

        # Creates version from template
        if version_template_path && File.exist?(version_template_path)
          version_template = eth.load_from_path(version_template_path)
        else
          version_template = eth.load("s3_android_version_template")
        end
        version_render = eth.render(version_template, {
          apk_url: apk_url,
          version_code: version_code,
          version_name: version_name,
          full_version: "#{version_code}_#{version_name}"
        })

        #####################################
        #
        # html and plist uploading
        #
        #####################################

        html_url = self.upload_file(s3_client, s3_bucket, app_directory, html_file_name, html_render, acl, expires_in)
        version_url = self.upload_file(s3_client, s3_bucket, app_directory, version_file_name, version_render, acl, expires_in)

        Actions.lane_context[SharedValues::S3_HTML_OUTPUT_PATH] = html_url
        ENV[SharedValues::S3_HTML_OUTPUT_PATH.to_s] = html_url

        Actions.lane_context[SharedValues::S3_VERSION_OUTPUT_PATH] = version_url
        ENV[SharedValues::S3_VERSION_OUTPUT_PATH.to_s] = version_url

        UI.success("Successfully uploaded apk file to '#{Actions.lane_context[SharedValues::S3_APK_OUTPUT_PATH]}'")
        UI.success("Android app can be downloaded at '#{Actions.lane_context[SharedValues::S3_HTML_OUTPUT_PATH]}'")
      end

      def self.get_apk_version(apk_file)
        require 'apktools/apkxml'

        # Load the XML data
        parser = ApkXml.new(apk_file)
        parser.parse_xml("AndroidManifest.xml", false, true)

        elements = parser.xml_elements

        versionCode = nil
        versionName = nil
        name = nil

        elements.each do |element|
          if element.name == "manifest"
            element.attributes.each do |attr|
              if attr.name == "versionCode"
                versionCode = attr.value
              elsif attr.name == "versionName"
                versionName = attr.value
              end
            end
          elsif element.name == "application"
            element.attributes.each do |attr|
              if attr.name == "label"
                name = attr.value
              end
            end
          end
        end

        if versionCode =~ /^0x[0-9A-Fa-f]+$/ #if is hex
          versionCode = versionCode.to_i(16)
        end

        [versionCode, versionName, name]
      end

      def self.upload_file(s3_client, bucket_name, app_directory, file_name, file_data, acl, expires_in)

        if app_directory
          file_name = "#{app_directory}/#{file_name}"
        end

        bucket = Aws::S3::Bucket.new(bucket_name, client: s3_client)
        obj = bucket.put_object({
          acl: acl,
          key: file_name,
          body: file_data
        })

        # When you enable versioning on a S3 bucket,
        # writing to an object will create an object version
        # instead of replacing the existing object.
        # http://docs.aws.amazon.com/AWSRubySDK/latest/AWS/S3/ObjectVersion.html
        if obj.kind_of? Aws::S3::ObjectVersion
          obj = obj.object
        end

        if expires_in
          # Generate a presigned GET URL
          obj.presigned_url(:get, expires_in: expires_in).to_s
        else
          # Return public url
          obj.public_url.to_s
        end
      end

      #
      # NOT a fan of this as this was taken straight from Shenzhen
      # https://github.com/nomad/shenzhen/blob/986792db5d4d16a80c865a2748ee96ba63644821/lib/shenzhen/plugins/s3.rb#L32
      #
      # Need to find a way to not use this copied method
      #
      # AGAIN, I am not happy about this right now.
      # Using this for prototype reasons.
      #
      def self.expand_path_with_substitutions_from_ipa_plist(ipa, path)
        substitutions = path.scan(/\{CFBundle[^}]+\}/)
        return path if substitutions.empty?
        info = FastlaneCore::IpaFileAnalyser.fetch_info_plist_file(ipa) or return path

        substitutions.uniq.each do |substitution|
          key = substitution[1...-1]
          value = info[key]
          path.gsub!(Regexp.new(substitution), value) if value
        end

        return path
      end

      def self.description
        "Generates a plist file and uploads all to AWS S3"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :apk,
                                       env_name: "",
                                       description: ".apk file for the build ",
                                       optional: true,
                                       default_value: Actions.lane_context[SharedValues::GRADLE_APK_OUTPUT_PATH]),
          FastlaneCore::ConfigItem.new(key: :ipa,
                                       env_name: "",
                                       description: ".ipa file for the build ",
                                       optional: true,
                                       default_value: Actions.lane_context[SharedValues::IPA_OUTPUT_PATH]),
          FastlaneCore::ConfigItem.new(key: :dsym,
                                       env_name: "",
                                       description: "zipped .dsym package for the build ",
                                       optional: true,
                                       default_value: Actions.lane_context[SharedValues::DSYM_OUTPUT_PATH]),
          FastlaneCore::ConfigItem.new(key: :upload_metadata,
                                       env_name: "",
                                       description: "Upload relevant metadata for this build",
                                       optional: true,
                                       default_value: true,
                                       is_string: false),
          FastlaneCore::ConfigItem.new(key: :plist_template_path,
                                       env_name: "",
                                       description: "plist template path",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :html_template_path,
                                       env_name: "",
                                       description: "html erb template path",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :html_file_name,
                                       env_name: "",
                                       description: "uploaded html filename",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :version_template_path,
                                       env_name: "",
                                       description: "version erb template path",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :version_file_name,
                                       env_name: "",
                                       description: "uploaded version filename",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :access_key,
                                       env_name: "S3_ACCESS_KEY",
                                       description: "AWS Access Key ID ",
                                       optional: true,
                                       default_value: ENV['AWS_ACCESS_KEY_ID']),
          FastlaneCore::ConfigItem.new(key: :secret_access_key,
                                       env_name: "S3_SECRET_ACCESS_KEY",
                                       description: "AWS Secret Access Key ",
                                       optional: true,
                                       default_value: ENV['AWS_SECRET_ACCESS_KEY']),
          FastlaneCore::ConfigItem.new(key: :bucket,
                                       env_name: "S3_BUCKET",
                                       description: "AWS bucket name",
                                       optional: true,
                                       default_value: ENV['AWS_BUCKET_NAME']),
         FastlaneCore::ConfigItem.new(key: :region,
                                       env_name: "S3_REGION",
                                       description: "AWS region (for bucket creation) ",
                                       optional: true,
                                       default_value: ENV['AWS_REGION']),
          FastlaneCore::ConfigItem.new(key: :app_directory,
                                       env_name: "S3_BUCKET_APP_DIRECTORY",
                                       description: "Directory in bucket for the app",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :path,
                                       env_name: "S3_PATH",
                                       description: "S3 'path'. Values from Info.plist will be substituded for keys wrapped in {}  ",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :source,
                                       env_name: "S3_SOURCE",
                                       description: "Optional source directory e.g. ./build ",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :acl,
                                       env_name: "S3_ACL",
                                       description: "Uploaded object permissions e.g public_read (default), private, public_read_write, authenticated_read ",
                                       optional: true,
                                       default_value: "public-read"
                                      ),
          FastlaneCore::ConfigItem.new(key: :expires_in,
                                       type: Integer,
                                       env_name: "S3_URL_EXPIRES_IN",
                                       description: "Expiration time for presigned S3 URLs",
                                       optional: true)
        ]
      end

      def self.output
        [
          ['S3_IPA_OUTPUT_PATH', 'Direct HTTP link to the uploaded ipa file'],
          ['S3_DSYM_OUTPUT_PATH', 'Direct HTTP link to the uploaded dsym file'],
          ['S3_PLIST_OUTPUT_PATH', 'Direct HTTP link to the uploaded plist file'],
          ['S3_HTML_OUTPUT_PATH', 'Direct HTTP link to the uploaded HTML file'],
          ['S3_VERSION_OUTPUT_PATH', 'Direct HTTP link to the uploaded Version file']
        ]
      end

      def self.author
        "joshdholtz"
      end

      def self.is_supported?(platform)
        platform == :ios || platform == :android
      end
    end
  end
end
# rubocop:enable Metrics/AbcSize
