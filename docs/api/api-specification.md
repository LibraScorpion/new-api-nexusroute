# API 接口规范文档

## 概述

本文档详细描述了 New API 项目的所有接口规范，包括用户管理、充值支付、供应商管理等模块的API设计。

## 1. 通用规范

### 1.1 基础信息

```
Base URL: https://api.your-domain.com
API Version: v1
Content-Type: application/json
Authorization: Bearer {token}
```

### 1.2 响应格式

#### 成功响应
```json
{
  "success": true,
  "data": {},
  "message": "操作成功"
}
```

#### 错误响应
```json
{
  "success": false,
  "error": {
    "code": "ERROR_CODE",
    "message": "错误描述"
  }
}
```

### 1.3 状态码

```
200 OK - 请求成功
400 Bad Request - 请求参数错误
401 Unauthorized - 未授权
403 Forbidden - 禁止访问
404 Not Found - 资源不存在
429 Too Many Requests - 请求过于频繁
500 Internal Server Error - 服务器内部错误
```

## 2. 用户认证模块

### 2.1 用户注册

#### 接口信息
```
POST /api/user/register
Content-Type: application/json
```

#### 请求参数
```json
{
  "username": "string",      // 用户名，3-12字符
  "email": "string",         // 邮箱地址
  "password": "string",      // 密码，8-20字符
  "display_name": "string"   // 显示名称（可选）
}
```

#### 响应示例
```json
{
  "success": true,
  "message": "注册成功，请查收验证邮件",
  "data": {
    "user_id": 123,
    "username": "testuser",
    "email": "test@example.com",
    "email_verified": false
  }
}
```

### 2.2 邮箱验证

#### 接口信息
```
GET /api/user/verify-email?token={verification_token}
```

#### 响应示例
```json
{
  "success": true,
  "message": "邮箱验证成功"
}
```

### 2.3 用户登录

#### 接口信息
```
POST /api/user/login
Content-Type: application/json
```

#### 请求参数
```json
{
  "username": "string",  // 用户名或邮箱
  "password": "string"   // 密码
}
```

#### 响应示例
```json
{
  "success": true,
  "message": "登录成功",
  "data": {
    "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "user": {
      "id": 123,
      "username": "testuser",
      "email": "test@example.com",
      "display_name": "Test User",
      "quota": 1000000,
      "used_quota": 50000,
      "role": "user"
    }
  }
}
```

### 2.4 修改密码

#### 接口信息
```
POST /api/user/change-password
Authorization: Bearer {token}
Content-Type: application/json
```

#### 请求参数
```json
{
  "old_password": "string",  // 原密码
  "new_password": "string"   // 新密码
}
```

#### 响应示例
```json
{
  "success": true,
  "message": "密码修改成功"
}
```

## 3. 充值支付模块

### 3.1 获取充值配置

#### 接口信息
```
GET /api/user/topup/configs
Authorization: Bearer {token}
```

#### 响应示例
```json
{
  "success": true,
  "data": [
    {
      "id": 1,
      "amount": 100,
      "bonus_amount": 10,
      "price": 10.00,
      "is_active": true,
      "sort_order": 1
    }
  ]
}
```

### 3.2 发起充值

#### 接口信息
```
POST /api/user/topup/request
Authorization: Bearer {token}
Content-Type: application/json
```

#### 请求参数
```json
{
  "amount": 100,              // 充值金额
  "payment_method": "alipay", // 支付方式：alipay, wechat
  "custom_amount": false      // 是否自定义金额
}
```

#### 响应示例
```json
{
  "success": true,
  "data": {
    "transaction_id": "TOP123456789",
    "payment_url": "https://payment.example.com/pay",
    "qr_code": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...",
    "amount": 10.00
  }
}
```

### 3.3 获取账单列表

#### 接口信息
```
GET /api/user/billing?page=1&page_size=20
Authorization: Bearer {token}
```

#### 响应示例
```json
{
  "success": true,
  "data": {
    "records": [
      {
        "id": 1,
        "type": "topup",
        "amount": 10.00,
        "quota_amount": 100000,
        "description": "充值 100 额度",
        "transaction_id": "TOP123456789",
        "payment_method": "alipay",
        "status": "completed",
        "created_at": "2025-05-30T10:00:00Z"
      }
    ],
    "total": 50,
    "page": 1,
    "page_size": 20
  }
}
```

