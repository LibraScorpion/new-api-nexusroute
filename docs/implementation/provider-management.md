# 中台管理系统（M8）实施方案

## 概述

本文档详细描述中台管理系统的实施方案，包括供应商管理、API配置、模型管理等功能。

## 1. 供应商管理系统

### 1.1 数据库设计

```sql
-- 供应商表
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
    INDEX idx_priority (priority)
);

-- 供应商模型表
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
    INDEX idx_status (status)
);

-- 供应商统计表
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
);

-- 插入Antinomy AI供应商
INSERT INTO providers (name, base_url, api_key, api_format, status, priority, weight, config) VALUES
('Antinomy AI', 'https://antinomy.ai/api/v1', 'sk-fg-v1-74c17c85c6cc5f762fde1149a0da4f3165ff6199b9aab698425d371088909306', 'openai', 'active', 1, 10, JSON_OBJECT(
    'timeout', 30,
    'retry_count', 3,
    'retry_delay', 1000,
    'headers', JSON_OBJECT('User-Agent', 'New-API/1.0')
));

-- 插入Antinomy AI模型
INSERT INTO provider_models (provider_id, model_name, display_name, model_type, input_price, output_price, max_tokens) VALUES
(1, 'anthropic/claude-opus-4', 'Claude Opus 4', 'chat', 0.000015, 0.000075, 200000),
(1, 'anthropic/claude-sonnet-4', 'Claude Sonnet 4', 'chat', 0.000003, 0.000015, 200000),
(1, 'anthropic/claude-3.7-sonnet', 'Claude 3.7 Sonnet', 'chat', 0.000003, 0.000015, 200000),
(1, 'anthropic/claude-3.5-sonnet', 'Claude 3.5 Sonnet', 'chat', 0.000003, 0.000015, 200000),
(1, 'anthropic/claude-3.7-sonnet:thinking', 'Claude 3.7 Sonnet (Thinking)', 'chat', 0.000003, 0.000015, 200000),
(1, 'google/gemini-2.5-pro-preview', 'Gemini 2.5 Pro Preview', 'chat', 0.000001, 0.000005, 1000000),
(1, 'x-ai/grok-3-beta', 'Grok 3 Beta', 'chat', 0.000002, 0.00001, 131072);
```

### 1.2 后端模型实现

#### 1.2.1 供应商模型

```go
// model/provider.go
package model

import (
    "encoding/json"
    "time"
    "gorm.io/gorm"
)

type Provider struct {
    Id        int                    `json:"id" gorm:"primaryKey"`
    Name      string                 `json:"name" gorm:"not null"`
    BaseURL   string                 `json:"base_url" gorm:"column:base_url;not null"`
    ApiKey    string                 `json:"api_key" gorm:"not null"`
    ApiFormat string                 `json:"api_format" gorm:"type:enum('openai','claude','custom');default:'openai'"`
    Status    string                 `json:"status" gorm:"type:enum('active','inactive','testing');default:'active'"`
    Priority  int                    `json:"priority" gorm:"default:0"`
    Weight    int                    `json:"weight" gorm:"default:1"`
    Config    map[string]interface{} `json:"config" gorm:"type:json"`
    RateLimit map[string]interface{} `json:"rate_limit" gorm:"type:json"`
    CreatedAt time.Time              `json:"created_at"`
    UpdatedAt time.Time              `json:"updated_at"`
    
    // 关联模型
    Models []ProviderModel `json:"models,omitempty" gorm:"foreignKey:ProviderId"`
}

func (p *Provider) TableName() string {
    return "providers"
}

// 创建供应商
func (p *Provider) Insert() error {
    return DB.Create(p).Error
}

// 更新供应商
func (p *Provider) Update() error {
    return DB.Save(p).Error
}

// 删除供应商
func (p *Provider) Delete() error {
    return DB.Delete(p).Error
}

// 获取所有供应商
func GetAllProviders() ([]*Provider, error) {
    var providers []*Provider
    err := DB.Preload("Models").Order("priority DESC, id ASC").Find(&providers).Error
    return providers, err
}

// 获取活跃供应商
func GetActiveProviders() ([]*Provider, error) {
    var providers []*Provider
    err := DB.Where("status = 'active'").
        Preload("Models", "status = 'active'").
        Order("priority DESC, weight DESC").
        Find(&providers).Error
    return providers, err
}

// 根据ID获取供应商
func GetProviderById(id int) (*Provider, error) {
    var provider Provider
    err := DB.Preload("Models").First(&provider, id).Error
    return &provider, err
}

// 测试供应商连接
func (p *Provider) TestConnection() error {
    // 实现连接测试逻辑
    // 发送一个简单的请求来测试API是否可用
    return nil
}
```

