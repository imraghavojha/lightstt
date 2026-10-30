#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
files=()
while IFS= read -r -d '' file; do
    file=${file#./}
    if ! grep -Fqx -- "$file" scripts/format-exempt.txt; then
        files+=("$file")
    fi
done < <(find . -type d \( -name .git -o -name .build \) -prune -o -type f -name '*.swift' -print0)
if ((${#files[@]})); then
    xcrun swift-format lint --strict --configuration .swift-format "${files[@]}"
fi