### 3.4 获取账单统计

#### 接口信息
```
GET /api/user/billing/stats?start_time=2025-05-01&end_time=2025-05-31
Authorization: Bearer {token}
```

#### 响应示例
```json
{
  "success": true,
  "data": {
    "total_topup": 100.00,
    "total_consumption": 50.00,
    "transaction_count": 25
  }
}
```

## 4. 密钥管理模块

### 4.1 获取密钥列表

#### 接口信息
```
GET /api/user/tokens?page=1&page_size=20
Authorization: Bearer {token}
```

#### 响应示例
```json
{
  "success": true,
  "data": {
    "tokens": [
      {
        "id": 1,
        "name": "Default Key",
        "key": "sk-***************",
        "status": "active",
        "quota": 100000,
        "used_quota": 5000,
        "unlimited_quota": false,
        "expired_time": null,
        "created_at": "2025-05-30T10:00:00Z"
      }
    ],
    "total": 5,
    "page": 1,
    "page_size": 20
  }
}
```

### 4.2 创建密钥

#### 接口信息
```
POST /api/user/tokens
Authorization: Bearer {token}
Content-Type: application/json
```

#### 请求参数
```json
{
  "name": "string",              // 密钥名称
  "quota": 100000,               // 额度限制
  "unlimited_quota": false,      // 是否无限额度
  "expired_time": "2025-12-31"   // 过期时间（可选）
}
```

#### 响应示例
```json
{
  "success": true,
  "message": "密钥创建成功",
  "data": {
    "id": 2,
    "name": "New Key",
    "key": "sk-1234567890abcdef",
    "quota": 100000,
    "status": "active"
  }
}
```

### 4.3 更新密钥

#### 接口信息
```
PUT /api/user/tokens/{id}
Authorization: Bearer {token}
Content-Type: application/json
```

#### 请求参数
```json
{
  "name": "string",         // 密钥名称
  "status": "active",       // 状态：active, disabled
  "quota": 200000          // 额度限制
}
```

### 4.4 删除密钥

#### 接口信息
```
DELETE /api/user/tokens/{id}
Authorization: Bearer {token}
```

## 5. 使用记录模块

### 5.1 获取使用记录

#### 接口信息
```
GET /api/user/logs?page=1&page_size=20&start_time=2025-05-01&end_time=2025-05-31
Authorization: Bearer {token}
```

#### 响应示例
```json
{
  "success": true,
  "data": {
    "logs": [
      {
        "id": 1,
        "type": "chat",
        "model": "gpt-3.5-turbo",
        "prompt_tokens": 100,
        "completion_tokens": 50,
        "quota": 150,
        "content": "用户对话内容",
        "created_at": "2025-05-30T10:00:00Z"
      }
    ],
    "total": 100,
    "page": 1,
    "page_size": 20
  }
}
```

### 5.2 获取使用统计

#### 接口信息
```
GET /api/user/usage/stats?period=month
Authorization: Bearer {token}
```

#### 响应示例
```json
{
  "success": true,
  "data": {
    "total_requests": 1000,
    "total_tokens": 50000,
    "total_quota": 25000,
    "model_usage": {
      "gpt-3.5-turbo": 30000,
      "gpt-4": 20000
    },
    "daily_usage": [
      {
        "date": "2025-05-30",
        "requests": 50,
        "tokens": 2500,
        "quota": 1250
      }
    ]
  }
}
```

## 6. 管理员接口

### 6.1 供应商管理

#### 获取供应商列表
```
GET /api/admin/providers
Authorization: Bearer {admin_token}
```

#### 创建供应商
```
POST /api/admin/providers
Authorization: Bearer {admin_token}
Content-Type: application/json

{
  "name": "Antinomy AI",
  "base_url": "https://antinomy.ai/api/v1",
  "api_key": "sk-xxx",
  "api_format": "openai",
  "status": "active",
  "priority": 1,
  "weight": 10,
  "config": {
    "timeout": 30,
    "retry_count": 3
  }
}
```

#### 更新供应商
```
PUT /api/admin/providers/{id}
Authorization: Bearer {admin_token}
```

#### 删除供应商
```
DELETE /api/admin/providers/{id}
Authorization: Bearer {admin_token}
```

