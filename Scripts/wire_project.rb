#!/usr/bin/env ruby
# Wires SwiftPM packages and build settings into Everywhere.xcodeproj. Idempotent.

require 'xcodeproj'

PROJECT_PATH       = File.expand_path('../Everywhere.xcodeproj', __dir__)
DEPLOYMENT_TARGET  = '15.0'
SHARED_FOLDER      = 'Shared'

EVERYWHERE_CORE_REPO        = 'https://github.com/NodePassProject/EverywhereCore'
EVERYWHERE_CORE_MIN_VERSION = '2026.11.15'
EVERYWHERE_CORE_REQ         = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => EVERYWHERE_CORE_MIN_VERSION }
EVERYWHERE_CORE_PRODUCT     = 'EverywhereCore'
EVERYWHERE_CORE_LOCAL_PATH  = ENV['EVERYWHERE_CORE_PATH'].to_s.strip

RUNESTONE_URL = 'https://github.com/simonbs/Runestone'
RUNESTONE_REQ = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => '0.5.0' }
TS_LANG_URL   = 'https://github.com/simonbs/TreeSitterLanguages'
TS_LANG_REQ   = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => '0.1.10' }
TS_LANG_PRODUCTS = %w[TreeSitterJSONRunestone TreeSitterYAMLRunestone]

project = Xcodeproj::Project.open(PROJECT_PATH)

app_target = project.targets.find { |t| t.name == 'Everywhere' } or abort 'Everywhere target missing'
ne_target  = project.targets.find { |t| t.name == 'EverywhereNE' } or abort 'EverywhereNE target missing'

# --- Tear down any prior local-xcframework wiring -------------------------
stale_xcfw = project.files.select { |f| f.path == 'Frameworks/EverywhereCore.xcframework' }
stale_xcfw.each do |ref|
  project.targets.each do |t|
    t.frameworks_build_phase.files.select { |bf| bf.file_ref == ref }.each do |bf|
      t.frameworks_build_phase.files.delete(bf)
    end
    t.copy_files_build_phases.each do |cp|
      cp.files.select { |bf| bf.file_ref == ref }.each do |bf|
        cp.files.delete(bf)
      end
    end
  end
  ref.remove_from_project
end

stale_search_path = '$(PROJECT_DIR)/Frameworks'
[app_target, ne_target].each do |target|
  target.build_configurations.each do |config|
    paths = config.build_settings['FRAMEWORK_SEARCH_PATHS']
    next unless paths.is_a?(Array) && paths.include?(stale_search_path)
    paths.delete(stale_search_path)
    if paths == ['$(inherited)'] || paths.empty?
      config.build_settings.delete('FRAMEWORK_SEARCH_PATHS')
    else
      config.build_settings['FRAMEWORK_SEARCH_PATHS'] = paths
    end
  end
end

# --- SwiftPM helpers ------------------------------------------------------
def ensure_swift_package(project, url, requirement)
  pkg = project.root_object.package_references.find do |p|
    p.respond_to?(:repositoryURL) && p.repositoryURL == url
  end
  unless pkg
    pkg = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
    pkg.repositoryURL = url
    project.root_object.package_references << pkg
  end
  pkg.requirement = requirement
  pkg
end

def add_product_dep(target, project, package_ref, product_name)
  dep = target.package_product_dependencies.find do |d|
    d.product_name == product_name && d.package == package_ref
  end
  unless dep
    dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dep.package = package_ref
    dep.product_name = product_name
    target.package_product_dependencies << dep
  end
  dep
end

def link_product(target, project, dep)
  phase = target.frameworks_build_phase
  return if phase.files.any? { |bf| bf.product_ref == dep }
  bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  bf.product_ref = dep
  phase.files << bf
end

def remove_swift_package(project, url)
  pkg = project.objects.find do |o|
    o.isa == 'XCRemoteSwiftPackageReference' && o.repositoryURL == url
  end
  return unless pkg

  project.objects.select do |o|
    o.isa == 'XCSwiftPackageProductDependency' && o.package == pkg
  end.each do |dep|
    project.targets.each do |target|
      target.frameworks_build_phase.files.select { |bf| bf.product_ref == dep }.each do |bf|
        target.frameworks_build_phase.files.delete(bf)
      end
      target.package_product_dependencies.delete(dep)
    end
    dep.remove_from_project
  end

  project.root_object.package_references.delete(pkg)
  pkg.remove_from_project
end

def ensure_local_swift_package(project, relative_path)
  pkg = project.root_object.package_references.find do |p|
    p.isa == 'XCLocalSwiftPackageReference' && p.relative_path == relative_path
  end
  unless pkg
    pkg = project.new(Xcodeproj::Project::Object::XCLocalSwiftPackageReference)
    pkg.relative_path = relative_path
    project.root_object.package_references << pkg
  end
  pkg
end

def remove_local_swift_packages(project, product_name)
  project.objects.select { |o| o.isa == 'XCLocalSwiftPackageReference' }.each do |pkg|
    deps = project.objects.select do |o|
      o.isa == 'XCSwiftPackageProductDependency' && o.package == pkg
    end
    next unless deps.any? { |d| d.product_name == product_name }
    deps.each do |dep|
      project.targets.each do |target|
        target.frameworks_build_phase.files.select { |bf| bf.product_ref == dep }.each do |bf|
          target.frameworks_build_phase.files.delete(bf)
        end
        target.package_product_dependencies.delete(dep)
      end
      dep.remove_from_project
    end
    project.root_object.package_references.delete(pkg)
    pkg.remove_from_project
  end
