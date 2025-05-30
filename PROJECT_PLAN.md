# New API 功能增强项目实施计划

## 项目概述

本项目旨在为 New API 系统添加完整的账户管理、支付充值、中台管理等功能，提升系统的商业化能力和用户体验。

## 需求分析

### 用户需求
1. **账户系统增强**：邮箱注册、登录、密码管理
2. **充值界面**：余额显示、多种充值方式、支付集成
3. **账单管理**：交易记录、消费统计
4. **密钥管理**：API Key 生成和管理
5. **使用记录**：详细的API调用历史
6. **个人设置**：用户偏好配置

### 管理员需求
1. **中台管理（M8）**：供应商管理、API配置
2. **供应商接入**：支持 OpenAI 格式的第三方API
3. **系统监控**：使用统计、性能监控

## 技术架构

### 当前系统分析
- **后端**：Go + Gin 框架
- **数据库**：支持 MySQL/PostgreSQL/SQLite
- **缓存**：Redis
- **前端**：React (位于 web/ 目录)
- **支付**：已集成 Epay 系统

### 新增组件
- **邮件服务**：SMTP 邮件发送
- **支付网关**：支付宝/微信支付集成
- **API网关**：统一的请求转发和管理
- **监控系统**：日志收集和分析

## 详细实施方案

### 阶段一：账户系统增强 (2-3天)

#### 1.1 邮箱注册功能
**目标**：实现完整的邮箱验证注册流程

**技术实现**：
- 扩展 `model/user.go` 用户模型
- 增强 `controller/user.go` 注册接口
- 完善邮件验证逻辑

**数据库变更**：
```sql
-- 用户表已有邮箱字段，需要添加验证状态
ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT FALSE;
ALTER TABLE users ADD COLUMN email_verification_token VARCHAR(64);
ALTER TABLE users ADD COLUMN email_verification_expires_at TIMESTAMP;
```

**API接口**：
- `POST /api/user/register` - 注册（需邮箱验证）
- `GET /api/user/verify-email` - 邮箱验证
- `POST /api/user/resend-verification` - 重发验证邮件

#### 1.2 邮箱登录
**目标**：支持用户名或邮箱登录

**技术实现**：
- 修改 `controller/user.go` 中的 `Login` 函数
- 更新登录验证逻辑

#### 1.3 密码管理
**目标**：完善密码重置和修改功能

**技术实现**：
- 增强现有的密码重置功能
- 添加用户主动修改密码接口

### 阶段二：充值和账单系统 (3-4天)

#### 2.1 充值界面开发
**目标**：创建用户友好的充值界面

**前端组件**：
```
web/src/pages/TopUp/
├── index.jsx          # 充值主页面
├── PaymentModal.jsx   # 支付弹窗
├── PaymentResult.jsx  # 支付结果页
└── styles.css         # 样式文件
```

**功能特性**：
- 余额显示
- 预设充值金额：50, 100, 150, 200, 300, 500, 1000
- 自定义金额输入
- 支付方式选择（支付宝/微信）

#### 2.2 账单系统
**目标**：完整的交易记录管理

**数据库设计**：
```sql
CREATE TABLE billing_records (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    type ENUM('topup', 'consumption', 'refund') NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    quota_amount BIGINT NOT NULL,
    description TEXT,
    transaction_id VARCHAR(64),
    status ENUM('pending', 'completed', 'failed', 'cancelled') DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_created_at (created_at),
    INDEX idx_transaction_id (transaction_id)
);
```

**API接口**：
- `GET /api/user/billing` - 获取账单列表
- `GET /api/user/billing/:id` - 获取账单详情
- `GET /api/user/billing/stats` - 账单统计

### 阶段三：中台管理和供应商接入 (2-3天)

#### 3.1 供应商管理系统
**目标**：统一管理第三方API供应商

**数据库设计**：
```sql
CREATE TABLE providers (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    base_url VARCHAR(255) NOT NULL,
    api_key VARCHAR(255) NOT NULL,
    api_format ENUM('openai', 'claude', 'custom') DEFAULT 'openai',
    status ENUM('active', 'inactive') DEFAULT 'active',
    config JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

CREATE TABLE provider_models (
    id INT PRIMARY KEY AUTO_INCREMENT,
    provider_id INT NOT NULL,
    model_name VARCHAR(100) NOT NULL,
    display_name VARCHAR(100),
    input_price DECIMAL(10,6) DEFAULT 0,
    output_price DECIMAL(10,6) DEFAULT 0,
    status ENUM('active', 'inactive') DEFAULT 'active',
    FOREIGN KEY (provider_id) REFERENCES providers(id),
    UNIQUE KEY unique_provider_model (provider_id, model_name)
);
```