#### 测试供应商连接
```
POST /api/admin/providers/{id}/test
Authorization: Bearer {admin_token}
```

### 6.2 模型管理

#### 获取模型列表
```
GET /api/admin/providers/{provider_id}/models
Authorization: Bearer {admin_token}
```

#### 创建模型
```
POST /api/admin/models
Authorization: Bearer {admin_token}
Content-Type: application/json

{
  "provider_id": 1,
  "model_name": "anthropic/claude-3.5-sonnet",
  "display_name": "Claude 3.5 Sonnet",
  "model_type": "chat",
  "input_price": 0.000003,
  "output_price": 0.000015,
  "max_tokens": 200000,
  "status": "active"
}
```

### 6.3 用户管理

#### 获取用户列表
```
GET /api/admin/users?page=1&page_size=20&keyword=search
Authorization: Bearer {admin_token}
```

#### 更新用户信息
```
PUT /api/admin/users/{id}
Authorization: Bearer {admin_token}
Content-Type: application/json

{
  "status": "active",
  "quota": 1000000,
  "role": "user"
}
```

## 7. 中转API接口

### 7.1 聊天完成

#### 接口信息
```
POST /v1/chat/completions
Authorization: Bearer {api_key}
Content-Type: application/json
```

#### 请求参数
```json
{
  "model": "gpt-3.5-turbo",
  "messages": [
    {
      "role": "user",
      "content": "Hello, how are you?"
    }
  ],
  "temperature": 0.7,
  "max_tokens": 150,
  "stream": false
}
```

#### 响应示例
```json
{
  "id": "chatcmpl-123",
  "object": "chat.completion",
  "created": 1677652288,
  "model": "gpt-3.5-turbo",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! I'm doing well, thank you for asking."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 9,
    "completion_tokens": 12,
    "total_tokens": 21
  }
}
```

### 7.2 模型列表

#### 接口信息
```
GET /v1/models
Authorization: Bearer {api_key}
```

#### 响应示例
```json
{
  "object": "list",
  "data": [
    {
      "id": "gpt-3.5-turbo",
      "object": "model",
      "created": 1677610602,
      "owned_by": "openai"
    },
    {
      "id": "anthropic/claude-3.5-sonnet",
      "object": "model",
      "created": 1677610602,
      "owned_by": "anthropic"
    }
  ]
}
```

## 8. 错误码定义

### 8.1 用户相关错误

```
USER_NOT_FOUND - 用户不存在
USER_ALREADY_EXISTS - 用户已存在
INVALID_CREDENTIALS - 用户名或密码错误
EMAIL_NOT_VERIFIED - 邮箱未验证
ACCOUNT_DISABLED - 账户已被禁用
```

### 8.2 认证相关错误

```
INVALID_TOKEN - 无效的令牌
TOKEN_EXPIRED - 令牌已过期
INSUFFICIENT_PERMISSIONS - 权限不足
RATE_LIMIT_EXCEEDED - 请求频率超限
```

### 8.3 支付相关错误

```
INSUFFICIENT_BALANCE - 余额不足
PAYMENT_FAILED - 支付失败
INVALID_AMOUNT - 无效的金额
PAYMENT_TIMEOUT - 支付超时
```

### 8.4 API相关错误

```
MODEL_NOT_FOUND - 模型不存在
PROVIDER_UNAVAILABLE - 供应商不可用
REQUEST_TOO_LARGE - 请求过大
QUOTA_EXCEEDED - 额度超限
```

## 9. 限流规则

### 9.1 用户接口限流

```
登录接口：5次/分钟
注册接口：3次/分钟
密码重置：3次/分钟
其他接口：100次/分钟
```

### 9.2 API接口限流

```
免费用户：60次/分钟
付费用户：600次/分钟
VIP用户：6000次/分钟
```

## 10. 版本更新

### 10.1 版本历史

```
v1.0.0 - 2025-05-30
- 初始版本发布
- 基础用户管理功能
- 充值支付功能
- 供应商管理功能
```

### 10.2 兼容性说明

```
- API版本向后兼容
- 废弃接口会提前30天通知
- 新功能通过版本号区分
```

---

**文档版本**：v1.0  
**创建时间**：2025年5月30日  
**最后更新**：2025年5月30日  
**维护人员**：开发团队
