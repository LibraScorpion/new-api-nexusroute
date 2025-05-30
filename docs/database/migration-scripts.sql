-- New API 数据库迁移脚本
-- 版本：v1.0
-- 创建时间：2025-05-30
-- 说明：包含所有新功能的数据库结构变更

-- ============================================
-- 1. 用户表增强 - 邮箱验证功能
-- ============================================

-- 为用户表添加邮箱验证相关字段
ALTER TABLE users 
ADD COLUMN email_verified BOOLEAN DEFAULT FALSE COMMENT '邮箱是否已验证',
ADD COLUMN email_verification_token VARCHAR(64) COMMENT '邮箱验证令牌',
ADD COLUMN email_verification_expires_at TIMESTAMP NULL COMMENT '验证令牌过期时间';

-- 添加索引
CREATE INDEX idx_users_email_verification_token ON users(email_verification_token);
CREATE INDEX idx_users_email_verified ON users(email_verified);

-- 将现有用户的邮箱设置为已验证（向后兼容）
UPDATE users SET email_verified = TRUE WHERE email IS NOT NULL AND email != '';

-- ============================================
-- 2. 账单记录表 - 充值和消费记录
-- ============================================

CREATE TABLE billing_records (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id INT NOT NULL,
    type ENUM('topup', 'consumption', 'refund') NOT NULL COMMENT '交易类型',
    amount DECIMAL(10,2) NOT NULL COMMENT '金额',
    quota_amount BIGINT NOT NULL COMMENT '额度数量',
    description TEXT COMMENT '交易描述',
    transaction_id VARCHAR(64) COMMENT '交易ID',
    payment_method ENUM('alipay', 'wechat', 'bank', 'other') COMMENT '支付方式',
    status ENUM('pending', 'completed', 'failed', 'cancelled') DEFAULT 'pending' COMMENT '状态',
    metadata JSON COMMENT '元数据',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_user_id (user_id),
    INDEX idx_created_at (created_at),
    INDEX idx_transaction_id (transaction_id),
    INDEX idx_status (status),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) COMMENT='账单记录表';

-- ============================================
-- 3. 充值配置表 - 预设充值金额
-- ============================================

CREATE TABLE topup_configs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    amount INT NOT NULL COMMENT '充值金额',
    bonus_amount INT DEFAULT 0 COMMENT '赠送金额',
    price DECIMAL(10,2) NOT NULL COMMENT '实际价格',
    is_active BOOLEAN DEFAULT TRUE COMMENT '是否启用',
    sort_order INT DEFAULT 0 COMMENT '排序',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_is_active (is_active),
    INDEX idx_sort_order (sort_order)
) COMMENT='充值配置表';

-- 插入默认充值配置
INSERT INTO topup_configs (amount, price, sort_order) VALUES
(50, 5.00, 1),
(100, 10.00, 2),
(150, 15.00, 3),
(200, 20.00, 4),
(300, 30.00, 5),
(500, 50.00, 6),
(1000, 100.00, 7);

-- ============================================
-- 4. 供应商管理表 - 中台管理系统
-- ============================================

CREATE TABLE providers (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL COMMENT '供应商名称',
    base_url VARCHAR(255) NOT NULL COMMENT 'API基础URL',
    api_key VARCHAR(255) NOT NULL COMMENT 'API密钥',
    api_format ENUM('openai', 'claude', 'custom') DEFAULT 'openai' COMMENT 'API格式',
    status ENUM('active', 'inactive', 'testing') DEFAULT 'active' COMMENT '状态',
    priority INT DEFAULT 0 COMMENT '优先级',
    weight INT DEFAULT 1 COMMENT '权重',
    config JSON COMMENT '配置信息',
    rate_limit JSON COMMENT '限流配置',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_status (status),
    INDEX idx_priority (priority),
    INDEX idx_name (name)
) COMMENT='供应商表';

-- ============================================
-- 5. 供应商模型表 - 模型管理
-- ============================================

