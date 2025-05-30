# 账户系统增强实施方案

## 概述

本文档详细描述账户系统的增强实施方案，包括邮箱注册、登录优化、密码管理等功能。

## 1. 邮箱注册功能

### 1.1 数据库变更

```sql
-- 为用户表添加邮箱验证相关字段
ALTER TABLE users ADD COLUMN email_verified BOOLEAN DEFAULT FALSE COMMENT '邮箱是否已验证';
ALTER TABLE users ADD COLUMN email_verification_token VARCHAR(64) COMMENT '邮箱验证令牌';
ALTER TABLE users ADD COLUMN email_verification_expires_at TIMESTAMP NULL COMMENT '验证令牌过期时间';

-- 添加索引
CREATE INDEX idx_users_email_verification_token ON users(email_verification_token);
CREATE INDEX idx_users_email_verified ON users(email_verified);
```

### 1.2 后端实现

#### 1.2.1 扩展用户模型

```go
// model/user.go 添加字段
type User struct {
    // ... 现有字段
    EmailVerified           bool      `json:"email_verified" gorm:"default:false"`
    EmailVerificationToken  string    `json:"-" gorm:"type:varchar(64)"`
    EmailVerificationExpires *time.Time `json:"-"`
}

// 生成邮箱验证令牌
func (user *User) GenerateEmailVerificationToken() error {
    token := common.GetRandomString(32)
    expires := time.Now().Add(24 * time.Hour) // 24小时过期
    
    user.EmailVerificationToken = token
    user.EmailVerificationExpires = &expires
    
    return DB.Model(user).Updates(map[string]interface{}{
        "email_verification_token": token,
        "email_verification_expires_at": expires,
    }).Error
}

// 验证邮箱令牌
func (user *User) VerifyEmailToken(token string) error {
    if user.EmailVerificationToken != token {
        return errors.New("无效的验证令牌")
    }
    
    if user.EmailVerificationExpires != nil && time.Now().After(*user.EmailVerificationExpires) {
        return errors.New("验证令牌已过期")
    }
    
    return DB.Model(user).Updates(map[string]interface{}{
        "email_verified": true,
        "email_verification_token": "",
        "email_verification_expires_at": nil,
    }).Error
}
```

#### 1.2.2 注册接口增强

```go
// controller/user.go 修改注册函数
func Register(c *gin.Context) {
    if !common.RegisterEnabled {
        c.JSON(http.StatusOK, gin.H{
            "message": "管理员关闭了新用户注册",
            "success": false,
        })
        return
    }

    var user model.User
    err := json.NewDecoder(c.Request.Body).Decode(&user)
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "无效的参数",
        })
        return
    }

    // 验证必填字段
    if user.Username == "" || user.Password == "" || user.Email == "" {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "用户名、密码和邮箱不能为空",
        })
        return
    }

    // 验证邮箱格式
    if !isValidEmail(user.Email) {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "邮箱格式不正确",
        })
        return
    }

    // 检查用户是否已存在
    exist, err := model.CheckUserExistOrDeleted(user.Username, user.Email)
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "数据库错误，请稍后重试",
        })
        return
    }
    if exist {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "用户名或邮箱已存在",
        })
        return
    }

    // 创建用户
    cleanUser := model.User{
        Username:    user.Username,
        Password:    user.Password,
        DisplayName: user.Username,
        Email:       user.Email,
        EmailVerified: false,
    }

    if err := cleanUser.Insert(0); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": err.Error(),
        })
        return
    }

    // 生成验证令牌并发送邮件
    if err := cleanUser.GenerateEmailVerificationToken(); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "生成验证令牌失败",
        })
        return
    }

    // 发送验证邮件
    if err := sendVerificationEmail(cleanUser.Email, cleanUser.EmailVerificationToken); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "发送验证邮件失败",
        })
        return
    }

    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "message": "注册成功，请查收验证邮件",
    })
}

// 邮箱验证接口
func VerifyEmail(c *gin.Context) {
    token := c.Query("token")
    if token == "" {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "验证令牌不能为空",
        })
        return
    }

    var user model.User
    err := model.DB.Where("email_verification_token = ?", token).First(&user).Error
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "无效的验证令牌",
        })
        return
    }

    if err := user.VerifyEmailToken(token); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": err.Error(),
        })
        return
    }

    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "message": "邮箱验证成功",
    })
}

// 重发验证邮件
func ResendVerificationEmail(c *gin.Context) {
    email := c.Query("email")
    if email == "" {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "邮箱地址不能为空",
        })
        return
    }

    var user model.User
    err := model.DB.Where("email = ? AND email_verified = false", email).First(&user).Error
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "用户不存在或邮箱已验证",
        })
        return
    }

    // 生成新的验证令牌
    if err := user.GenerateEmailVerificationToken(); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "生成验证令牌失败",
        })
        return
    }

    // 发送验证邮件
    if err := sendVerificationEmail(user.Email, user.EmailVerificationToken); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "发送验证邮件失败",
        })
        return
    }

    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "message": "验证邮件已重新发送",
    })
}
```

