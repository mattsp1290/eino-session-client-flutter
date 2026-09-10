#!/usr/bin/env bash
set -euo pipefail

: "${CORE_REF:?Set CORE_REF to the published core commit}"
: "${DEPENDENTS_REF:?Set DEPENDENTS_REF to the published dependent-packages commit}"

repo_url="${REPOSITORY_URL:-https://github.com/mattsp1290/eino-session-client-flutter.git}"
temporary_dir="$(mktemp -d)"
temporary_cache="$(mktemp -d)"
trap 'rm -rf "$temporary_dir" "$temporary_cache"' EXIT

mkdir -p "$temporary_dir/lib"
printf 'void main() {}\n' > "$temporary_dir/lib/main.dart"
printf '%s\n' \
  'name: public_consumer_probe' \
  'environment:' \
  "  sdk: '>=3.13.1 <4.0.0'" \
  'dependencies:' \
  '  ag_ui_view_state:' \
  '    git:' \
  "      url: $repo_url" \
  "      ref: $CORE_REF" \
  '      path: packages/ag_ui_view_state' \
  '  ag_ui_widgets:' \
  '    git:' \
  "      url: $repo_url" \
  "      ref: $DEPENDENTS_REF" \
  '      path: packages/ag_ui_widgets' \
  '  eino_session_client:' \
  '    git:' \
  "      url: $repo_url" \
  "      ref: $DEPENDENTS_REF" \
  '      path: packages/eino_session_client' > "$temporary_dir/pubspec.yaml"

(
  cd "$temporary_dir"
  PUB_CACHE="$temporary_cache" dart pub get
  dart analyze
  dart pub deps --json > /dev/null
)
echo 'PASS: fresh public consumer resolved immutable package refs'
