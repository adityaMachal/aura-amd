package routes

import (
	"backend/core/controllers"
	"backend/core/repositories"
	"backend/core/services"

	"github.com/gin-gonic/gin"
)

func SetupSysRoutes(rg *gin.RouterGroup) {
	repo := repositories.NewSysRepo()
	svc := services.NewSysSvc(repo)
	ctrl := controllers.NewSysCtrl(svc)

	sysGroup := rg.Group("/system")
	{
		sysGroup.GET("/info", ctrl.GetInfo)
	}
}
