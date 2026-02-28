package main

import (
	"backend/core/routes"

	"github.com/gin-gonic/gin"
)

func main() {
	router := gin.Default()

	// CORS Middleware
	router.Use(func(c *gin.Context) {
		c.Writer.Header().Set("Access-Control-Allow-Origin", "*")
		c.Writer.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, DELETE")
		c.Writer.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	})

	v1 := router.Group("/api/v1")

	// Register Domain Routes
	routes.SetupSysRoutes(v1)
	routes.SetupAnalyzeRoutes(v1)
	routes.SetupChatRoutes(v1)

	router.Run(":8080")
}
