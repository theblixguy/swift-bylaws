#!/usr/bin/env bash
set -euo pipefail

repository=$(cd "$(dirname "$0")/../.." && pwd)
tool=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
work=$(mktemp -d "${TMPDIR:-/tmp}/bylaws-lint.XXXXXX")
cleanup() {
    status=$?
    if [ "$status" -ne 0 ] && [ -f "$work/build.log" ]; then
        cat "$work/build.log"
    fi
    bazel --output_base="$work/output" clean --expunge > /dev/null 2>&1 || true
    rm -rf "$work"
    exit "$status"
}
trap cleanup EXIT

cp -R "$repository/Distribution/BazelModule" "$work/module"
cp -R "$repository/Distribution/BazelSupport" "$work/tool"
cp "$tool" "$work/tool/bin/bylaws"
tar -czf "$work/bylaws-macos.tar.gz" -C "$work/tool" .
cp "$work/bylaws-macos.tar.gz" "$work/bylaws-linux.tar.gz"
checksum=$(shasum -a 256 "$work/bylaws-macos.tar.gz" | cut -d ' ' -f 1)
cp -R "$work/module/e2e/bzlmod" "$work/project"
cp -R "$repository/Tests/Bazel/Cases" "$work/project/Cases"
for manifest in "$work/module/MODULE.bazel" "$work/project/MODULE.bazel"; do
    sed -e 's/{{VERSION}}/0.0.0/g' \
        -e "s|https://github.com/theblixguy/swift-bylaws/releases/download/{{TAG}}|file://$work|g" \
        -e "s/{{MACOS_SHA256}}/$checksum/g" \
        -e "s/{{LINUX_SHA256}}/$checksum/g" \
        "$manifest" > "$manifest.new"
    mv "$manifest.new" "$manifest"
done

cd "$work/project"
export USE_BAZEL_VERSION=${USE_BAZEL_VERSION:-8.0.0}
cache_flags=("--disk_cache=$work/cache")
if [ -n "${BYLAWS_BAZEL_REMOTE_CACHE:-}" ]; then
    cache_flags=("--remote_cache=$BYLAWS_BAZEL_REMOTE_CACHE" "--disk_cache=")
fi

build() {
    echo "Checking $1"
    bazel --output_base="$work/output" build \
        --override_module="swift-bylaws=$work/module" \
        --spawn_strategy=sandboxed \
        "${cache_flags[@]}" \
        --execution_log_json_file="$work/actions.json" \
        "$1" > "$work/build.log" 2>&1
}

passes() {
    local report=${1#//}
    report=${report/:/\/}
    build "$1"
    jq -e '.summary.violations == 0 and .summary.checkedRules == 1 and .events == []' \
        "bazel-bin/$report.json" > /dev/null
}

fails() {
    if build "$1"; then
        echo "Expected $1 to fail: $2"
        exit 1
    fi
    grep -F "$2" "$work/build.log"
}

changed_source() {
    passes //Cases:cache
    cp "$repository/Tests/Bazel/Updates/$2" "$1"
    fails //Cases:cache "$3"
    cp "$repository/Tests/Bazel/$1" "$1"
}

"$tool" lint --root . --rules Cases/Rules/Final.swift \
    --record-baseline Cases/Baseline.swift > "$work/baseline.log"

passes //:architecture
jq -se 'any(.[]; .mnemonic == "BylawsLint" and (.commandArgs | index("--selection-cache-size") == null))' \
    "$work/actions.json" > /dev/null

for setting in size:32MiB disabled:0; do
    passes "//Cases:selection_cache_${setting%%:*}"
    jq -se --arg size "${setting#*:}" \
        'any(.[]; .mnemonic == "BylawsLint" and (
            .commandArgs | index("--selection-cache-size") as $i |
            $i != null and .[$i + 1] == $size
        ))' \
        "$work/actions.json" > /dev/null
done
fails //Cases:selection_cache_invalid "Size must be a non-negative whole number of bytes"

passes //Cases:cache
grep -q '"mnemonic": "BylawsLint"' "$work/actions.json"
passes //Cases:cache
if grep -q '"mnemonic": "BylawsLint"' "$work/actions.json"; then
    echo "Unchanged inputs ran the lint action again."
    exit 1
fi

changed_source Cases/Sources/Model.swift Model.swift "Model violates 'Final classes'"
changed_source Cases/Inputs/Generated.swift Generated.swift "Generated violates 'Final classes'"
changed_source Cases/Inputs/GeneratedTree.swift GeneratedTree.swift "GeneratedTree violates 'Final classes'"
changed_source "Cases/Sources/Other folder/Model.swift" Model.swift "Cases/Sources/Other folder/Model.swift"

passes //Cases:cache
cp "$repository/Tests/Bazel/Updates/Data.txt" Cases/Inputs/Data.txt
passes //Cases:cache
grep -q '"mnemonic": "BylawsLint"' "$work/actions.json"
cp "$repository/Tests/Bazel/Cases/Inputs/Data.txt" Cases/Inputs/Data.txt

passes //Cases:cache
cp "$repository/Tests/Bazel/Updates/Final.swift" Cases/Rules/Final.swift
passes //Cases:cache
jq -e '.rules[0].name == "Final types"' bazel-bin/Cases/cache.json > /dev/null
cp "$repository/Tests/Bazel/Cases/Rules/Final.swift" Cases/Rules/Final.swift

build //Cases:advisory
jq -e '.summary.checkedRules == 1 and .summary.violations == 1 and .events[0].level == "warning"' \
    bazel-bin/Cases/advisory.json > /dev/null
fails //Cases:strict "Violation violates 'Final classes'"
passes //Cases:baseline
fails //Cases:stale_baseline "baseline entry no longer matches a violation"
passes //Cases:discovery
fails //Cases:index "index queries need a completed build"
fails //Cases:overlap "bylaws_lint must have separate input paths"

passes //Cases:cache
bazel --output_base="$work/output" clean > "$work/clean.log" 2>&1
passes //Cases:cache
jq -se 'any(.[]; .mnemonic == "BylawsLint" and .cacheHit == true)' \
    "$work/actions.json" > /dev/null

echo "Bazel lint checks passed with Bazel $USE_BAZEL_VERSION."
