package services

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"

	"backend/core/dtos"
)

type ChatSvc interface {
	ProcessChat(req dtos.ChatReq) dtos.ChatRes
}

type chatSvcImpl struct {
	mu     sync.Mutex
	stdin  io.WriteCloser
	reader *bufio.Scanner
}

// NewChatSvc starts the Python process ONCE and keeps it alive
func NewChatSvc() ChatSvc {
	pythonBin := filepath.Join("..", "ml-engine", ".venv", "Scripts", "python.exe")
	scriptPath := filepath.Join("..", "ml-engine", "inference", "chat.py")

	cmd := exec.Command(pythonBin, scriptPath)

	stdin, err := cmd.StdinPipe()
	if err != nil {
		fmt.Printf("Error creating stdin pipe: %v\n", err)
	}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		fmt.Printf("Error creating stdout pipe: %v\n", err)
	}

	// Start the process in the background
	if err := cmd.Start(); err != nil {
		fmt.Printf("Error starting Python process: %v\n", err)
	}

	scanner := bufio.NewScanner(stdout)

	// Wait for the "READY" signal from Python so we know the 2.7GB model is loaded
	fmt.Println("[Aura-AMD] Loading INT8 Model into VRAM... Please wait.")
	for scanner.Scan() {
		text := scanner.Text()
		if strings.Contains(text, "READY") {
			fmt.Println("[Aura-AMD] Model loaded successfully! Ready for instant chat.")
			break
		}
	}

	return &chatSvcImpl{
		stdin:  stdin,
		reader: scanner,
	}
}

func (s *chatSvcImpl) ProcessChat(req dtos.ChatReq) dtos.ChatRes {
	// Lock the process so concurrent API requests don't overlap in the STDIN pipe
	s.mu.Lock()
	defer s.mu.Unlock()

	// Convert request to JSON and send to Python
	reqBytes, _ := json.Marshal(req)
	reqString := string(reqBytes) + "\n"

	_, err := s.stdin.Write([]byte(reqString))
	if err != nil {
		return dtos.ChatRes{Answer: "Error writing to ML Engine.", Sources: []int{}}
	}

	// Wait for the JSON response from Python
	if s.reader.Scan() {
		out := s.reader.Bytes()
		var res dtos.ChatRes
		if err := json.Unmarshal(out, &res); err != nil {
			fmt.Printf("\n[RAG Engine] JSON Parse Error!\nRaw Output: %s\n", string(out))
			return dtos.ChatRes{Answer: "Invalid response from ML Engine.", Sources: []int{}}
		}
		return res
	}

	return dtos.ChatRes{Answer: "ML Engine timeout or crash.", Sources: []int{}}
}