CREATE TABLE provider_models (
    id INT PRIMARY KEY AUTO_INCREMENT,
    provider_id INT NOT NULL,
    model_name VARCHAR(100) NOT NULL COMMENT '模型名称',
    display_name VARCHAR(100) COMMENT '显示名称',
    model_type ENUM('chat', 'embedding', 'image', 'audio') DEFAULT 'chat' COMMENT '模型类型',
    input_price DECIMAL(10,6) DEFAULT 0 COMMENT '输入价格',
    output_price DECIMAL(10,6) DEFAULT 0 COMMENT '输出价格',
    max_tokens INT DEFAULT 4096 COMMENT '最大令牌数',
    status ENUM('active', 'inactive') DEFAULT 'active' COMMENT '状态',
    config JSON COMMENT '模型配置',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (provider_id) REFERENCES providers(id) ON DELETE CASCADE,
    UNIQUE KEY unique_provider_model (provider_id, model_name),
    INDEX idx_model_type (model_type),
    INDEX idx_status (status),
    INDEX idx_model_name (model_name)
) COMMENT='供应商模型表';

-- ============================================
-- 6. 供应商统计表 - 性能监控
-- ============================================

CREATE TABLE provider_stats (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    provider_id INT NOT NULL,
    date DATE NOT NULL,
    request_count INT DEFAULT 0 COMMENT '请求次数',
    success_count INT DEFAULT 0 COMMENT '成功次数',
    error_count INT DEFAULT 0 COMMENT '错误次数',
    total_tokens BIGINT DEFAULT 0 COMMENT '总令牌数',
    total_cost DECIMAL(10,4) DEFAULT 0 COMMENT '总成本',
    avg_response_time INT DEFAULT 0 COMMENT '平均响应时间(ms)',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (provider_id) REFERENCES providers(id) ON DELETE CASCADE,
    UNIQUE KEY unique_provider_date (provider_id, date),
    INDEX idx_date (date)
) COMMENT='供应商统计表';

-- ============================================
-- 7. 插入初始数据 - Antinomy AI 供应商
-- ============================================

-- 插入Antinomy AI供应商
INSERT INTO providers (name, base_url, api_key, api_format, status, priority, weight, config) VALUES
('Antinomy AI', 'https://antinomy.ai/api/v1', 'sk-fg-v1-74c17c85c6cc5f762fde1149a0da4f3165ff6199b9aab698425d371088909306', 'openai', 'active', 1, 10, JSON_OBJECT(
    'timeout', 30,
    'retry_count', 3,
    'retry_delay', 1000,
    'headers', JSON_OBJECT('User-Agent', 'New-API/1.0')
));

-- 获取刚插入的供应商ID
SET @provider_id = LAST_INSERT_ID();

-- 插入Antinomy AI模型
INSERT INTO provider_models (provider_id, model_name, display_name, model_type, input_price, output_price, max_tokens) VALUES
(@provider_id, 'anthropic/claude-opus-4', 'Claude Opus 4', 'chat', 0.000015, 0.000075, 200000),
(@provider_id, 'anthropic/claude-sonnet-4', 'Claude Sonnet 4', 'chat', 0.000003, 0.000015, 200000),
(@provider_id, 'anthropic/claude-3.7-sonnet', 'Claude 3.7 Sonnet', 'chat', 0.000003, 0.000015, 200000),
(@provider_id, 'anthropic/claude-3.5-sonnet', 'Claude 3.5 Sonnet', 'chat', 0.000003, 0.000015, 200000),
(@provider_id, 'anthropic/claude-3.7-sonnet:thinking', 'Claude 3.7 Sonnet (Thinking)', 'chat', 0.000003, 0.000015, 200000),
(@provider_id, 'google/gemini-2.5-pro-preview', 'Gemini 2.5 Pro Preview', 'chat', 0.000001, 0.000005, 1000000),
(@provider_id, 'x-ai/grok-3-beta', 'Grok 3 Beta', 'chat', 0.000002, 0.00001, 131072);

-- ============================================
-- 8. 系统配置表增强 - 新增配置项
-- ============================================

-- 插入邮箱验证相关配置
INSERT INTO options (name, value, description) VALUES
('EmailVerificationEnabled', 'true', '是否启用邮箱验证'),
('EmailVerificationTokenExpiry', '24', '邮箱验证令牌过期时间（小时）'),
('AllowUnverifiedLogin', 'false', '是否允许未验证邮箱的用户登录')
ON DUPLICATE KEY UPDATE value = VALUES(value);

