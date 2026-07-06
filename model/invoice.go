package model

import (
	"errors"
	"time"
)

// InvoiceRequest 开票申请。MVP 为人工开票流程：用户提交抬头信息，admin 线下开票后标记已开。
type InvoiceRequest struct {
	Id          int    `json:"id"`
	UserId      int    `json:"user_id" gorm:"index"`
	Title       string `json:"title" gorm:"type:varchar(255)"`
	TaxNo       string `json:"tax_no" gorm:"type:varchar(64)"`
	Email       string `json:"email" gorm:"type:varchar(128)"`
	Remark      string `json:"remark" gorm:"type:varchar(255)"`
	Status      int    `json:"status"` // 1 待开票 2 已开票
	CreatedTime int64  `json:"created_time" gorm:"bigint"`
	IssuedTime  int64  `json:"issued_time" gorm:"bigint"`
}

const (
	InvoiceStatusPending = 1
	InvoiceStatusIssued  = 2
)

func (i *InvoiceRequest) Insert() error {
	i.Status = InvoiceStatusPending
	i.CreatedTime = time.Now().Unix()
	return DB.Create(i).Error
}

func GetInvoiceRequestsByUserId(userId int) ([]*InvoiceRequest, error) {
	var items []*InvoiceRequest
	err := DB.Where("user_id = ?", userId).Order("id desc").Limit(100).Find(&items).Error
	return items, err
}

// ponytail: 固定取最新 100 条，admin 待开票远不到这个量级；超了再加分页
func GetAllInvoiceRequestsLatest() ([]*InvoiceRequest, error) {
	var items []*InvoiceRequest
	err := DB.Order("id desc").Limit(100).Find(&items).Error
	return items, err
}

func CompleteInvoiceRequest(id int) error {
	result := DB.Model(&InvoiceRequest{}).Where("id = ? AND status = ?", id, InvoiceStatusPending).
		Updates(map[string]interface{}{"status": InvoiceStatusIssued, "issued_time": time.Now().Unix()})
	if result.Error != nil {
		return result.Error
	}
	if result.RowsAffected == 0 {
		return errors.New("开票申请不存在或已开票")
	}
	return nil
}
