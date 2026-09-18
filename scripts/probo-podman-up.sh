#!/usr/bin/env bash

set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATE_DIR="${TMPDIR:-/tmp}/probo-dev"
mkdir -p "$STATE_DIR"
RUNTIME_COMPOSE="$(mktemp "$ROOT_DIR/.podman-compose-runtime.XXXXXX")"
KEYCLOAK_ENV="$(mktemp "$STATE_DIR/keycloak-env.XXXXXX")"
PROBOD_LOG="$STATE_DIR/probod.log"
PROBOD_PID="$STATE_DIR/probod.pid"

cleanup() { rm -f "$RUNTIME_COMPOSE" "$KEYCLOAK_ENV"; }
trap cleanup EXIT INT TERM

die() { echo "错误：$*" >&2; exit 1; }

command -v podman >/dev/null 2>&1 || die "未找到 podman，请先安装 Podman。"
command -v podman-compose >/dev/null 2>&1 || die "未找到 podman-compose，请先安装 podman-compose。"

echo "[1/4] 启动 Podman Machine"
podman machine start >/dev/null 2>&1 || true
podman info >/dev/null 2>&1 || die "Podman Machine 未就绪。"

port_start="$(podman machine ssh "sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null" 2>/dev/null || true)"
if [ "$port_start" != "80" ]; then
  podman machine ssh "sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80" >/dev/null
fi
podman machine ssh "printf 'net.ipv4.ip_unprivileged_port_start=80\\n' | sudo tee /etc/sysctl.d/99-podman-rootless-ports.conf >/dev/null" >/dev/null

[ -f "$ROOT_DIR/cfg/dev.yaml" ] || die "缺少 cfg/dev.yaml，请先执行 make dev-config。"
[ -f "$ROOT_DIR/compose/keycloak/probo-realm.json" ] || die "缺少 Keycloak realm 文件，请先完成一次基线初始化。"
[ -f "$ROOT_DIR/compose/step-ca/certs/root_ca.crt" ] || die "缺少 step-ca 根证书，请先完成一次基线初始化。"

cat >"$KEYCLOAK_ENV" <<'EOF'
KC_HOSTNAME=localhost
KC_HOSTNAME_PORT=8082
KC_HOSTNAME_STRICT=false
KC_HOSTNAME_STRICT_HTTPS=false
KC_LOG_LEVEL=info
KC_METRICS_ENABLED=true
KC_HEALTH_ENABLED=true
KEYCLOAK_ADMIN=admin
KEYCLOAK_ADMIN_PASSWORD=admin
EOF

for image in \
  localhost/postgres:latest localhost/seaweedfs:latest localhost/grafana:latest \
  localhost/prometheus:latest localhost/loki:latest localhost/tempo:latest \
  localhost/mailpit:latest localhost/chrome:latest localhost/caddy:latest \
  localhost/stepca:latest localhost/keycloak:latest; do
  podman image exists "$image" || die "缺少本地镜像 $image；请先按 BASELINE.md 完成镜像导入。"
done

cp "$ROOT_DIR/compose.yaml" "$RUNTIME_COMPOSE"
perl -0pi -e 's#postgres\@sha256:[0-9a-f]+#localhost/postgres:latest#g; s#chrislusf/seaweedfs\@sha256:[0-9a-f]+#localhost/seaweedfs:latest#g; s#grafana/grafana\@sha256:[0-9a-f]+#localhost/grafana:latest#g; s#prom/prometheus\@sha256:[0-9a-f]+#localhost/prometheus:latest#g; s#grafana/loki\@sha256:[0-9a-f]+#localhost/loki:latest#g; s#grafana/tempo\@sha256:[0-9a-f]+#localhost/tempo:latest#g; s#axllent/mailpit\@sha256:[0-9a-f]+#localhost/mailpit:latest#g; s#chromedp/headless-shell\@sha256:[0-9a-f]+#localhost/chrome:latest#g; s#caddy:2\.10\.2\@sha256:[0-9a-f]+#localhost/caddy:latest#g; s#smallstep/step-ca:0\.28\.4\@sha256:[0-9a-f]+#localhost/stepca:latest#g; s#quay\.io/keycloak/keycloak:26\.6\.1\@sha256:[0-9a-f]+#localhost/keycloak:latest#g' "$RUNTIME_COMPOSE"
perl -0pi -e "s|    environment:\n      KC_HOSTNAME: localhost\n      KC_HOSTNAME_PORT: 8082\n      KC_HOSTNAME_STRICT: false\n      KC_HOSTNAME_STRICT_HTTPS: false\n\n      KC_LOG_LEVEL: info\n      KC_METRICS_ENABLED: true\n      KC_HEALTH_ENABLED: true\n      KEYCLOAK_ADMIN: admin\n      KEYCLOAK_ADMIN_PASSWORD: admin\n|    env_file:\n      - $KEYCLOAK_ENV\n|" "$RUNTIME_COMPOSE"

echo "[2/4] 启动固定端口依赖服务"
(cd "$ROOT_DIR" && podman-compose -p certscope -f "$RUNTIME_COMPOSE" up -d)

wait_http() {
  label="$1"; url="$2"; attempts=0
  while [ "$attempts" -lt 60 ]; do
    if curl -kfsS --max-time 2 "$url" >/dev/null 2>&1; then
      echo "  $label 就绪"; return 0
    fi
    attempts=$((attempts + 1)); sleep 1
  done
  die "$label 未在 60 秒内就绪：$url"
}

echo "[3/4] 等待依赖服务"
wait_http "Keycloak" "http://127.0.0.1:8082/realms/master"
wait_http "step-ca ACME" "https://127.0.0.1:9000/acme/acme/directory"
wait_http "Mailpit" "http://127.0.0.1:8025"
wait_http "Prometheus" "http://127.0.0.1:9191/-/ready"
wait_http "Grafana" "http://127.0.0.1:3001/api/health"
wait_http "Loki" "http://127.0.0.1:3100/ready"
wait_http "Chrome" "http://127.0.0.1:9222/json/version"

echo "[4/4] 启动 Probo 并确认固定端口"
if ! curl -fsS --max-time 2 http://127.0.0.1:8080/healthz >/dev/null 2>&1; then
  [ -x "$ROOT_DIR/bin/probod" ] || die "缺少 bin/probod，请先执行 make build。"
  nohup env TZ=UTC "$ROOT_DIR/bin/probod" -cfg-file "$ROOT_DIR/cfg/dev.yaml" >"$PROBOD_LOG" 2>&1 &
  echo $! >"$PROBOD_PID"
fi
wait_http "Probo" "http://127.0.0.1:8080/healthz"
wait_http "Probo metrics" "http://127.0.0.1:8081/metrics"

echo "启动完成："
echo "  Console/API: http://localhost:8080"
echo "  Keycloak:    http://localhost:8082"
echo "  Mailpit:     http://localhost:8025"
echo "  Probo 日志:  $PROBOD_LOG"
