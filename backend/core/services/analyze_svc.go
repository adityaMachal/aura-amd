package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os/exec"
	"path/filepath"

	"backend/core/dtos"
	"backend/core/repositories"
)

type aiRes struct {
	Summary      string  `json:"summary"`
	TokensPerSec float64 `json:"tokens_per_sec"`
}

type AnalyzeSvc interface {
	InitTask(id string, ext string) dtos.UploadRes
	CheckStatus(id string) (dtos.StatusRes, bool)
	PurgeTask(id string) (dtos.PurgeRes, error)
	runAI(id string, ext string)
}

type analyzeSvcImpl struct {
	repo repositories.AnalyzeRepo
}

func NewAnalyzeSvc(r repositories.AnalyzeRepo) AnalyzeSvc {
	return &analyzeSvcImpl{repo: r}
}

func (s *analyzeSvcImpl) InitTask(id string, ext string) dtos.UploadRes {
	s.repo.CreateTask(id)

	// Run the AI ingestion asynchronously so we don't block the UI
	go s.runAI(id, ext)

	return dtos.UploadRes{
		TaskID:  id,
		Message: "File received. Analyzing...",
	}
}

func (s *analyzeSvcImpl) runAI(id string, ext string) {
	fp := filepath.Join("uploads", id+ext)

	// Hardwire Go to use the virtual environment's Python executable
	pythonBin := filepath.Join("..", "ml-engine", ".venv", "Scripts", "python.exe")
	scriptPath := filepath.Join("..", "ml-engine", "inference", "predict.py")

	cmd := exec.Command(pythonBin, scriptPath, fp)

	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	out, err := cmd.Output()

	if err != nil {
		fmt.Printf("\n[AI Service] Python Execution Failed!\nError: %v\nPython Traceback:\n%s\n", err, stderr.String())
		s.repo.UpdateTask(id, "error", "Local AI process failed to execute.", 0)
		return
	}

	var res aiRes
	if err := json.Unmarshal(out, &res); err != nil {
		fmt.Printf("\n[AI Service] JSON Parse Error!\nError: %v\nRaw Python Output:\n%s\n", err, string(out))
		s.repo.UpdateTask(id, "error", "Invalid response from local AI engine.", 0)
		return
	}

	s.repo.UpdateTask(id, "completed", res.Summary, res.TokensPerSec)
}

func (s *analyzeSvcImpl) CheckStatus(id string) (dtos.StatusRes, bool) {
	return s.repo.GetTask(id)
}

func (s *analyzeSvcImpl) PurgeTask(id string) (dtos.PurgeRes, error) {
	s.repo.DeleteTask(id)
	err := s.repo.DeleteFiles(id)
	if err != nil {
		return dtos.PurgeRes{}, err
	}

	return dtos.PurgeRes{Message: "Local cache purged successfully."}, nil
}
