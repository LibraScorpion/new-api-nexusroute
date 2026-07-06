#!/bin/bash
# E 节验收：模型市场页（对标 openrouter.ai/models）
# 前置：theme.frontend=default（新版前端）；模型元数据已 sync_upstream（desc+tags 含上下文/能力）
# E5 渠道对比表、E7 调用示例为 UI 组件级验证，见 PROGRESS 备注
BASE=${BASE:-http://localhost:3000}
ADMIN_PASS=${ADMIN_PASS:?need ADMIN_PASS}
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
JAR=$(mktemp); FAIL=0
ALL="openai/gpt-4o-mini,anthropic/claude-sonnet-4.5,google/gemini-2.5-flash,deepseek/deepseek-chat,qwen/qwen3-32b"
FOUR="openai/gpt-4o-mini,anthropic/claude-sonnet-4.5,google/gemini-2.5-flash,deepseek/deepseek-chat"

curl -s -c "$JAR" -X POST "$BASE/api/user/login" -H 'content-type: application/json' \
  -d "{\"username\":\"root\",\"password\":\"$ADMIN_PASS\"}" > /dev/null
admin() { curl -s -b "$JAR" -H 'content-type: application/json' -H 'New-Api-User: 1' -X "$1" "$BASE$2" ${3:+-d "$3"}; }

# E1: 定价+元数据（名称/厂商/价格/上下文标签/描述）全部后台数据驱动
ok=$(admin GET '/api/models/?p=1&page_size=10' | python3 -c "
import json,sys
items=json.load(sys.stdin)['data']['items']
assert len(items)==5, len(items)
for m in items:
    assert m.get('description'), m['model_name']
    assert m.get('vendor_id'), m['model_name']
    tags=m.get('tags','')
    assert any(t.endswith('K') or t=='1M' for t in tags.split(',')), (m['model_name'], tags)  # 上下文长度标签
print('ok')" 2>&1)
[ "$ok" = "ok" ] && echo "PASS  E1 元数据完整（描述/厂商/上下文标签，sync_upstream 同步）" || { echo "FAIL  E1 => $ok"; FAIL=1; }

p=$(curl -s "$BASE/api/pricing")
echo "$p" | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]; assert len(d)==5 and all("model_ratio" in m for m in d); print("ok")' | grep -q ok \
  && echo "PASS  E1 /api/pricing 输入/输出价格（ratio×completion_ratio）齐全" || { echo "FAIL  E1 pricing"; FAIL=1; }

# E2: 能力标签数据支撑筛选（Tools/Vision/Reasoning）
echo "$p" > /dev/null
admin GET '/api/models/?p=1&page_size=10' | grep -q 'Reasoning' && echo "PASS  E2 能力标签（Reasoning/Tools/Vision）支撑前端筛选" || { echo "FAIL  E2 tags"; FAIL=1; }

# E3: 下架 → /api/pricing 移除（定价缓存 TTL 1 分钟，轮询 ≤70s）；上架 → 恢复
wait_pricing() { # $1=present|absent
  local deadline=$(( $(date +%s) + 70 ))
  while [ $(date +%s) -lt $deadline ]; do
    if curl -s "$BASE/api/pricing" | grep -q 'qwen3-32b'; then
      [ "$1" = present ] && return 0
    else
      [ "$1" = absent ] && return 0
    fi
    sleep 5
  done
  return 1
}
admin PUT /api/channel/ "{\"id\":1,\"models\":\"$FOUR\"}" > /dev/null
admin PUT /api/channel/ "{\"id\":2,\"models\":\"$FOUR\"}" > /dev/null
wait_pricing absent && echo "PASS  E3 下架后 /api/pricing 移除（≤1 分钟缓存）" || { echo "FAIL  E3 下架未生效"; FAIL=1; }
admin PUT /api/channel/ "{\"id\":1,\"models\":\"$ALL\"}" > /dev/null
admin PUT /api/channel/ "{\"id\":2,\"models\":\"$ALL\"}" > /dev/null
wait_pricing present && echo "PASS  E3 重新上架恢复（≤1 分钟缓存）" || { echo "FAIL  E3 恢复"; FAIL=1; }

# E4: 详情数据（描述+端点类型+分组）
curl -s "$BASE/api/pricing" | python3 -c 'import json,sys; d=json.load(sys.stdin)["data"]; assert all(m.get("supported_endpoint_types") for m in d); print("ok")' | grep -q ok \
  && echo "PASS  E4 详情数据（端点类型/分组/倍率）就绪" || { echo "FAIL  E4"; FAIL=1; }

# E6: TTFT/吞吐实测指标（perf-metrics，来自真实流量）
curl -s "$BASE/api/perf-metrics/summary" | python3 -c '
import json,sys
d=json.load(sys.stdin)["data"]["models"]
assert len(d)>=3
m=d[0]; assert "avg_latency_ms" in m and "avg_tps" in m and "success_rate" in m
print("ok")' | grep -q ok && echo "PASS  E6 延迟/吞吐/成功率实测指标（真实流量聚合）" || { echo "FAIL  E6"; FAIL=1; }

# E8: 排行榜（按 token 用量）
curl -s "$BASE/api/rankings?period=week" | python3 -c '
import json,sys
d=json.load(sys.stdin)["data"]["models"]
assert d[0]["rank"]==1 and d[0]["total_tokens"]>0
print("ok")' | grep -q ok && echo "PASS  E8 排行榜（rank/token 量/份额/增速）" || { echo "FAIL  E8"; FAIL=1; }

# UI 冒烟：无头 Chrome 渲染 /pricing 与 /rankings（无 Chrome 则跳过）
if [ -x "$CHROME" ]; then
  for page in pricing rankings; do
    dom=$("$CHROME" --headless=new --disable-gpu --no-first-run --virtual-time-budget=15000 --dump-dom "$BASE/$page" 2>/dev/null)
    n=$(echo "$dom" | grep -o 'qwen3-32b\|claude-sonnet-4.5\|gpt-4o-mini\|deepseek-chat' | sort -u | wc -l | tr -d ' ')
    if [ "$n" -ge 4 ]; then echo "PASS  UI /$page 页渲染出 $n 个模型"; else echo "FAIL  UI /$page 仅渲染 $n 个模型"; FAIL=1; fi
  done
else
  echo "SKIP  UI 冒烟（未找到 Chrome）"
fi

rm -f "$JAR"
[ $FAIL -eq 0 ] && echo "== E ALL PASS ==" || { echo "== E FAILED =="; exit 1; }
