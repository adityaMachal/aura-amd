package dtos

type SysInfoRes struct {
	DeviceName   string `json:"device_name"`
	Runtime      string `json:"runtime"`
	Quantization string `json:"quantization"`
}
