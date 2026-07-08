#!/bin/bash
# Apps 页验收：X-Title 归因入账 → /api/apps/rankings 聚合返回 → 无标题请求不产生空条目
# 用法: BASE=... KEY=sk-... bash apps.sh
BASE=${BASE:-http://localhost:3000}
KEY=${KEY:?need KEY=sk-...}
FAIL=0
APP="AcceptApp-$$"

for i in 1 2; do
  curl -s -o /dev/null "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" \
    -H 'content-type: application/json' -H "X-Title: $APP" \
    -d '{"model":"openai/gpt-4o-mini","messages":[{"role":"user","content":"hi"}],"max_tokens":16}'
done
curl -s -o /dev/null "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" \
  -H 'content-type: application/json' \
  -d '{"model":"openai/gpt-4o-mini","messages":[{"role":"user","content":"hi"}],"max_tokens":16}'
sleep 1

curl -s "$BASE/api/apps/rankings" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['success'], d
apps = {a['app']: a for a in (d['data']['most_popular'] or [])}
me = apps.get('$APP')
assert me and me['tokens'] > 0 and me['requests'] == 2, ('attribution missing', me)
assert '' not in apps, 'empty-title requests must not rank'
tr = {a['app'] for a in d['data']['trending']}
assert '$APP' in tr, 'trending missing new app'
print(f\"PASS  Apps 归因+排行: $APP requests={me['requests']} tokens={me['tokens']} (trending 含新应用, 空标题不入榜)\")
" || { echo "FAIL  Apps 排行"; FAIL=1; }

[ $FAIL -eq 0 ] && echo "== APPS ALL PASS ==" || { echo "== APPS FAILED =="; exit 1; }
