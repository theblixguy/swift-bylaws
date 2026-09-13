#!/usr/bin/env bash
set -euo pipefail

RELEASE_TAG="${1:?Release tag is required}"
[[ "${RELEASE_TAG}" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[A-Za-z]+[0-9]*)?$ ]]
VERSION="${RELEASE_TAG#v}"
export RELEASE_TAG VERSION

BUNDLE_SHA256=$(shasum -a 256 bylaws-artifactbundle/bylaws.artifactbundle.zip | cut -d' ' -f1)
jq -e --arg version "${VERSION}" --arg checksum "${BUNDLE_SHA256}" \
  '.mode == "remote" and .version == $version and .checksum == $checksum' \
  Distribution/PluginTool.json >&2

MACOS_SHA256=$(shasum -a 256 bylaws-macos/bylaws-macos.tar.gz | cut -d' ' -f1)
LINUX_SHA256=$(shasum -a 256 bylaws-linux/bylaws-linux.tar.gz | cut -d' ' -f1)
export MACOS_SHA256 LINUX_SHA256

MODULE_DIR=$(mktemp -d)
trap 'rm -rf "${MODULE_DIR}"' EXIT
cp -R Distribution/BazelModule/. "${MODULE_DIR}/"
for f in "${MODULE_DIR}/MODULE.bazel" "${MODULE_DIR}/e2e/bzlmod/MODULE.bazel"; do
  ruby -r uri -pe '
    gsub("{{MACOS_SHA256}}", ENV.fetch("MACOS_SHA256"))
    gsub("{{LINUX_SHA256}}", ENV.fetch("LINUX_SHA256"))
    gsub("{{TAG}}", URI.encode_www_form_component(ENV.fetch("RELEASE_TAG")))
    gsub("{{VERSION}}", ENV.fetch("VERSION"))
  ' "${f}" > "${f}.rendered"
  mv "${f}.rendered" "${f}"
done

mkdir -p release-assets
cp bylaws-artifactbundle/bylaws.artifactbundle.zip release-assets/
cp bylaws-macos/bylaws-macos.tar.gz release-assets/
cp bylaws-linux/bylaws-linux.tar.gz release-assets/
tar -czf release-assets/bylaws-bazel-module.tar.gz -C "${MODULE_DIR}" .

printf 'initial version\n'
