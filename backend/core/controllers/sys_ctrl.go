package controllers

import (
	"net/http"

	"backend/core/services"

	"github.com/gin-gonic/gin"
)

type SysCtrl struct {
	svc services.SysSvc
}

func NewSysCtrl(s services.SysSvc) *SysCtrl {
	return &SysCtrl{svc: s}
}

func (ctrl *SysCtrl) GetInfo(c *gin.Context) {
	res := ctrl.svc.FetchInfo()
	c.JSON(http.StatusOK, res)
}
