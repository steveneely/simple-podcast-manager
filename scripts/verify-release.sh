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
short_version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$info_plist")
feed_url=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$info_plist")
public_key=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$info_plist")
allows_automatic_updates=$(/usr/libexec/PlistBuddy -c "Print :SUAllowsAutomaticUpdates" "$info_plist")
update_dmg_path="${repo_root}/dist/updates/SimplePodcastManager-${release_tag}.dmg"

if [[ ! "$bundle_version" =~ '^[0-9]+$' ]]; then
  echo "CFBundleVersion must be an incrementing integer for Sparkle: $bundle_version" >&2
  exit 1
fi

if [[ -z "$release_tag" || "$release_tag" != v* ]]; then
    echo "SPMReleaseTag must be set to a release tag like v0.1.0-beta.27." >&2
    exit 1
fi

if [[ -z "$short_version" || "$release_tag" != v${short_version}* ]]; then
  echo "SPMReleaseTag (${release_tag}) must start with v<CFBundleShortVersionString> (${short_version}) so Sparkle shows the intended user-visible version." >&2
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

if [[ "$allows_automatic_updates" != false ]]; then
  echo "SUAllowsAutomaticUpdates must be false so updates cannot silently install and relaunch the app." >&2
  exit 1
fi

if [[ ! -d "${app_path}/Contents/Frameworks/Sparkle.framework" ]]; then
  echo "Sparkle.framework is missing from the app bundle." >&2
  exit 1
fi

if [[ ! -f "$update_dmg_path" ]]; then
  echo "Missing Sparkle update DMG for ${release_tag}: ${update_dmg_path}" >&2
  exit 1
fi

if ! otool -l "${app_path}/Contents/MacOS/${app_name}" | grep -q "@executable_path/../Frameworks"; then
  echo "App executable is missing @executable_path/../Frameworks rpath for bundled frameworks." >&2
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

if grep -q "Build ${bundle_version}\\." "$appcast_path"; then
  echo "Appcast release notes are too generic. Describe the user-visible update details for Sparkle." >&2
  exit 1
fi

if ! grep -q "$release_tag" "$appcast_path"; then
  echo "Appcast release notes should mention ${release_tag}." >&2
  exit 1
fi

if ! /usr/bin/python3 - "$appcast_path" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET

appcast_path = sys.argv[1]
root = ET.parse(appcast_path).getroot()
for enclosure in root.findall(".//enclosure"):
    url = enclosure.attrib.get("url", "")
    match = re.search(r"/releases/download/(v[^/]+)/SimplePodcastManager-(v[^/]+)\.dmg$", url)
    if not match:
        print(f"Appcast enclosure URL has unexpected format: {url}", file=sys.stderr)
        sys.exit(1)
    release_tag, file_tag = match.groups()
    if release_tag != file_tag:
        print(f"Appcast enclosure URL release tag {release_tag} does not match DMG tag {file_tag}.", file=sys.stderr)
        sys.exit(1)
PY
then
  exit 1
fi

if ! /usr/bin/python3 - "$appcast_path" "$bundle_version" "$short_version" <<'PY'
import sys
import xml.etree.ElementTree as ET

appcast_path, bundle_version, short_version = sys.argv[1:4]
current_version = int(bundle_version)
root = ET.parse(appcast_path).getroot()
namespace = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}

for item in root.findall(".//item"):
    item_version_text = item.findtext("sparkle:version", namespaces=namespace)
    item_short_version = item.findtext("sparkle:shortVersionString", namespaces=namespace)
    if item_version_text is None or item_short_version is None:
        continue
    item_version = int(item_version_text)
    if item_version < current_version and item_short_version == short_version:
        print(
            f"CFBundleShortVersionString ({short_version}) matches older appcast build {item_version}. "
            "Choose a new user-visible semver version for this release.",
            file=sys.stderr,
        )
        sys.exit(1)
PY
then
  exit 1
fi

codesign --verify --deep --strict "$app_path"

echo "Release verification passed for ${release_tag} build ${bundle_version}."
