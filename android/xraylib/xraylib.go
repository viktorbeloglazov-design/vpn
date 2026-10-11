// Package xraylib — туннель X-Ray для Android одной библиотекой.
//
// Внутри два движка: xray (соединение с сервером, socks-вход на самом
// телефоне) и tun2socks (берёт пакеты из VpnService и отдаёт их в этот
// вход). Снаружи — пять простых вызовов, которые видит Kotlin. Своя
// обёртка, а не готовая: у готовых от версии к версии меняются имена,
// а у этой они наши.
package xraylib

import (
	"errors"
	"fmt"
	"sync"
	"syscall"

	"github.com/xjasonlyu/tun2socks/v2/engine"
	"github.com/xtls/xray-core/core"
	_ "github.com/xtls/xray-core/main/distro/all"
	"github.com/xtls/xray-core/transport/internet"
	_ "golang.org/x/mobile/bind"
)

// Protector выводит сокет из туннеля: VpnService.protect(fd).
//
// Без этого соединение xray с сервером ушло бы в тот же туннель,
// который оно и обслуживает, — и замкнулось бы само на себя.
type Protector interface {
	Protect(fd int64) bool
}

var (
	mu         sync.Mutex
	instance   *core.Instance
	protector  Protector
	registered bool
	tunRunning bool
)

// SetProtector запоминает, кому отдавать сокеты xray.
func SetProtector(p Protector) error {
	mu.Lock()
	defer mu.Unlock()
	protector = p
	if registered {
		return nil
	}
	registered = true
	return internet.RegisterDialerController(func(network, address string, c syscall.RawConn) error {
		mu.Lock()
		current := protector
		mu.Unlock()
		if current == nil {
			return nil
		}
		protected := false
		if err := c.Control(func(fd uintptr) {
			protected = current.Protect(int64(fd))
		}); err != nil {
			return err
		}
		if !protected {
			return errors.New("сокет не удалось вывести из VPN")
		}
		return nil
	})
}

// StartXray запускает xray с настройками в JSON.
func StartXray(config string) error {
	mu.Lock()
	defer mu.Unlock()
	if instance != nil {
		_ = instance.Close()
		instance = nil
	}
	started, err := core.StartInstance("json", []byte(config))
	if err != nil {
		return err
	}
	instance = started
	return nil
}

// StopXray останавливает xray.
func StopXray() error {
	mu.Lock()
	defer mu.Unlock()
	if instance == nil {
		return nil
	}
	err := instance.Close()
	instance = nil
	return err
}

// StartTun берёт пакеты из дескриптора VpnService и отдаёт в socks-вход.
func StartTun(fd int64, socksPort int64, mtu int64) error {
	mu.Lock()
	defer mu.Unlock()
	if tunRunning {
		_ = engine.Stop()
		tunRunning = false
	}
	if fd <= 0 {
		return errors.New("нет дескриптора туннеля")
	}
	engine.Insert(&engine.Key{
		Device:   fmt.Sprintf("fd://%d", fd),
		Proxy:    fmt.Sprintf("socks5://127.0.0.1:%d", socksPort),
		MTU:      int(mtu),
		LogLevel: "warning",
	})
	if err := engine.Start(); err != nil {
		return err
	}
	tunRunning = true
	return nil
}

// StopTun останавливает tun2socks.
func StopTun() {
	mu.Lock()
	defer mu.Unlock()
	if tunRunning {
		_ = engine.Stop()
		tunRunning = false
	}
}

// Version — версия xray внутри, для отчёта диагностики.
func Version() string {
	return core.Version()
}