#### 1.2.3 邮件发送服务

```go
// service/email_verification.go
package service

import (
    "fmt"
    "one-api/common"
    "net/smtp"
    "strings"
)

func sendVerificationEmail(email, token string) error {
    if !common.EmailEnabled {
        return fmt.Errorf("邮件服务未启用")
    }

    verificationURL := fmt.Sprintf("%s/verify-email?token=%s", common.ServerAddress, token)
    
    subject := "验证您的邮箱地址"
    body := fmt.Sprintf(`
        <html>
        <body>
            <h2>欢迎注册 New API</h2>
            <p>请点击下面的链接验证您的邮箱地址：</p>
            <p><a href="%s">验证邮箱</a></p>
            <p>如果链接无法点击，请复制以下地址到浏览器：</p>
            <p>%s</p>
            <p>此链接24小时内有效。</p>
        </body>
        </html>
    `, verificationURL, verificationURL)

    return common.SendEmail(email, subject, body)
}

// 邮箱格式验证
func isValidEmail(email string) bool {
    return strings.Contains(email, "@") && strings.Contains(email, ".")
}
```

### 1.3 前端实现

#### 1.3.1 注册页面组件

```jsx
// web/src/pages/Register/index.jsx
import React, { useState } from 'react';
import { Form, Input, Button, message } from 'antd';
import { UserOutlined, LockOutlined, MailOutlined } from '@ant-design/icons';
import { register } from '../../services/auth';

const Register = () => {
    const [loading, setLoading] = useState(false);
    const [form] = Form.useForm();

    const onFinish = async (values) => {
        setLoading(true);
        try {
            const response = await register(values);
            if (response.success) {
                message.success('注册成功，请查收验证邮件');
                // 跳转到邮箱验证提示页面
                window.location.href = '/email-verification-sent';
            } else {
                message.error(response.message);
            }
        } catch (error) {
            message.error('注册失败，请重试');
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="register-container">
            <Form
                form={form}
                name="register"
                onFinish={onFinish}
                autoComplete="off"
            >
                <Form.Item
                    name="username"
                    rules={[
                        { required: true, message: '请输入用户名' },
                        { min: 3, max: 12, message: '用户名长度为3-12个字符' }
                    ]}
                >
                    <Input 
                        prefix={<UserOutlined />} 
                        placeholder="用户名" 
                    />
                </Form.Item>

                <Form.Item
                    name="email"
                    rules={[
                        { required: true, message: '请输入邮箱地址' },
                        { type: 'email', message: '请输入有效的邮箱地址' }
                    ]}
                >
                    <Input 
                        prefix={<MailOutlined />} 
                        placeholder="邮箱地址" 
                    />
                </Form.Item>

                <Form.Item
                    name="password"
                    rules={[
                        { required: true, message: '请输入密码' },
                        { min: 8, max: 20, message: '密码长度为8-20个字符' }
                    ]}
                >
                    <Input.Password 
                        prefix={<LockOutlined />} 
                        placeholder="密码" 
                    />
                </Form.Item>

                <Form.Item
                    name="confirmPassword"
                    dependencies={['password']}
                    rules={[
                        { required: true, message: '请确认密码' },
                        ({ getFieldValue }) => ({
                            validator(_, value) {
                                if (!value || getFieldValue('password') === value) {
                                    return Promise.resolve();
                                }
                                return Promise.reject(new Error('两次输入的密码不一致'));
                            },
                        }),
                    ]}
                >
                    <Input.Password 
                        prefix={<LockOutlined />} 
                        placeholder="确认密码" 
                    />
                </Form.Item>

                <Form.Item>
                    <Button 
                        type="primary" 
                        htmlType="submit" 
                        loading={loading}
                        block
                    >
                        注册
                    </Button>
                </Form.Item>
            </Form>
        </div>
    );
};

export default Register;
```

