#!/bin/bash
# H3 验收：请求/响应正文不落盘——发送唯一标记串，验证网关日志文件与数据库均无痕
# 用法: BASE=... KEY=sk-... GATEWAY_LOG=path DB_PATH=~/.astro-router/one-api.db bash h3.sh
BASE=${BASE:-http://localhost:3000}
KEY=${KEY:?need KEY=sk-...}
GATEWAY_LOG=${GATEWAY_LOG:?need GATEWAY_LOG}
DB_PATH=${DB_PATH:-$HOME/.astro-router/one-api.db}
FAIL=0
MARKER="SECRET-MARKER-$(date +%s)-$$"

# 非流式 + 流式各发一次含标记的请求
curl -s "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d "{\"model\":\"qwen/qwen3-32b\",\"messages\":[{\"role\":\"user\",\"content\":\"$MARKER\"}]}" | grep -q 'mock@' \
  || { echo "FAIL  标记请求未成功"; exit 1; }
curl -sN "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d "{\"model\":\"qwen/qwen3-32b\",\"messages\":[{\"role\":\"user\",\"content\":\"$MARKER\"}],\"stream\":true}" > /dev/null
sleep 1

# 1) 网关日志文件无正文
if grep -aq "$MARKER" "$GATEWAY_LOG"; then
  echo "FAIL  H3 网关日志泄露正文"; FAIL=1
else echo "PASS  H3 网关日志不含请求正文"; fi

# 2) 数据库全库扫描无正文（含 logs.content 等一切字段）
if [ -f "$DB_PATH" ]; then
  hits=$(sqlite3 "$DB_PATH" ".dump" 2>/dev/null | grep -c "$MARKER")
  if [ "$hits" = "0" ]; then echo "PASS  H3 数据库全库无正文（sqlite dump 扫描）"; else echo "FAIL  H3 数据库出现正文 $hits 处"; FAIL=1; fi
else
  echo "SKIP  H3 未找到 SQLite 文件（$DB_PATH），生产 PG 环境请用 pg_dump 扫描"
fi

# 3) 消费日志确有该请求的元数据（记了账但没记内容）
meta=$(sqlite3 "$DB_PATH" "select count(*) from logs where type=2 and model_name like '%qwen%'" 2>/dev/null)
[ -n "$meta" ] && [ "$meta" -gt 0 ] && echo "PASS  H3 元数据正常入账（qwen 消费日志 $meta 条）" || { echo "FAIL  H3 元数据缺失"; FAIL=1; }

[ $FAIL -eq 0 ] && echo "== H3 ALL PASS ==" || { echo "== H3 FAILED =="; exit 1; }
