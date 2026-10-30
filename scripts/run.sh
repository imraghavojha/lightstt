#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d "$HOME/Applications/LightTTS.app" ] || scripts/build-app.sh
open "$HOME/Applications/LightTTS.app"
