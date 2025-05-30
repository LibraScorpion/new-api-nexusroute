# 充值和账单系统实施方案

## 概述

本文档详细描述充值界面和账单系统的实施方案，包括支付集成、账单管理、交易记录等功能。

## 1. 充值系统增强

### 1.1 数据库设计

```sql
-- 账单记录表
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
);

-- 充值配置表
CREATE TABLE topup_configs (
    id INT PRIMARY KEY AUTO_INCREMENT,
    amount INT NOT NULL COMMENT '充值金额',
    bonus_amount INT DEFAULT 0 COMMENT '赠送金额',
    price DECIMAL(10,2) NOT NULL COMMENT '实际价格',
    is_active BOOLEAN DEFAULT TRUE COMMENT '是否启用',
    sort_order INT DEFAULT 0 COMMENT '排序',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- 插入默认充值配置
INSERT INTO topup_configs (amount, price, sort_order) VALUES
(50, 5.00, 1),
(100, 10.00, 2),
(150, 15.00, 3),
(200, 20.00, 4),
(300, 30.00, 5),
(500, 50.00, 6),
(1000, 100.00, 7);
```

### 1.2 后端模型实现

#### 1.2.1 账单记录模型

```go
// model/billing.go
package model

import (
    "encoding/json"
    "time"
    "gorm.io/gorm"
)

type BillingRecord struct {
    Id            int64                  `json:"id" gorm:"primaryKey"`
    UserId        int                    `json:"user_id" gorm:"not null;index"`
    Type          string                 `json:"type" gorm:"type:enum('topup','consumption','refund');not null"`
    Amount        float64                `json:"amount" gorm:"type:decimal(10,2);not null"`
    QuotaAmount   int64                  `json:"quota_amount" gorm:"not null"`
    Description   string                 `json:"description" gorm:"type:text"`
    TransactionId string                 `json:"transaction_id" gorm:"type:varchar(64);index"`
    PaymentMethod string                 `json:"payment_method" gorm:"type:enum('alipay','wechat','bank','other')"`
    Status        string                 `json:"status" gorm:"type:enum('pending','completed','failed','cancelled');default:'pending';index"`
    Metadata      map[string]interface{} `json:"metadata" gorm:"type:json"`
    CreatedAt     time.Time              `json:"created_at"`
    UpdatedAt     time.Time              `json:"updated_at"`
}

func (br *BillingRecord) TableName() string {
    return "billing_records"
}

// 创建账单记录
func (br *BillingRecord) Insert() error {
    return DB.Create(br).Error
}

// 更新账单记录
func (br *BillingRecord) Update() error {
    return DB.Save(br).Error
}

// 获取用户账单列表
func GetUserBillingRecords(userId int, page, pageSize int) ([]*BillingRecord, int64, error) {
    var records []*BillingRecord
    var total int64
    
    offset := (page - 1) * pageSize
    
    err := DB.Model(&BillingRecord{}).Where("user_id = ?", userId).Count(&total).Error
    if err != nil {
        return nil, 0, err
    }
    
    err = DB.Where("user_id = ?", userId).
        Order("created_at DESC").
        Limit(pageSize).
        Offset(offset).
        Find(&records).Error
    
    return records, total, err
}

// 获取账单统计
func GetUserBillingStats(userId int, startTime, endTime time.Time) (map[string]interface{}, error) {
    var stats struct {
        TotalTopup      float64 `json:"total_topup"`
        TotalConsumption float64 `json:"total_consumption"`
        TransactionCount int64   `json:"transaction_count"`
    }
    
    // 总充值金额
    err := DB.Model(&BillingRecord{}).
        Where("user_id = ? AND type = 'topup' AND status = 'completed' AND created_at BETWEEN ? AND ?", 
              userId, startTime, endTime).
        Select("COALESCE(SUM(amount), 0)").
        Scan(&stats.TotalTopup).Error
    if err != nil {
        return nil, err
    }
    
    // 总消费金额
    err = DB.Model(&BillingRecord{}).
        Where("user_id = ? AND type = 'consumption' AND created_at BETWEEN ? AND ?", 
              userId, startTime, endTime).
        Select("COALESCE(SUM(amount), 0)").
        Scan(&stats.TotalConsumption).Error
    if err != nil {
        return nil, err
    }
    
    // 交易次数
    err = DB.Model(&BillingRecord{}).
        Where("user_id = ? AND created_at BETWEEN ? AND ?", userId, startTime, endTime).
        Count(&stats.TransactionCount).Error
    if err != nil {
        return nil, err
    }
    
    return map[string]interface{}{
        "total_topup":       stats.TotalTopup,
        "total_consumption": stats.TotalConsumption,
        "transaction_count": stats.TransactionCount,
    }, nil
}
```