#### 1.2.2 供应商模型管理

```go
// model/provider_model.go
package model

type ProviderModel struct {
    Id          int                    `json:"id" gorm:"primaryKey"`
    ProviderId  int                    `json:"provider_id" gorm:"not null"`
    ModelName   string                 `json:"model_name" gorm:"not null"`
    DisplayName string                 `json:"display_name"`
    ModelType   string                 `json:"model_type" gorm:"type:enum('chat','embedding','image','audio');default:'chat'"`
    InputPrice  float64                `json:"input_price" gorm:"type:decimal(10,6);default:0"`
    OutputPrice float64                `json:"output_price" gorm:"type:decimal(10,6);default:0"`
    MaxTokens   int                    `json:"max_tokens" gorm:"default:4096"`
    Status      string                 `json:"status" gorm:"type:enum('active','inactive');default:'active'"`
    Config      map[string]interface{} `json:"config" gorm:"type:json"`
    CreatedAt   time.Time              `json:"created_at"`
    UpdatedAt   time.Time              `json:"updated_at"`
    
    // 关联供应商
    Provider Provider `json:"provider,omitempty" gorm:"foreignKey:ProviderId"`
}

func (pm *ProviderModel) TableName() string {
    return "provider_models"
}

// 创建模型
func (pm *ProviderModel) Insert() error {
    return DB.Create(pm).Error
}

// 更新模型
func (pm *ProviderModel) Update() error {
    return DB.Save(pm).Error
}

// 删除模型
func (pm *ProviderModel) Delete() error {
    return DB.Delete(pm).Error
}

// 获取供应商的所有模型
func GetProviderModels(providerId int) ([]*ProviderModel, error) {
    var models []*ProviderModel
    err := DB.Where("provider_id = ?", providerId).Find(&models).Error
    return models, err
}

// 获取所有活跃模型
func GetActiveProviderModels() ([]*ProviderModel, error) {
    var models []*ProviderModel
    err := DB.Joins("JOIN providers ON providers.id = provider_models.provider_id").
        Where("providers.status = 'active' AND provider_models.status = 'active'").
        Preload("Provider").
        Find(&models).Error
    return models, err
}

// 根据模型名称获取模型
func GetProviderModelByName(modelName string) (*ProviderModel, error) {
    var model ProviderModel
    err := DB.Joins("JOIN providers ON providers.id = provider_models.provider_id").
        Where("provider_models.model_name = ? AND providers.status = 'active' AND provider_models.status = 'active'", modelName).
        Preload("Provider").
        First(&model).Error
    return &model, err
}
```

### 1.3 控制器实现

#### 1.3.1 供应商管理控制器

