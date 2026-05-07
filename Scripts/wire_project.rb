#!/usr/bin/env ruby
# Wires EverywhereCore.xcframework + the Runestone SwiftPM package
# into Everywhere.xcodeproj. Idempotent — running it twice is safe.

require 'xcodeproj'

PROJECT_PATH = '/Volumes/Work/Everywhere/Everywhere.xcodeproj'
XCFW_REL_PATH = 'Frameworks/EverywhereCore.xcframework'
YACD_REL_PATH = 'ThirdParty/yacd-gh-pages'
DEPLOYMENT_TARGET = '15.0'
RUNESTONE_URL = 'https://github.com/simonbs/Runestone'
RUNESTONE_MIN = '0.5.0'
YAML_URL = 'https://github.com/Argsment/YAML'
TS_LANG_URL   = 'https://github.com/simonbs/TreeSitterLanguages'
TS_LANG_MIN   = '0.1.10'
TS_LANG_PRODUCTS = %w[TreeSitterJSONRunestone TreeSitterYAMLRunestone]

# SwiftPM requirements per package
RUNESTONE_REQ = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => RUNESTONE_MIN }
YAML_REQ      = { 'kind' => 'branch', 'branch' => 'main' }
TS_LANG_REQ   = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => TS_LANG_MIN }

project = Xcodeproj::Project.open(PROJECT_PATH)

app_target = project.targets.find { |t| t.name == 'Everywhere' } or abort 'Everywhere target missing'
ne_target  = project.targets.find { |t| t.name == 'EverywhereNE' } or abort 'EverywhereNE target missing'

# --- XCFramework reference -------------------------------------------------
frameworks_group = project.frameworks_group
xcfw_ref = frameworks_group.files.find { |f| f.path == XCFW_REL_PATH }
unless xcfw_ref
  xcfw_ref = frameworks_group.new_file(XCFW_REL_PATH)
  xcfw_ref.source_tree = 'SOURCE_ROOT'
end

# --- Link XCFramework into both targets -----------------------------------
def link_once(target, ref)
  phase = target.frameworks_build_phase
  return if phase.files.any? { |bf| bf.file_ref == ref }
  phase.add_file_reference(ref)
end

link_once(app_target, xcfw_ref)
link_once(ne_target, xcfw_ref)

# --- libresolv.tbd (Go runtime's DNS resolver needs it) -------------------
def link_system_lib(target, project, name, sdk_path)
  return if target.frameworks_build_phase.files.any? do |bf|
    bf.file_ref&.path == sdk_path
  end
  ref = project.frameworks_group.files.find { |f| f.path == sdk_path }
  unless ref
    ref = project.frameworks_group.new_file(sdk_path)
    ref.source_tree = 'SDKROOT'
    ref.name = name
    ref.last_known_file_type = 'sourcecode.text-based-dylib-definition'
  end
  target.frameworks_build_phase.add_file_reference(ref)
end

link_system_lib(ne_target,  project, 'libresolv.tbd', 'usr/lib/libresolv.tbd')
link_system_lib(app_target, project, 'libresolv.tbd', 'usr/lib/libresolv.tbd')

# --- Embed XCFramework in app target only ---------------------------------
embed_phase = app_target.copy_files_build_phases.find do |p|
  p.symbol_dst_subfolder_spec == :frameworks
end
unless embed_phase
  embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed_phase.name = 'Embed Frameworks'
  embed_phase.symbol_dst_subfolder_spec = :frameworks
  app_target.build_phases << embed_phase
end
unless embed_phase.files.any? { |bf| bf.file_ref == xcfw_ref }
  bf = embed_phase.add_file_reference(xcfw_ref)
  bf.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }
end

# --- IPHONEOS_DEPLOYMENT_TARGET (project + every target) -----------------
project.build_configurations.each do |config|
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
end
[app_target, ne_target].each do |target|
  target.build_configurations.each do |config|
    # Only override if a target-level value already exists; otherwise
    # let the project-level setting flow through.
    if config.build_settings.key?('IPHONEOS_DEPLOYMENT_TARGET')
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT_TARGET
    end
  end
