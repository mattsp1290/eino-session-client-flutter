#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root/conformance/go"
GOWORK=off go run ./cmd/generate-fixtures -output ../fixtures
