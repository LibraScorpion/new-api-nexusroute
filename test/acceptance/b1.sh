#!/bin/bash
# B1 验收：首选渠道故障 → 自动 fallback 备用渠道成功返回，日志可见切换记录
# 做法：渠道1(优先级10)指向永远500的mock:8101，渠道2(优先级5)指向正常mock:8102
# 用法: BASE=... KEY=sk-... ADMIN_PASS=... GATEWAY_LOG=path bash b1.sh
BASE=${BASE:-http://localhost:3000}
KEY=${KEY:?need KEY=sk-...}
ADMIN_PASS=${ADMIN_PASS:?need ADMIN_PASS}
GATEWAY_LOG=${GATEWAY_LOG:-}
JAR=$(mktemp); FAIL=0

curl -s -c "$JAR" -X POST "$BASE/api/user/login" -H 'content-type: application/json' \
  -d "{\"username\":\"root\",\"password\":\"$ADMIN_PASS\"}" > /dev/null
admin() { curl -s -b "$JAR" -H 'content-type: application/json' -H 'New-Api-User: 1' -X "$1" "$BASE$2" ${3:+-d "$3"}; }

admin PUT /api/option/ '{"key":"RetryTimes","value":"3"}' > /dev/null
admin PUT /api/channel/ '{"id":1,"base_url":"http://localhost:8101"}' > /dev/null   # 首选渠道 → 坏上游

marker="b1-$$"
r=$(curl -s "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
  -d "{\"model\":\"deepseek/deepseek-chat\",\"messages\":[{\"role\":\"user\",\"content\":\"$marker\"}]}")

if echo "$r" | grep -q 'mock@8102'; then
  echo "PASS  首选渠道故障，自动 fallback 到备用渠道成功返回 (mock@8102)"
else
  echo "FAIL  fallback => $(echo "$r" | head -c 300)"; FAIL=1
fi

# 日志切换记录：channel error + use_channel 链路（["1","2"] 表示先 1 失败再走 2）
if [ -n "$GATEWAY_LOG" ]; then
  if grep -a 'channel error (channel #1' "$GATEWAY_LOG" | tail -1 | grep -q . \
     && grep -aF '"use_channel":["1","2"]' "$GATEWAY_LOG" | tail -1 | grep -q .; then
    echo "PASS  日志可见切换记录:"
    grep -a 'channel error (channel #1' "$GATEWAY_LOG" | tail -1 | cut -c1-140 | sed 's/^/      /'
  else
    echo "FAIL  日志无切换记录"; FAIL=1
  fi
fi

admin PUT /api/channel/ '{"id":1,"base_url":"http://localhost:8100"}' > /dev/null   # 恢复
rm -f "$JAR"
[ $FAIL -eq 0 ] && echo "== B1 ALL PASS ==" || { echo "== B1 FAILED =="; exit 1; }
