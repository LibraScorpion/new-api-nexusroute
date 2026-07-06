#!/bin/bash
# A5 验收：统一入参 + 模型×参数映射（渠道 param_override 配置数据，非硬编码）
# 前置：渠道 1 已配 operations（openai/* 删 top_k；openai/* 带 reasoning 明确报错）
# 用法: BASE=http://localhost:3000 KEY=sk-xxx bash a5.sh
BASE=${BASE:-http://localhost:3000}
KEY=${KEY:?need KEY=sk-...}
FAIL=0
UNIFIED='"temperature":0.7,"top_p":0.9,"top_k":40,"max_tokens":100'

call() { # model extra_json -> content 或 error message
  curl -s "$BASE/v1/chat/completions" -H "Authorization: Bearer $KEY" -H 'content-type: application/json' \
    -d "{\"model\":\"$1\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],$2}"
}

# 1) 同一组统一入参 → openai 模型：top_k 被映射表删除，请求不失败
r=$(call openai/gpt-4o-mini "$UNIFIED")
if echo "$r" | grep -q 'params=\[' && ! echo "$r" | grep -q 'top_k'; then
  echo "PASS  openai/* 收到请求且 top_k 已被丢弃: $(echo "$r" | grep -oE 'params=\[[^]]*\]')"
else
  echo "FAIL  openai/* => $(echo "$r" | head -c 250)"; FAIL=1
fi

# 2) 同一组统一入参 → qwen 模型：top_k 原样透传
r=$(call qwen/qwen3-32b "$UNIFIED")
if echo "$r" | grep -q 'top_k'; then
  echo "PASS  qwen/* top_k 原样透传: $(echo "$r" | grep -oE 'params=\[[^]]*\]')"
else
  echo "FAIL  qwen/* => $(echo "$r" | head -c 250)"; FAIL=1
fi

# 3) 不支持参数的另一种可配行为：明确报错（openai/* + reasoning）
r=$(call openai/gpt-4o-mini "$UNIFIED,\"reasoning\":{\"effort\":\"high\"}")
if echo "$r" | grep -q 'reasoning 不支持'; then
  echo "PASS  openai/* + reasoning 明确报错（消息可读）"
else
  echo "FAIL  期望明确报错 => $(echo "$r" | head -c 250)"; FAIL=1
fi

# 4) 同参数发给支持的模型：不受影响
r=$(call qwen/qwen3-32b "$UNIFIED,\"reasoning\":{\"effort\":\"high\"}")
if echo "$r" | grep -q 'reasoning'; then
  echo "PASS  qwen/* reasoning 正常透传"
else
  echo "FAIL  qwen/* reasoning => $(echo "$r" | head -c 250)"; FAIL=1
fi

[ $FAIL -eq 0 ] && echo "== A5 ALL PASS ==" || { echo "== A5 FAILED =="; exit 1; }