-- 插入支付相关配置
INSERT INTO options (name, value, description) VALUES
('PaymentEnabled', 'true', '是否启用支付功能'),
('MinTopupAmount', '10', '最小充值金额'),
('MaxTopupAmount', '10000', '最大充值金额'),
('DefaultQuotaRatio', '500000', '默认额度比例（1元=500000额度）')
ON DUPLICATE KEY UPDATE value = VALUES(value);

-- 插入供应商相关配置
INSERT INTO options (name, value, description) VALUES
('ProviderLoadBalancing', 'weighted_random', '供应商负载均衡策略'),
('ProviderFailoverEnabled', 'true', '是否启用供应商故障转移'),
('ProviderHealthCheckInterval', '300', '供应商健康检查间隔（秒）')
ON DUPLICATE KEY UPDATE value = VALUES(value);

-- ============================================
-- 9. 现有表结构优化
-- ============================================

-- 优化用户表索引
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_users_created_at ON users(created_at);

-- 优化令牌表索引
CREATE INDEX idx_tokens_user_id_status ON tokens(user_id, status);
CREATE INDEX idx_tokens_expired_time ON tokens(expired_time);

-- 优化日志表索引
CREATE INDEX idx_logs_user_id_created_at ON logs(user_id, created_at);
CREATE INDEX idx_logs_type ON logs(type);

-- ============================================
-- 10. 数据清理和维护
-- ============================================

-- 清理过期的邮箱验证令牌（定期执行）
-- DELETE FROM users WHERE email_verification_expires_at < NOW() AND email_verified = FALSE;

-- 清理过期的账单记录（保留1年）
-- DELETE FROM billing_records WHERE created_at < DATE_SUB(NOW(), INTERVAL 1 YEAR) AND status IN ('failed', 'cancelled');

-- 清理过期的供应商统计数据（保留3个月）
-- DELETE FROM provider_stats WHERE date < DATE_SUB(CURDATE(), INTERVAL 3 MONTH);

-- ============================================
-- 11. 权限和安全设置
-- ============================================

-- 创建只读用户（用于监控和报表）
-- CREATE USER 'newapi_readonly'@'%' IDENTIFIED BY 'strong_password_here';
-- GRANT SELECT ON newapi.* TO 'newapi_readonly'@'%';

-- 创建备份用户
-- CREATE USER 'newapi_backup'@'%' IDENTIFIED BY 'strong_password_here';
-- GRANT SELECT, LOCK TABLES ON newapi.* TO 'newapi_backup'@'%';

-- ============================================
-- 12. 视图创建 - 便于查询统计
-- ============================================

-- 用户统计视图
CREATE VIEW user_stats AS
SELECT 
    u.id,
    u.username,
    u.email,
    u.quota,
    u.used_quota,
    u.quota - u.used_quota AS remaining_quota,
    COALESCE(SUM(CASE WHEN br.type = 'topup' AND br.status = 'completed' THEN br.amount ELSE 0 END), 0) AS total_topup,
    COALESCE(COUNT(CASE WHEN l.type IN (1, 2) THEN 1 END), 0) AS total_requests,
    u.created_at AS register_time
FROM users u
LEFT JOIN billing_records br ON u.id = br.user_id
LEFT JOIN logs l ON u.id = l.user_id
GROUP BY u.id;

-- 供应商性能视图
CREATE VIEW provider_performance AS
SELECT 
    p.id,
    p.name,
    p.status,
    COUNT(pm.id) AS model_count,
    COALESCE(AVG(ps.avg_response_time), 0) AS avg_response_time,
    COALESCE(SUM(ps.request_count), 0) AS total_requests,
    COALESCE(SUM(ps.success_count), 0) AS total_success,
    CASE 
        WHEN SUM(ps.request_count) > 0 
        THEN ROUND(SUM(ps.success_count) * 100.0 / SUM(ps.request_count), 2)
        ELSE 0 
    END AS success_rate
FROM providers p
LEFT JOIN provider_models pm ON p.id = pm.provider_id AND pm.status = 'active'
LEFT JOIN provider_stats ps ON p.id = ps.provider_id AND ps.date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY p.id;

-- ============================================
-- 13. 存储过程 - 常用操作
-- ============================================

DELIMITER //

