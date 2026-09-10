#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temporary_dir="$(mktemp -d)"
ready_file="$temporary_dir/address"
server_log="$temporary_dir/server.log"
server_pid=''
driver_pid=''

cleanup() {
  if [[ -n "$server_pid" ]] && kill -0 "$server_pid" 2>/dev/null; then
    kill "$server_pid"
    wait "$server_pid" 2>/dev/null || true
  fi
  if [[ -n "$driver_pid" ]] && kill -0 "$driver_pid" 2>/dev/null; then
    kill "$driver_pid"
    wait "$driver_pid" 2>/dev/null || true
  fi
  rm -rf "$temporary_dir"
}
trap cleanup EXIT INT TERM

(
  cd "$repo_root/conformance/go"
  GOWORK=off go run ./cmd/fixture-server -addr 127.0.0.1:0 \
    -ready-file "$ready_file" -db "$temporary_dir/fixture.db"
) > "$server_log" 2>&1 &
server_pid=$!

for _ in $(seq 1 100); do
  if [[ -s "$ready_file" ]]; then
    break
  fi
  if ! kill -0 "$server_pid" 2>/dev/null; then
    sed -n '1,80p' "$server_log"
    exit 1
  fi
  sleep 0.1
done

if [[ ! -s "$ready_file" ]]; then
  echo 'fixture server readiness deadline exceeded'
  exit 1
fi
base_url="http://$(<"$ready_file")"

if ! command -v chromedriver >/dev/null 2>&1; then
  echo 'chromedriver is required for Flutter web integration tests'
  exit 1
fi
chromedriver --port=4444 > "$temporary_dir/chromedriver.log" 2>&1 &
driver_pid=$!
sleep 0.5
if ! kill -0 "$driver_pid" 2>/dev/null; then
  sed -n '1,80p' "$temporary_dir/chromedriver.log"
  exit 1
fi

(
  cd "$repo_root/examples/generic_ag_ui"
  timeout 180 flutter drive -d web-server \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/session_flow_test.dart \
    --dart-define="AG_UI_ENDPOINT=$base_url/generic/run"
)
(
  cd "$repo_root/examples/eino_session"
  timeout 180 flutter drive -d web-server \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/session_flow_test.dart \
    --dart-define="EINO_SERVER=$base_url"
)
