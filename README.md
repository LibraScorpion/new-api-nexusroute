<div align="center">

<img src="/web/default/public/logo.png" width="96" alt="agent-api" />

# agent-api

**统一大模型 API 网关 —— 一个 Key 调用所有主流模型，充值 → 调用 → 计费全闭环**

</div>

## 功能

- **双协议兼容**：OpenAI `/v1/chat/completions`（含流式 SSE）与 Anthropic `/v1/messages`，客户端只改 `base_url` 即可迁移
- **多渠道智能路由**：按优先级/权重选路，上游故障自动 fallback，持续异常渠道自动禁用；流式 TTFT 分渠道记录
- **计费系统**：预充值 + 按 token 精确计费、账单明细、用量看板、兑换码入账（公对公转账可审计）、开票申请流
- **企业账号**：主账号 + 分额度子 Key，部门间额度隔离，用量各查各的、主账号看全部
- **模型市场**：定价页、能力标签（Reasoning/Tools/Vision）、延迟/吞吐/成功率实测指标、排行榜
- **渠道管理**：admin `/channels` 页配置上游（类型/base_url/密钥/模型列表一键拉取/参数覆盖），改价即时生效
- **数据安全**：请求正文不落盘（日志与库中均无痕），密钥仅存渠道配置（落库加密）或环境变量

## 快速开始

```bash
# 构建（前端 bun + 后端 go 1.22+）
cd web/default && bun install && bun run build && cd ../..
go build -o agent-api .

# 运行
PORT=3000 SQLITE_PATH=~/.agent-api/one-api.db ./agent-api
# 首次启动后用 root 登录 http://localhost:3000，改密码 → /channels 配置上游渠道
```

常用环境变量：`PORT`、`SQLITE_PATH`（或 `SQL_DSN` 连 PG/MySQL）、`REDIS_CONN_STRING`、`SESSION_SECRET`（多机必配）、`CRITICAL_RATE_LIMIT`。

## 部署与验收

- 生产部署：`docs/DEPLOY.md`（docker compose：网关 + PostgreSQL + Redis + 健康检查）
- 验收测试：`test/acceptance/*.sh`，13 个脚本覆盖 双格式调用/路由/计费/企业账号/定价页/admin/不落盘；
  真实上游复验用 `OPENROUTER_KEY=sk-or-... bash test/acceptance/real-upstream.sh`（密钥只走环境变量）

## 上游与许可

本项目基于 [QuantumNous/new-api](https://github.com/QuantumNous/new-api) 二次开发（自 v1.0.0-rc.19 分叉），遵循 [AGPL-3.0](./LICENSE) 许可发布，完整保留上游版权声明与许可文本。

同步上游安全更新：

```bash
git fetch upstream --tags && git merge <tag>   # upstream = QuantumNous/new-api
```