#### 3.2 Antinomy AI 接入
**配置信息**：
```json
{
  "name": "Antinomy AI",
  "base_url": "https://antinomy.ai/api/v1",
  "api_key": "sk-fg-v1-74c17c85c6cc5f762fde1149a0da4f3165ff6199b9aab698425d371088909306",
  "api_format": "openai",
  "models": [
    "anthropic/claude-opus-4",
    "anthropic/claude-sonnet-4",
    "anthropic/claude-3.7-sonnet",
    "anthropic/claude-3.5-sonnet",
    "anthropic/claude-3.7-sonnet:thinking",
    "google/gemini-2.5-pro-preview",
    "x-ai/grok-3-beta"
  ]
}
```

### 阶段四：后端优化和部署 (2-3天)

#### 4.1 API网关增强
**目标**：统一的请求转发和管理

**技术实现**：
- 扩展现有的 `relay/` 模块
- 添加供应商路由逻辑
- 实现请求转换适配器

#### 4.2 密钥管理系统
**目标**：安全的API密钥生成和管理

**功能特性**：
- 密钥生成算法优化
- 使用限制和配额管理
- 密钥使用统计

## 部署方案

### 腾讯云服务器配置

#### 应用服务器
```
规格：4核8GB内存
系统：Ubuntu 22.04 LTS
硬盘：100GB SSD云硬盘
带宽：10Mbps
```

#### 数据库服务器
```
MySQL 8.0 云数据库
规格：2核4GB
存储：50GB高性能云硬盘
备份：自动备份，保留7天
```

#### Redis缓存
```
Redis 6.0+ 云缓存
规格：1核2GB
持久化：RDB + AOF
```

#### 负载均衡（可选）
```
腾讯云CLB
支持HTTPS
健康检查
```

### 部署架构图
```
Internet
    ↓
[腾讯云CLB] → [Nginx] → [Go App Instance 1]
                      → [Go App Instance 2]
                      → [Go App Instance N]
    ↓
[MySQL Cluster] ← → [Redis Cluster]
    ↓
[备份存储] + [日志收集] + [监控告警]
```

### 部署脚本
```bash
#!/bin/bash
# 部署脚本示例

# 1. 环境准备
sudo apt update && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose nginx

# 2. 应用部署
git clone <repository>
cd new-api-nexusroute
docker-compose up -d

# 3. Nginx配置
sudo cp deploy/nginx.conf /etc/nginx/sites-available/new-api
sudo ln -s /etc/nginx/sites-available/new-api /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

# 4. SSL证书
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d your-domain.com
```

## 开发时间规划

### 第一周
- **Day 1-2**：账户系统增强
  - 邮箱注册验证
  - 登录功能优化
- **Day 3-4**：充值系统开发
  - 充值界面设计
  - 支付流程优化
- **Day 5**：账单系统基础功能

### 第二周
- **Day 1-2**：中台管理系统
  - 供应商管理界面
  - API配置功能
- **Day 3**：Antinomy AI接入
- **Day 4-5**：系统测试和优化

### 第三周
- **Day 1-2**：部署准备
  - 服务器配置
  - 环境搭建
- **Day 3-4**：生产部署
- **Day 5**：监控和维护

## 风险评估

### 技术风险
1. **第三方API稳定性**：Antinomy AI服务可用性
2. **支付安全**：支付流程的安全性保障
3. **数据迁移**：现有数据的平滑迁移

### 解决方案
1. **API监控**：实时监控第三方服务状态
2. **支付加密**：使用HTTPS和数据加密
3. **灰度发布**：分阶段部署，降低风险

## 成功指标

### 功能指标
- [ ] 邮箱注册成功率 > 95%
- [ ] 支付成功率 > 98%
- [ ] API响应时间 < 500ms
- [ ] 系统可用性 > 99.5%

### 业务指标
- [ ] 用户注册转化率提升 20%
- [ ] 充值转化率 > 15%
- [ ] 用户活跃度提升 30%

## 后续维护

### 监控告警
- 系统性能监控
- 错误日志告警
- 支付异常监控
- 第三方API状态监控

### 定期维护
- 数据库优化
- 缓存清理
- 安全更新
- 性能调优

---

**项目负责人**：开发团队
**创建时间**：2025年5月30日
**最后更新**：2025年5月30日

**备注**：本计划为初版，在实施过程中可能根据实际情况进行调整。
