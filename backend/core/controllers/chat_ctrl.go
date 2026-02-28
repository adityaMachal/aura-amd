package controllers

import (
	"net/http"

	"backend/core/dtos"
	"backend/core/services"

	"github.com/gin-gonic/gin"
)

type ChatCtrl struct {
	svc services.ChatSvc
}

func NewChatCtrl(s services.ChatSvc) *ChatCtrl {
	return &ChatCtrl{svc: s}
}

func (ctrl *ChatCtrl) HandleChat(c *gin.Context) {
	var req dtos.ChatReq

	// ShouldBindJSON will automatically fail if task_id or query are missing/empty
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request. Missing Task ID or Query."})
		return
	}

	res := ctrl.svc.ProcessChat(req)
	c.JSON(http.StatusOK, res)
}
