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
sparkle_disabled="${SPARKLE_DISABLED:-0}"
feed_url="${SPARKLE_FEED_URL:-https://raw.githubusercontent.com/itisrmk/VISH/main/appcast.xml}"
public_key="${SPARKLE_PUBLIC_ED_KEY:-6ir0pzMbfSy/Jo73NC8GlOIRX2Rv5WjN3aZgfh9bmbk=}"
marketing_version="${MARKETING_VERSION:-${version%%-*}}"
build_version="${CURRENT_PROJECT_VERSION:-}"
sparkle_account="${SPARKLE_ACCOUNT:-com.vish.app}"
sparkle_ed_key_file="${SPARKLE_ED_KEY_FILE:-$root/resources/provisioning/sparkle_ed25519_private_key.txt}"

if [[ -z "$build_version" ]]; then
  if [[ "$version" =~ (alpha|beta|rc)\.([0-9]+)$ ]]; then
    build_version="${BASH_REMATCH[2]}"
  else
    build_version="$(git -C "$root" rev-list --count HEAD 2>/dev/null || date +%s)"
  fi
fi

build_settings=(
  MARKETING_VERSION="$marketing_version"
  CURRENT_PROJECT_VERSION="$build_version"
)

if [[ "$sparkle_disabled" != "1" ]]; then
  build_settings+=(
    VISH_SPARKLE_FEED_URL="$feed_url"
    VISH_SPARKLE_PUBLIC_ED_KEY="$public_key"
  )
fi

find_sparkle_tool() {
  local tool="$1"
  local candidate=""
  if [[ -n "${SPARKLE_TOOL_DIR:-}" && -x "$SPARKLE_TOOL_DIR/$tool" ]]; then
    echo "$SPARKLE_TOOL_DIR/$tool"
    return 0
  fi
  candidate="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/$tool" -type f 2>/dev/null | head -n 1 || true)"
  if [[ -n "$candidate" ]]; then
    echo "$candidate"
    return 0
  fi
  return 1
}

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

archive_command+=("${build_settings[@]}")
"${archive_command[@]}"

app="$archive/Products/Applications/vish.app"
hdiutil create -volname "vish $version" -srcfolder "$app" -ov -format UDZO "$dmg" >/dev/null

if [[ -n "${AC_PROFILE:-}" ]]; then
  xcrun notarytool submit "$dmg" --keychain-profile "$AC_PROFILE" --wait
  xcrun stapler staple "$dmg"
fi

if [[ "$sparkle_disabled" != "1" && "${SPARKLE_GENERATE_APPCAST:-1}" != "0" ]]; then
  generate_appcast="${SPARKLE_GENERATE_APPCAST_TOOL:-}"
  if [[ -z "$generate_appcast" ]]; then
    generate_appcast="$(find_sparkle_tool generate_appcast)"
  fi
  if [[ -z "$generate_appcast" ]]; then
    echo "Sparkle generate_appcast not found. Set SPARKLE_GENERATE_APPCAST=0 to skip appcast generation." >&2
    exit 69
  fi

  appcast_dir="${SPARKLE_APPCAST_DIR:-$dist/appcast}"
  appcast_output="${SPARKLE_APPCAST_OUTPUT:-$root/appcast.xml}"
  download_url_prefix="${SPARKLE_DOWNLOAD_URL_PREFIX:-https://github.com/itisrmk/VISH/releases/download/v$version/}"
  mkdir -p "$appcast_dir"
  if [[ -f "$appcast_output" ]]; then
    cp "$appcast_output" "$appcast_dir/appcast.xml"
  fi
  cp "$dmg" "$appcast_dir/"

  for release_notes in "$root/docs/releases/v$version.md" "$root/docs/releases/$version.md"; do
    if [[ -f "$release_notes" ]]; then
      cp "$release_notes" "$appcast_dir/$(basename "$dmg" .dmg).md"
      break
    fi
  done

  appcast_command=(
    "$generate_appcast"
    --embed-release-notes
    --download-url-prefix "$download_url_prefix"
  )
  if [[ -f "$sparkle_ed_key_file" ]]; then
    appcast_command+=(--ed-key-file "$sparkle_ed_key_file")
  else
    appcast_command+=(--account "$sparkle_account")
  fi
  appcast_command+=("$appcast_dir")
  "${appcast_command[@]}"

  if [[ "${SPARKLE_APPCAST_KEEP_ALL:-0}" != "1" && -f "$appcast_dir/appcast.xml" ]]; then
    perl -0pi -e '
      BEGIN { $target = shift @ARGV; }
      s{(\n\s*<item>\s*(?:(?!</item>).)*?<sparkle:version>([^<]+)</sparkle:version>(?:(?!</item>).)*?</item>)}{$2 eq $target ? $1 : ""}gse;
    ' "$build_version" "$appcast_dir/appcast.xml"
  fi

  if [[ -n "$appcast_output" && -f "$appcast_dir/appcast.xml" ]]; then
    cp "$appcast_dir/appcast.xml" "$appcast_output"
  fi
fi

echo "$dmg"
