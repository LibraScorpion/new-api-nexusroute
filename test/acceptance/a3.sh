#!/bin/bash
# A3 验收：Anthropic /v1/messages 格式（非流式 + 流式），上游为 OpenAI 兼容渠道 → 证明双格式共用一渠道
BASE=${BASE:-http://localhost:3000}
KEY=${KEY:?need KEY=sk-...}
M="anthropic/claude-sonnet-4.5"
FAIL=0

resp=$(curl -s "$BASE/v1/messages" -H "x-api-key: $KEY" -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' \
  -d "{\"model\":\"$M\",\"max_tokens\":100,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}")
if echo "$resp" | grep -q '"type":"message"' && echo "$resp" | grep -q '"stop_reason"'; then
  echo "PASS  /v1/messages non-stream ($M)"
else
  echo "FAIL  /v1/messages non-stream => $(echo "$resp" | head -c 200)"; FAIL=1
fi

sse=$(curl -sN "$BASE/v1/messages" -H "x-api-key: $KEY" -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' \
  -d "{\"model\":\"$M\",\"max_tokens\":100,\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"stream\":true}")
if echo "$sse" | grep -q 'message_start' && echo "$sse" | grep -q 'message_stop'; then
  echo "PASS  /v1/messages stream (anthropic SSE events)"
else
  echo "FAIL  /v1/messages stream => $(echo "$sse" | head -c 300)"; FAIL=1
fi

[ $FAIL -eq 0 ] && echo "== A3 ALL PASS ==" || { echo "== A3 FAILED =="; exit 1; }
