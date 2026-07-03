#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}

app_name="Simple Podcast Manager"
app_path="${repo_root}/dist/build/${app_name}.app"
info_plist="${app_path}/Contents/Info.plist"
dmg_path="${repo_root}/dist/SimplePodcastManager.dmg"
appcast_path="${repo_root}/dist/updates/appcast.xml"

if [[ ! -d "$app_path" ]]; then
  echo "Missing built app: $app_path" >&2
  exit 1
fi

if [[ ! -f "$dmg_path" ]]; then
  echo "Missing DMG: $dmg_path" >&2
  exit 1
fi

if [[ ! -f "$appcast_path" ]]; then
  echo "Missing Sparkle appcast: $appcast_path" >&2
  exit 1
fi

/usr/bin/plutil -lint "$info_plist" >/dev/null
/usr/bin/xmllint --noout "$appcast_path"

bundle_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$info_plist")
release_tag=$(/usr/libexec/PlistBuddy -c "Print :SPMReleaseTag" "$info_plist")
feed_url=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$info_plist")
public_key=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$info_plist")

if [[ ! "$bundle_version" =~ '^[0-9]+$' ]]; then
  echo "CFBundleVersion must be an incrementing integer for Sparkle: $bundle_version" >&2
  exit 1
fi

if [[ -z "$release_tag" || "$release_tag" != v* ]]; then
  echo "SPMReleaseTag must be set to a release tag like v0.1.0-beta.27." >&2
  exit 1
fi

if [[ "$feed_url" != https://* ]]; then
  echo "SUFeedURL must be an HTTPS URL." >&2
  exit 1
fi

if [[ -z "$public_key" ]]; then
  echo "SUPublicEDKey must be set." >&2
  exit 1
fi

if [[ ! -d "${app_path}/Contents/Frameworks/Sparkle.framework" ]]; then
  echo "Sparkle.framework is missing from the app bundle." >&2
  exit 1
fi

if ! grep -q "<sparkle:version>${bundle_version}</sparkle:version>" "$appcast_path"; then
  echo "Appcast does not contain bundle version $bundle_version." >&2
  exit 1
fi

if ! grep -q "/releases/download/${release_tag}/" "$appcast_path"; then
  echo "Appcast enclosure URL does not include release tag ${release_tag}." >&2
  exit 1
fi

if ! grep -q 'sparkle:edSignature=' "$appcast_path"; then
  echo "Appcast does not include Sparkle EdDSA signatures." >&2
  exit 1
fi

codesign --verify --deep --strict "$app_path"

echo "Release verification passed for ${release_tag} build ${bundle_version}."
