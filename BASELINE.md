# Probo 稳定开发基线

## 记录信息

- 记录日期：2026-09-17（Asia/Shanghai）
- 仓库：`Certscope`（Probo 二次开发基线）
- 当前 commit：`fb227004519d7e13671cc8df197b5f353aab22e1`
- 工作树：本次仅修改 `eslint.config.mjs` 和本文件；已有未跟踪文件 `.joycode/project.json`、`gen-dev-config.sh`，本次未修改

## 技术栈

- Backend：Go，PostgreSQL
- API：GraphQL、MCP、CLI
- Frontend：React、TypeScript、Relay、TailwindCSS、Vite
- Monorepo：npm workspaces、Turborepo
- Infrastructure：Docker Compose、step-ca、Keycloak、SeaweedFS、Mailpit、Chrome、Prometheus、Grafana、Loki、Tempo

## 服务组成

仓库包含 `probod` API 服务、`prb` CLI、`probod-bootstrap` 配置生成器、`proboctl` 及 Console、Compliance Portal、Employee Portal 前端。

完整 Docker Compose 依赖栈已启动：PostgreSQL、SeaweedFS、Mailpit、step-ca、Chrome、ACME HTTP-01 proxy、Keycloak、Prometheus、Grafana、Loki、Tempo。Keycloak 首次从 Docker Desktop 内置代理下载过慢，最终使用宿主机直连 Quay 的 Skopeo OCI 归档路径导入；镜像已验证为 `linux/arm64`，之后 `docker compose up -d` 成功复用本地镜像。

`bin/probod -cfg-file cfg/dev.yaml` 已冷启动两轮；每轮 `/healthz` 和 `:8081/metrics` 均返回 HTTP 200，并正常退出。

## 数据库

- 类型：PostgreSQL
- 本地地址：`localhost:5432`
- 数据库：`probod`
- 用户：`postgres`
- 本地默认密码：`postgres`
- 启动方式：`make stack-up`
- 本次未执行数据库迁移或数据修改

## 本地启动步骤

```sh
cd /Users/xuhao.alex/Documents/PROBO系统/Certscope
go mod download
npm ci
make stack-up
make generate WITH_APPS=1
make build
make dev-config
TZ=UTC bin/probod -cfg-file cfg/dev.yaml
```

Console 前端：

```sh
npm -w @probo/console run dev
```

## macOS + Podman 启动方式

Docker Desktop 不可用时，可使用 Podman Machine 运行同一套 Linux 容器。2026-09-18 已在 Apple Silicon macOS 上完成验证：Podman 6.1.2、podman-compose 1.6.0、AppleHV、6 CPU、8 GiB 内存、100 GiB 磁盘，rootless 模式运行。

首次初始化和启动：

```sh
brew install podman podman-compose
podman machine init --cpus 6 --memory 8192 --disk-size 100
podman machine start
```

`acme-http-01-proxy` 需要绑定宿主机 80 端口。Podman Machine 的 rootless 默认禁止低于 1024 的端口，需在 Machine 内设置一次，并保留为启动时的 sysctl 配置：

```sh
podman machine ssh "sudo sysctl -w net.ipv4.ip_unprivileged_port_start=80"
podman machine ssh "printf 'net.ipv4.ip_unprivileged_port_start=80\\n' | sudo tee /etc/sysctl.d/99-podman-rootless-ports.conf >/dev/null"
```

本次 Podman 验收使用经过摘要校验的 `linux/arm64` OCI 镜像导入本地存储，再启动 Compose；普通 `podman pull` 在当前网络环境中仍可能卡在 Registry Blob 响应阶段。不要执行来源不明的远程 `sudo` 安装脚本，也不要把未验证的镜像源写入全局 Registry 配置。

`podman-compose 1.6.0` 会把 Compose 映射中的布尔环境变量序列化为 `True/False`；Keycloak 26.6.1 要求小写 `true/false`，因此启动 Podman 验收时需使用 env-file 适配，或使用已验证的临时完整 Compose 适配文件。原始 `compose.yaml` 的 Docker 启动方式保持不变。

日常开发可直接使用仓库内的联动启动入口。它会启动 Podman Machine，设置低端口权限，使用本地已验证镜像生成临时 Podman Compose 适配文件，启动 11 个依赖服务，并在依赖就绪后以 `cfg/dev.yaml` 启动 Probo：

```sh
cd /Users/xuhao.alex/Documents/PROBO系统/Certscope
make podman-up
```

该入口固定使用 API `:8080`、metrics `:8081`、Keycloak `:8082`、ACME `:9000`、SMTP `:1025`、PostgreSQL `:5432`、Mailpit `:8025`、Chrome `:9222` 以及 Compose 中声明的其余端口。运行时适配文件和 Probo 日志均不写入 Git；首次初始化仍需先完成镜像导入、`make dev-config`、证书和 realm 文件生成。

验证顺序必须保持为：Podman Machine → 11 个依赖服务 → step-ca ACME directory/HTTP-01 → Probo `:8080/healthz` 与 `:8081/metrics` → E2E → 两轮冷启动。E2E 运行时使用 `TZ=UTC`、`PROBOD_ACME_ROOT_CA` 和 `PROBOD_ACME_ACCOUNT_KEY`，并先停止手动启动的 `probod` 实例。

## Build / Test / Lint / Code Generation

