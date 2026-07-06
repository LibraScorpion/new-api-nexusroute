#!/bin/bash
# F1 验收：Quickstart 文档存在且示例可直接复制运行
# G 节验收：G1 渠道增删改/单价配置即时生效（上下架见 a4.sh）；G2 用户管理（查/封禁/调额度/看用量）
BASE=${BASE:-http://localhost:3000}
KEY=${KEY:?need KEY=sk-...}
ADMIN_PASS=${ADMIN_PASS:?need ADMIN_PASS}
REPO_DIR=${REPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}
JAR=$(mktemp); FAIL=0

curl -s -c "$JAR" -X POST "$BASE/api/user/login" -H 'content-type: application/json' \
  -d "{\"username\":\"root\",\"password\":\"$ADMIN_PASS\"}" > /dev/null
admin() { curl -s -b "$JAR" -H 'content-type: application/json' -H 'New-Api-User: 1' -X "$1" "$BASE$2" ${3:+-d "$3"}; }

# ---------- F1: 文档存在 + 两种格式示例照抄可跑 ----------
DOC="$REPO_DIR/docs/QUICKSTART.md"
grep -q '/v1/chat/completions' "$DOC" && grep -q '/v1/messages' "$DOC" && grep -q '注册' "$DOC" \
  && echo "PASS  F1 Quickstart 覆盖 注册→建Key→双格式调用" || { echo "FAIL  F1 文档内容"; FAIL=1; }

# 按文档原样执行（仅替换 Key 与 BASE_URL 环境变量）
export NEWAPI_KEY=$KEY BASE_URL=$BASE
r=$(curl -s $BASE_URL/v1/chat/completions -H "Authorization: Bearer $NEWAPI_KEY" -H "Content-Type: application/json" \
  -d '{"model": "deepseek/deepseek-chat", "messages": [{"role": "user", "content": "你好"}]}')
echo "$r" | grep -q 'mock@' && echo "PASS  F1 OpenAI 示例照抄可跑" || { echo "FAIL  F1 openai => $(echo "$r"|head -c 120)"; FAIL=1; }
r=$(curl -s $BASE_URL/v1/messages -H "x-api-key: $NEWAPI_KEY" -H "anthropic-version: 2023-06-01" -H "Content-Type: application/json" \
  -d '{"model": "anthropic/claude-sonnet-4.5", "max_tokens": 1024, "messages": [{"role": "user", "content": "你好"}]}')
echo "$r" | grep -q '"type":"message"' && echo "PASS  F1 Anthropic 示例照抄可跑" || { echo "FAIL  F1 anthropic => $(echo "$r"|head -c 120)"; FAIL=1; }

# ---------- G1: 渠道增删改 + 单价配置即时生效（无重启） ----------
CID=$(admin POST /api/channel/ '{"mode":"single","channel":{"type":1,"name":"g1-temp","key":"sk-g1","base_url":"http://localhost:8100","models":"qwen/qwen3-32b","group":"default","priority":1}}' > /dev/null; \
  admin GET '/api/channel/search?keyword=g1-temp' | python3 -c 'import json,sys;d=json.load(sys.stdin)["data"];items=d["items"] if isinstance(d,dict) else d;print(items[0]["id"])')
[ -n "$CID" ] && echo "PASS  G1 渠道新增 (id=$CID)"
admin PUT /api/channel/ "{\"id\":$CID,\"name\":\"g1-temp-renamed\"}" > /dev/null
admin GET /api/channel/$CID | grep -q 'g1-temp-renamed' && echo "PASS  G1 渠道修改即时生效" || { echo "FAIL  G1 改名"; FAIL=1; }
admin DELETE /api/channel/$CID > /dev/null
admin GET /api/channel/$CID | grep -q '"success":false' && echo "PASS  G1 渠道删除" || { echo "FAIL  G1 删除"; FAIL=1; }

# 单价翻倍 → 同一调用扣费从 2 变 4，全程无重启
MR_HI='{"key":"ModelRatio","value":"{\"openai/gpt-4o-mini\":0.075,\"anthropic/claude-sonnet-4.5\":1.5,\"google/gemini-2.5-flash\":0.15,\"deepseek/deepseek-chat\":0.135,\"qwen/qwen3-32b\":0.1}"}'
MR_LO='{"key":"ModelRatio","value":"{\"openai/gpt-4o-mini\":0.075,\"anthropic/claude-sonnet-4.5\":1.5,\"google/gemini-2.5-flash\":0.15,\"deepseek/deepseek-chat\":0.135,\"qwen/qwen3-32b\":0.05}"}'
admin PUT /api/option/ "$MR_HI" > /dev/null
curl -s "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d '{"model":"qwen/qwen3-32b","messages":[{"role":"user","content":"price"}]}' > /dev/null
sleep 1
q=$(admin GET '/api/log/self?p=1&page_size=3&type=2' | python3 -c 'import json,sys;print([i["quota"] for i in json.load(sys.stdin)["data"]["items"] if "qwen" in i["model_name"]][0])')
[ "$q" = "4" ] && echo "PASS  G1 单价改 0.05→0.1，扣费 2→4 即时生效（无重启）" || { echo "FAIL  G1 调价后 quota=$q（期望 4）"; FAIL=1; }
admin PUT /api/option/ "$MR_LO" > /dev/null

# ---------- G2: 用户管理 ----------
GU="gu$$"
curl -s -X POST "$BASE/api/user/register" -H 'content-type: application/json' \
  -d "{\"username\":\"$GU\",\"password\":\"Gu@2026xxx\",\"password2\":\"Gu@2026xxx\"}" > /dev/null
GUID=$(admin GET "/api/user/search?keyword=$GU" | python3 -c 'import json,sys;d=json.load(sys.stdin)["data"];items=d["items"] if isinstance(d,dict) else d;print(items[0]["id"])')
[ -n "$GUID" ] && echo "PASS  G2 查用户 (id=$GUID)" || { echo "FAIL  G2 查用户"; FAIL=1; }
admin POST /api/user/manage "{\"id\":$GUID,\"action\":\"add_quota\",\"mode\":\"add\",\"value\":12345}" > /dev/null
q=$(admin GET /api/user/$GUID | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["quota"])')
[ "$q" = "12345" ] && echo "PASS  G2 调额度精确生效" || { echo "FAIL  G2 quota=$q"; FAIL=1; }
admin POST /api/user/manage "{\"id\":$GUID,\"action\":\"disable\"}" > /dev/null
r=$(curl -s -X POST "$BASE/api/user/login" -H 'content-type: application/json' -d "{\"username\":\"$GU\",\"password\":\"Gu@2026xxx\"}")
echo "$r" | grep -q '"success":false' && echo "PASS  G2 封禁后登录被拒" || { echo "FAIL  G2 封禁 => $(echo "$r"|head -c 120)"; FAIL=1; }
u=$(admin GET '/api/log/?p=1&page_size=5&type=2' | python3 -c 'import json,sys;items=json.load(sys.stdin)["data"]["items"];print("ok" if items and all("username" in i for i in items) else "no")')
[ "$u" = "ok" ] && echo "PASS  G2 admin 看全站用量明细（含用户名维度）" || { echo "FAIL  G2 用量"; FAIL=1; }

rm -f "$JAR"
[ $FAIL -eq 0 ] && echo "== F1/G ALL PASS ==" || { echo "== F1/G FAILED =="; exit 1; }
