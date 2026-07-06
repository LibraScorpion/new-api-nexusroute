# 部署文档 — 算力路由 MVP

## 一键部署

```bash
git clone <本仓库>
cd astro-router
# 编辑 docker-compose.deploy.yml，替换所有 CHANGE_ME
docker compose -f docker-compose.deploy.yml up -d
# 首次访问 http://<host>:3000 进入初始化向导，创建管理员
```

## 环境变量清单

| 变量 | 必填 | 说明 |
|---|---|---|
| `SQL_DSN` | 是 | 主库连接串（postgresql://... 或 mysql tcp()；不设则用本地 SQLite `/data/one-api.db`） |
| `REDIS_CONN_STRING` | 建议 | Redis 连接串，多副本部署必须 |
| `SESSION_SECRET` | 是 | 会话签名密钥，随机长串；不设则每次重启所有登录失效 |
| `CRYPTO_SECRET` | 是 | 敏感字段（渠道 Key 等）加密密钥，**设定后不可更换** |
| `PORT` | 否 | 监听端口，默认 3000 |
| `TZ` | 否 | 时区，建议 Asia/Shanghai |
| `CRITICAL_RATE_LIMIT` | 否 | 登录/取 Key 等关键接口限流（默认 20 次/20 分钟），压测或自动化场景调大 |
| `STREAMING_TIMEOUT` | 否 | 流式无响应超时秒数，默认 120 |
| `SESSION_COOKIE_SECURE` + `SESSION_COOKIE_TRUSTED_URL` | 生产必设 | HTTPS 下启用 Secure Cookie |

上游渠道的 API Key 不走环境变量，在 admin 控制台「渠道」中配置（落库加密）。

## 初始化清单（首次部署后按序执行）

1. 初始化向导创建管理员账号
2. 系统设置 → 主题切换为 `default`（新版前端，含模型市场/排行榜页）
3. 添加上游渠道（OpenRouter / 硅基流动等），填入真实 Key
4. 渠道页「获取模型列表」拉取模型 → 勾选上架
5. 模型元数据同步：`POST /api/models/sync_upstream`（补齐描述/上下文/能力标签）
6. 定价：系统设置 → 倍率设置，或 `POST /api/ratio_sync/fetch` 从上游同步后确认
7. 运营设置 → 确认支付合规声明（启用兑换码/充值功能）
8. 跑一遍 `test/acceptance/`（a1-a2 / a3 / a4 / c / d 至少各一次）作为上线冒烟

## 数据备份与恢复

- **PostgreSQL**：`docker exec astro-postgres pg_dump -U root new-api > backup-$(date +%F).sql`；
  恢复：`cat backup.sql | docker exec -i astro-postgres psql -U root -d new-api`
- **SQLite（未配 SQL_DSN 时）**：停服后直接拷贝 `./data/one-api.db`
- 建议每日定时备份 + 异地留存；`CRYPTO_SECRET` 与备份同等级保管（丢失则渠道 Key 无法解密）

## 版本升级

```bash
git pull
docker compose -f docker-compose.deploy.yml build gateway
docker compose -f docker-compose.deploy.yml up -d gateway   # 数据库迁移自动执行（GORM AutoMigrate）
```

回滚：`git checkout <上一版本 tag>` 后重复上述两步（迁移向前兼容，跨大版本回滚前先恢复备份）。

## 数据安全承诺（对客户）

- 请求与响应**正文不落盘**：日志仅记录元数据（时间、模型、tokens、金额、状态码、渠道），
  消费日志 `content` 字段恒为空。验证脚本：`test/acceptance/h3.sh`
- 渠道上游 Key 落库加密（CRYPTO_SECRET）
- 客户 API Key 仅创建时明文展示一次，列表与详情接口均脱敏
