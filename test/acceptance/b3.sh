#!/bin/bash
# B3 验收：流式 TTFT 分渠道记录 + 持续异常渠道自动禁用
# 用法: BASE=... KEY=sk-... ADMIN_PASS=... GATEWAY_LOG=path REPO_DIR=path bash b3.sh
BASE=${BASE:-http://localhost:3000}
KEY=${KEY:?need KEY=sk-...}
ADMIN_PASS=${ADMIN_PASS:?need ADMIN_PASS}
GATEWAY_LOG=${GATEWAY_LOG:?need GATEWAY_LOG}
REPO_DIR=${REPO_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}
JAR=$(mktemp); FAIL=0

curl -s -c "$JAR" -X POST "$BASE/api/user/login" -H 'content-type: application/json' \
  -d "{\"username\":\"root\",\"password\":\"$ADMIN_PASS\"}" > /dev/null
admin() { curl -s -b "$JAR" -H 'content-type: application/json' -H 'New-Api-User: 1' -X "$1" "$BASE$2" ${3:+-d "$3"}; }

# ---- 1) TTFT 分渠道记录：mock 注入 300ms 首字延迟，流式调用后日志 frt >= 300 ----
lsof -ti tcp:8100 -sTCP:LISTEN | xargs kill 2>/dev/null; sleep 0.5
(cd "$REPO_DIR" && TTFT_MS=300 node test/mockupstream/server.mjs > /dev/null 2>&1 &)
sleep 1
admin PUT /api/channel/ '{"id":1,"base_url":"http://localhost:8100","priority":10}' > /dev/null
admin POST /api/channel/1/status '{"status":1}' > /dev/null

curl -sN "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d '{"model":"google/gemini-2.5-flash","messages":[{"role":"user","content":"ttft"}],"stream":true}' > /dev/null
sleep 1
line=$(grep -a 'record consume log' "$GATEWAY_LOG" | grep -a '"channel_id":1' | grep -a '"is_stream":true' | tail -1)
frt=$(echo "$line" | grep -oE '"frt":[0-9]+' | grep -oE '[0-9]+')
if [ -n "$frt" ] && [ "$frt" -ge 300 ]; then
  echo "PASS  流式 TTFT 分渠道记录: channel_id=1 frt=${frt}ms（注入 300ms 延迟被如实记录）"
else
  echo "FAIL  TTFT 记录缺失或异常: frt='$frt' line=$(echo "$line" | head -c 200)"; FAIL=1
fi

# 恢复无延迟 mock
lsof -ti tcp:8100 -sTCP:LISTEN | xargs kill 2>/dev/null; sleep 0.5
(cd "$REPO_DIR" && node test/mockupstream/server.mjs > /dev/null 2>&1 &)
sleep 1

# ---- 2) 持续异常自动禁用：开启自动禁用，渠道1指向永远500的上游 ----
admin PUT /api/option/ '{"key":"AutomaticDisableChannelEnabled","value":"true"}' > /dev/null
admin PUT /api/option/ '{"key":"AutomaticDisableStatusCodes","value":"500-599"}' > /dev/null
admin PUT /api/channel/ '{"id":1,"base_url":"http://localhost:8101"}' > /dev/null   # 坏上游

r=$(curl -s "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d '{"model":"deepseek/deepseek-chat","messages":[{"role":"user","content":"ban"}]}')
sleep 1
st=$(admin GET /api/channel/1 | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["status"])')
if [ "$st" = "3" ]; then
  echo "PASS  异常渠道被自动禁用 (status=3 AutoDisabled)，请求仍 fallback 成功: $(echo "$r" | grep -oE 'mock@81[0-9]+')"
else
  echo "FAIL  期望渠道1 status=3，实际 status=$st"; FAIL=1
fi

# ---- 恢复现场（自动禁用开关关回，避免影响其他验收脚本） ----
admin PUT /api/option/ '{"key":"AutomaticDisableChannelEnabled","value":"false"}' > /dev/null
admin PUT /api/channel/ '{"id":1,"base_url":"http://localhost:8100"}' > /dev/null
admin POST /api/channel/1/status '{"status":1}' > /dev/null

rm -f "$JAR"
[ $FAIL -eq 0 ] && echo "== B3 ALL PASS ==" || { echo "== B3 FAILED =="; exit 1; }
