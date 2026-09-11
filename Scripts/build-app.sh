#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
build_dir="${CODEX_USAGE_WIDGET_BUILD_DIR:-${project_dir}/build}"
swift_build_dir="${build_dir}/swiftpm"

if (( $# > 1 )); then
    print -u2 "Usage: $0 [CodexUsageWidget|CodexUsageCapsuleWidget]"
    exit 64
fi

app_name="${1:-CodexUsageWidget}"
case "$app_name" in
    CodexUsageWidget)
        info_path="$project_dir/Resources/Info.plist"
        icon_path="$project_dir/Resources/AppIcon.icns"
        ;;
    CodexUsageCapsuleWidget)
        info_path="$project_dir/Resources/CodexUsageCapsuleWidget/Info.plist"
        icon_path="$project_dir/Resources/CodexUsageCapsuleWidget/AppIcon.icns"
        ;;
    *)
        print -u2 "Unsupported app: $app_name"
        print -u2 "Usage: $0 [CodexUsageWidget|CodexUsageCapsuleWidget]"
        exit 64
        ;;
esac

if [[ ! -f "$info_path" ]]; then
    print -u2 "Required app metadata is missing: $info_path"
    exit 1
fi
if [[ ! -f "$icon_path" ]]; then
    print -u2 "Required app icon is missing: $icon_path"
    exit 1
fi

plist_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_path")"
if [[ "$plist_executable" != "$app_name" ]]; then
    print -u2 "CFBundleExecutable must match the selected app: $app_name"
    exit 1
fi

app_path="${build_dir}/${app_name}.app"
swift_build_arguments=(
    --disable-sandbox
    -c release
    --product "$app_name"
    --scratch-path "$swift_build_dir"
    -Xswiftc -gnone
)

cd "$project_dir"
CLANG_MODULE_CACHE_PATH="${swift_build_dir}/clang-module-cache" \
    swift build "${swift_build_arguments[@]}"

binary_dir="$(CLANG_MODULE_CACHE_PATH="${swift_build_dir}/clang-module-cache" \
    swift build "${swift_build_arguments[@]}" --show-bin-path)"
binary_path="${binary_dir}/${app_name}"
if [[ ! -x "$binary_path" ]]; then
    print -u2 "Could not locate the release executable at ${binary_path}."
    exit 1
fi

binary_architectures="$(lipo -archs "$binary_path")"
if [[ "$binary_architectures" != "arm64" ]]; then
    print -u2 "Expected an arm64 release executable, found: ${binary_architectures}."
    exit 1
fi

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_path" "$app_path/Contents/MacOS/$app_name"
cp "$info_path" "$app_path/Contents/Info.plist"
cp "$icon_path" "$app_path/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
zip_path="${build_dir}/${app_name}-${version}-macos-arm64.zip"
rm -f "$zip_path"
(
    cd "$build_dir"
    COPYFILE_DISABLE=1 /usr/bin/zip -r -X "$(basename "$zip_path")" "$(basename "$app_path")" >/dev/null
)

print "Built $app_path"
print "Built $zip_path"
