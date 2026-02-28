package services

import (
	"bytes"
	"encoding/json"
	"fmt"
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

	// Hardwire Go to use the virtual environment's Python executable
	pythonBin := filepath.Join("..", "ml-engine", ".venv", "Scripts", "python.exe")
	scriptPath := filepath.Join("..", "ml-engine", "inference", "chat.py")

	cmd := exec.Command(pythonBin, scriptPath, req.TaskID, req.Query)

	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	out, err := cmd.Output()

	if err != nil {
		fmt.Printf("\n[RAG Engine] Inference Error!\nError: %v\nPython Traceback:\n%s\n", err, stderr.String())
		return dtos.ChatRes{
			Answer:  "The local AI engine encountered an error or is currently offline. Please check the backend terminal for details.",
			Sources: []int{},
		}
	}

	var res dtos.ChatRes
	if err := json.Unmarshal(out, &res); err != nil {
		fmt.Printf("\n[RAG Engine] JSON Parse Error!\nError: %v\nRaw Python Output:\n%s\n", err, string(out))
		return dtos.ChatRes{
			Answer:  "I processed the context, but my output format was invalid.",
			Sources: []int{},
		}
	}

	return res
}
