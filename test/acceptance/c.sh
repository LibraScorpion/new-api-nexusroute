#!/bin/bash
# C 节验收：C1 注册登录/Key 管理；C2 主账号分额度子 Key + 用量隔离；C3 主账号看板汇总
# 子账号按 MVP 映射为「主账号下的分额度 API Key」（每部门一个 Key，独立额度）
# 用法: BASE=... ADMIN_PASS=... bash c.sh
BASE=${BASE:-http://localhost:3000}
ADMIN_PASS=${ADMIN_PASS:?need ADMIN_PASS}
JAR=$(mktemp); AJAR=$(mktemp); FAIL=0
ACME="acme$$"

# ---------- C1: 注册 / 登录 ----------
r=$(curl -s -X POST "$BASE/api/user/register" -H 'content-type: application/json' \
  -d "{\"username\":\"$ACME\",\"password\":\"Acme@2026x\",\"password2\":\"Acme@2026x\"}")
echo "$r" | grep -q '"success":true' && echo "PASS  C1 注册企业账号 $ACME" || { echo "FAIL  C1 注册 => $(echo "$r"|head -c 150)"; FAIL=1; }

UID_=$(curl -s -c "$JAR" -X POST "$BASE/api/user/login" -H 'content-type: application/json' \
  -d "{\"username\":\"$ACME\",\"password\":\"Acme@2026x\"}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["id"])' 2>/dev/null)
if [ -n "$UID_" ]; then echo "PASS  C1 登录成功 (user id=$UID_)"; else echo "FAIL  C1 登录"; FAIL=1; fi
acme() { curl -s -b "$JAR" -H 'content-type: application/json' -H "New-Api-User: $UID_" -X "$1" "$BASE$2" ${3:+-d "$3"}; }

# 主账号需有额度才能给子 Key 用：root 给 acme 充值
curl -s -c "$AJAR" -X POST "$BASE/api/user/login" -H 'content-type: application/json' \
  -d "{\"username\":\"root\",\"password\":\"$ADMIN_PASS\"}" > /dev/null
rootapi() { curl -s -b "$AJAR" -H 'content-type: application/json' -H 'New-Api-User: 1' -X "$1" "$BASE$2" ${3:+-d "$3"}; }
# 分组走 PUT（EditWithTx 只更新 username/group 等），额度走 manage add_quota
rootapi PUT /api/user/ "{\"id\":$UID_,\"username\":\"$ACME\",\"group\":\"default\"}" > /dev/null
rootapi POST /api/user/manage "{\"id\":$UID_,\"action\":\"add_quota\",\"mode\":\"add\",\"value\":10000000}" > /dev/null

# ---------- C2: 分额度子 Key（A=50万 B=500 C=1） ----------
for spec in 'dept-A:500000' 'dept-B:500' 'dept-C:1'; do
  acme POST /api/token/ "{\"name\":\"${spec%%:*}\",\"remain_quota\":${spec##*:},\"unlimited_quota\":false,\"expired_time\":-1}" > /dev/null
done
TOKS=$(acme GET '/api/token/?p=1&size=10')
tid() { echo "$TOKS" | python3 -c "import json,sys;d=json.load(sys.stdin)['data']['items'];print([t['id'] for t in d if t['name']=='$1'][0])"; }
IDA=$(tid dept-A); IDB=$(tid dept-B); IDC=$(tid dept-C)
key() { echo sk-$(acme POST /api/token/$1/key | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["key"])'); }
KA=$(key $IDA); KB=$(key $IDB); KC=$(key $IDC)
[ -n "$IDA" ] && [ -n "$IDB" ] && [ -n "$IDC" ] && echo "PASS  C2 主账号创建 3 个分额度子 Key（50万/500/1）"

call() { curl -s "$BASE/v1/chat/completions" -H "Authorization: Bearer $1" -H 'content-type: application/json' \
  -d '{"model":"qwen/qwen3-32b","messages":[{"role":"user","content":"hi"}]}'; }

# 额度内的 A、B 正常；额度 1 的 C 被拒 → 额度分配真实生效
r=$(call "$KA"); echo "$r" | grep -q 'mock@' && echo "PASS  C2 dept-A 额度内正常调用" || { echo "FAIL  dept-A => $(echo "$r"|head -c 150)"; FAIL=1; }
r=$(call "$KB"); echo "$r" | grep -q 'mock@' && echo "PASS  C2 dept-B 额度内正常调用" || { echo "FAIL  dept-B => $(echo "$r"|head -c 150)"; FAIL=1; }
r=$(call "$KC")
echo "$r" | grep -qiE 'quota|额度' && echo "PASS  C2 dept-C(额度1) 被拒（额度隔离生效）" || { echo "FAIL  dept-C 未被限额 => $(echo "$r"|head -c 150)"; FAIL=1; }

# 子 Key 只能查自己的用量
u=$(curl -s "$BASE/api/usage/token/" -H "Authorization: Bearer $KA")
if echo "$u" | grep -q 'dept-A' && ! echo "$u" | grep -q 'dept-B'; then
  echo "PASS  C2 子 Key 用量查询只见自己 (dept-A)"
else echo "FAIL  usage/token => $(echo "$u" | head -c 200)"; FAIL=1; fi

# ---------- C3: 主账号看板汇总全部子 Key ----------
logs=$(acme GET '/api/log/self?p=1&page_size=20&type=0')
if echo "$logs" | grep -q 'dept-A' && echo "$logs" | grep -q 'dept-B'; then
  echo "PASS  C3 主账号明细含全部子 Key（dept-A + dept-B）"
else echo "FAIL  C3 log/self => $(echo "$logs" | head -c 200)"; FAIL=1; fi

# ---------- C1 收尾: Key 禁用立即失效、删除 ----------
acme PUT "/api/token/?status_only=true" "{\"id\":$IDA,\"status\":2}" > /dev/null
r=$(call "$KA")
echo "$r" | grep -q 'mock@' && { echo "FAIL  C1 禁用后仍可调用"; FAIL=1; } || echo "PASS  C1 Key 禁用后立即失效"
acme DELETE "/api/token/$IDA" > /dev/null
r=$(call "$KA")
echo "$r" | grep -q 'mock@' && { echo "FAIL  C1 删除后仍可调用"; FAIL=1; } || echo "PASS  C1 Key 删除后失效"

rm -f "$JAR" "$AJAR"
[ $FAIL -eq 0 ] && echo "== C ALL PASS ==" || { echo "== C FAILED =="; exit 1; }