#### 1.2.2 充值配置模型

```go
// model/topup_config.go
package model

type TopupConfig struct {
    Id          int     `json:"id" gorm:"primaryKey"`
    Amount      int     `json:"amount" gorm:"not null"`
    BonusAmount int     `json:"bonus_amount" gorm:"default:0"`
    Price       float64 `json:"price" gorm:"type:decimal(10,2);not null"`
    IsActive    bool    `json:"is_active" gorm:"default:true"`
    SortOrder   int     `json:"sort_order" gorm:"default:0"`
    CreatedAt   time.Time `json:"created_at"`
    UpdatedAt   time.Time `json:"updated_at"`
}

func (tc *TopupConfig) TableName() string {
    return "topup_configs"
}

// 获取所有启用的充值配置
func GetActiveTopupConfigs() ([]*TopupConfig, error) {
    var configs []*TopupConfig
    err := DB.Where("is_active = true").Order("sort_order ASC").Find(&configs).Error
    return configs, err
}

// 获取充值配置
func GetTopupConfigByAmount(amount int) (*TopupConfig, error) {
    var config TopupConfig
    err := DB.Where("amount = ? AND is_active = true", amount).First(&config).Error
    return &config, err
}
```

### 1.3 控制器实现

#### 1.3.1 充值控制器增强

```go
// controller/topup_enhanced.go
package controller

import (
    "fmt"
    "net/http"
    "strconv"
    "time"
    "one-api/common"
    "one-api/model"
    "github.com/gin-gonic/gin"
)

// 获取充值配置
func GetTopupConfigs(c *gin.Context) {
    configs, err := model.GetActiveTopupConfigs()
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "获取充值配置失败",
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "data":    configs,
    })
}

// 增强的充值请求
func RequestTopupEnhanced(c *gin.Context) {
    var req struct {
        Amount        int    `json:"amount" binding:"required"`
        PaymentMethod string `json:"payment_method" binding:"required"`
        CustomAmount  bool   `json:"custom_amount"`
    }
    
    if err := c.ShouldBindJSON(&req); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "参数错误",
        })
        return
    }
    
    userId := c.GetInt("id")
    
    // 验证充值金额
    var config *model.TopupConfig
    var err error
    
    if !req.CustomAmount {
        config, err = model.GetTopupConfigByAmount(req.Amount)
        if err != nil {
            c.JSON(http.StatusOK, gin.H{
                "success": false,
                "message": "无效的充值金额",
            })
            return
        }
    } else {
        // 自定义金额验证
        if req.Amount < 10 || req.Amount > 10000 {
            c.JSON(http.StatusOK, gin.H{
                "success": false,
                "message": "自定义充值金额范围为10-10000",
            })
            return
        }
        
        // 创建临时配置
        config = &model.TopupConfig{
            Amount: req.Amount,
            Price:  float64(req.Amount) * 0.1, // 假设1元=10额度
        }
    }
    
    // 创建账单记录
    billingRecord := &model.BillingRecord{
        UserId:        userId,
        Type:          "topup",
        Amount:        config.Price,
        QuotaAmount:   int64(config.Amount + config.BonusAmount),
        Description:   fmt.Sprintf("充值 %d 额度", config.Amount),
        PaymentMethod: req.PaymentMethod,
        Status:        "pending",
        Metadata: map[string]interface{}{
            "original_amount": config.Amount,
            "bonus_amount":    config.BonusAmount,
            "price":          config.Price,
        },
    }
    
    if err := billingRecord.Insert(); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "创建订单失败",
        })
        return
    }
    
    // 生成交易ID
    tradeNo := fmt.Sprintf("TOP%d%d", userId, time.Now().Unix())
    billingRecord.TransactionId = tradeNo
    billingRecord.Update()
    
    // 调用支付接口
    paymentResult, err := processPayment(billingRecord, req.PaymentMethod)
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "支付请求失败: " + err.Error(),
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "data": gin.H{
            "transaction_id": tradeNo,
            "payment_url":    paymentResult.PaymentURL,
            "qr_code":        paymentResult.QRCode,
            "amount":         config.Price,
        },
    })
}

// 支付结果结构
type PaymentResult struct {
    PaymentURL string `json:"payment_url"`
    QRCode     string `json:"qr_code"`
}

// 处理支付
func processPayment(record *model.BillingRecord, method string) (*PaymentResult, error) {
    // 这里集成具体的支付SDK
    switch method {
    case "alipay":
        return processAlipay(record)
    case "wechat":
        return processWechatPay(record)
    default:
        return nil, fmt.Errorf("不支持的支付方式")
    }
}

// 支付宝支付处理
func processAlipay(record *model.BillingRecord) (*PaymentResult, error) {
    // 集成支付宝SDK
    // 这里使用现有的Epay系统
    client := GetEpayClient()
    if client == nil {
        return nil, fmt.Errorf("支付配置错误")
    }
    
    // 调用支付宝接口
    // ... 支付宝具体实现
    
    return &PaymentResult{
        PaymentURL: "https://payment.example.com/alipay",
        QRCode:     "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...",
    }, nil
}

// 微信支付处理
func processWechatPay(record *model.BillingRecord) (*PaymentResult, error) {
    // 集成微信支付SDK
    // ... 微信支付具体实现
    
    return &PaymentResult{
        PaymentURL: "https://payment.example.com/wechat",
        QRCode:     "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...",
    }, nil
}
```

