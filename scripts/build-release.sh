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
rw_dmg_path="${build_dir}/SimplePodcastManager-rw.dmg"
mount_dir="${build_dir}/dmg-mount"
background_dir="${dmg_root}/.background"
background_path="${background_dir}/installer-background.png"
background_generator="${build_dir}/generate-dmg-background.swift"

rm -rf "$build_dir" "$dmg_path"
mkdir -p "$macos_dir" "$resources_dir" "$dmg_root" "$dist_dir" "$background_dir"

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

cat > "$background_generator" <<'SWIFT'
import AppKit
import Foundation

let outputPath = CommandLine.arguments[1]
let imageSize = NSSize(width: 620, height: 360)
let image = NSImage(size: imageSize)

image.lockFocus()

let bounds = NSRect(origin: .zero, size: imageSize)
let backgroundGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.950, green: 0.955, blue: 0.965, alpha: 1),
    NSColor(calibratedRed: 0.870, green: 0.885, blue: 0.905, alpha: 1)
])!
backgroundGradient.draw(in: bounds, angle: 90)

let vignette = NSBezierPath(rect: bounds)
NSColor(calibratedWhite: 1, alpha: 0.18).setFill()
vignette.fill()

let arrowColor = NSColor(calibratedWhite: 0.36, alpha: 0.55)
arrowColor.setStroke()

let arrow = NSBezierPath()
arrow.lineWidth = 3.5
arrow.lineCapStyle = .round
arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 255, y: 178))
arrow.curve(
    to: NSPoint(x: 365, y: 178),
    controlPoint1: NSPoint(x: 292, y: 197),
    controlPoint2: NSPoint(x: 328, y: 197)
)
arrow.stroke()

let arrowHead = NSBezierPath()
arrowHead.lineWidth = 3.5
arrowHead.lineCapStyle = .round
arrowHead.lineJoinStyle = .round
arrowHead.move(to: NSPoint(x: 348, y: 195))
arrowHead.line(to: NSPoint(x: 367, y: 178))
arrowHead.line(to: NSPoint(x: 348, y: 161))
arrowHead.stroke()

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    throw CocoaError(.fileWriteUnknown)
}

try pngData.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
SWIFT

swift "$background_generator" "$background_path"

hdiutil create -volname "$app_name" -srcfolder "$dmg_root" -ov -format UDRW "$rw_dmg_path"
mkdir -p "$mount_dir"
hdiutil attach "$rw_dmg_path" -mountpoint "$mount_dir" -nobrowse -quiet

cleanup_mount() {
  if [[ -d "$mount_dir" ]]; then
    hdiutil detach "$mount_dir" -quiet || true
  fi
}
trap cleanup_mount EXIT

osascript <<APPLESCRIPT
tell application "Finder"
  set dmgFolder to POSIX file "$mount_dir" as alias
  set backgroundImage to POSIX file "$mount_dir/.background/installer-background.png" as alias
  open dmgFolder
  set current view of container window of dmgFolder to icon view
  set toolbar visible of container window of dmgFolder to false
  set statusbar visible of container window of dmgFolder to false
  set the bounds of container window of dmgFolder to {120, 120, 740, 480}
  set viewOptions to the icon view options of container window of dmgFolder
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 96
  set background picture of viewOptions to backgroundImage
  set position of item "$app_name.app" of dmgFolder to {170, 185}
  set position of item "Applications" of dmgFolder to {450, 185}
  update dmgFolder without registering applications
  delay 1
  close container window of dmgFolder
end tell
APPLESCRIPT

sync
hdiutil detach "$mount_dir" -quiet
trap - EXIT
hdiutil convert "$rw_dmg_path" -format UDZO -o "$dmg_path" -ov

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$dmg_path"
fi

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$dmg_path" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$dmg_path"
fi

echo "$dmg_path"