```go
// controller/provider.go
package controller

import (
    "net/http"
    "strconv"
    "one-api/model"
    "github.com/gin-gonic/gin"
)

// 获取所有供应商
func GetAllProviders(c *gin.Context) {
    providers, err := model.GetAllProviders()
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "获取供应商列表失败",
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "data":    providers,
    })
}

// 获取供应商详情
func GetProvider(c *gin.Context) {
    id, err := strconv.Atoi(c.Param("id"))
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "无效的供应商ID",
        })
        return
    }
    
    provider, err := model.GetProviderById(id)
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "供应商不存在",
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "data":    provider,
    })
}

// 创建供应商
func CreateProvider(c *gin.Context) {
    var provider model.Provider
    if err := c.ShouldBindJSON(&provider); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "参数错误: " + err.Error(),
        })
        return
    }
    
    // 验证必填字段
    if provider.Name == "" || provider.BaseURL == "" || provider.ApiKey == "" {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "名称、URL和API密钥不能为空",
        })
        return
    }
    
    if err := provider.Insert(); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "创建供应商失败: " + err.Error(),
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "message": "供应商创建成功",
        "data":    provider,
    })
}

// 更新供应商
func UpdateProvider(c *gin.Context) {
    id, err := strconv.Atoi(c.Param("id"))
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "无效的供应商ID",
        })
        return
    }
    
    provider, err := model.GetProviderById(id)
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "供应商不存在",
        })
        return
    }
    
    var updateData model.Provider
    if err := c.ShouldBindJSON(&updateData); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "参数错误: " + err.Error(),
        })
        return
    }
    
    // 更新字段
    provider.Name = updateData.Name
    provider.BaseURL = updateData.BaseURL
    provider.ApiKey = updateData.ApiKey
    provider.ApiFormat = updateData.ApiFormat
    provider.Status = updateData.Status
    provider.Priority = updateData.Priority
    provider.Weight = updateData.Weight
    provider.Config = updateData.Config
    provider.RateLimit = updateData.RateLimit
    
    if err := provider.Update(); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "更新供应商失败: " + err.Error(),
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "message": "供应商更新成功",
        "data":    provider,
    })
}

// 删除供应商
func DeleteProvider(c *gin.Context) {
    id, err := strconv.Atoi(c.Param("id"))
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "无效的供应商ID",
        })
        return
    }
    
    provider, err := model.GetProviderById(id)
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "供应商不存在",
        })
        return
    }
    
    if err := provider.Delete(); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "删除供应商失败: " + err.Error(),
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "message": "供应商删除成功",
    })
}

// 测试供应商连接
func TestProvider(c *gin.Context) {
    id, err := strconv.Atoi(c.Param("id"))
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "无效的供应商ID",
        })
        return
    }
    
    provider, err := model.GetProviderById(id)
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "供应商不存在",
        })
        return
    }
    
    if err := provider.TestConnection(); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "连接测试失败: " + err.Error(),
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "message": "连接测试成功",
    })
}
```

#### 1.3.2 模型管理控制器

