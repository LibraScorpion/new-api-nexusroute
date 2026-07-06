#!/bin/bash
# D4 验收：用户提交开票信息（抬头/税号/邮箱），admin 可见并标记已开（人工开票流程）
BASE=${BASE:-http://localhost:3000}
ADMIN_PASS=${ADMIN_PASS:?need ADMIN_PASS}
JAR=$(mktemp); UJAR=$(mktemp); FAIL=0
IU="inv$$"

# 用户注册登录并提交开票申请
curl -s -X POST "$BASE/api/user/register" -H 'content-type: application/json' \
  -d "{\"username\":\"$IU\",\"password\":\"Inv@2026xx\",\"password2\":\"Inv@2026xx\"}" > /dev/null
UID_=$(curl -s -c "$UJAR" -X POST "$BASE/api/user/login" -H 'content-type: application/json' \
  -d "{\"username\":\"$IU\",\"password\":\"Inv@2026xx\"}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["id"])')
iu() { curl -s -b "$UJAR" -H 'content-type: application/json' -H "New-Api-User: $UID_" -X "$1" "$BASE$2" ${3:+-d "$3"}; }

# 校验：空税号被拒（信任边界输入校验）
r=$(iu POST /api/invoice/ '{"title":"某某科技有限公司","tax_no":"","email":"fin@acme.cn"}')
echo "$r" | grep -q '不能为空' && echo "PASS  D4 必填字段校验（空税号被拒）" || { echo "FAIL  D4 校验 => $(echo "$r"|head -c 150)"; FAIL=1; }

r=$(iu POST /api/invoice/ '{"title":"某某科技有限公司","tax_no":"91330100MA27XW8L2K","email":"fin@acme.cn","remark":"2026Q3 token 采购"}')
IID=$(echo "$r" | python3 -c 'import json,sys;print(json.load(sys.stdin)["data"]["id"])' 2>/dev/null)
[ -n "$IID" ] && echo "PASS  D4 用户提交开票申请 (id=$IID)" || { echo "FAIL  D4 提交 => $(echo "$r"|head -c 200)"; FAIL=1; }

# admin 可见
curl -s -c "$JAR" -X POST "$BASE/api/user/login" -H 'content-type: application/json' \
  -d "{\"username\":\"root\",\"password\":\"$ADMIN_PASS\"}" > /dev/null
rootapi() { curl -s -b "$JAR" -H 'content-type: application/json' -H 'New-Api-User: 1' -X "$1" "$BASE$2" ${3:+-d "$3"}; }
l=$(rootapi GET /api/invoice/)
echo "$l" | grep -q '91330100MA27XW8L2K' && echo "PASS  D4 admin 列表可见申请（含税号/抬头）" || { echo "FAIL  D4 admin 列表 => $(echo "$l"|head -c 200)"; FAIL=1; }

# admin 标记已开 → 用户侧状态翻转；重复标记被拒
rootapi POST /api/invoice/$IID/complete > /dev/null
st=$(iu GET /api/invoice/self | python3 -c "import json,sys;print([i['status'] for i in json.load(sys.stdin)['data'] if i['id']==$IID][0])")
[ "$st" = "2" ] && echo "PASS  D4 admin 标记已开，用户侧状态=已开票" || { echo "FAIL  D4 状态=$st"; FAIL=1; }
r=$(rootapi POST /api/invoice/$IID/complete)
echo "$r" | grep -q '已开票\|不存在' && echo "PASS  D4 重复标记被拒（幂等保护）" || { echo "FAIL  D4 重复标记 => $(echo "$r"|head -c 150)"; FAIL=1; }

# 越权：普通用户不能看 admin 列表
r=$(iu GET /api/invoice/)
echo "$r" | grep -q '"success":false' && echo "PASS  D4 普通用户禁访 admin 列表" || { echo "FAIL  D4 越权 => $(echo "$r"|head -c 150)"; FAIL=1; }

rm -f "$JAR" "$UJAR"
[ $FAIL -eq 0 ] && echo "== D4 ALL PASS ==" || { echo "== D4 FAILED =="; exit 1; }
