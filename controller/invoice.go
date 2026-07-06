package controller

import (
	"strconv"
	"strings"

	"github.com/QuantumNous/new-api/common"
	"github.com/QuantumNous/new-api/model"
	"github.com/gin-gonic/gin"
)

type submitInvoiceRequest struct {
	Title  string `json:"title"`
	TaxNo  string `json:"tax_no"`
	Email  string `json:"email"`
	Remark string `json:"remark"`
}

func SubmitInvoiceRequest(c *gin.Context) {
	var req submitInvoiceRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		common.ApiErrorMsg(c, "参数错误")
		return
	}
	req.Title = strings.TrimSpace(req.Title)
	req.TaxNo = strings.TrimSpace(req.TaxNo)
	req.Email = strings.TrimSpace(req.Email)
	if req.Title == "" || req.TaxNo == "" || req.Email == "" {
		common.ApiErrorMsg(c, "抬头、税号、邮箱均不能为空")
		return
	}
	invoice := model.InvoiceRequest{
		UserId: c.GetInt("id"),
		Title:  req.Title,
		TaxNo:  req.TaxNo,
		Email:  req.Email,
		Remark: strings.TrimSpace(req.Remark),
	}
	if err := invoice.Insert(); err != nil {
		common.ApiError(c, err)
		return
	}
	common.ApiSuccess(c, &invoice)
}

func GetMyInvoiceRequests(c *gin.Context) {
	items, err := model.GetInvoiceRequestsByUserId(c.GetInt("id"))
	if err != nil {
		common.ApiError(c, err)
		return
	}
	common.ApiSuccess(c, items)
}

func GetAllInvoiceRequests(c *gin.Context) {
	items, err := model.GetAllInvoiceRequestsLatest()
	if err != nil {
		common.ApiError(c, err)
		return
	}
	common.ApiSuccess(c, items)
}

func CompleteInvoiceRequest(c *gin.Context) {
	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		common.ApiErrorMsg(c, "参数错误")
		return
	}
	if err := model.CompleteInvoiceRequest(id); err != nil {
		common.ApiError(c, err)
		return
	}
	common.ApiSuccess(c, nil)
}
