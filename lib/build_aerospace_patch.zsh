#!/usr/bin/env zsh
set -euo pipefail

ROOT="${0:A:h:h}"
UPSTREAM_TAG="v0.21.3-Beta"
UPSTREAM_COMMIT="d56e1637c3a1ed660d0cadd7534e94fb3218d1c3"
PATCH_FILE="$ROOT/patches/aerospace/workspace-transition.patch"

if (( $# > 1 )) || [[ "${1:-}" == --help ]]; then
  printf 'Usage: zsh lib/build_aerospace_patch.zsh [build-parent-directory]\n'
  printf 'Builds and tests a local AeroSpace App and matching CLI; does not install them.\n'
  (( $# <= 1 )) && exit 0
  exit 2
fi

[[ "$(uname -m)" == arm64 ]] || {
  printf 'This build supports Apple Silicon only.\n' >&2
  exit 1
}
[[ -f "$PATCH_FILE" && -x /opt/homebrew/bin/bash ]] || {
  printf 'The patch file and Homebrew Bash 5 are required.\n' >&2
  exit 1
}

build_parent="${1:-$HOME/Library/Caches/dotfiles/aerospace}"
mkdir -p "$build_parent"
build_parent="${build_parent:A}"
build_dir="$(mktemp -d "$build_parent/build.XXXXXX")"
source_dir="$build_dir/source"
artifact_dir="$build_dir/artifacts"
patch_snapshot="$build_dir/workspace-transition.patch"
cp "$PATCH_FILE" "$patch_snapshot"
patch_sha="$(shasum -a 256 "$patch_snapshot")"
patch_sha="${patch_sha%% *}"
build_version="${UPSTREAM_TAG#v}-workspace-fix.${patch_sha[1,12]}"

printf 'Building %s in %s\n' "$build_version" "$build_dir"
git clone --depth=1 --branch "$UPSTREAM_TAG" \
  https://github.com/nikitabobko/AeroSpace.git "$source_dir"
cd "$source_dir"
[[ "$(git rev-parse HEAD)" == "$UPSTREAM_COMMIT" ]] || {
  printf 'Upstream tag no longer matches the reviewed commit.\n' >&2
  exit 1
}
git apply --check "$patch_snapshot"
git apply "$patch_snapshot"
/opt/homebrew/bin/bash ./generate.sh --ignore-xcodeproj --ignore-cmd-help \
  --build-version "$build_version" --generate-git-hash

xcrun swift test > "$build_dir/tests.log" 2>&1 || {
  tail -n 60 "$build_dir/tests.log" >&2
  exit 1
}
# Newer Xcode toolchains diagnose pre-existing upstream code (e.g. Swift 6.4's
# unnecessary unsafe expressions). Keep warnings in the logs without failing
# a local build solely because its compiler is newer than upstream's.
xcrun swift build --configuration release --arch arm64 --product aerospace \
  > "$build_dir/cli-build.log" 2>&1 || {
  tail -n 60 "$build_dir/cli-build.log" >&2
  exit 1
}
xcrun xcodebuild -project xcode/AeroSpace.xcodeproj -scheme AeroSpace \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$build_dir/xcode" CODE_SIGN_IDENTITY=- \
  MARKETING_VERSION="$build_version" ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=NO \
  build > "$build_dir/app-build.log" 2>&1 || {
  tail -n 60 "$build_dir/app-build.log" >&2
  exit 1
}

mkdir -p "$artifact_dir"
ditto "$build_dir/xcode/Build/Products/Release/AeroSpace.app" "$artifact_dir/AeroSpace.app"
cli_dir="$(xcrun swift build --configuration release --arch arm64 --show-bin-path)"
cp "$cli_dir/aerospace" "$artifact_dir/aerospace"
cp LICENSE.txt "$artifact_dir/LICENSE.txt"
codesign --force --sign - "$artifact_dir/aerospace"
codesign --verify --deep --strict "$artifact_dir/AeroSpace.app"
codesign --verify --strict "$artifact_dir/aerospace"
{
  printf 'version=%s\nupstream_commit=%s\npatch_sha256=%s\n' \
    "$build_version" "$UPSTREAM_COMMIT" "$patch_sha"
  xcrun swift --version
  xcodebuild -version
} > "$artifact_dir/build-info.txt"
printf 'Build and tests passed. Artifacts: %s\nLogs: %s\n' "$artifact_dir" "$build_dir"
