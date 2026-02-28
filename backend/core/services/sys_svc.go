package services

import (
	"backend/core/dtos"
	"backend/core/repositories"
)

type SysSvc interface {
	FetchInfo() dtos.SysInfoRes
}

type sysSvcImpl struct {
	repo repositories.SysRepo
}

func NewSysSvc(r repositories.SysRepo) SysSvc {
	return &sysSvcImpl{repo: r}
}

func (s *sysSvcImpl) FetchInfo() dtos.SysInfoRes {
	osName, cpuName := s.repo.GetDeviceInfo()

	return dtos.SysInfoRes{
		DeviceName:   cpuName + " (" + osName + ")",
		Runtime:      "ONNX + DirectML",
		Quantization: "INT8",
	}
}