## 2. 邮箱登录功能

### 2.1 后端实现

```go
// controller/user.go 修改登录函数
func Login(c *gin.Context) {
    if !common.PasswordLoginEnabled {
        c.JSON(http.StatusOK, gin.H{
            "message": "管理员关闭了密码登录",
            "success": false,
        })
        return
    }

    var loginRequest LoginRequest
    err := json.NewDecoder(c.Request.Body).Decode(&loginRequest)
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "message": "无效的参数",
            "success": false,
        })
        return
    }

    username := strings.TrimSpace(loginRequest.Username)
    password := loginRequest.Password
    
    if username == "" || password == "" {
        c.JSON(http.StatusOK, gin.H{
            "message": "用户名/邮箱和密码不能为空",
            "success": false,
        })
        return
    }

    user := model.User{
        Username: username,
        Password: password,
    }
    
    // 支持用户名或邮箱登录
    err = user.ValidateAndFillByUsernameOrEmail()
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "message": err.Error(),
            "success": false,
        })
        return
    }

    // 检查邮箱是否已验证（如果启用了邮箱验证）
    if common.EmailVerificationEnabled && !user.EmailVerified {
        c.JSON(http.StatusOK, gin.H{
            "message": "请先验证邮箱后再登录",
            "success": false,
        })
        return
    }

    setupLogin(&user, c)
}
```

### 2.2 用户模型扩展

```go
// model/user.go 添加方法
func (user *User) ValidateAndFillByUsernameOrEmail() error {
    password := user.Password
    usernameOrEmail := strings.TrimSpace(user.Username)
    
    if usernameOrEmail == "" || password == "" {
        return errors.New("用户名/邮箱或密码为空")
    }

    // 尝试通过用户名或邮箱查找用户
    var dbUser User
    err := DB.Where("username = ? OR email = ?", usernameOrEmail, usernameOrEmail).First(&dbUser).Error
    if err != nil {
        return errors.New("用户名/邮箱或密码错误")
    }

    // 验证密码
    if !common.ValidatePasswordAndHash(password, dbUser.Password) {
        return errors.New("用户名/邮箱或密码错误")
    }

    // 检查用户状态
    if dbUser.Status != common.UserStatusEnabled {
        return errors.New("用户已被封禁")
    }

    // 填充用户信息
    *user = dbUser
    return nil
}
```

## 3. 密码管理功能

### 3.1 修改密码接口

