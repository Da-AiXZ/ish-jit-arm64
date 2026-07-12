#!/usr/bin/env ruby
# inject_codingpad.rb
#
# Injects all CodingPad/*.swift files into the iSH-ARM64 Xcode target,
# and configures the Swift bridging header.
#
# Run in CI before xcodebuild. Requires the 'xcodeproj' gem.

require 'xcodeproj'
require 'pathname'

project_path = 'iSH.xcodeproj'
target_name = 'iSH-ARM64'
codingpad_dir = File.expand_path('CodingPad')
bridging_header = 'CodingPad/CodingPad-Bridging-Header.h'

abort "Xcode project not found at #{project_path}" unless File.exist?(project_path)
abort "CodingPad directory not found at #{codingpad_dir}" unless File.directory?(codingpad_dir)

project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == target_name }
abort "Target '#{target_name}' not found. Available: #{project.targets.map(&:name).join(', ')}" unless target

puts "==> Target found: #{target.name}"
puts "==> CodingPad directory: #{codingpad_dir}"

# Create or find a CodingPad group in the project
codingpad_group = project.main_group.find_subpath('CodingPad', true)
codingpad_group.set_source_tree('<group>')
codingpad_group.set_path('CodingPad') unless codingpad_group.real_path

# Recursively add all .swift files
swift_files = Dir.glob(File.join(codingpad_dir, '**', '*.swift')).sort
puts "==> Found #{swift_files.length} Swift files to add"

added_count = 0
swift_files.each do |abs_path|
  rel_path = abs_path.sub("#{codingpad_dir}/", '')

  # Skip if already referenced in the target
  existing = target.source_build_phase.files_references.find do |f|
    f.real_path && f.real_path.to_s.end_with?(rel_path)
  end
  if existing
    puts "   skip (already added): #{rel_path}"
    next
  end

  # Create file reference in the appropriate subgroup
  file_ref = codingpad_group.find_subpath(rel_path, true)
  file_ref.last_known_file_type = 'sourcecode.swift'

  target.add_file_references([file_ref])
  added_count += 1
  puts "   added: #{rel_path}"
end

# Add the bridging header file reference
unless project.files.find { |f| f.path == bridging_header }
  bh_ref = codingpad_group.new_reference('CodingPad-Bridging-Header.h')
  bh_ref.last_known_file_type = 'sourcecode.c.h'
  puts "==> Added bridging header reference"
end

# Configure Swift bridging header in all build configurations
target.build_configurations.each do |config|
  config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = bridging_header
  # Allow Swift and Obj-C interop
  config.build_settings['SWIFT_OBJC_INTERFACE_HEADER_NAME'] = 'CodingPad-Swift.h'
  # Enable Swift in the target
  config.build_settings['SWIFT_VERSION'] = '5.0' unless config.build_settings['SWIFT_VERSION']
end
puts "==> Configured bridging header: #{bridging_header}"

# Also enable 'Always Search User Paths' to find our headers
target.build_configurations.each do |config|
  config.build_settings['USER_HEADER_SEARCH_PATHS'] ||= []
  config.build_settings['USER_HEADER_SEARCH_PATHS'] << '$(SRCROOT)/CodingPad'
end

project.save
puts ""
puts "==> SUCCESS: Added #{added_count} Swift files to target '#{target_name}'"
puts "==> Project saved."