#### 1.3.2 账单控制器

```go
// controller/billing.go
package controller

import (
    "net/http"
    "strconv"
    "time"
    "one-api/model"
    "github.com/gin-gonic/gin"
)

// 获取用户账单列表
func GetUserBilling(c *gin.Context) {
    userId := c.GetInt("id")
    page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
    pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
    
    if page < 1 {
        page = 1
    }
    if pageSize < 1 || pageSize > 100 {
        pageSize = 20
    }
    
    records, total, err := model.GetUserBillingRecords(userId, page, pageSize)
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "获取账单失败",
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "data": gin.H{
            "records":   records,
            "total":     total,
            "page":      page,
            "page_size": pageSize,
        },
    })
}

// 获取账单详情
func GetBillingDetail(c *gin.Context) {
    userId := c.GetInt("id")
    recordId, err := strconv.ParseInt(c.Param("id"), 10, 64)
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "无效的记录ID",
        })
        return
    }
    
    var record model.BillingRecord
    err = model.DB.Where("id = ? AND user_id = ?", recordId, userId).First(&record).Error
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "记录不存在",
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "data":    record,
    })
}

// 获取账单统计
func GetBillingStats(c *gin.Context) {
    userId := c.GetInt("id")
    
    // 获取时间范围参数
    startTimeStr := c.DefaultQuery("start_time", "")
    endTimeStr := c.DefaultQuery("end_time", "")
    
    var startTime, endTime time.Time
    var err error
    
    if startTimeStr != "" {
        startTime, err = time.Parse("2006-01-02", startTimeStr)
        if err != nil {
            c.JSON(http.StatusOK, gin.H{
                "success": false,
                "message": "开始时间格式错误",
            })
            return
        }
    } else {
        // 默认最近30天
        startTime = time.Now().AddDate(0, 0, -30)
    }
    
    if endTimeStr != "" {
        endTime, err = time.Parse("2006-01-02", endTimeStr)
        if err != nil {
            c.JSON(http.StatusOK, gin.H{
                "success": false,
                "message": "结束时间格式错误",
            })
            return
        }
    } else {
        endTime = time.Now()
    }
    
    stats, err := model.GetUserBillingStats(userId, startTime, endTime)
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "获取统计数据失败",
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "data":    stats,
    })
}
```

### 1.4 前端实现

#### 1.4.1 充值页面组件

