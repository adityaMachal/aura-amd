package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"backend/core/dtos"
)

type ChatSvc interface {
	ProcessChat(req dtos.ChatReq) dtos.ChatRes
}

type chatSvcImpl struct{}

func NewChatSvc() ChatSvc {
	return &chatSvcImpl{}
}

func (s *chatSvcImpl) ProcessChat(req dtos.ChatReq) dtos.ChatRes {

	// 1. Define the default Windows path
	pythonBin := filepath.Join("..", "ml-engine", ".venv", "Scripts", "python.exe")

	// 2. Check if the Scripts path exists. If not, switch to the bin path.
	if _, err := os.Stat(pythonBin); os.IsNotExist(err) {
		pythonBin = filepath.Join("..", "ml-engine", ".venv", "bin", "python.exe")
	}

	scriptPath := filepath.Join("..", "ml-engine", "inference", "chat.py")

	cmd := exec.Command(pythonBin, scriptPath, req.TaskID, req.Query)

	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	out, err := cmd.Output()

	if err != nil {
		fmt.Printf("\n[RAG Engine] Inference Error!\nError: %v\nPython Traceback:\n%s\n", err, stderr.String())
		return dtos.ChatRes{
			Answer:  "The local AI engine encountered an error or is currently offline.",
			Sources: []int{},
		}
	}

	var res dtos.ChatRes
	if err := json.Unmarshal(out, &res); err != nil {
		return dtos.ChatRes{
			Answer:  "I processed the context, but my output format was invalid.",
			Sources: []int{},
		}
	}

	return res
}
