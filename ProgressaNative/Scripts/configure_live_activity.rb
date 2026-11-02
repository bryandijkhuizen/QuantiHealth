# frozen_string_literal: true

def configure_live_activity(project, app)
  extension = project.targets.find { |target| target.name == 'ProgressaLiveActivity' } ||
    project.new_target(:app_extension, 'ProgressaLiveActivity', :ios, '16.2')
  shared = project.main_group.find_subpath('Shared', true)
  shared.path = 'Shared'
  attributes = shared.files.find { |file| file.path == 'WorkoutActivityAttributes.swift' } || shared.new_file('WorkoutActivityAttributes.swift')
  [app, extension].each do |target|
    target.source_build_phase.add_file_reference(attributes, true)
  end
  group = project.main_group.find_subpath('ProgressaLiveActivity', true)
  group.path = 'ProgressaLiveActivity'
  source = group.files.find { |file| file.path == 'ProgressaLiveActivity.swift' } || group.new_file('ProgressaLiveActivity.swift')
  extension.source_build_phase.add_file_reference(source, true)
  extension.build_configurations.each do |config|
    config.build_settings.merge!(
      'PRODUCT_BUNDLE_IDENTIFIER' => 'com.bryandijkh.progressa.liveactivity',
      'INFOPLIST_FILE' => 'ProgressaLiveActivity/Info.plist',
      'SWIFT_VERSION' => '5.9', 'TARGETED_DEVICE_FAMILY' => '1,2',
      'CODE_SIGN_STYLE' => 'Automatic', 'DEVELOPMENT_TEAM' => '85RT3VH5D8',
      'APPLICATION_EXTENSION_API_ONLY' => 'YES', 'SKIP_INSTALL' => 'YES'
    )
  end
  app.add_dependency(extension) unless app.dependencies.any? { |dependency| dependency.target == extension }
  embed = app.copy_files_build_phases.find { |phase| phase.name == 'Embed App Extensions' } || app.new_copy_files_build_phase('Embed App Extensions')
  embed.dst_subfolder_spec = '13'
  embed.add_file_reference(extension.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
end
