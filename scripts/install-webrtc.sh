#!/bin/sh
# Official universal macOS (Intel/Apple Silicon) and Linux binaries, same release as Windows.
set -eu
project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
version=1.2.2-stable
expected=98e9446921740d995bd9ca1be48798dc3c2ceed51e044a25ce18b3cff11f56e5
destination="$project_root/addons/webrtc_native"
if [ -e "$destination" ]; then
    printf '%s\n' "WebRTC directory already exists: $destination" "If loading fails, move it outside the project first, then run this installer again."
    exit 0
fi
work=$(mktemp -d "${TMPDIR:-/tmp}/foxha-webrtc.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM
curl --fail --location --retry 3 "https://github.com/godotengine/webrtc-native/releases/download/$version/godot-extension-webrtc_native.zip" -o "$work/webrtc.zip"
if command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$work/webrtc.zip" | cut -d ' ' -f 1)
else
    actual=$(sha256sum "$work/webrtc.zip" | cut -d ' ' -f 1)
fi
if [ "$actual" != "$expected" ]; then
    printf '%s\n' 'WebRTC archive checksum mismatch.' >&2
    exit 1
fi
unzip -q "$work/webrtc.zip" -d "$work/unpacked"
test -f "$work/unpacked/addons/webrtc_native/webrtc_native.gdextension"
mkdir -p "$project_root/addons"
mv "$work/unpacked/addons/webrtc_native" "$destination"
printf '%s\n' "Installed official webrtc-native $version." 'Fully quit and reopen Godot so the native extension is loaded.'