```go
// controller/provider_model.go
package controller

import (
    "net/http"
    "strconv"
    "one-api/model"
    "github.com/gin-gonic/gin"
)

// 获取供应商模型列表
func GetProviderModels(c *gin.Context) {
    providerId, err := strconv.Atoi(c.Param("provider_id"))
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "无效的供应商ID",
        })
        return
    }
    
    models, err := model.GetProviderModels(providerId)
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "获取模型列表失败",
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "data":    models,
    })
}

// 创建模型
func CreateProviderModel(c *gin.Context) {
    var model model.ProviderModel
    if err := c.ShouldBindJSON(&model); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "参数错误: " + err.Error(),
        })
        return
    }
    
    if err := model.Insert(); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "创建模型失败: " + err.Error(),
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "message": "模型创建成功",
        "data":    model,
    })
}

// 更新模型
func UpdateProviderModel(c *gin.Context) {
    id, err := strconv.Atoi(c.Param("id"))
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "无效的模型ID",
        })
        return
    }
    
    var model model.ProviderModel
    if err := model.DB.First(&model, id).Error; err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "模型不存在",
        })
        return
    }
    
    var updateData model.ProviderModel
    if err := c.ShouldBindJSON(&updateData); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "参数错误: " + err.Error(),
        })
        return
    }
    
    // 更新字段
    model.ModelName = updateData.ModelName
    model.DisplayName = updateData.DisplayName
    model.ModelType = updateData.ModelType
    model.InputPrice = updateData.InputPrice
    model.OutputPrice = updateData.OutputPrice
    model.MaxTokens = updateData.MaxTokens
    model.Status = updateData.Status
    model.Config = updateData.Config
    
    if err := model.Update(); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "更新模型失败: " + err.Error(),
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "message": "模型更新成功",
        "data":    model,
    })
}

// 删除模型
func DeleteProviderModel(c *gin.Context) {
    id, err := strconv.Atoi(c.Param("id"))
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "无效的模型ID",
        })
        return
    }
    
    var model model.ProviderModel
    if err := model.DB.First(&model, id).Error; err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "模型不存在",
        })
        return
    }
    
    if err := model.Delete(); err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "删除模型失败: " + err.Error(),
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "message": "模型删除成功",
    })
}

// 获取所有可用模型
func GetAvailableModels(c *gin.Context) {
    models, err := model.GetActiveProviderModels()
    if err != nil {
        c.JSON(http.StatusOK, gin.H{
            "success": false,
            "message": "获取模型列表失败",
        })
        return
    }
    
    c.JSON(http.StatusOK, gin.H{
        "success": true,
        "data":    models,
    })
}
```

### 1.4 API网关增强

#### 1.4.1 请求路由器

```go
// relay/provider_router.go
package relay

import (
    "fmt"
    "math/rand"
    "one-api/model"
    "sort"
    "time"
)

type ProviderRouter struct {
    providers []*model.Provider
}

func NewProviderRouter() *ProviderRouter {
    return &ProviderRouter{}
}

// 初始化路由器
func (pr *ProviderRouter) Initialize() error {
    providers, err := model.GetActiveProviders()
    if err != nil {
        return err
    }
    pr.providers = providers
    return nil
}

// 选择供应商
func (pr *ProviderRouter) SelectProvider(modelName string) (*model.Provider, *model.ProviderModel, error) {
    // 获取支持该模型的供应商
    var candidates []*model.Provider
    var targetModel *model.ProviderModel
    
    for _, provider := range pr.providers {
        for _, providerModel := range provider.Models {
            if providerModel.ModelName == modelName && providerModel.Status == "active" {
                candidates = append(candidates, provider)
                targetModel = &providerModel
                break
            }
        }
    }
    
    if len(candidates) == 0 {
        return nil, nil, fmt.Errorf("没有找到支持模型 %s 的供应商", modelName)
    }
    
    // 按优先级和权重排序
    sort.Slice(candidates, func(i, j int) bool {
        if candidates[i].Priority != candidates[j].Priority {
            return candidates[i].Priority > candidates[j].Priority
        }
        return candidates[i].Weight > candidates[j].Weight
    })
    
    // 加权随机选择
    return pr.weightedRandomSelect(candidates), targetModel, nil
}

// 加权随机选择
func (pr *ProviderRouter) weightedRandomSelect(providers []*model.Provider) *model.Provider {
    if len(providers) == 1 {
        return providers[0]
    }
    
    totalWeight := 0
    for _, provider := range providers {
        totalWeight += provider.Weight
    }
    
    rand.Seed(time.Now().UnixNano())
    randomWeight := rand.Intn(totalWeight)
    
    currentWeight := 0
    for _, provider := range providers {
        currentWeight += provider.Weight
        if randomWeight < currentWeight {
            return provider
        }
    }
    
    return providers[0] // 默认返回第一个
}

// 刷新供应商列表
func (pr *ProviderRouter) Refresh() error {
    return pr.Initialize()
}
```

#### 1.4.2 请求适配器

