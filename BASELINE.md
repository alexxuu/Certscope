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

## 已知问题 / 基线风险

1. Go 1.27.1 和 golangci-lint 2.13.2 使用用户目录安装；新终端需将 `/Users/xuhao.alex/.local/go-1.27.1/bin`、`/Users/xuhao.alex/.local/bin` 加入 `PATH`。
2. 仓库声明使用 npm workspaces；bundled pnpm 会尝试从公共 registry 获取本地包 `@probo/eslint-config` 并 404，不应使用 pnpm 作为本仓库基线安装入口。
3. `npm ci` 可成功安装依赖，但当前 npm 11.17.0 低于仓库要求的 npm 12.0.2；Node 24.19.0 满足 Node 24.15+ 要求。
4. E2E 本地运行必须显式提供 step-ca 根证书/account key，并设置 `TZ=UTC`；否则分别会出现 CA trust 失败或时区断言失败。E2E 临时实例使用固定的 `:10080`/`:8443`，运行 E2E 前需停止另一个手动 `probod` 实例，避免端口占用。
5. `gen-dev-config.sh` 是外部工具生成的本地快捷脚本，硬编码仓库绝对路径并重复 `make dev-config` 的逻辑；可借鉴其配置值，但本基线以官方 Make target 为准，未将该脚本纳入正式启动流程。
6. Docker Desktop 对 `quay.io` 使用的 `http.docker.internal:3128` 代理下载 Keycloak 大层速度很慢；宿主机直连 Quay 的 `skopeo copy --override-os linux --override-arch arm64 ... oci-archive:...` 可作为一次性镜像导入和 Registry 故障绕过方案。

## 基线使用注意事项

- 运行 E2E 前，先停止手动启动的 `probod` 实例；E2E 临时实例会占用固定的 `:10080` 和 `:8443` 端口。E2E 完成后再按本文件的启动步骤恢复 Probo。
- E2E 必须使用 `TZ=UTC`，并设置 `PROBOD_ACME_ROOT_CA` 与 `PROBOD_ACME_ACCOUNT_KEY`；否则可能出现本地 CA 不受信任或时区断言失败。
- 新终端使用 Go 和 `golangci-lint` 前，将 `/Users/xuhao.alex/.local/go-1.27.1/bin` 与 `/Users/xuhao.alex/.local/bin` 加入 `PATH`。
- 基线安装入口使用 npm，不使用 bundled pnpm；pnpm 可能把本地包 `@probo/eslint-config` 当作公共包请求并产生 404。

## 数据库 / 兼容性说明

本次只做环境、构建、启动和测试基线，没有新增 migration、Entity、Service、API、UI 或业务规则修改；因此没有本次引入的数据迁移、tenant isolation、RBAC 或兼容性变化。

## 验收结论

构建、代码生成、前端检查、Go 单元测试、E2E、完整 11 服务 Compose 启动和 Probo 冷启动均通过；当前工作树可作为 Probo 应用稳定开发基线。
