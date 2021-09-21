# rubocop:disable Metrics/AbcSize
require 'fastlane/erb_template_helper'
include ERB::Util
require 'ostruct'
require 'cgi'
require 'mime-types'
require 'pathname'

module Fastlane
  module Actions
    module SharedValues
      S3_APK_OUTPUT_PATH ||= :S3_APK_OUTPUT_PATH
      S3_IPA_OUTPUT_PATH ||= :S3_IPA_OUTPUT_PATH
      S3_DSYM_OUTPUT_PATH ||= :S3_DSYM_OUTPUT_PATH
      S3_PLIST_OUTPUT_PATH ||= :S3_PLIST_OUTPUT_PATH
      S3_HTML_OUTPUT_PATH ||= :S3_HTML_OUTPUT_PATH
      S3_VERSION_OUTPUT_PATH ||= :S3_VERSION_OUTPUT_PATH
      S3_SOURCE_OUTPUT_PATH ||= :S3_SOURCE_OUTPUT_PATH
      S3_XCARCHIVE_OUTPUT_PATH ||= :S3_XCARCHIVE_OUTPUT_PATH
      S3_FILES_OUTPUT_PATHS ||= :S3_FILES_OUTPUT_PATHS
      S3_FOLDER_OUTPUT_PATH ||= :S3_FOLDER_OUTPUT_PATH
    end

    class AwsS3Action < Action
      def self.run(config)
        # Calling fetch on config so that default values will be used
        params = {}
        params[:apk] = config[:apk]
        params[:ipa] = config[:ipa]
        params[:xcarchive] = config[:xcarchive]
        params[:dsym] = config[:dsym]
        params[:release_notes] = config[:release_notes]
        params[:access_key] = config[:access_key]
        params[:secret_access_key] = config[:secret_access_key]
        params[:aws_session_token] = config[:aws_session_token]
        params[:aws_profile] = config[:aws_profile]
        params[:bucket] = config[:bucket]
        params[:endpoint] = config[:endpoint]
        params[:download_endpoint] = config[:download_endpoint]
        params[:download_endpoint_replacement_regex] = config[:download_endpoint_replacement_regex]
        params[:region] = config[:region]
        params[:app_directory] = config[:app_directory]
        params[:acl] = config[:acl]
        params[:server_side_encryption] = config[:server_side_encryption]
        params[:source] = config[:source]
        params[:path] = config[:path]
        params[:upload_metadata] = config[:upload_metadata]
        params[:plist_template_path] = config[:plist_template_path]
        params[:plist_file_name] = config[:plist_file_name]
        params[:html_template_path] = config[:html_template_path]
        params[:html_template_params] = config[:html_template_params]
        params[:html_file_name] = config[:html_file_name]
        params[:skip_html_upload] = config[:skip_html_upload]
        params[:html_in_folder] = config[:html_in_folder]
        params[:html_in_root] = config[:html_in_root]
        params[:version_in_folder] = config[:version_in_folder]
        params[:version_in_root] = config[:version_in_root]
        params[:version_template_path] = config[:version_template_path]
        params[:version_file_name] = config[:version_file_name]
        params[:version_template_params] = config[:version_template_params]
        params[:override_file_name] = config[:override_file_name]
        params[:files] = config[:files]
        params[:folder] = config[:folder]

        # Pulling parameters for other uses
        s3_region = params[:region]
        s3_access_key = params[:access_key]
        s3_secret_access_key = params[:secret_access_key]
        s3_session_token = params[:aws_session_token]
        s3_profile = params[:aws_profile]
        s3_bucket = params[:bucket]
        s3_endpoint = params[:endpoint]
        apk_file = params[:apk]
        ipa_file = params[:ipa]
        release_notes = params[:release_notes]
        xcarchive_file = params[:xcarchive]
        files = params[:files]
        folder = params[:folder]
        dsym_file = params[:dsym]
        s3_path = params[:path]
        acl     = params[:acl].to_sym
        server_side_encryption = params[:server_side_encryption]

        UI.user_error!("No S3 bucket given, pass using `bucket: 'bucket'`") unless s3_bucket.to_s.length > 0
        UI.user_error!("No IPA, APK file, folder or files paths given, pass using `ipa: 'ipa path'` or `apk: 'apk path'` or `folder: 'folder path' or files: [`file path1`, `file path 2`]") if ipa_file.to_s.length == 0 && apk_file.to_s.length == 0 && files.to_a.count == 0 && folder.to_s.length == 0
        UI.user_error!("Please only give IPA path or APK path (not both)") if ipa_file.to_s.length > 0 && apk_file.to_s.length > 0

        require 'aws-sdk-s3'

        client_cfg = {}
        client_cfg[:region] = s3_region if s3_region
        client_cfg[:endpoint] = s3_endpoint if s3_endpoint
        client_cfg[:profile] = s3_profile if s3_profile
        client_cfg[:credentials] = Aws::Credentials.new(s3_access_key, s3_secret_access_key, s3_session_token) if s3_access_key && s3_secret_access_key

        s3_client = Aws::S3::Client.new(client_cfg)

        if xcarchive_file.nil?
          xcarchive_file = Actions.lane_context[SharedValues::XCODEBUILD_ARCHIVE]
        end

        upload_ipa(s3_client, params, s3_region, s3_access_key, s3_secret_access_key, s3_bucket, ipa_file, dsym_file, release_notes, s3_path, acl, server_side_encryption) if ipa_file.to_s.length > 0
        upload_apk(s3_client, params, s3_region, s3_access_key, s3_secret_access_key, s3_bucket, apk_file, release_notes, s3_path, acl, server_side_encryption) if apk_file.to_s.length > 0
        upload_xcarchive(s3_client, params, s3_region, s3_access_key, s3_secret_access_key, s3_bucket, ipa_file, xcarchive_file, s3_path, acl, server_side_encryption) if xcarchive_file.to_s.length > 0
        upload_files(s3_client, params, s3_region, s3_access_key, s3_secret_access_key, s3_bucket, files, s3_path, acl, server_side_encryption) if files.to_a.count > 0
        upload_folder(s3_client, params, s3_region, s3_access_key, s3_secret_access_key, s3_bucket, folder, s3_path, acl, server_side_encryption) if folder.to_s.length > 0

        return true
      end

      def self.upload_ipa(s3_client, params, s3_region, s3_access_key, s3_secret_access_key, s3_bucket, ipa_file, dsym_file, release_notes, s3_path, acl, server_side_encryption)

        s3_path = "v{CFBundleShortVersionString}_b{CFBundleVersion}/" unless s3_path

        app_directory = params[:app_directory]

        plist_template_path = params[:plist_template_path]
        plist_file_name = params[:plist_file_name]
        html_template_path = params[:html_template_path]
        html_template_params = params[:html_template_params] || {}
        html_file_name = params[:html_file_name]
        generate_html_in_folder = params[:html_in_folder]
        generate_html_in_root = params[:html_in_root]
        generate_version_in_folder = params[:version_in_folder]
        generate_version_in_root = params[:version_in_root]
        version_template_path = params[:version_template_path]
        version_template_params = params[:version_template_params] || {}
        version_file_name = params[:version_file_name]
        override_file_name = params[:override_file_name]
        download_endpoint = params[:download_endpoint]
        download_endpoint_replacement_regex = params[:download_endpoint_replacement_regex]
        url_part = self.expand_path_with_substitutions_from_ipa_plist(ipa_file, s3_path)

        ipa_file_basename = File.basename(ipa_file)
        ipa_file_name = "#{url_part}#{override_file_name ? override_file_name : ipa_file_basename}"
        ipa_file_data = File.open(ipa_file, 'rb')

        ipa_url = self.upload_file(s3_client, s3_bucket, app_directory, ipa_file_name, ipa_file_data, acl, server_side_encryption, download_endpoint, download_endpoint_replacement_regex)

        # Setting action and environment variables
        Actions.lane_context[SharedValues::S3_IPA_OUTPUT_PATH] = ipa_url
        ENV[SharedValues::S3_IPA_OUTPUT_PATH.to_s] = ipa_url

        if dsym_file
          dsym_file_basename = File.basename(dsym_file)
          dsym_file_name = "#{url_part}#{dsym_file_basename}"
          dsym_file_data = File.open(dsym_file, 'rb')

          dsym_url = self.upload_file(s3_client, s3_bucket, app_directory, dsym_file_name, dsym_file_data, acl, server_side_encryption, download_endpoint, download_endpoint_replacement_regex)

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
        display_name = info['CFBundleDisplayName']
        if display_name.nil?
          display_name = info['CFBundleName']
        end
        title = CGI.escapeHTML(display_name)
        full_version = "#{bundle_version}.#{build_num}"

        # Creating plist and html names
        plist_file_name ||= "#{url_part}#{CGI.escape(title.delete(' '))}.plist"

        html_file_name ||= "index.html"

        version_file_name ||= "version.json"

        # grabs module
        eth = Fastlane::Helper::AwsS3Helper

        # Creates plist from template
        if plist_template_path && File.exist?(plist_template_path)
          plist_template = eth.load_from_path(plist_template_path)
        else
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
        plist_url = self.upload_file(s3_client, s3_bucket, app_directory, plist_file_name, plist_render, acl, server_side_encryption, download_endpoint, download_endpoint_replacement_regex)

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
          title: title,
          release_notes: release_notes
        }.merge(html_template_params))

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
          full_version: full_version,
          release_notes: release_notes
        }.merge(version_template_params))

        #####################################
        #
        # html uploading
        #
        #####################################

        skip_html = params[:skip_html_upload]

        html_file_names = []
        version_file_names = []

        unless skip_html
          if generate_html_in_root
            html_file_names << html_file_name
          end
          if generate_html_in_folder
            html_file_names << "#{url_part}#{html_file_name}"
          end
        end
        if generate_version_in_root
          version_file_names << version_file_name
        end
        if generate_version_in_folder
          version_file_names << "#{url_part}#{version_file_name}"
        end

        html_url = nil
        version_url = nil

        html_file_names.each do |html_file_name|
          html_url = self.upload_file(s3_client, s3_bucket, app_directory, html_file_name, html_render, acl, server_side_encryption, download_endpoint, download_endpoint_replacement_regex)
        end
        version_file_names.each do |version_file_name|
          version_url = self.upload_file(s3_client, s3_bucket, app_directory, version_file_name, version_render, acl, server_side_encryption, download_endpoint, download_endpoint_replacement_regex)
        end

        # Setting action and environment variables
        Actions.lane_context[SharedValues::S3_PLIST_OUTPUT_PATH] = plist_url
        ENV[SharedValues::S3_PLIST_OUTPUT_PATH.to_s] = plist_url

        Actions.lane_context[SharedValues::S3_HTML_OUTPUT_PATH] = html_url unless skip_html
        ENV[SharedValues::S3_HTML_OUTPUT_PATH.to_s] = html_url unless skip_html

        Actions.lane_context[SharedValues::S3_VERSION_OUTPUT_PATH] = version_url
        ENV[SharedValues::S3_VERSION_OUTPUT_PATH.to_s] = version_url

        self.upload_source(s3_client, params, s3_bucket, params[:source], s3_path, acl, server_side_encryption)

        UI.success("Successfully uploaded ipa file to '#{Actions.lane_context[SharedValues::S3_IPA_OUTPUT_PATH]}'")
        UI.success("iOS app can be downloaded at '#{Actions.lane_context[SharedValues::S3_HTML_OUTPUT_PATH]}'") unless skip_html
      end

      def self.upload_xcarchive(s3_client, params, s3_region, s3_access_key, s3_secret_access_key, s3_bucket, ipa_file, archive, s3_path, acl, server_side_encryption)

        s3_path = "v{CFBundleShortVersionString}_b{CFBundleVersion}/" unless s3_path

        app_directory = params[:app_directory]

        url_part = self.expand_path_with_substitutions_from_ipa_plist(ipa_file, s3_path)

        archive_name = archive.gsub(' ','_')
        archive_zip = "#{archive_name}.zip"
        archive_zip_name = File.basename(archive_zip)
        sh("zip -r '#{archive_zip}' '#{archive}'")
        full_archive_zip_name = "#{url_part}#{archive_zip_name}"
        archive_zip_data = File.open(archive_zip, 'rb')
        download_endpoint = params[:download_endpoint]
        download_endpoint_replacement_regex = params[:download_endpoint_replacement_regex]

        archive_url = self.upload_file(s3_client, s3_bucket, app_directory, full_archive_zip_name, archive_zip_data, acl, server_side_encryption, download_endpoint, download_endpoint_replacement_regex)

        Actions.lane_context[SharedValues::S3_XCARCHIVE_OUTPUT_PATH] = archive_url
        ENV[SharedValues::S3_XCARCHIVE_OUTPUT_PATH.to_s] = archive_url

        UI.success("Successfully uploaded archive file to '#{Actions.lane_context[SharedValues::S3_XCARCHIVE_OUTPUT_PATH]}'")
      end

      def self.upload_apk(s3_client, params, s3_region, s3_access_key, s3_secret_access_key, s3_bucket, apk_file, release_notes, s3_path, acl, server_side_encryption)
        version = get_apk_version(apk_file)

        version_code = version[0]
        version_name = version[1]
        title = version[2]

        s3_path = "v{version_name}_b{version_code}/" unless s3_path

        app_directory = params[:app_directory]

        html_template_path = params[:html_template_path]
        html_template_params = params[:html_template_params] || {}
        html_file_name = params[:html_file_name]
        generate_html_in_folder = params[:html_in_folder]
        generate_html_in_root = params[:html_in_root]
        generate_version_in_folder = params[:version_in_folder]
        generate_version_in_root = params[:version_in_root]
        version_template_path = params[:version_template_path]
        version_template_params = params[:version_template_params] || {}
        version_file_name = params[:version_file_name]
        override_file_name = params[:override_file_name]
        download_endpoint = params[:download_endpoint]
        download_endpoint_replacement_regex = params[:download_endpoint_replacement_regex]

        url_part = self.expand_path_with_substitutions_with_versions(version_code, version_name, s3_path)

        apk_file_basename = File.basename(apk_file)
        apk_file_name = "#{url_part}#{override_file_name ? override_file_name : apk_file_basename}"
        apk_file_data = File.open(apk_file, 'rb')

        apk_url = self.upload_file(s3_client, s3_bucket, app_directory, apk_file_name, apk_file_data, acl, server_side_encryption, download_endpoint, download_endpoint_replacement_regex)

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
          title: title,
          release_notes: release_notes
        }.merge(html_template_params))

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
          full_version: "#{version_code}_#{version_name}",
          release_notes: release_notes
        }.merge(version_template_params))

        #####################################
        #
        # html and plist uploading
        #
        #####################################

        skip_html = params[:skip_html_upload]

        html_file_names = []
        version_file_names = []

        unless skip_html
          if generate_html_in_root
            html_file_names << html_file_name
          end
          if generate_html_in_folder
            html_file_names << "#{url_part}#{html_file_name}"
          end
        end
        if generate_version_in_root
          version_file_names << version_file_name
        end
        if generate_version_in_folder
          version_file_names << "#{url_part}#{version_file_name}"
        end

        html_url = nil
        version_url = nil

        html_file_names.each do |html_file_name|
          html_url = self.upload_file(s3_client, s3_bucket, app_directory, html_file_name, html_render, acl, server_side_encryption, download_endpoint, download_endpoint_replacement_regex)
        end

        version_file_names.each do |version_file_name|
          version_url = self.upload_file(s3_client, s3_bucket, app_directory, version_file_name, version_render, acl, server_side_encryption, download_endpoint, download_endpoint_replacement_regex)
        end

        Actions.lane_context[SharedValues::S3_HTML_OUTPUT_PATH] = html_url unless skip_html
        ENV[SharedValues::S3_HTML_OUTPUT_PATH.to_s] = html_url unless skip_html

        Actions.lane_context[SharedValues::S3_VERSION_OUTPUT_PATH] = version_url
        ENV[SharedValues::S3_VERSION_OUTPUT_PATH.to_s] = version_url

        self.upload_source(s3_client, params, s3_bucket, params[:source], s3_path, acl, server_side_encryption)

        UI.success("Successfully uploaded apk file to '#{Actions.lane_context[SharedValues::S3_APK_OUTPUT_PATH]}'")
        UI.success("Android app can be downloaded at '#{Actions.lane_context[SharedValues::S3_HTML_OUTPUT_PATH]}'") unless skip_html
      end

      def self.upload_source(s3_client, params, s3_bucket, source_directory, s3_path, acl, server_side_encryption)
        if source_directory && File.directory?(source_directory)
          source_directory = File.absolute_path source_directory
          output_file_path = Tempfile.new('aws_s3_source').path

          output_file_path = other_action.zip(
            path: source_directory,
            output_path: output_file_path.gsub(/(?<!.zip)$/, ".zip")
          )

          s3_path = "#{version_code}_#{version_name}/" unless s3_path
          app_directory = params[:app_directory]
          url_part = s3_path
          zip_file_name = "#{url_part}source.zip"

          output_path_data = File.open("#{output_file_path}", 'rb')
          download_endpoint = params[:download_endpoint]
          download_endpoint_replacement_regex = params[:download_endpoint_replacement_regex]
          source_url = self.upload_file(s3_client, s3_bucket, app_directory, zip_file_name, output_path_data, acl, server_side_encryption, download_endpoint, download_endpoint_replacement_regex)

          Actions.lane_context[SharedValues::S3_SOURCE_OUTPUT_PATH] = source_url
          ENV[SharedValues::S3_SOURCE_OUTPUT_PATH.to_s] = source_url

          UI.success("Source can be downloaded at '#{Actions.lane_context[SharedValues::S3_SOURCE_OUTPUT_PATH]}'")
        end
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

      def self.upload_files(s3_client, params, s3_region, s3_access_key, s3_secret_access_key, s3_bucket, files, s3_path, acl, server_side_encryption)

        s3_path = "files" unless s3_path

        app_directory = params[:app_directory]
        url_part = s3_path

        download_endpoint = params[:download_endpoint]
        download_endpoint_replacement_regex = params[:download_endpoint_replacement_regex]

        Actions.lane_context[SharedValues::S3_FILES_OUTPUT_PATHS] = []
        files.each do |file|
          file_basename = File.basename(file)
          file_data = File.open(file, 'rb')
          file_name = url_part + '/' + file_basename

          file_url = self.upload_file(s3_client, s3_bucket, app_directory, file_name, file_data, acl, server_side_encryption, download_endpoint, download_endpoint_replacement_regex)

          # Setting action and environment variables
          Actions.lane_context[SharedValues::S3_FILES_OUTPUT_PATHS] << file_url
        end
      end

      def self.upload_folder(s3_client, params, s3_region, s3_access_key, s3_secret_access_key, s3_bucket, folder, s3_path, acl, server_side_encryption)

        s3_path = "files" unless s3_path

        s3_path = s3_path.to_s + '/' + File.basename(folder)
        url_part = s3_path
        app_directory = params[:app_directory]

        download_endpoint = params[:download_endpoint]
        download_endpoint_replacement_regex = params[:download_endpoint_replacement_regex]

        unless File.directory?(folder)
          UI.user_error!("Invalid folder parameter. `#{File.expand_path(folder)} is not a directory!")
        end

        Dir.glob("#{folder}/**/*") do |file|
          next if File.directory?(file)
          file_data = File.open(file, 'rb')
          file_relative_path_to_folder = Pathname.new(File.expand_path(file)).relative_path_from(Pathname.new(File.expand_path(folder))).to_s
          file_name = url_part + '/' + file_relative_path_to_folder

          file_url = self.upload_file(s3_client, s3_bucket, app_directory, file_name, file_data, acl, server_side_encryption, download_endpoint, download_endpoint_replacement_regex)
          Actions.lane_context[SharedValues::S3_FOLDER_OUTPUT_PATH] = CGI.unescape(file_url).gsub('/' + file_relative_path_to_folder, '')
        end
      end

      def self.upload_file(s3_client, bucket_name, app_directory, file_name, file_data, acl, server_side_encryption, download_endpoint, download_endpoint_replacement_regex)

        if app_directory
          file_name = "#{app_directory}/#{file_name}"
        end

        bucket = Aws::S3::Bucket.new(bucket_name, client: s3_client)
        details = {
          acl: acl,
          key: file_name,
          body: file_data,
          content_type: MIME::Types.type_for(File.extname(file_name)).first.to_s
        }
        details = details.merge(server_side_encryption: server_side_encryption) if server_side_encryption.length > 0
        obj = bucket.put_object(details)

        # When you enable versioning on a S3 bucket,
        # writing to an object will create an object version
        # instead of replacing the existing object.
        # http://docs.aws.amazon.com/AWSRubySDK/latest/AWS/S3/ObjectVersion.html
        if obj.kind_of? Aws::S3::ObjectVersion
          obj = obj.object
        end

        # Return public url
        url = obj.public_url.to_s

        # if a download endpoint is provided, then swap it in before returning
        if download_endpoint
          url = url.gsub(Regexp.new(download_endpoint_replacement_regex), download_endpoint)
        end

        return url
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

      def self.expand_path_with_substitutions_with_versions(version_code, version_name, path)
        path.gsub!(/\{version_code\}/, version_code.to_s) if version_code
        path.gsub!(/\{version_name\}/, version_name) if version_name
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
          FastlaneCore::ConfigItem.new(key: :xcarchive,
                                       env_name: "",
                                       description: ".xcarchive file for the build. Set to a path to an `.xcarchive` file or `nil` for `Actions.lane_context[SharedValues::XCODEBUILD_ARCHIVE])` to be used",
                                       optional: true,
                                       default_value: ""),
          FastlaneCore::ConfigItem.new(key: :dsym,
                                       env_name: "",
                                       description: "zipped .dsym package for the build ",
                                       optional: true,
                                       default_value: Actions.lane_context[SharedValues::DSYM_OUTPUT_PATH]),
          FastlaneCore::ConfigItem.new(key: :release_notes,
                                       env_name: "",
                                       description: "release notes to display on the html page and version json",
                                       optional: true),
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
          FastlaneCore::ConfigItem.new(key: :plist_file_name,
                                       env_name: "",
                                       description: "uploaded plist filename",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :html_template_path,
                                       env_name: "",
                                       description: "html erb template path",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :html_template_params,
                                       env_name: "",
                                       description: "additional params for use in the html template",
                                       optional: true,
                                       type: Hash),
          FastlaneCore::ConfigItem.new(key: :html_file_name,
                                       env_name: "",
                                       description: "uploaded html filename",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :skip_html_upload,
                                       env_name: "",
                                       description: "skip html upload if true",
                                       optional: true,
                                       default_value: false,
                                       is_string: false),
          FastlaneCore::ConfigItem.new(key: :html_in_folder,
                                       env_name: "",
                                       description: "upload the html file into the version folder",
                                       optional: true,
                                       default_value: false,
                                       is_string: false),
          FastlaneCore::ConfigItem.new(key: :html_in_root,
                                       env_name: "",
                                       description: "upload the html file into the 'root' folder",
                                       optional: true,
                                       default_value: true,
                                       is_string: false),
          FastlaneCore::ConfigItem.new(key: :version_in_folder,
                                       env_name: "",
                                       description: "upload the version file into the version folder",
                                       optional: true,
                                       default_value: false,
                                       is_string: false),
          FastlaneCore::ConfigItem.new(key: :version_in_root,
                                       env_name: "",
                                       description: "upload the html file into the 'root' folder",
                                       optional: true,
                                       default_value: true,
                                       is_string: false),
          FastlaneCore::ConfigItem.new(key: :version_template_path,
                                       env_name: "",
                                       description: "version erb template path",
                                       optional: true),
          FastlaneCore::ConfigItem.new(key: :version_template_params,
                                       env_name: "",
                                       description: "additional params for use in the version template",
                                       optional: true,
                                       type: Hash),
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
          FastlaneCore::ConfigItem.new(key: :aws_session_token,
                                       env_name: "S3_SESSION_TOKEN",
                                       description: "AWS Session TOKEN ",
                                       optional: true,
                                       default_value: ENV['AWS_SESSION_TOKEN']),
          FastlaneCore::ConfigItem.new(key: :aws_profile,
                                       env_name: "S3_PROFILE",
                                       description: "AWS profile to use for credentials",
                                       optional: true,
                                       default_value: ENV['AWS_PROFILE']),
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
                                       default_value: "public-read"),
          FastlaneCore::ConfigItem.new(key: :server_side_encryption,
                                       env_name: "S3_SERVER_SIDE_ENCRYPTION",
                                       description: "Enable encryption of the uploaded S3 object (set it to 'AES256' for example)",
                                       optional: true,
                                       default_value: ""),
          FastlaneCore::ConfigItem.new(key: :endpoint,
                                       env_name: "S3_ENDPOINT",
                                       description: "The base endpoint for your S3 bucket",
                                       optional: true,
                                       default_value: nil),
          FastlaneCore::ConfigItem.new(key: :download_endpoint,
                                       env_name: "S3_DOWNLOAD_ENDPOINT",
                                       description: "The endpoint for downloads from your S3 bucket",
                                       optional: true,
                                       default_value: nil),
          FastlaneCore::ConfigItem.new(key: :download_endpoint_replacement_regex,
                                       env_name: "S3_DOWNLOAD_ENDPOINT_REPLACEMENT_REGEX",
                                       description: "A regex used to determine which part of the S3 URL to replace with S3_DOWNLOAD_ENDPOINT",
                                       optional: true,
                                       default_value: '^https?://[^/]*'),
          FastlaneCore::ConfigItem.new(key: :override_file_name,
                                       env_name: "",
                                       description: "Optional override ipa/apk uploaded file name",
                                       optional: true,
                                       default_value: nil),
          FastlaneCore::ConfigItem.new(key: :files,
                                       env_name: "",
                                       description: "Collection: Allows you to simply upload any files to s3. Ex: ['filename1', filename2]",
                                       is_string: false,
                                       optional: true,
                                       default_value: nil),
          FastlaneCore::ConfigItem.new(key: :folder,
                                       env_name: "",
                                       description: "Path to the folder you want to upload",
                                       is_string: true,
                                       optional: true,
                                       default_value: nil)
        ]
      end

      def self.output
        [
          ['S3_APK_OUTPUT_PATH', 'Direct HTTP link to the uploaded apk file'],
          ['S3_IPA_OUTPUT_PATH', 'Direct HTTP link to the uploaded ipa file'],
          ['S3_XCARCHIVE_OUTPUT_PATH', 'Direct HTTP link to the uploaded xcarchive file '],
          ['S3_DSYM_OUTPUT_PATH', 'Direct HTTP link to the uploaded dsym file'],
          ['S3_PLIST_OUTPUT_PATH', 'Direct HTTP link to the uploaded plist file'],
          ['S3_HTML_OUTPUT_PATH', 'Direct HTTP link to the uploaded HTML file'],
          ['S3_VERSION_OUTPUT_PATH', 'Direct HTTP link to the uploaded Version file'],
          ['S3_SOURCE_OUTPUT_PATH', 'Direct HTTP link to the uploaded source '],
          ['S3_FILES_OUTPUT_PATHS', 'Collection of HTTP links to the uploaded files'],
          ['S3_FOLDER_OUTPUT_PATH', 'Direct HTTP link to the uploaded folder']
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
