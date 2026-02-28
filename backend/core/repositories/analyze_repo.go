package repositories

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	"backend/core/dtos"

	_ "github.com/mattn/go-sqlite3"
)

type AnalyzeRepo interface {
	CreateTask(id string)
	UpdateTask(id string, status string, summary string, speed float64)
	GetTask(id string) (dtos.StatusRes, bool)
	DeleteTask(id string)
	DeleteFiles(id string) error
}

type analyzeRepoImpl struct {
	store map[string]dtos.StatusRes
	mu    sync.RWMutex
}

func NewAnalyzeRepo() AnalyzeRepo {
	return &analyzeRepoImpl{
		store: make(map[string]dtos.StatusRes),
	}
}

func (r *analyzeRepoImpl) CreateTask(id string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.store[id] = dtos.StatusRes{
		TaskID: id,
		Status: "processing",
	}
}

func (r *analyzeRepoImpl) UpdateTask(id string, status string, summary string, speed float64) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if task, exists := r.store[id]; exists {
		task.Status = status
		task.Summary = summary
		task.TokensPerSec = speed
		r.store[id] = task
	}
}

func (r *analyzeRepoImpl) GetTask(id string) (dtos.StatusRes, bool) {
	r.mu.RLock()
	defer r.mu.RUnlock()
	task, exists := r.store[id]
	return task, exists
}

func (r *analyzeRepoImpl) DeleteTask(id string) {
	r.mu.Lock()
	defer r.mu.Unlock()
	delete(r.store, id)
}

func (r *analyzeRepoImpl) DeleteFiles(id string) error {
	fmt.Printf("\n[Garbage Collection] Initiating Purge for Task ID: %s\n", id)

	// 1. Delete the uploaded files (using Glob to catch .pdf, .txt, etc.)
	files, err := filepath.Glob(filepath.Join("uploads", id+"*"))
	if err == nil {
		for _, f := range files {
			if err := os.Remove(f); err != nil {
				fmt.Printf("[Garbage Collection] Warning: Could not delete file %s: %v\n", f, err)
			} else {
				fmt.Printf(" -> Deleted uploaded file: %s\n", f)
			}
		}
	}

	// 2. Delete the FAISS Vector Database directory
	vectorDbPath := filepath.Join("..", "ml-engine", "vector_stores", id)
	if err := os.RemoveAll(vectorDbPath); err != nil {
		fmt.Printf("[Garbage Collection] Warning: Could not delete FAISS Vector DB: %v\n", err)
	} else {
		fmt.Printf(" -> Deleted Vector DB: %s\n", vectorDbPath)
	}

	// 3. Purge metadata and chat history from SQLite
	dbPath := filepath.Join("..", "ml-engine", "aura_store.db")
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		fmt.Printf("[Garbage Collection] Database Error: %v\n", err)
	} else {
		defer db.Close()

		// Wipe from documents table
		_, err = db.Exec("DELETE FROM documents WHERE task_id = ?", id)
		if err != nil {
			fmt.Printf("[Garbage Collection] Warning: Failed to purge document records: %v\n", err)
		}

		// Wipe from chats table
		_, err = db.Exec("DELETE FROM chats WHERE task_id = ?", id)
		if err != nil {
			fmt.Printf("[Garbage Collection] Warning: Failed to purge chat history: %v\n", err)
		}

		fmt.Printf(" -> Purged SQLite Records\n")
	}

	fmt.Printf("[Garbage Collection] Task %s successfully nuked.\n\n", id)
	return nil
}
