#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'
require 'fileutils'

root = File.expand_path('..', __dir__)
project_path = File.join(root, 'QuantivitaNative.xcodeproj')
FileUtils.rm_rf(project_path)
project = Xcodeproj::Project.new(project_path)

app = project.new_target(:application, 'QuantivitaNative', :ios, '16.0')
tests = project.new_target(:unit_test_bundle, 'QuantivitaNativeTests', :ios, '16.0')
ui_tests = project.new_target(:ui_test_bundle, 'QuantivitaNativeUITests', :ios, '16.0')
tests.add_dependency(app)
ui_tests.add_dependency(app)

app_group = project.main_group.new_group('QuantivitaNative', 'QuantivitaNative')
Dir.glob(File.join(root, 'QuantivitaNative/**/*.swift')).sort.each do |file|
  ref = app_group.new_file(file.delete_prefix("#{root}/QuantivitaNative/"))
  app.source_build_phase.add_file_reference(ref)
end
resources_group = app_group.new_group('Resources', 'Resources')
%w[Assets.xcassets PrivacyInfo.xcprivacy].each do |name|
  ref = resources_group.new_file(name)
  app.resources_build_phase.add_file_reference(ref)
end

test_group = project.main_group.new_group('QuantivitaNativeTests', 'QuantivitaNativeTests')
Dir.glob(File.join(root, 'QuantivitaNativeTests/**/*.swift')).sort.each do |file|
  ref = test_group.new_file(file.delete_prefix("#{root}/QuantivitaNativeTests/"))
  tests.source_build_phase.add_file_reference(ref)
end
ui_test_group = project.main_group.new_group('QuantivitaNativeUITests', 'QuantivitaNativeUITests')
Dir.glob(File.join(root, 'QuantivitaNativeUITests/**/*.swift')).sort.each do |file|
  ref = ui_test_group.new_file(file.delete_prefix("#{root}/QuantivitaNativeUITests/"))
  ui_tests.source_build_phase.add_file_reference(ref)
end

app.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.bryandijkh.quantivita',
    'INFOPLIST_FILE' => 'QuantivitaNative/Resources/Info.plist',
    'CODE_SIGN_ENTITLEMENTS' => 'QuantivitaNative/Resources/QuantivitaNative.entitlements',
    'CODE_SIGN_STYLE' => 'Automatic',
    'DEVELOPMENT_TEAM' => '85RT3VH5D8',
    'SWIFT_VERSION' => '5.9',
    'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
    'TARGETED_DEVICE_FAMILY' => '1,2'
  )
end
tests.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.bryandijkh.quantivita.native-tests',
    'GENERATE_INFOPLIST_FILE' => 'YES',
    'SWIFT_VERSION' => '5.9',
    'TEST_HOST' => '$(BUILT_PRODUCTS_DIR)/QuantivitaNative.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/QuantivitaNative',
    'BUNDLE_LOADER' => '$(TEST_HOST)',
    'CODE_SIGNING_ALLOWED' => 'NO'
  )
end
ui_tests.build_configurations.each do |config|
  config.build_settings.merge!(
    'PRODUCT_BUNDLE_IDENTIFIER' => 'com.bryandijkh.quantivita.native-ui-tests',
    'GENERATE_INFOPLIST_FILE' => 'YES', 'SWIFT_VERSION' => '5.9',
    'TEST_TARGET_NAME' => 'QuantivitaNative', 'CODE_SIGNING_ALLOWED' => 'NO'
  )
end

project.recreate_user_schemes
project.save
Xcodeproj::XCScheme.share_scheme(project_path, 'QuantivitaNative')
Xcodeproj::XCScheme.share_scheme(project_path, 'QuantivitaNativeTests')
Xcodeproj::XCScheme.share_scheme(project_path, 'QuantivitaNativeUITests')
puts project_path
