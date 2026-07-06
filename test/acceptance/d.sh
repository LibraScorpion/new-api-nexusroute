#!/bin/bash
# D 节验收：D1 计费分毫不差 + 账单明细；D2 预充值（公对公人工入账=兑换码流）；D3 用量看板
# 前置：DataExportInterval 已设为 1（分钟），mock 上游 usage 固定 12/8
# 计费公式：quota = (prompt + completion×completion_ratio) × model_ratio × group_ratio(默认1)，向上取整
#   qwen   (ratio 0.05, cr 3):   (12 + 8×3)  × 0.05 = 1.8 → 2
#   claude (ratio 1.5,  cr 5):   (12 + 8×5)  × 1.5  = 78  → 78（整数无舍入，纯公式）
BASE=${BASE:-http://localhost:3000}
ADMIN_PASS=${ADMIN_PASS:?need ADMIN_PASS}
JAR=$(mktemp); FAIL=0

curl -s -c "$JAR" -X POST "$BASE/api/user/login" -H 'content-type: application/json' \
  -d "{\"username\":\"root\",\"password\":\"$ADMIN_PASS\"}" > /dev/null
rootapi() { curl -s -b "$JAR" -H 'content-type: application/json' -H 'New-Api-User: 1' -X "$1" "$BASE$2" ${3:+-d "$3"}; }
py() { python3 -c "$1"; }

# ---------- D1: 按 token 计费，扣减与公式分毫不差 ----------
rootapi POST /api/token/ "{\"name\":\"bill-$$\",\"remain_quota\":1000000,\"unlimited_quota\":false,\"expired_time\":-1}" > /dev/null
TID=$(rootapi GET '/api/token/?p=1&size=10' | py "import json,sys;d=json.load(sys.stdin)['data']['items'];print([t['id'] for t in d if t['name']=='bill-$$'][0])")
BK=sk-$(rootapi POST /api/token/$TID/key | py 'import json,sys;print(json.load(sys.stdin)["data"]["key"])')
Q0=$(rootapi GET /api/token/$TID | py 'import json,sys;print(json.load(sys.stdin)["data"]["remain_quota"])')

for m in 'qwen/qwen3-32b' 'anthropic/claude-sonnet-4.5'; do
  curl -s "$BASE/v1/chat/completions" -H "Authorization: Bearer $BK" -H 'content-type: application/json' \
    -d "{\"model\":\"$m\",\"messages\":[{\"role\":\"user\",\"content\":\"bill\"}]}" > /dev/null
done
sleep 1
Q1=$(rootapi GET /api/token/$TID | py 'import json,sys;print(json.load(sys.stdin)["data"]["remain_quota"])')
DELTA=$((Q0 - Q1))
if [ "$DELTA" = "80" ]; then
  echo "PASS  D1 余额扣减与公式分毫不差：qwen 2 + claude 78 = 80（实扣 $DELTA）"
else
  echo "FAIL  D1 期望扣 80，实扣 $DELTA"; FAIL=1
fi

# 账单明细字段：时间 / 模型 / tokens / 金额
L=$(rootapi GET '/api/log/self?p=1&page_size=5&type=2')
ok=$(echo "$L" | py "
import json,sys
items=[i for i in json.load(sys.stdin)['data']['items'] if i['token_name']=='bill-$$']
qw=[i for i in items if 'qwen' in i['model_name']][0]
cl=[i for i in items if 'claude' in i['model_name']][0]
assert qw['prompt_tokens']==12 and qw['completion_tokens']==8 and qw['quota']==2 and qw['created_at']>0
assert cl['prompt_tokens']==12 and cl['completion_tokens']==8 and cl['quota']==78 and cl['created_at']>0
print('ok')")
[ "$ok" = "ok" ] && echo "PASS  D1 账单明细含 时间/模型/tokens/金额，逐条与公式一致" || { echo "FAIL  D1 明细校验"; FAIL=1; }

# ---------- D2: 公对公人工入账（合规确认 + 兑换码 + 记录可审计） ----------
rootapi POST /api/option/payment_compliance '{"confirmed":true}' > /dev/null
RNAME="公对公-回单#B123-$$"
RRESP=$(rootapi POST /api/redemption/ "{\"name\":\"$RNAME\",\"quota\":654321,\"count\":1}")
RKEY=$(echo "$RRESP" | py 'import json,sys;d=json.load(sys.stdin)["data"];print(d[0] if isinstance(d,list) else d)')
if [ -n "$RKEY" ] && [ "$RKEY" != "None" ]; then echo "PASS  D2 admin 生成入账兑换码（备注=转账回单号）"; else echo "FAIL  D2 生成兑换码 => $(echo "$RRESP"|head -c 200)"; FAIL=1; fi

DU="dtopup$$"
curl -s -X POST "$BASE/api/user/register" -H 'content-type: application/json' \
  -d "{\"username\":\"$DU\",\"password\":\"Dtop@2026x\",\"password2\":\"Dtop@2026x\"}" > /dev/null
DJAR=$(mktemp)
DUID=$(curl -s -c "$DJAR" -X POST "$BASE/api/user/login" -H 'content-type: application/json' \
  -d "{\"username\":\"$DU\",\"password\":\"Dtop@2026x\"}" | py 'import json,sys;print(json.load(sys.stdin)["data"]["id"])')
duser() { curl -s -b "$DJAR" -H 'content-type: application/json' -H "New-Api-User: $DUID" -X "$1" "$BASE$2" ${3:+-d "$3"}; }

got=$(duser POST /api/user/topup "{\"key\":\"$RKEY\"}" | py 'import json,sys;print(json.load(sys.stdin).get("data"))')
Q=$(duser GET /api/user/self | py 'import json,sys;print(json.load(sys.stdin)["data"]["quota"])')
if [ "$Q" = "654321" ]; then
  echo "PASS  D2 客户兑换入账，余额精确到账 654321"
else echo "FAIL  D2 入账后 quota=$Q (topup resp=$got)"; FAIL=1; fi

used=$(rootapi GET '/api/redemption/?p=1&size=10' | py "
import json,sys
d=json.load(sys.stdin)['data']
items=d['items'] if isinstance(d,dict) else d
r=[x for x in items if x['name']=='$RNAME'][0]
print(r['status'], r.get('used_user_id') or r.get('user_id'))")
echo "$used" | grep -q "3 $DUID" && echo "PASS  D2 入账记录可审计（status=已使用, 兑换人=$DUID）" || { echo "FAIL  D2 审计 => $used"; FAIL=1; }
echo "NOTE  D2 线上沙箱支付（Stripe/易支付）⛔ 缺商户凭据，接入后复验"

# ---------- D3: 用量看板（按日/按模型聚合，DataExportInterval=1 分钟内落库） ----------
deadline=$(( $(date +%s) + 100 ))
D3=""
while [ $(date +%s) -lt $deadline ]; do
  D3=$(rootapi GET "/api/data/self?start_timestamp=$(( $(date +%s) - 3600 ))&end_timestamp=$(( $(date +%s) + 60 ))&default_time=hour")
  echo "$D3" | grep -q 'qwen' && break
  sleep 10
done
ok=$(echo "$D3" | py "
import json,sys
rows=json.load(sys.stdin)['data']
models={r['model_name'] for r in rows}
assert any('qwen' in m for m in models), models
row=[r for r in rows if 'qwen' in r['model_name']][0]
assert row['quota']>0 and row['count']>0 and row['created_at']>0
print('ok')" 2>&1)
[ "$ok" = "ok" ] && echo "PASS  D3 看板聚合数据（按时段×模型：count/quota/created_at）" || { echo "FAIL  D3 => $(echo "$D3"|head -c 200) [$ok]"; FAIL=1; }

rm -f "$JAR" "$DJAR"
[ $FAIL -eq 0 ] && echo "== D ALL PASS（线上支付沙箱除外，见 NOTE）==" || { echo "== D FAILED =="; exit 1; }
