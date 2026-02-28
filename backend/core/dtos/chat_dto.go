package dtos

type ChatReq struct {
	TaskID string `json:"task_id" binding:"required"`
	Query  string `json:"query" binding:"required"`
}

type ChatRes struct {
	Answer  string `json:"answer"`
	Sources []int  `json:"sources"`
}
