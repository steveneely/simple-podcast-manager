#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}
product_name="Simple Podcast Manager"
app_name="Simple Podcast Manager Dev"
app_path="${repo_root}/dist/dev/${app_name}.app"
contents_dir="${app_path}/Contents"
repo_hash=$(printf '%s' "$repo_root" | shasum | awk '{print substr($1, 1, 12)}')

cd "$repo_root"
# The native engine records the selected SDK correctly with the current toolchain.
# The default Swift Build engine currently records the deployment target as the SDK.
swift build --build-system native -c release --product "$product_name"
bin_dir=$(swift build --build-system native -c release --show-bin-path)

mkdir -p "${contents_dir}/MacOS" "${contents_dir}/Resources" "${contents_dir}/Frameworks"
cp "${bin_dir}/${product_name}" "${contents_dir}/MacOS/${product_name}"
cp Packaging/Info.plist "${contents_dir}/Info.plist"
/usr/bin/plutil -replace CFBundleIdentifier -string "com.steveneely.simple-podcast-manager.dev.${repo_hash}" "${contents_dir}/Info.plist"
/usr/bin/plutil -replace CFBundleName -string "$app_name" "${contents_dir}/Info.plist"
/usr/bin/plutil -replace CFBundleDisplayName -string "$app_name" "${contents_dir}/Info.plist"
/usr/bin/plutil -insert SPMDevelopmentBuild -bool true "${contents_dir}/Info.plist"
/usr/bin/plutil -insert SUEnableAutomaticChecks -bool false "${contents_dir}/Info.plist"
/usr/bin/plutil -remove SUFeedURL "${contents_dir}/Info.plist"
/usr/bin/plutil -remove SUPublicEDKey "${contents_dir}/Info.plist"
cp THIRD_PARTY_NOTICES.md "${contents_dir}/Resources/THIRD_PARTY_NOTICES.md"
if [[ -f Packaging/AppIcon.icns ]]; then
    cp Packaging/AppIcon.icns "${contents_dir}/Resources/AppIcon.icns"
fi
sparkle_framework="${repo_root}/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
/usr/bin/ditto "$sparkle_framework" "${contents_dir}/Frameworks/Sparkle.framework"
if ! otool -l "${contents_dir}/MacOS/${product_name}" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "${contents_dir}/MacOS/${product_name}"
fi
codesign --force --sign - "${contents_dir}/Frameworks/Sparkle.framework"
codesign --force --sign - "$app_path"
codesign --verify --deep --strict "$app_path"
print "Development app: ${app_path}"
print "Isolated app data: ${repo_root}/.dev-data/SimplePodcastManager"
