#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "$temporary_dir"' EXIT
cd "$repo_root/conformance/go"
GOWORK=off go run ./cmd/generate-fixtures -output "$temporary_dir"
diff -ru "$repo_root/conformance/fixtures" "$temporary_dir"