```jsx
// web/src/pages/TopUp/index.jsx
import React, { useState, useEffect } from 'react';
import { Card, Row, Col, Button, Input, Radio, Modal, message, Spin } from 'antd';
import { AlipayOutlined, WechatOutlined, DollarOutlined } from '@ant-design/icons';
import { getTopupConfigs, requestTopup, getUserInfo } from '../../services/api';
import PaymentModal from './PaymentModal';
import './styles.css';

const TopUp = () => {
    const [loading, setLoading] = useState(false);
    const [configs, setConfigs] = useState([]);
    const [selectedAmount, setSelectedAmount] = useState(null);
    const [customAmount, setCustomAmount] = useState('');
    const [paymentMethod, setPaymentMethod] = useState('alipay');
    const [userInfo, setUserInfo] = useState(null);
    const [paymentModalVisible, setPaymentModalVisible] = useState(false);
    const [paymentData, setPaymentData] = useState(null);

    useEffect(() => {
        loadData();
    }, []);

    const loadData = async () => {
        setLoading(true);
        try {
            const [configsRes, userRes] = await Promise.all([
                getTopupConfigs(),
                getUserInfo()
            ]);
            
            if (configsRes.success) {
                setConfigs(configsRes.data);
            }
            
            if (userRes.success) {
                setUserInfo(userRes.data);
            }
        } catch (error) {
            message.error('加载数据失败');
        } finally {
            setLoading(false);
        }
    };

    const handleAmountSelect = (config) => {
        setSelectedAmount(config);
        setCustomAmount('');
    };

    const handleCustomAmountChange = (e) => {
        const value = e.target.value;
        if (value && !isNaN(value)) {
            setCustomAmount(value);
            setSelectedAmount(null);
        } else {
            setCustomAmount('');
        }
    };

    const handleTopup = async () => {
        const amount = selectedAmount ? selectedAmount.amount : parseInt(customAmount);
        
        if (!amount || amount <= 0) {
            message.error('请选择充值金额');
            return;
        }

        if (!paymentMethod) {
            message.error('请选择支付方式');
            return;
        }

        setLoading(true);
        try {
            const response = await requestTopup({
                amount,
                payment_method: paymentMethod,
                custom_amount: !selectedAmount
            });

            if (response.success) {
                setPaymentData(response.data);
                setPaymentModalVisible(true);
            } else {
                message.error(response.message);
            }
        } catch (error) {
            message.error('发起充值失败');
        } finally {
            setLoading(false);
        }
    };

    const formatQuota = (quota) => {
        return (quota / 500000).toFixed(2);
    };

    return (
        <div className="topup-container">
            <Row gutter={[24, 24]}>
                {/* 余额显示 */}
                <Col span={24}>
                    <Card title="账户余额" className="balance-card">
                        <div className="balance-info">
                            <div className="balance-amount">
                                <DollarOutlined className="balance-icon" />
                                <span className="balance-value">
                                    {userInfo ? formatQuota(userInfo.quota) : '0.00'}
                                </span>
                                <span className="balance-unit">元</span>
                            </div>
                            <div className="balance-desc">
                                可用额度：{userInfo ? userInfo.quota.toLocaleString() : '0'}
                            </div>
                        </div>
                    </Card>
                </Col>

                {/* 充值金额选择 */}
                <Col span={24}>
                    <Card title="选择充值金额" loading={loading}>
                        <Row gutter={[16, 16]}>
                            {configs.map(config => (
                                <Col xs={12} sm={8} md={6} key={config.id}>
                                    <Card
                                        className={`amount-card ${selectedAmount?.id === config.id ? 'selected' : ''}`}
                                        onClick={() => handleAmountSelect(config)}
                                        hoverable
                                    >
                                        <div className="amount-value">{config.amount}</div>
                                        <div className="amount-price">¥{config.price}</div>
                                        {config.bonus_amount > 0 && (
                                            <div className="amount-bonus">
                                                赠送 {config.bonus_amount}
                                            </div>
                                        )}
                                    </Card>
                                </Col>
                            ))}
                        </Row>

                        {/* 自定义金额 */}
                        <div className="custom-amount">
                            <h4>自定义金额</h4>
                            <Input
                                placeholder="请输入充值金额 (10-10000)"
                                value={customAmount}
                                onChange={handleCustomAmountChange}
                                type="number"
                                min={10}
                                max={10000}
                                addonAfter="额度"
                            />
                        </div>
                    </Card>
                </Col>

                {/* 支付方式选择 */}
                <Col span={24}>
                    <Card title="选择支付方式">
                        <Radio.Group
                            value={paymentMethod}
                            onChange={(e) => setPaymentMethod(e.target.value)}
                            className="payment-methods"
                        >
                            <Radio.Button value="alipay" className="payment-method">
                                <AlipayOutlined /> 支付宝
                            </Radio.Button>
                            <Radio.Button value="wechat" className="payment-method">
                                <WechatOutlined /> 微信支付
                            </Radio.Button>
                        </Radio.Group>
                    </Card>
                </Col>

                {/* 充值按钮 */}
                <Col span={24}>
                    <Card>
                        <Button
                            type="primary"
                            size="large"
                            block
                            loading={loading}
                            onClick={handleTopup}
                            className="topup-button"
                        >
                            立即充值
                        </Button>
                    </Card>
                </Col>
            </Row>

            {/* 支付弹窗 */}
            <PaymentModal
                visible={paymentModalVisible}
                onCancel={() => setPaymentModalVisible(false)}
                paymentData={paymentData}
                onSuccess={() => {
                    setPaymentModalVisible(false);
                    loadData(); // 刷新余额
                    message.success('充值成功');
                }}
            />
        </div>
    );
};

export default TopUp;
```

