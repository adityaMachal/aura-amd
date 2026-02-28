package routes

import (
	"backend/core/controllers"
	"backend/core/repositories"
	"backend/core/services"

	"github.com/gin-gonic/gin"
)

func SetupAnalyzeRoutes(rg *gin.RouterGroup) {
	repo := repositories.NewAnalyzeRepo()
	svc := services.NewAnalyzeSvc(repo)
	ctrl := controllers.NewAnalyzeCtrl(svc)

	analyzeGroup := rg.Group("/analyze")
	{
		analyzeGroup.POST("/upload", ctrl.UploadFile)
		analyzeGroup.GET("/status/:task_id", ctrl.GetStatus)
		analyzeGroup.DELETE("/purge/:task_id", ctrl.PurgeTask)
	}
}