-- 用户充值存储过程
CREATE PROCEDURE ProcessTopup(
    IN p_user_id INT,
    IN p_amount DECIMAL(10,2),
    IN p_quota_amount BIGINT,
    IN p_transaction_id VARCHAR(64),
    IN p_payment_method VARCHAR(20)
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- 插入账单记录
    INSERT INTO billing_records (
        user_id, type, amount, quota_amount, description, 
        transaction_id, payment_method, status
    ) VALUES (
        p_user_id, 'topup', p_amount, p_quota_amount, 
        CONCAT('充值 ', p_quota_amount, ' 额度'),
        p_transaction_id, p_payment_method, 'completed'
    );
    
    -- 更新用户额度
    UPDATE users 
    SET quota = quota + p_quota_amount 
    WHERE id = p_user_id;
    
    COMMIT;
END //

-- 记录API使用存储过程
CREATE PROCEDURE RecordAPIUsage(
    IN p_user_id INT,
    IN p_token_id INT,
    IN p_model_name VARCHAR(100),
    IN p_prompt_tokens INT,
    IN p_completion_tokens INT,
    IN p_quota_used BIGINT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;
    
    START TRANSACTION;
    
    -- 更新用户已使用额度
    UPDATE users 
    SET used_quota = used_quota + p_quota_used 
    WHERE id = p_user_id;
    
    -- 更新令牌已使用额度
    UPDATE tokens 
    SET used_quota = used_quota + p_quota_used 
    WHERE id = p_token_id;
    
    -- 插入消费记录
    INSERT INTO billing_records (
        user_id, type, amount, quota_amount, description, status
    ) VALUES (
        p_user_id, 'consumption', 0, p_quota_used,
        CONCAT('API调用 - ', p_model_name), 'completed'
    );
    
    COMMIT;
END //

DELIMITER ;

-- ============================================
-- 14. 触发器 - 自动化操作
-- ============================================

-- 用户注册时自动创建默认令牌
DELIMITER //
CREATE TRIGGER after_user_insert
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO tokens (
        user_id, name, `key`, quota, unlimited_quota, status
    ) VALUES (
        NEW.id, 'Default', CONCAT('sk-', SUBSTRING(MD5(CONCAT(NEW.id, NOW())), 1, 32)), 
        100000, FALSE, 1
    );
END //
DELIMITER ;

-- 账单记录更新时同步统计
DELIMITER //
CREATE TRIGGER after_billing_update
AFTER UPDATE ON billing_records
FOR EACH ROW
BEGIN
    IF NEW.status = 'completed' AND OLD.status != 'completed' AND NEW.type = 'topup' THEN
        UPDATE users 
        SET quota = quota + NEW.quota_amount 
        WHERE id = NEW.user_id;
    END IF;
END //
DELIMITER ;

-- ============================================
-- 15. 数据验证和完整性检查
-- ============================================

-- 检查用户表数据完整性
SELECT 'Users with invalid email' AS check_name, COUNT(*) AS count
FROM users 
WHERE email IS NOT NULL AND email NOT REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$';

-- 检查令牌表数据完整性
SELECT 'Tokens with invalid key format' AS check_name, COUNT(*) AS count
FROM tokens 
WHERE `key` NOT REGEXP '^sk-[a-zA-Z0-9]{32}$';

-- 检查账单记录数据完整性
SELECT 'Billing records with negative amounts' AS check_name, COUNT(*) AS count
FROM billing_records 
WHERE amount < 0 OR quota_amount < 0;

-- ============================================
-- 16. 性能优化建议
-- ============================================

-- 分析表并优化
-- ANALYZE TABLE users, tokens, logs, billing_records, providers, provider_models;

-- 检查慢查询
-- SELECT * FROM mysql.slow_log WHERE start_time > DATE_SUB(NOW(), INTERVAL 1 DAY);

-- 建议的定期维护任务：
-- 1. 每日清理过期的验证令牌
-- 2. 每周分析表性能
-- 3. 每月归档旧的日志数据
-- 4. 每季度检查索引使用情况

-- ============================================
-- 迁移完成标记
-- ============================================

INSERT INTO options (name, value, description) VALUES
('DatabaseVersion', '1.0.0', '数据库版本号'),
('MigrationDate', NOW(), '最后迁移时间'),
('MigrationStatus', 'completed', '迁移状态')
ON DUPLICATE KEY UPDATE 
    value = VALUES(value),
    description = VALUES(description);

-- 输出迁移完成信息
SELECT 
    'Database migration completed successfully!' AS status,
    NOW() AS completion_time,
    '1.0.0' AS version;
