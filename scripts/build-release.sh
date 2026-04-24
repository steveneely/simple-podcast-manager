#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h}

app_name="Simple Podcast Manager"
bundle_id="com.steveneely.simple-podcast-manager"
dist_dir="${repo_root}/dist"
build_dir="${dist_dir}/build"
app_path="${build_dir}/${app_name}.app"
contents_dir="${app_path}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"
dmg_root="${build_dir}/dmg-root"
dmg_path="${dist_dir}/SimplePodcastManager.dmg"

rm -rf "$build_dir" "$dmg_path"
mkdir -p "$macos_dir" "$resources_dir" "$dmg_root" "$dist_dir"

cd "$repo_root"
swift build -c release --product "$app_name"

cp "${repo_root}/.build/release/${app_name}" "${macos_dir}/${app_name}"
cp "${repo_root}/Packaging/Info.plist" "${contents_dir}/Info.plist"
cp "${repo_root}/THIRD_PARTY_NOTICES.md" "${resources_dir}/THIRD_PARTY_NOTICES.md"
chmod 755 "${macos_dir}/${app_name}"

if [[ -f "${repo_root}/Packaging/AppIcon.icns" ]]; then
  cp "${repo_root}/Packaging/AppIcon.icns" "${resources_dir}/AppIcon.icns"
fi

if [[ -n "${FFMPEG_PATH:-}" ]]; then
  if [[ ! -x "$FFMPEG_PATH" ]]; then
    echo "FFMPEG_PATH must point to an executable ffmpeg binary: $FFMPEG_PATH" >&2
    exit 1
  fi

  if [[ -z "${FFMPEG_SOURCE_URL:-}" ]]; then
    echo "Set FFMPEG_SOURCE_URL to the exact source or build recipe URL for the bundled ffmpeg binary." >&2
    exit 1
  fi

  cp "$FFMPEG_PATH" "${resources_dir}/ffmpeg"
  chmod 755 "${resources_dir}/ffmpeg"
  printf '%s\n' "$FFMPEG_SOURCE_URL" > "${resources_dir}/FFMPEG_SOURCE.txt"

  if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "${resources_dir}/ffmpeg"
  else
    codesign --force --sign - "${resources_dir}/ffmpeg"
  fi
fi

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$app_path"
else
  codesign --force --sign - "$app_path"
fi

cp -R "$app_path" "$dmg_root/"
ln -s /Applications "${dmg_root}/Applications"
hdiutil create -volname "$app_name" -srcfolder "$dmg_root" -ov -format UDZO "$dmg_path"

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$dmg_path"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$dmg_path"
fi

echo "$dmg_path"
