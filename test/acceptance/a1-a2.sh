#!/bin/bash
# A1/A2 验收：5 个模型经网关调通，非流式 + 流式（SSE）
# 用法: BASE=http://localhost:3000 KEY=sk-xxx bash a1-a2.sh
BASE=${BASE:-http://localhost:3000}
KEY=${KEY:?need KEY=sk-...}
MODELS=("openai/gpt-4o-mini" "anthropic/claude-sonnet-4.5" "google/gemini-2.5-flash" "deepseek/deepseek-chat" "qwen/qwen3-32b")
FAIL=0

for m in "${MODELS[@]}"; do
  # 非流式
  resp=$(curl -s "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
    -d "{\"model\":\"$m\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}")
  if echo "$resp" | grep -q '"finish_reason":"stop"'; then
    echo "PASS  non-stream  $m"
  else
    echo "FAIL  non-stream  $m  => $(echo "$resp" | head -c 200)"; FAIL=1
  fi
  # 流式：要求有 chunk 且以 [DONE] 结束
  sse=$(curl -sN "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
    -d "{\"model\":\"$m\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"stream\":true}")
  chunks=$(echo "$sse" | grep -c '^data: {')
  if [ "$chunks" -ge 2 ] && echo "$sse" | grep -q 'data: \[DONE\]'; then
    echo "PASS  stream($chunks chunks)  $m"
  else
    echo "FAIL  stream  $m  => $(echo "$sse" | head -c 200)"; FAIL=1
  fi
done

[ $FAIL -eq 0 ] && echo "== A1/A2 ALL PASS ==" || { echo "== A1/A2 FAILED =="; exit 1; }
