#!/bin/sh
# Add SPDX license headers
# The explicit template file avoids blank separator lines
set -eu

cd "$(dirname "$0")/.."

ADDON=addons/blanket
COPYRIGHT="1hue"
LICENSE=MIT

annotate() {
	reuse annotate \
		--copyright "$COPYRIGHT" \
		--license "$LICENSE" \
		--copyright-prefix spdx-symbol \
		--merge-copyrights \
		--template compact \
		"$@"
}

annotate --style python $(find "$ADDON" -name '*.gd')
annotate --style cpp --single-line $(find "$ADDON" -name '*.glsl' -o -name '*.glsl.inc' -o -name '*.gdshader')
