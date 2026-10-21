#!/bin/sh
set -eu
probe_dir=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
root=$(CDPATH= cd -- "$probe_dir/../../.." && pwd)
session="$root/macos/Sources/IBMSNative/PreviewUnifiedAudioSession.swift"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
awk '/AS-SPAN-CLOCK-BEGIN/{flag=1; next} /AS-SPAN-CLOCK-END/{flag=0} flag' "$session" > "$work/clock.swift"
cat "$probe_dir/span-clock-checks.swift" >> "$work/clock.swift"
swiftc -parse-as-library -o "$work/probe" "$work/clock.swift"
"$work/probe"
