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
codingpad_dir = 'CodingPad'
bridging_header = 'CodingPad/CodingPad-Bridging-Header.h'

abort "Xcode project not found at #{project_path}" unless File.exist?(project_path)
abort "CodingPad directory not found" unless File.directory?(codingpad_dir)

project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == target_name }
abort "Target '#{target_name}' not found. Available: #{project.targets.map(&:name).join(', ')}" unless target

puts "==> Target: #{target.name}"

# Find or create the CodingPad group at project root
codingpad_group = project.main_group['CodingPad'] || project.main_group.new_group('CodingPad', 'CodingPad')

# Helper: find or create nested groups from a relative directory path
def find_or_create_group(parent, rel_dir)
  parts = rel_dir.split('/')
  current = parent
  parts.each do |part|
    existing = current[part]
    if existing.is_a?(Xcodeproj::Project::Object::PBXGroup)
      current = existing
    else
      current = current.new_group(part, part)
    end
  end
  current
end

# Collect all .swift files and the bridging header
swift_files = Dir.glob("#{codingpad_dir}/**/*.swift").sort
header_file = bridging_header

puts "==> Found #{swift_files.length} Swift files"

added_count = 0

swift_files.each do |file_path|
  # relative path within CodingPad/ e.g. "Core/LLM/SSEParser.swift"
  rel = file_path.sub("#{codingpad_dir}/", '')
  dir = File.dirname(rel)
  filename = File.basename(rel)

  # Find or create the appropriate group
  group = dir == '.' ? codingpad_group : find_or_create_group(codingpad_group, dir)

  # Check if file reference already exists in this group
  existing = group.files.find { |f| f.display_name == filename }
  if existing
    puts "   skip: #{rel}"
    next
  end

  # Create file reference
  file_ref = group.new_reference(file_path)
  file_ref.last_known_file_type = 'sourcecode.swift'
  file_ref.source_tree = 'SOURCE_ROOT'

  # Add to target's compile sources
  target.source_build_phase.add_file_reference(file_ref)
  added_count += 1
  puts "   add: #{rel}"
end

# Add bridging header reference (not to compile sources, just to project)
if File.exist?(header_file)
  bh_group = codingpad_group
  unless bh_group.files.find { |f| f.display_name == File.basename(header_file) }
    bh_ref = bh_group.new_reference(header_file)
    bh_ref.last_known_file_type = 'sourcecode.c.h'
    bh_ref.source_tree = 'SOURCE_ROOT'
    puts "==> Added bridging header reference"
  end
end

# Add ISHShellExecutor.m and .h to the target (they exist in app/ but aren't in pbxproj)
app_group = project.main_group['app'] || project.main_group.new_group('app', 'app')

ish_objc_files = [
  { path: 'app/ISHShellExecutor.m', type: 'sourcecode.c.objc', compile: true },
  { path: 'app/ISHShellExecutor.h', type: 'sourcecode.c.h', compile: false },
]

ish_objc_files.each do |info|
  next unless File.exist?(info[:path])
  filename = File.basename(info[:path])
  existing = app_group.files.find { |f| f.display_name == filename }
  unless existing
    ref = app_group.new_reference(info[:path])
    ref.last_known_file_type = info[:type]
    ref.source_tree = 'SOURCE_ROOT'
    if info[:compile]
      target.source_build_phase.add_file_reference(ref)
      puts "   add (objc): #{info[:path]}"
    else
      puts "   add (header): #{info[:path]}"
    end
  end
end

# Configure bridging header and Swift version in build settings
target.build_configurations.each do |config|
  config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = bridging_header
  config.build_settings['SWIFT_VERSION'] ||= '5.0'
  config.build_settings['CLANG_ENABLE_MODULES'] = 'YES'
  # CodingPad requires iOS 17 for @Observable, SwiftUI features
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  # Ensure the target can find iSH's headers
  paths = config.build_settings['HEADER_SEARCH_PATHS'] || ['$(inherited)']
  paths = [paths] if paths.is_a?(String)
  paths << '$(SRCROOT)/app' unless paths.include?('$(SRCROOT)/app')
  config.build_settings['HEADER_SEARCH_PATHS'] = paths
end
puts "==> Configured SWIFT_OBJC_BRIDGING_HEADER = #{bridging_header}"

project.save
puts ""
puts "==> SUCCESS: Added #{added_count} Swift files to '#{target_name}'"
