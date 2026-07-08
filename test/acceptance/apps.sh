#!/bin/bash
# Apps 排行验收（OpenRouter 归因规范 openrouter.ai/docs/app-attribution）：
#   HTTP-Referer 必填（域名=标识）；X-OpenRouter-Title/X-Title 显示名；
#   localhost 必须带 title；X-OpenRouter-Categories 过滤入分类榜
# 用法: BASE=... KEY=sk-... bash apps.sh
BASE=${BASE:-http://localhost:3000}
KEY=${KEY:?need KEY=sk-...}
FAIL=0
TAG=$$
call() { curl -s -o /dev/null "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" \
  -H 'content-type: application/json' "$@" \
  -d '{"model":"openai/gpt-4o-mini","messages":[{"role":"user","content":"hi"}],"max_tokens":16}'; }

# 1) 完整归因：域名标识 + 显示名 + 分类（bogus 应被忽略、只取前 2 个合法值）
call -H "HTTP-Referer: https://cline-$TAG.example.com/path" -H "X-OpenRouter-Title: Cline E2E" \
     -H "X-OpenRouter-Categories: bogus,cli-agent,ide-extension,game"
call -H "HTTP-Referer: https://cline-$TAG.example.com/" -H "X-OpenRouter-Title: Cline E2E"
# 2) 只有 X-Title 没有 Referer → 不归因
call -H "X-Title: NoReferer-$TAG"
# 3) localhost 无 title → 不归因；带 title → 以 title 为标识
call -H "HTTP-Referer: http://localhost:5173"
call -H "HTTP-Referer: http://localhost:5173" -H "X-Title: LocalDev-$TAG"
sleep 1

curl -s "$BASE/api/apps/rankings" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['success'], d
apps = {a['app']: a for a in (d['data']['most_popular'] or [])}

me = apps.get('cline-$TAG.example.com')
assert me and me['requests'] == 2 and me['tokens'] > 0, ('domain attribution', me)
assert me['title'] == 'Cline E2E', me
assert me['categories'] == ['cli-agent', 'ide-extension'], ('category filter', me['categories'])
assert me['url'] == 'https://cline-$TAG.example.com', me['url']

assert 'NoReferer-$TAG' not in apps, 'X-Title alone must not attribute'
assert 'localhost' not in apps, 'bare localhost must not attribute'
assert apps.get('LocalDev-$TAG', {}).get('requests') == 1, 'localhost+title keys by title'

coding = {a['app'] for a in (d['data']['top_categories'] or {}).get('coding', [])}
assert 'cline-$TAG.example.com' in coding, 'coding category ranking'
tr = {a['app'] for a in (d['data']['trending'] or [])}
assert 'cline-$TAG.example.com' in tr, 'trending'
print('PASS  Apps 归因规范: 域名标识/显示名/分类过滤/无Referer不归因/localhost规则/分类榜/Trending 全通过')
" || { echo "FAIL  Apps 排行"; FAIL=1; }

[ $FAIL -eq 0 ] && echo "== APPS ALL PASS ==" || { echo "== APPS FAILED =="; exit 1; }