#### 1.4.2 支付弹窗组件

```jsx
// web/src/pages/TopUp/PaymentModal.jsx
import React, { useState, useEffect } from 'react';
import { Modal, QRCode, Button, Result, Spin } from 'antd';
import { CheckCircleOutlined, CloseCircleOutlined } from '@ant-design/icons';

const PaymentModal = ({ visible, onCancel, paymentData, onSuccess }) => {
    const [paymentStatus, setPaymentStatus] = useState('pending'); // pending, success, failed
    const [countdown, setCountdown] = useState(300); // 5分钟倒计时

    useEffect(() => {
        if (visible && paymentData) {
            setPaymentStatus('pending');
            setCountdown(300);
            
            // 开始轮询支付状态
            const pollInterval = setInterval(() => {
                checkPaymentStatus(paymentData.transaction_id);
            }, 3000);

            // 倒计时
            const countdownInterval = setInterval(() => {
                setCountdown(prev => {
                    if (prev <= 1) {
                        clearInterval(pollInterval);
                        clearInterval(countdownInterval);
                        setPaymentStatus('failed');
                        return 0;
                    }
                    return prev - 1;
                });
            }, 1000);

            return () => {
                clearInterval(pollInterval);
                clearInterval(countdownInterval);
            };
        }
    }, [visible, paymentData]);

    const checkPaymentStatus = async (transactionId) => {
        try {
            // 这里调用检查支付状态的API
            const response = await fetch(`/api/payment/status/${transactionId}`);
            const result = await response.json();
            
            if (result.success && result.data.status === 'completed') {
                setPaymentStatus('success');
                setTimeout(() => {
                    onSuccess();
                }, 1500);
            }
        } catch (error) {
            console.error('检查支付状态失败:', error);
        }
    };

    const formatTime = (seconds) => {
        const mins = Math.floor(seconds / 60);
        const secs = seconds % 60;
        return `${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    };

    const renderContent = () => {
        if (paymentStatus === 'success') {
            return (
                <Result
                    icon={<CheckCircleOutlined style={{ color: '#52c41a' }} />}
                    title="支付成功"
                    subTitle="充值已完成，余额已更新"
                />
            );
        }

        if (paymentStatus === 'failed') {
            return (
                <Result
                    icon={<CloseCircleOutlined style={{ color: '#ff4d4f' }} />}
                    title="支付超时"
                    subTitle="请重新发起充值"
                />
            );
        }

        return (
            <div className="payment-content">
                <div className="payment-info">
                    <h3>扫码支付</h3>
                    <p>支付金额：¥{paymentData?.amount}</p>
                    <p>剩余时间：{formatTime(countdown)}</p>
                </div>
                
                <div className="qr-code-container">
                    {paymentData?.qr_code ? (
                        <img 
                            src={paymentData.qr_code} 
                            alt="支付二维码"
                            style={{ width: 200, height: 200 }}
                        />
                    ) : (
                        <QRCode 
                            value={paymentData?.payment_url || ''} 
                            size={200}
                        />
                    )}
                </div>

                <div className="payment-tips">
                    <p>请使用对应的支付应用扫描二维码完成支付</p>
                    <p>支付完成后页面将自动跳转</p>
                </div>
            </div>
        );
    };

    return (
        <Modal
            title="完成支付"
            open={visible}
            onCancel={onCancel}
            footer={paymentStatus !== 'pending' ? [
                <Button key="close" onClick={onCancel}>
                    关闭
                </Button>
            ] : null}
            width={400}
            centered
        >
            {renderContent()}
        </Modal>
    );
};

export default PaymentModal;
```

### 1.5 路由配置

```go
// router/api-router.go 添加路由
selfRoute := userRoute.Group("/")
selfRoute.Use(middleware.UserAuth())
{
    // ... 现有路由
    selfRoute.GET("/topup/configs", controller.GetTopupConfigs)
    selfRoute.POST("/topup/request", controller.RequestTopupEnhanced)
    selfRoute.GET("/billing", controller.GetUserBilling)
    selfRoute.GET("/billing/:id", controller.GetBillingDetail)
    selfRoute.GET("/billing/stats", controller.GetBillingStats)
}
```

## 2. 支付回调处理

### 2.1 支付回
