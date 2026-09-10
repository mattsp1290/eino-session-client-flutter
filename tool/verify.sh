#!/usr/bin/env bash
set -euo pipefail

export GIT_LFS_SKIP_SMUDGE=1

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
flutter_bin="$(command -v flutter)"
dart_bin="$(dirname "$flutter_bin")/dart"

"$dart_bin" --version
flutter --version
go version

find "$repo_root/packages" "$repo_root/examples" "$repo_root/tool" \
  \( -name .dart_tool -o -name build \) -prune -o -name '*.dart' -type f -print0 | \
  xargs -0 "$dart_bin" format --output=none --set-exit-if-changed

for package in ag_ui_view_state eino_session_client; do
  (
    cd "$repo_root/packages/$package"
    "$dart_bin" pub get
    "$dart_bin" analyze
    "$dart_bin" test
  )
done

for project in packages/ag_ui_widgets examples/generic_ag_ui examples/eino_session; do
  (
    cd "$repo_root/$project"
    flutter pub get
    flutter analyze
    flutter test
  )
done

(
  cd "$repo_root/conformance/go"
  GOWORK=off go mod verify
  GOWORK=off go test -race ./...
)

"$repo_root/tool/verify_fixtures.sh"

for example in generic_ag_ui eino_session; do
  (
    cd "$repo_root/examples/$example"
    flutter build web
  )
done

if command -v timeout >/dev/null 2>&1; then
  "$repo_root/tool/run_browser_integration.sh"
else
  echo 'SKIP: browser integration runner requires timeout (CI runs on Linux)'
fi

(
  cd "$repo_root"
  "$dart_bin" run tool/check_boundaries.dart
)

if [[ -n "${CORE_REF:-}" && -n "${DEPENDENTS_REF:-}" ]]; then
  "$repo_root/tool/verify_public_consumer.sh"
else
  echo 'SKIP: public consumer requires CORE_REF and DEPENDENTS_REF after publication'
fi
