#!/bin/bash
# A1-A4 真实上游复验：用真实 OpenRouter Key 走一遍 模型同步/双格式调用/流式/计费
# 用法: OPENROUTER_KEY=sk-or-v1-... KEY=sk-... ADMIN_PASS=... bash real-upstream.sh
# Key 只走环境变量与渠道配置（落库加密），不写入任何文件
BASE=${BASE:-http://localhost:3000}
KEY=${KEY:?need KEY=sk-...(网关用户 Key)}
ADMIN_PASS=${ADMIN_PASS:?need ADMIN_PASS}
OPENROUTER_KEY=${OPENROUTER_KEY:?need OPENROUTER_KEY=sk-or-v1-...}
MODELS="openai/gpt-4o-mini,deepseek/deepseek-chat,qwen/qwen3-32b,google/gemini-2.5-flash,anthropic/claude-sonnet-4.5"
JAR=$(mktemp); FAIL=0

curl -s -c "$JAR" -X POST "$BASE/api/user/login" -H 'content-type: application/json' \
  -d "{\"username\":\"root\",\"password\":\"$ADMIN_PASS\"}" > /dev/null
admin() { curl -s -b "$JAR" -H 'content-type: application/json' -H 'New-Api-User: 1' -X "$1" "$BASE$2" ${3:+-d "$3"}; }

# ---------- A4 复验: 从真实上游拉取模型列表（admin 渠道页「获取模型」同一接口） ----------
n=$(admin POST /api/channel/fetch_models "{\"type\":20,\"base_url\":\"\",\"key\":\"$OPENROUTER_KEY\"}" \
  | python3 -c 'import json,sys;d=json.load(sys.stdin);print(len(d["data"]) if d.get("success") else 0)')
[ "$n" -gt 100 ] && echo "PASS  A4 真实上游 fetch_models 拉到 $n 个模型" || { echo "FAIL  A4 fetch_models n=$n"; FAIL=1; }

# ---------- 建/复用真实渠道（base_url 留空=官方 https://openrouter.ai/api），priority 100 压过 mock ----------
CID=$(admin GET '/api/channel/search?keyword=openrouter-real' | python3 -c 'import json,sys;d=json.load(sys.stdin)["data"];items=d["items"] if isinstance(d,dict) else d;print(items[0]["id"] if items else "")')
if [ -z "$CID" ]; then
  admin POST /api/channel/ "{\"mode\":\"single\",\"channel\":{\"type\":20,\"name\":\"openrouter-real\",\"key\":\"$OPENROUTER_KEY\",\"base_url\":\"\",\"models\":\"$MODELS\",\"group\":\"default\",\"priority\":100}}" > /dev/null
  CID=$(admin GET '/api/channel/search?keyword=openrouter-real' | python3 -c 'import json,sys;d=json.load(sys.stdin)["data"];items=d["items"] if isinstance(d,dict) else d;print(items[0]["id"])')
else
  admin PUT /api/channel/ "{\"id\":$CID,\"key\":\"$OPENROUTER_KEY\",\"priority\":100}" > /dev/null
fi
admin POST /api/channel/$CID/status '{"status":1}' > /dev/null   # PUT /api/channel/ 会忽略 status 字段，必须走 :id/status
echo "INFO  真实渠道 id=$CID 已启用 (priority 100)"

# ---------- A1/A2 复验: 非流式 + 流式，5 模型真实调用（max_tokens 限 24 控成本） ----------
for m in openai/gpt-4o-mini deepseek/deepseek-chat qwen/qwen3-32b google/gemini-2.5-flash anthropic/claude-sonnet-4.5; do
  r=$(curl -s --max-time 60 "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
    -d "{\"model\":\"$m\",\"messages\":[{\"role\":\"user\",\"content\":\"只回复两个字:收到\"}],\"max_tokens\":24}")
  # 验收点=网关正确转发且回真实 usage；推理模型可能 content 空、只有 reasoning（模型行为，不算网关失败）
  c=$(echo "$r" | python3 -c 'import json,sys
try:
  d=json.load(sys.stdin); m=d["choices"][0]["message"]
  txt=(m.get("content") or "").strip() or ("[仅reasoning]" if m.get("reasoning") else "")
  assert d["usage"]["total_tokens"]>0
  print(txt[:20].replace("\n"," "),"| tokens:",d["usage"]["total_tokens"])
except Exception: print("")')
  [ -n "$c" ] && echo "PASS  A1 非流式 $m => $c" || { echo "FAIL  A1 $m => $(echo "$r"|head -c 160)"; FAIL=1; }
done
s=$(curl -sN --max-time 60 "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d '{"model":"openai/gpt-4o-mini","messages":[{"role":"user","content":"只回复两个字:收到"}],"stream":true,"max_tokens":24}')
echo "$s" | grep -q '^data: ' && echo "$s" | grep -q 'data: \[DONE\]' \
  && echo "PASS  A2 流式 SSE 分片+DONE (openai/gpt-4o-mini)" || { echo "FAIL  A2 流式 => $(echo "$s"|head -c 160)"; FAIL=1; }

# ---------- A3 复验: Anthropic /v1/messages 格式打到真实上游 ----------
r=$(curl -s --max-time 60 "$BASE/v1/messages" -H "x-api-key: $KEY" -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' \
  -d '{"model":"anthropic/claude-sonnet-4.5","max_tokens":24,"messages":[{"role":"user","content":"只回复两个字:收到"}]}')
echo "$r" | grep -q '"type":"message"' && echo "PASS  A3 /v1/messages 真实上游 => $(echo "$r" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["content"][0]["text"][:20])' 2>/dev/null)" \
  || { echo "FAIL  A3 => $(echo "$r"|head -c 160)"; FAIL=1; }

# ---------- 计费复验: 消费日志按真实 usage 入账且走了真实渠道 ----------
sleep 1
admin GET '/api/log/self?p=1&page_size=8&type=2' | python3 -c "
import json,sys
items=json.load(sys.stdin)['data']['items']
real=[i for i in items if i.get('channel')==$CID]
assert real, 'no logs on real channel'
i=real[0]
assert i['prompt_tokens']>0 and i['quota']>0, i
print(f\"PASS  计费复验 真实 usage 入账: {i['model_name']} prompt={i['prompt_tokens']} completion={i['completion_tokens']} quota={i['quota']} (channel $CID)\")
" || { echo "FAIL  计费复验"; FAIL=1; }

# ---------- 收尾: 禁用真实渠道，保住 mock 回归环境 ----------
admin POST /api/channel/$CID/status '{"status":2}' > /dev/null
st=$(admin GET /api/channel/$CID | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["status"])')
[ "$st" = "2" ] && echo "INFO  真实渠道已禁用（回归环境恢复 mock；复验时在 admin 渠道页一键启用）" || { echo "FAIL  真实渠道未禁用 status=$st"; FAIL=1; }

rm -f "$JAR"
[ $FAIL -eq 0 ] && echo "== REAL-UPSTREAM ALL PASS ==" || { echo "== REAL-UPSTREAM FAILED =="; exit 1; }
