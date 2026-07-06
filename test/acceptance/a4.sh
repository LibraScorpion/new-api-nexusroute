#!/bin/bash
# A4 验收：上游模型清单+价格同步、admin 上下架、/v1/models 只见已上架且不泄露渠道
# 用法: BASE=http://localhost:3000 KEY=sk-xxx ADMIN_USER=root ADMIN_PASS=xxx bash a4.sh
BASE=${BASE:-http://localhost:3000}
KEY=${KEY:?need KEY=sk-...}
ADMIN_USER=${ADMIN_USER:-root}
ADMIN_PASS=${ADMIN_PASS:?need ADMIN_PASS}
JAR=$(mktemp)
FAIL=0
ALL="openai/gpt-4o-mini,anthropic/claude-sonnet-4.5,google/gemini-2.5-flash,deepseek/deepseek-chat,qwen/qwen3-32b"
FOUR="openai/gpt-4o-mini,anthropic/claude-sonnet-4.5,google/gemini-2.5-flash,deepseek/deepseek-chat"

admin() { # method path [data]
  curl -s -b "$JAR" -H 'content-type: application/json' -H 'New-Api-User: 1' -X "$1" "$BASE$2" ${3:+-d "$3"}
}

curl -s -c "$JAR" -X POST "$BASE/api/user/login" -H 'content-type: application/json' \
  -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" > /dev/null

# 1) 一键拉取上游模型清单
ids=$(admin GET /api/channel/fetch_models/1)
n=$(echo "$ids" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["data"]))' 2>/dev/null)
if [ "$n" = "5" ]; then echo "PASS  fetch_models 拉到 5 个模型"; else echo "FAIL  fetch_models => $(echo "$ids" | head -c 200)"; FAIL=1; fi

# 2) 拉取上游价格（OpenRouter 格式 pricing，endpoint 必须显式指定 openrouter）
ratios=$(admin POST /api/ratio_sync/fetch '{"upstreams":[{"id":1,"name":"mock-openrouter","base_url":"http://localhost:8100","endpoint":"openrouter"}],"timeout":10}')
# differences 只列与当前配置有差异的模型；能算出 upstreams 倍率即证明价格拉取+解析成功
if echo "$ratios" | grep -q '"upstreams":{"mock-openrouter'; then echo "PASS  ratio_sync 拉到上游价格并算出倍率"; else echo "FAIL  ratio_sync => $(echo "$ratios" | head -c 300)"; FAIL=1; fi

# 3) 下架 qwen（两渠道同时摘除）→ /v1/models 即时消失
admin PUT /api/channel/ "{\"id\":1,\"models\":\"$FOUR\"}" > /dev/null
admin PUT /api/channel/ "{\"id\":2,\"models\":\"$FOUR\"}" > /dev/null
if curl -s "$BASE/v1/models" -H "Authorization: Bearer $KEY" | grep -q 'qwen3-32b'; then
  echo "FAIL  下架后 /v1/models 仍含 qwen"; FAIL=1
else echo "PASS  下架 qwen 后 /v1/models 即时移除"; fi

# 4) 重新上架 → 即时恢复
admin PUT /api/channel/ "{\"id\":1,\"models\":\"$ALL\"}" > /dev/null
admin PUT /api/channel/ "{\"id\":2,\"models\":\"$ALL\"}" > /dev/null
if curl -s "$BASE/v1/models" -H "Authorization: Bearer $KEY" | grep -q 'qwen3-32b'; then
  echo "PASS  重新上架后 /v1/models 即时恢复"
else echo "FAIL  上架后未恢复"; FAIL=1; fi

# 5) 不泄露渠道：owned_by 不得出现渠道名
models=$(curl -s "$BASE/v1/models" -H "Authorization: Bearer $KEY")
if echo "$models" | grep -qiE '"owned_by":"(openrouter|siliconflow)"'; then
  echo "FAIL  owned_by 泄露渠道: $(echo "$models" | grep -oiE '"owned_by":"[^"]*"' | sort -u | tr '\n' ' ')"; FAIL=1
else
  echo "PASS  owned_by 无渠道泄露 ($(echo "$models" | grep -oE '"owned_by":"[^"]*"' | sort -u | tr '\n' ' '))"
fi

rm -f "$JAR"
[ $FAIL -eq 0 ] && echo "== A4 ALL PASS ==" || { echo "== A4 FAILED =="; exit 1; }
