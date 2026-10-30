#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d "$HOME/Applications/LightTTS.app" ] || scripts/install.sh --no-launch
open "$HOME/Applications/LightTTS.app"
