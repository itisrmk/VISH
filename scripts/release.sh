#!/usr/bin/env bash
set -euo pipefail

version="${1:-}"
if [[ -z "$version" ]]; then
  echo "usage: scripts/release.sh <version>" >&2
  exit 64
fi

root="$(cd "$(dirname "$0")/.." && pwd)"
dist="$root/dist"
archive="$dist/vish-$version.xcarchive"
dmg="$dist/vish-$version.dmg"
scheme="${SCHEME:-vish}"
identity="${DEVELOPER_ID_APPLICATION:-${CODE_SIGN_IDENTITY:--}}"
feed_url="${SPARKLE_FEED_URL:-}"
public_key="${SPARKLE_PUBLIC_ED_KEY:-}"
build_settings=()

if [[ -n "$feed_url" ]]; then
  build_settings+=(VISH_SPARKLE_FEED_URL="$feed_url")
fi

if [[ -n "$public_key" ]]; then
  build_settings+=(VISH_SPARKLE_PUBLIC_ED_KEY="$public_key")
fi

mkdir -p "$dist"
rm -rf "$archive" "$dmg"

archive_command=(
  xcodebuild archive
  -scheme "$scheme"
  -configuration Release
  -destination "generic/platform=macOS"
  -archivePath "$archive"
  CODE_SIGN_STYLE=Manual
  CODE_SIGN_IDENTITY="$identity"
  SKIP_INSTALL=NO
)

if ((${#build_settings[@]})); then
  archive_command+=("${build_settings[@]}")
fi
"${archive_command[@]}"

app="$archive/Products/Applications/vish.app"
hdiutil create -volname "vish $version" -srcfolder "$app" -ov -format UDZO "$dmg" >/dev/null

if [[ -n "${AC_PROFILE:-}" ]]; then
  xcrun notarytool submit "$dmg" --keychain-profile "$AC_PROFILE" --wait
  xcrun stapler staple "$dmg"
fi

if [[ -n "${SPARKLE_GENERATE_APPCAST:-}" ]]; then
  appcast_dir="$dist/appcast"
  mkdir -p "$appcast_dir"
  cp "$dmg" "$appcast_dir/"
  "$SPARKLE_GENERATE_APPCAST" "$appcast_dir"
fi

echo "$dmg"