end

# --- FRAMEWORK_SEARCH_PATHS for both targets ------------------------------
search_path = '$(PROJECT_DIR)/Frameworks'
[app_target, ne_target].each do |target|
  target.build_configurations.each do |config|
    raw = config.build_settings['FRAMEWORK_SEARCH_PATHS']
    paths = case raw
            when nil then ['$(inherited)']
            when Array then raw.dup
            else [raw]
            end
    unless paths.include?(search_path)
      paths << search_path
      config.build_settings['FRAMEWORK_SEARCH_PATHS'] = paths
    end
  end
end

# --- Runestone Swift Package ---------------------------------------------
def ensure_swift_package(project, url, requirement)
  pkg = project.root_object.package_references.find do |p|
    p.respond_to?(:repositoryURL) && p.repositoryURL == url
  end
  return pkg if pkg
  pkg = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  pkg.repositoryURL = url
  pkg.requirement = requirement
  project.root_object.package_references << pkg
  pkg
end

def ensure_product_dep(target, project, package, product_name)
  dep = target.package_product_dependencies.find do |d|
    d.product_name == product_name && d.package == package
  end
  unless dep
    dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
    dep.package = package
    dep.product_name = product_name
    target.package_product_dependencies << dep
  end
  phase = target.frameworks_build_phase
  unless phase.files.any? { |bf| bf.product_ref == dep }
    bf = project.new(Xcodeproj::Project::Object::PBXBuildFile)
    bf.product_ref = dep
    phase.files << bf
  end
  dep
end

runestone_pkg = ensure_swift_package(project, RUNESTONE_URL, RUNESTONE_REQ)
ensure_product_dep(app_target, project, runestone_pkg, 'Runestone')

ts_lang_pkg = ensure_swift_package(project, TS_LANG_URL, TS_LANG_REQ)
TS_LANG_PRODUCTS.each do |product|
  ensure_product_dep(app_target, project, ts_lang_pkg, product)
end

# YAML has no tagged release; pin to its main branch.
yaml_pkg = ensure_swift_package(project, YAML_URL, YAML_REQ)
ensure_product_dep(app_target, project, yaml_pkg, 'YAML')

# --- yacd-gh-pages folder reference (bundled into the app target) --------
# `lastKnownFileType = folder` is the magic that makes Xcode treat this
# as a "blue folder" — it copies the whole tree into the .app preserving
# relative paths, which yacd's index.html requires (./assets/index-*.js).

# Drop any stale yacd-gh-pages reference whose path differs from the
# current canonical one, so re-pointing the script is self-healing.
project.files.select { |f|
  next false unless f.path
  f.path.end_with?('yacd-gh-pages') && f.path != YACD_REL_PATH
}.each do |stale|
  project.targets.each do |t|
    t.resources_build_phase.files.select { |bf| bf.file_ref == stale }.each do |bf|
      t.resources_build_phase.files.delete(bf)
    end
  end
  stale.remove_from_project
end

yacd_ref = project.main_group.files.find { |f| f.path == YACD_REL_PATH }
unless yacd_ref
  yacd_ref = project.new(Xcodeproj::Project::Object::PBXFileReference)
  yacd_ref.path = YACD_REL_PATH
  yacd_ref.name = 'yacd-gh-pages'
  yacd_ref.source_tree = 'SOURCE_ROOT'
  yacd_ref.last_known_file_type = 'folder'
  project.main_group << yacd_ref
end
unless app_target.resources_build_phase.files.any? { |bf| bf.file_ref == yacd_ref }
  app_target.resources_build_phase.add_file_reference(yacd_ref)
end

project.save
puts "Wired #{XCFW_REL_PATH} + Runestone + YAML + yacd-gh-pages into #{PROJECT_PATH}"
