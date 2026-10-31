#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d "${TMPDIR:-/tmp}/lighttts-wav-bench.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
swiftc -O Sources/LightTTSRuntime/Audio/RecordingWAV.swift scripts/perf/wav-encoding.swift -o "$tmp/benchmark"
shasum -a 256 "$1"
"$tmp/benchmark" "$1"
