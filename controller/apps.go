package controller

import (
	"net/http"

	"github.com/QuantumNous/new-api/model"
	"github.com/gin-gonic/gin"
)

// GetAppRankings 应用消耗排行（公开页 /apps 数据源），归因来自客户端 X-Title 头
func GetAppRankings(c *gin.Context) {
	result, err := model.GetAppRankings()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"success": false,
			"message": err.Error(),
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success": true,
		"data":    result,
	})
}
