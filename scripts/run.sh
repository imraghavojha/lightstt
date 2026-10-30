#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d build/LightTTS.app ] || scripts/build-app.sh
open build/LightTTS.app