```go
// relay/provider_adapter.go
package relay

import (
    "bytes"
    "encoding/json"
    "fmt"
    "io"
    "net/http"
    "one-api/model"
    "time"
)

type ProviderAdapter struct {
    provider *model.Provider
    model    *model.ProviderModel
    client   *http.Client
}

func NewProviderAdapter(provider *model.Provider, model *model.ProviderModel) *ProviderAdapter {
    timeout := 30 * time.Second
    if provider.Config != nil {
        if t, ok := provider.Config["timeout"].(float64); ok {
            timeout = time.Duration(t) * time.Second
        }
    }
    
    return &ProviderAdapter{
        provider: provider,
        model:    model,
        client: &http.Client{
            Timeout: timeout,
        },
    }
}

// 转发请求
func (pa *ProviderAdapter) ForwardRequest(originalReq *http.Request, requestBody []byte) (*http.Response, error) {
    // 构建目标URL
    targetURL := pa.provider.BaseURL + originalReq.URL.Path
    
    // 创建新请求
    req, err := http.NewRequest(originalReq.Method, targetURL, bytes.NewReader(requestBody))
    if err != nil {
        return nil, err
    }
    
    // 设置请求头
    pa.setHeaders(req, originalReq)
    
    // 根据API格式转换请求体
    if err := pa.transformRequest(req, requestBody); err != nil {
        return nil, err
    }
    
    // 发送请求
    resp, err := pa.client.Do(req)
    if err != nil {
        return nil, err
    }
    
    return resp, nil
}

// 设置请求头
func (pa *ProviderAdapter) setHeaders(req *http.Request, originalReq *http.Request) {
    // 复制原始请求头
    for key, values := range originalReq.Header {
        if key != "Authorization" && key != "Host" {
            for _, value := range values {
                req.Header.Add(key, value)
            }
        }
    }
    
    // 设置认证头
    req.Header.Set("Authorization", "Bearer "+pa.provider.ApiKey)
    
    // 设置自定义头
    if pa.provider.Config != nil {
        if headers, ok := pa.provider.Config["headers"].(map[string]interface{}); ok {
            for key, value := range headers {
                if strValue, ok := value.(string); ok {
                    req.Header.Set(key, strValue)
                }
            }
        }
    }
}

// 转换请求格式
func (pa *ProviderAdapter) transformRequest(req *http.Request, requestBody []byte) error {
    switch pa.provider.ApiFormat {
    case "openai":
        return pa.transformOpenAIRequest(req, requestBody)
    case "claude":
        return pa.transformClaudeRequest(req, requestBody)
    case "custom":
        return pa.transformCustomRequest(req, requestBody)
    default:
        return nil
    }
}

// OpenAI格式转换
func (pa *ProviderAdapter) transformOpenAIRequest(req *http.Request, requestBody []byte) error {
    var requestData map[string]interface{}
    if err := json.Unmarshal(requestBody, &requestData); err != nil {
        return err
    }
    
    // 替换模型名称
    if _, ok := requestData["model"]; ok {
        requestData["model"] = pa.model.ModelName
    }
    
    // 设置最大令牌数
    if pa.model.MaxTokens > 0 {
        if _, ok := requestData["max_tokens"]; !ok {
            requestData["max_tokens"] = pa.model.MaxTokens
        }
    }
    
    // 重新编码请求体
    newBody, err := json.Marshal(requestData)
    if err != nil {
        return err
    }
    
    req.Body = io.NopCloser(bytes.NewReader(newBody))
    req.ContentLength = int64(len(newBody))
    
    return nil
}

// Claude格式转换
func (pa *ProviderAdapter) transformClaudeRequest(req *http.Request, requestBody []byte) error {
    // 实现Claude API格式转换
    // 这里需要根据Claude API的具体格式进行转换
    return nil
}

// 自定义格式转换
func (pa *ProviderAdapter) transformCustomRequest(req *http.Request, requestBody []byte) error {
    // 实现自定义格式转换
    // 可以根
