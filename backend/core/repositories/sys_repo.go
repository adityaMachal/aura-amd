package repositories

import (
	"github.com/shirou/gopsutil/v3/cpu"
	"github.com/shirou/gopsutil/v3/host"
)

type SysRepo interface {
	GetDeviceInfo() (string, string)
}

type sysRepoImpl struct{}

func NewSysRepo() SysRepo {
	return &sysRepoImpl{}
}

func (r *sysRepoImpl) GetDeviceInfo() (string, string) {
	hostInfo, _ := host.Info()
	cpuInfo, _ := cpu.Info()

	osName := "Unknown OS"
	if hostInfo != nil {
		osName = hostInfo.OS + " " + hostInfo.Platform
	}

	cpuName := "Unknown CPU"
	if len(cpuInfo) > 0 {
		cpuName = cpuInfo[0].ModelName
	}

	return osName, cpuName
}