```go
// controller/user.go 添加修改密码接口
func ChangePassword(c *gin.Context) {
    var req struct {
        OldPassword string `json:"old_password" binding:"required"`
        NewPassword string `json:"new_password" binding:"required,min=8,max=20"`
    }

    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "参数错误",
        })
        return
    }

    userId := c.GetInt("id")
    user, err := model.GetUserById(userId, true)
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "用户不存在",
        })
        return
    }

    // 验证旧密码
    if !common.ValidatePasswordAndHash(req.OldPassword, user.Password) {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "原密码错误",
        })
        return
    }

    // 更新密码
    user.Password = req.NewPassword
    if err := user.Update(true); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "密码更新失败",
        })
        return
    }

    // 记录日志
    model.RecordLog(userId, model.LogTypeSystem, "用户修改密码")

    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "message": "密码修改成功",
    })
}
```

### 3.2 路由配置

```go
// router/api-router.go 添加路由
selfRoute := userRoute.Group("/")
selfRoute.Use(middleware.UserAuth())
{
    // ... 现有路由
    selfRoute.POST("/change-password", controller.ChangePassword)
    selfRoute.GET("/verify-email", controller.VerifyEmail)
    selfRoute.POST("/resend-verification", controller.ResendVerificationEmail)
}
```

## 4. 测试方案

### 4.1 单元测试

```go
// test/user_test.go
package test

import (
    "testing"
    "one-api/model"
)

func TestEmailVerification(t *testing.T) {
    user := &model.User{
        Username: "testuser",
        Email:    "test@example.com",
        Password: "testpassword",
    }

    // 测试生成验证令牌
    err := user.GenerateEmailVerificationToken()
    if err != nil {
        t.Errorf("生成验证令牌失败: %v", err)
    }

    // 测试验证令牌
    err = user.VerifyEmailToken(user.EmailVerificationToken)
    if err != nil {
        t.Errorf("验证令牌失败: %v", err)
    }

    if !user.EmailVerified {
        t.Error("邮箱验证状态未更新")
    }
}
```

### 4.2 集成测试

```bash
#!/bin/bash
# test/integration_test.sh

# 测试注册接口
curl -X POST http://localhost:3000/api/user/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "testpassword"
  }'

# 测试登录接口
curl -X POST http://localhost:3000/api/user/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "test@example.com",
    "password": "testpassword"
  }'
```

## 5. 部署注意事项

### 5.1 环境变量配置

```bash
# .env 文件添加
EMAIL_VERIFICATION_ENABLED=true
EMAIL_SMTP_HOST=smtp.gmail.com
EMAIL_SMTP_PORT=587
EMAIL_SMTP_USERNAME=your-email@gmail.com
EMAIL_SMTP_PASSWORD=your-app-password
SERVER_ADDRESS=https://your-domain.com
```

### 5.2 数据库迁移

```sql
-- 生产环境迁移脚本
-- migration_email_verification.sql

START TRANSACTION;

-- 添加邮箱验证相关字段
ALTER TABLE users 
ADD COLUMN email_verified BOOLEAN DEFAULT FALSE COMMENT '邮箱是否已验证',
ADD COLUMN email_verification_token VARCHAR(64) COMMENT '邮箱验证令牌',
ADD COLUMN email_verification_expires_at TIMESTAMP NULL COMMENT '验证令牌过期时间';

-- 添加索引
CREATE INDEX idx_users_email_verification_token ON users(email_verification_token);
CREATE INDEX idx_users_email_verified ON users(email_verified);

-- 将现有用户的邮箱设置为已验证（向后兼容）
UPDATE users SET email_verified = TRUE WHERE email IS NOT NULL AND email != '';

COMMIT;
```

## 6. 监控和维护

### 6.1 监控指标

- 注册成功率
- 邮箱验证率
- 登录成功率
- 密码重置请求数量

### 6.2 日志记录

```go
// 在关键操作中添加日志
common.SysLog(fmt.Sprintf("用户 %s 注册成功", user.Username))
common.SysLog(fmt.Sprintf("用户 %s 邮箱验证成功", user.Email))
common.SysLog(fmt.Sprintf("用户 %s 登录成功", user.Username))
```

---

**文档版本**：v1.0  
**创建时间**：2025年5月30日  
**最后更新**：2025年5月30日
