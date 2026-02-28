package controllers

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"backend/core/services"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

type AnalyzeCtrl struct {
	svc services.AnalyzeSvc
}

func NewAnalyzeCtrl(s services.AnalyzeSvc) *AnalyzeCtrl {
	return &AnalyzeCtrl{svc: s}
}

func (ctrl *AnalyzeCtrl) UploadFile(c *gin.Context) {
	file, err := c.FormFile("file")
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "No file uploaded"})
		return
	}

	ext := strings.ToLower(filepath.Ext(file.Filename))

	// Security: Only allow specific document types
	if ext != ".pdf" && ext != ".txt" && ext != ".md" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Unsupported file type. Please upload a PDF, TXT, or MD."})
		return
	}

	id := uuid.New().String()

	// Failsafe: Ensure the uploads directory exists before attempting to save
	uploadDir := "uploads"
	if err := os.MkdirAll(uploadDir, os.ModePerm); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to initialize storage directory"})
		return
	}

	path := filepath.Join(uploadDir, id+ext)

	if err := c.SaveUploadedFile(file, path); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save file"})
		return
	}

	res := ctrl.svc.InitTask(id, ext)
	c.JSON(http.StatusAccepted, res)
}

func (ctrl *AnalyzeCtrl) GetStatus(c *gin.Context) {
	id := c.Param("task_id")
	res, exists := ctrl.svc.CheckStatus(id)

	if !exists {
		c.JSON(http.StatusNotFound, gin.H{"error": "Task not found"})
		return
	}

	c.JSON(http.StatusOK, res)
}

func (ctrl *AnalyzeCtrl) PurgeTask(c *gin.Context) {
	id := c.Param("task_id")
	res, err := ctrl.svc.PurgeTask(id)

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to purge files"})
		return
	}

	c.JSON(http.StatusOK, res)
}
