#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'xcodeproj'

root = File.expand_path('..', __dir__)
native_config = File.join(root, 'Configuration/ProgressaNative.xcconfig')
abort "Missing native configuration: #{native_config}" unless File.exist?(native_config)
anon_key = File.read(native_config)[/^SUPABASE_ANON_KEY\s*=\s*(\S+)\s*$/, 1].to_s
abort 'SUPABASE_ANON_KEY is missing or invalid in the native configuration' unless anon_key.match?(/\AeyJ[\w-]+\.[\w-]+\.[\w-]+\z/)

project_path = File.join(root, 'ProgressaNative.xcodeproj')
FileUtils.rm_rf(project_path)
project = Xcodeproj::Project.new(project_path)
app = project.new_target(:application, 'ProgressaNative', :ios, '16.0')
tests = project.new_target(:unit_test_bundle, 'ProgressaNativeTests', :ios, '16.0')
tests.add_dependency(app)

configuration_group = project.main_group.new_group('Configuration', 'Configuration')
configuration_reference = configuration_group.new_file('ProgressaNative.xcconfig')

app_group = project.main_group.new_group('ProgressaNative', 'ProgressaNative')
Dir.glob(File.join(root, 'ProgressaNative/**/*.swift')).sort.each do |file|
  app.source_build_phase.add_file_reference(app_group.new_file(file.delete_prefix("#{root}/ProgressaNative/")))
end
resources_group = app_group.new_group('Resources', 'Resources')
%w[Assets.xcassets PrivacyInfo.xcprivacy].each do |name|
  ref = resources_group.new_file(name)
  app.resources_build_phase.add_file_reference(ref)
end
test_group = project.main_group.new_group('ProgressaNativeTests', 'ProgressaNativeTests')
Dir.glob(File.join(root, 'ProgressaNativeTests/**/*.swift')).sort.each do |file|
  tests.source_build_phase.add_file_reference(test_group.new_file(file.delete_prefix("#{root}/ProgressaNativeTests/")))
end

app.build_configurations.each do |config|
  config.base_configuration_reference = configuration_reference
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.bryandijkh.progressa',
    'INFOPLIST_FILE' => 'ProgressaNative/Resources/Info.plist',
    'CODE_SIGN_ENTITLEMENTS' => 'ProgressaNative/Resources/ProgressaNative.entitlements',
    'CODE_SIGN_STYLE' => 'Automatic', 'DEVELOPMENT_TEAM' => '85RT3VH5D8',
    'SWIFT_VERSION' => '5.9', 'TARGETED_DEVICE_FAMILY' => '1,2',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon'
  )
end
configuration_check = app.new_shell_script_build_phase('Validate native configuration')
configuration_check.always_out_of_date = '1'
configuration_check.shell_script = <<~'SH'
  if [ -z "${SUPABASE_ANON_KEY:-}" ] || [ -z "${PROGRESSA_SUPABASE_URL:-}" ] || [ -z "${PROGRESSA_CONNECT_URL:-}" ]; then
    echo "error: Progressa native backend configuration is missing" >&2
    exit 1
  fi
SH
tests.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.bryandijkh.progressa.native-tests',
    'GENERATE_INFOPLIST_FILE' => 'YES', 'SWIFT_VERSION' => '5.9',
    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/ProgressaNative.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ProgressaNative',
    'BUNDLE_LOADER' => '$(TEST_HOST)', 'CODE_SIGNING_ALLOWED' => 'NO'
  )
end
project.recreate_user_schemes
project.save
Xcodeproj::XCScheme.share_scheme(project_path, 'ProgressaNative')
Xcodeproj::XCScheme.share_scheme(project_path, 'ProgressaNativeTests')
puts project_path