```sh
# Backend and binaries
make build

# Frontend and all packages
npm run build

# Unit tests
make test

# Integration / end-to-end tests（本地 step-ca 根证书和 UTC 时区）
export TZ=UTC
export PROBOD_ACME_ROOT_CA="$(< compose/step-ca/certs/root_ca.crt)"
export PROBOD_ACME_ACCOUNT_KEY="$(< cfg/.dev-acme-account-key.pem)"
make test-e2e

# Go + JavaScript lint
make lint

# Frontend type checks
npm run check

# Go code generation
make generate

# Full generation including Relay/frontend artifacts
make generate WITH_APPS=1
```

## 本次验证结果

| 检查项 | 结果 | 说明 |
|---|---|---|
| Docker Desktop / Compose | 通过 | Docker 29.8.0，Compose v5.5.1 |
| 完整 Docker Compose 服务 | 通过 | 11 个服务均为 running；PostgreSQL/Mailpit/step-ca healthy，Keycloak、Prometheus、Grafana、Loki、Tempo 就绪检查通过 |
| Frontend build | 通过 | `npm run build`，7 个任务成功；有 Vite chunk/dynamic-import 警告 |
| Frontend type check | 通过 | `npm run check`，6 个任务成功 |
| Frontend lint | 通过 | 0 errors、13 warnings；已忽略 `.cache/**` 生成缓存目录 |
| Backend build | 通过 | Go 1.27.1；`make build WITH_APPS=1` 成功 |
| Unit tests | 通过 | `make test`：6384 tests，5 skipped |
| E2E tests | 通过 | UTC + 本地 step-ca CA/account key：2151 tests，2 skipped |
| Code generation | 通过 | `make generate WITH_APPS=1` 成功 |
| Probo health check | 通过 | 冷启动两轮：每轮 `:8080/healthz`、`:8081/metrics` 均为 200 |
| Podman Machine + 11 服务 | 通过 | AppleHV rootless；PostgreSQL、SeaweedFS、Grafana、Prometheus、Loki、Tempo、Mailpit、Chrome、Caddy、step-ca、Keycloak 均运行 |
| Podman ACME / Probo / E2E | 通过 | step-ca ACME directory、Probo `/healthz`/metrics 返回 200；E2E 2151 tests，2 skipped；两轮冷启动均返回 200 |

## 已知问题 / 基线风险

1. Go 1.27.1 和 golangci-lint 2.13.2 使用用户目录安装；新终端需将 `/Users/xuhao.alex/.local/go-1.27.1/bin`、`/Users/xuhao.alex/.local/bin` 加入 `PATH`。
2. 仓库声明使用 npm workspaces；bundled pnpm 会尝试从公共 registry 获取本地包 `@probo/eslint-config` 并 404，不应使用 pnpm 作为本仓库基线安装入口。
3. `npm ci` 可成功安装依赖，但当前 npm 11.17.0 低于仓库要求的 npm 12.0.2；Node 24.19.0 满足 Node 24.15+ 要求。
4. E2E 本地运行必须显式提供 step-ca 根证书/account key，并设置 `TZ=UTC`；否则分别会出现 CA trust 失败或时区断言失败。E2E 临时实例使用固定的 `:10080`/`:8443`，运行 E2E 前需停止另一个手动 `probod` 实例，避免端口占用。
5. `gen-dev-config.sh` 是外部工具生成的本地快捷脚本，硬编码仓库绝对路径并重复 `make dev-config` 的逻辑；可借鉴其配置值，但本基线以官方 Make target 为准，未将该脚本纳入正式启动流程。
6. Docker Desktop 对 `quay.io` 使用的 `http.docker.internal:3128` 代理下载 Keycloak 大层速度很慢；宿主机直连 Quay 的 `skopeo copy --override-os linux --override-arch arm64 ... oci-archive:...` 可作为一次性镜像导入和 Registry 故障绕过方案。
7. Podman macOS 验收已通过，但首次镜像获取仍受当前 Registry 网络质量影响；Podman 低端口 sysctl 和 `podman-compose` 的 Keycloak 布尔环境变量适配不可省略。

## 基线使用注意事项

- 运行 E2E 前，先停止手动启动的 `probod` 实例；E2E 临时实例会占用固定的 `:10080` 和 `:8443` 端口。E2E 完成后再按本文件的启动步骤恢复 Probo。
- E2E 必须使用 `TZ=UTC`，并设置 `PROBOD_ACME_ROOT_CA` 与 `PROBOD_ACME_ACCOUNT_KEY`；否则可能出现本地 CA 不受信任或时区断言失败。
- 新终端使用 Go 和 `golangci-lint` 前，将 `/Users/xuhao.alex/.local/go-1.27.1/bin` 与 `/Users/xuhao.alex/.local/bin` 加入 `PATH`。
- 基线安装入口使用 npm，不使用 bundled pnpm；pnpm 可能把本地包 `@probo/eslint-config` 当作公共包请求并产生 404。

## 数据库 / 兼容性说明

本次只做环境、构建、启动和测试基线，没有新增 migration、Entity、Service、API、UI 或业务规则修改；因此没有本次引入的数据迁移、tenant isolation、RBAC 或兼容性变化。

## 验收结论

构建、代码生成、前端检查、Go 单元测试、E2E、完整 11 服务 Compose 启动和 Probo 冷启动均通过；当前工作树可作为 Probo 应用稳定开发基线。
