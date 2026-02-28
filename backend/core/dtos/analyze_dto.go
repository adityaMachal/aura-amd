package dtos

type UploadRes struct {
	TaskID  string `json:"task_id"`
	Message string `json:"message"`
}

type StatusRes struct {
	TaskID       string  `json:"task_id"`
	Status       string  `json:"status"`
	Summary      string  `json:"summary"`
	TokensPerSec float64 `json:"tokens_per_sec"`
}

type PurgeRes struct {
	Message string `json:"message"`
}