end

# --- EverywhereCore (both targets) ---------------------------------------
if EVERYWHERE_CORE_LOCAL_PATH.empty?
  remove_local_swift_packages(project, EVERYWHERE_CORE_PRODUCT)
  core_pkg = ensure_swift_package(project, EVERYWHERE_CORE_REPO, EVERYWHERE_CORE_REQ)
else
  local_xcframework = File.expand_path(
    File.join('..', EVERYWHERE_CORE_LOCAL_PATH, 'EverywhereCore.xcframework'), __dir__
  )
  File.directory?(local_xcframework) or
    abort "#{local_xcframework} is missing — run Scripts/build.sh in the EverywhereCore checkout first"
  remove_swift_package(project, EVERYWHERE_CORE_REPO)
  core_pkg = ensure_local_swift_package(project, EVERYWHERE_CORE_LOCAL_PATH)
end
core_app_dep = add_product_dep(app_target, project, core_pkg, EVERYWHERE_CORE_PRODUCT)
core_ne_dep  = add_product_dep(ne_target,  project, core_pkg, EVERYWHERE_CORE_PRODUCT)
link_product(app_target, project, core_app_dep)
link_product(ne_target,  project, core_ne_dep)

stale_embed = app_target.copy_files_build_phases.find do |p|
  p.symbol_dst_subfolder_spec == :frameworks
end
if stale_embed
  stale_embed.files.select { |bf|
    bf.product_ref&.product_name == EVERYWHERE_CORE_PRODUCT
  }.each { |bf| stale_embed.files.delete(bf) }
  if stale_embed.files.empty?
    app_target.build_phases.delete(stale_embed)
    stale_embed.remove_from_project
  end
end

# --- Runestone + TreeSitterLanguages (app target only) -------------------
runestone_pkg = ensure_swift_package(project, RUNESTONE_URL, RUNESTONE_REQ)
link_product(app_target, project, add_product_dep(app_target, project, runestone_pkg, 'Runestone'))

ts_lang_pkg = ensure_swift_package(project, TS_LANG_URL, TS_LANG_REQ)
TS_LANG_PRODUCTS.each do |product|
  link_product(app_target, project, add_product_dep(app_target, project, ts_lang_pkg, product))
end

remove_swift_package(project, 'https://github.com/Argsment/YAML')

# --- libresolv.tbd (Go runtime's DNS resolver needs it) ------------------
def link_system_lib(target, project, name, sdk_path, file_type = 'sourcecode.text-based-dylib-definition')
  return if target.frameworks_build_phase.files.any? do |bf|
    bf.file_ref&.path == sdk_path
  end
  ref = project.frameworks_group.files.find { |f| f.path == sdk_path }
  unless ref
    ref = project.frameworks_group.new_file(sdk_path)
    ref.source_tree = 'SDKROOT'
    ref.name = name
    ref.last_known_file_type = file_type
  end
  target.frameworks_build_phase.add_file_reference(ref)
end

link_system_lib(ne_target,  project, 'libresolv.tbd', 'usr/lib/libresolv.tbd')
link_system_lib(app_target, project, 'libresolv.tbd', 'usr/lib/libresolv.tbd')

# --- UIKit.framework (sing-box's device_darwin.m calls UIDevice) ---------
link_system_lib(ne_target, project, 'UIKit.framework',
                'System/Library/Frameworks/UIKit.framework', 'wrapper.framework')

# --- IPHONEOS_DEPLOYMENT_TARGET (project + every target) -----------------
project.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
end
[app_target, ne_target].each do |target|
  target.build_configurations.each do |config|
    if config.build_settings.key?('IPHONEOS_DEPLOYMENT_TARGET')
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
    end
  end
end

# --- Retired dashboard bundles -------------------------------------------
project.files.select { |f|
  f.path && %w[zashboard yacd-gh-pages].include?(File.basename(f.path))
}.each do |stale|
  project.targets.each do |t|
    t.resources_build_phase.files.select { |bf| bf.file_ref == stale }.each do |bf|
      t.resources_build_phase.files.delete(bf)
    end
  end
  stale.remove_from_project
end

# --- Shared/ synced root group (both targets compile its sources) --------
shared_group = project.main_group.children.find do |c|
  c.is_a?(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup) && c.path == SHARED_FOLDER
end
unless shared_group
  shared_group = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
  shared_group.path = SHARED_FOLDER
  shared_group.source_tree = '<group>'
  project.main_group << shared_group
end
[app_target, ne_target].each do |target|
  target.file_system_synchronized_groups ||= []
  next if target.file_system_synchronized_groups.include?(shared_group)
  target.file_system_synchronized_groups << shared_group
end

project.save
core_source = EVERYWHERE_CORE_LOCAL_PATH.empty? ? ">= #{EVERYWHERE_CORE_MIN_VERSION}, SwiftPM" : "local, #{EVERYWHERE_CORE_LOCAL_PATH}"
puts "Wired EverywhereCore (#{core_source}) + Runestone into #{PROJECT_PATH}"
