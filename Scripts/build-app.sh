#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
build_dir="${CODEX_USAGE_WIDGET_BUILD_DIR:-${project_dir}/build}"
swift_build_dir="${build_dir}/swiftpm"
app_path="${build_dir}/CodexUsageWidget.app"

cd "$project_dir"
CLANG_MODULE_CACHE_PATH="${swift_build_dir}/clang-module-cache" \
    swift build --disable-sandbox -c release --scratch-path "$swift_build_dir"

binary_path="$(find "$swift_build_dir" -type f -path '*/release/CodexUsageWidget' -print -quit)"
if [[ -z "$binary_path" ]]; then
    print -u2 "Could not locate the release executable."
    exit 1
fi

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_path" "$app_path/Contents/MacOS/CodexUsageWidget"
cp "$project_dir/Resources/Info.plist" "$app_path/Contents/Info.plist"

icon_path="$project_dir/Resources/AppIcon.icns"
if [[ ! -f "$icon_path" ]]; then
    print -u2 "Required app icon is missing: $icon_path"
    exit 1
fi
cp "$icon_path" "$app_path/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$app_path"
print "Built $app_path"
