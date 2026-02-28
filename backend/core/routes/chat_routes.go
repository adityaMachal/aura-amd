package routes

import (
	"backend/core/controllers"
	"backend/core/services"

	"github.com/gin-gonic/gin"
)

func SetupChatRoutes(rg *gin.RouterGroup) {
	// 1. Initialize the Chat Service
	svc := services.NewChatSvc()

	// 2. Inject the Service into the Chat Controller
	ctrl := controllers.NewChatCtrl(svc)

	// 3. Mount the route exactly where the Next.js frontend expects it
	// Endpoint will be: POST /api/v1/analyze/chat
	analyzeGroup := rg.Group("/analyze")
	analyzeGroup.POST("/chat", ctrl.HandleChat)
}
