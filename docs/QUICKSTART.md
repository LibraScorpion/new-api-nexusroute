# Quickstart — 5 分钟完成首次调用

> 以下 `<BASE_URL>` 为平台地址（如 `https://api.example.com`），自部署默认 `http://localhost:3000`。

## 1. 注册并登录（1 分钟）

打开 `<BASE_URL>`，点击右上角「注册」，填写用户名与密码后登录。

## 2. 创建 API Key（1 分钟）

控制台 →「令牌」→「添加令牌」：

- 名称随意（建议按部门/用途命名，如 `dept-finance`）
- 额度：按需分配，或勾选「无限额度」
- 提交后在列表中点「复制」获得 `sk-` 开头的 Key

## 3. 首次调用（1 分钟）

### OpenAI 格式（/v1/chat/completions）

```bash
export NEWAPI_KEY=sk-你的Key
export BASE_URL=http://localhost:3000

curl $BASE_URL/v1/chat/completions \
  -H "Authorization: Bearer $NEWAPI_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "deepseek/deepseek-chat",
    "messages": [{"role": "user", "content": "你好"}]
  }'
```

流式输出加 `"stream": true`。

### Anthropic 格式（/v1/messages）

```bash
curl $BASE_URL/v1/messages \
  -H "x-api-key: $NEWAPI_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "anthropic/claude-sonnet-4.5",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "你好"}]
  }'
```

### Python（OpenAI SDK 直接可用）

```python
from openai import OpenAI

client = OpenAI(api_key="sk-你的Key", base_url="http://localhost:3000/v1")
resp = client.chat.completions.create(
    model="deepseek/deepseek-chat",
    messages=[{"role": "user", "content": "你好"}],
)
print(resp.choices[0].message.content)
```

## 4. 之后去哪里

- **模型与价格**：`<BASE_URL>/pricing` — 全部可用模型、上下文长度、输入/输出单价、调用示例
- **用量与账单**：控制台 →「日志」/「数据看板」— 每笔调用的模型、tokens、金额
- **充值**：控制台 →「钱包」；对公转账请联系商务，确认到账后按转账单号入账

## 常见问题

- **401 Invalid token**：Key 复制不完整或已被禁用/删除
- **No available channel**：该模型未对你的分组开放，联系管理员
- **额度不足**：令牌额度或账户余额不足，充值或调整令牌额度
