#!/bin/bash
# B2 验收：同一模型多渠道，按优先级/权重选路，策略 admin 可配（改配置即改路由，无需重启）
# 用法: BASE=... KEY=sk-... ADMIN_PASS=... bash b2.sh
BASE=${BASE:-http://localhost:3000}
KEY=${KEY:?need KEY=sk-...}
ADMIN_PASS=${ADMIN_PASS:?need ADMIN_PASS}
JAR=$(mktemp); FAIL=0

curl -s -c "$JAR" -X POST "$BASE/api/user/login" -H 'content-type: application/json' \
  -d "{\"username\":\"root\",\"password\":\"$ADMIN_PASS\"}" > /dev/null
admin() { curl -s -b "$JAR" -H 'content-type: application/json' -H 'New-Api-User: 1' -X "$1" "$BASE$2" ${3:+-d "$3"}; }
call() {
  curl -s "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
    -d '{"model":"deepseek/deepseek-chat","messages":[{"role":"user","content":"route"}]}' | grep -oE 'mock@81[0-9]+'
}

# 前置：两渠道均健康（ch1→8100, ch2→8102）
admin PUT /api/channel/ '{"id":1,"base_url":"http://localhost:8100"}' > /dev/null
admin POST /api/channel/1/status '{"status":1}' > /dev/null

# 1) ch2 优先级更高 → 流量走 ch2
admin PUT /api/channel/ '{"id":1,"priority":5}' > /dev/null
admin PUT /api/channel/ '{"id":2,"priority":10}' > /dev/null
r1=$(call); r2=$(call)
if [ "$r1" = "mock@8102" ] && [ "$r2" = "mock@8102" ]; then
  echo "PASS  ch2 优先级高 → 连续请求均走 ch2 ($r1)"
else echo "FAIL  期望 mock@8102，得到 $r1 $r2"; FAIL=1; fi

# 2) 翻转优先级 → 流量即时切回 ch1（无需重启）
admin PUT /api/channel/ '{"id":1,"priority":10}' > /dev/null
admin PUT /api/channel/ '{"id":2,"priority":5}' > /dev/null
r1=$(call); r2=$(call)
if [ "$r1" = "mock@8100" ] && [ "$r2" = "mock@8100" ]; then
  echo "PASS  翻转优先级 → 流量即时切回 ch1 ($r1)"
else echo "FAIL  期望 mock@8100，得到 $r1 $r2"; FAIL=1; fi

# 3) 权重参数 admin 可配（同优先级内加权随机的配置面）
admin PUT /api/channel/ '{"id":1,"weight":7}' > /dev/null
w=$(admin GET /api/channel/1 | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["weight"])')
if [ "$w" = "7" ]; then echo "PASS  权重可配并生效读回 (weight=7)"; else echo "FAIL  weight=$w"; FAIL=1; fi

rm -f "$JAR"
[ $FAIL -eq 0 ] && echo "== B2 ALL PASS ==" || { echo "== B2 FAILED =="; exit 1; }
