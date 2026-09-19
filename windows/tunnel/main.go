// Служба туннеля QP VPN для Windows.
//
// Само шифрование и маскировку делает библиотека AmneziaWG (лицензия MIT):
// она поднимает сетевой адаптер Wintun, настраивает адреса, маршруты и DNS
// по обычному файлу .conf. Здесь — только оболочка: поставить службу,
// снять её и рассказать, что с ней сейчас.
//
//	qpvpn-tunnel.exe /installtunnelservice C:\ProgramData\QPVPN\qpvpn.conf
//	qpvpn-tunnel.exe /uninstalltunnelservice qpvpn
//	qpvpn-tunnel.exe /status qpvpn
//	qpvpn-tunnel.exe /tunnelservice C:\ProgramData\QPVPN\qpvpn.conf   (запускает Windows)
//
// Всё, кроме /status, требует прав администратора: служб без них Windows
// не создаёт, а адаптер Wintun не поднимает.
package main

import (
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/svc"
	"golang.org/x/sys/windows/svc/mgr"

	"github.com/amnezia-vpn/amneziawg-windows/v3/conf"
	"github.com/amnezia-vpn/amneziawg-windows/v3/services"
	"github.com/amnezia-vpn/amneziawg-windows/v3/tunnel"
)

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}

	var err error
	switch strings.ToLower(os.Args[1]) {
	case "/tunnelservice":
		if len(os.Args) < 3 {
			usage()
			os.Exit(2)
		}
		err = tunnel.Run(os.Args[2])

	case "/installtunnelservice":
		if len(os.Args) < 3 {
			usage()
			os.Exit(2)
		}
		err = installTunnel(os.Args[2])

	case "/uninstalltunnelservice":
		if len(os.Args) < 3 {
			usage()
			os.Exit(2)
		}
		err = uninstallTunnel(os.Args[2])

	case "/status":
		if len(os.Args) < 3 {
			usage()
			os.Exit(2)
		}
		err = printStatus(os.Args[2])

	default:
		usage()
		os.Exit(2)
	}

	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "qpvpn-tunnel: /installtunnelservice <файл.conf> | /uninstalltunnelservice <имя> | /status <имя> | /tunnelservice <файл.conf>")
}

// MARK: - Служба

// Создаёт службу туннеля и запускает её.
//
// Имя службы и туннеля берётся из имени файла настроек — так же, как это
// делает сама библиотека, иначе служба не найдёт свой канал управления.
func installTunnel(configPath string) error {
	name, err := conf.NameFromPath(configPath)
	if err != nil {
		return err
	}
	serviceName, err := services.ServiceNameOfTunnel(name)
	if err != nil {
		return err
	}

	manager, err := mgr.Connect()
	if err != nil {
		return fmt.Errorf("не удалось подключиться к диспетчеру служб: %w", err)
	}
	defer manager.Disconnect()

	// Старую службу с тем же именем убираем: иначе создать новую нельзя.
	if err := removeService(manager, serviceName); err != nil {
		return err
	}

	executable, err := os.Executable()
	if err != nil {
		return err
	}

	config := mgr.Config{
		ServiceType:  windows.SERVICE_WIN32_OWN_PROCESS,
		StartType:    mgr.StartAutomatic,
		ErrorControl: mgr.ErrorNormal,
		Dependencies: []string{"Nsi", "TcpIp"},
		DisplayName:  "QP VPN: " + name,
		Description:  "Туннель QP VPN (AmneziaWG).",
		SidType:      windows.SERVICE_SID_TYPE_UNRESTRICTED,
	}

	service, err := manager.CreateService(serviceName, executable, config, "/tunnelservice", configPath)
	if err != nil {
		return fmt.Errorf("не удалось создать службу: %w", err)
	}
	defer service.Close()

	if err := service.Start(); err != nil {
		service.Delete()
		return fmt.Errorf("не удалось запустить службу: %w", err)
	}
	return nil
}

func uninstallTunnel(name string) error {
	serviceName, err := services.ServiceNameOfTunnel(name)
	if err != nil {
		return err
	}
	manager, err := mgr.Connect()
	if err != nil {
		return fmt.Errorf("не удалось подключиться к диспетчеру служб: %w", err)
	}
	defer manager.Disconnect()
	return removeService(manager, serviceName)
}

// Останавливает и удаляет службу, если она есть. Отсутствие службы — не ошибка.
func removeService(manager *mgr.Mgr, serviceName string) error {
	service, err := manager.OpenService(serviceName)
	if err != nil {
		return nil
	}
	defer service.Close()

	if status, err := service.Control(svc.Stop); err == nil {
		// Даём службе закрыть адаптер: иначе следующий запуск упрётся
		// в занятое имя.
		for i := 0; i < 50 && status.State != svc.Stopped; i++ {
			time.Sleep(100 * time.Millisecond)
			if status, err = service.Query(); err != nil {
				break
			}
		}
	}

	if err := service.Delete(); err != nil {
		return fmt.Errorf("не удалось удалить службу: %w", err)
	}

	// Windows удаляет службу не мгновенно — дожидаемся, чтобы сразу же
	// можно было поставить её заново.
	for i := 0; i < 50; i++ {
		again, err := manager.OpenService(serviceName)
		if err != nil {
			return nil
		}
		again.Close()
		time.Sleep(100 * time.Millisecond)
	}
	return nil
}

// MARK: - Состояние

type status struct {
	Running       bool   `json:"running"`
	State         string `json:"state"`
	RxBytes       uint64 `json:"rxBytes"`
	TxBytes       uint64 `json:"txBytes"`
	LastHandshake int64  `json:"lastHandshake"`
	Error         string `json:"error,omitempty"`
}

// Печатает состояние туннеля одной строкой JSON — её читает приложение.
func printStatus(name string) error {
	result := status{State: "stopped"}

	serviceName, err := services.ServiceNameOfTunnel(name)
	if err != nil {
		return err
	}

	manager, err := mgr.Connect()
	if err == nil {
		defer manager.Disconnect()
		if service, err := manager.OpenService(serviceName); err == nil {
			defer service.Close()
			if state, err := service.Query(); err == nil {
				result.State = stateName(state.State)
				result.Running = state.State == svc.Running
			}
		}
	}

	if result.Running {
		if rx, tx, handshake, err := readCounters(name); err == nil {
			result.RxBytes, result.TxBytes, result.LastHandshake = rx, tx, handshake
		} else {
			result.Error = err.Error()
		}
	}

	line, err := json.Marshal(result)
	if err != nil {
		return err
	}
	fmt.Println(string(line))
	return nil
}

func stateName(state svc.State) string {
	switch state {
	case svc.Stopped:
		return "stopped"
	case svc.StartPending:
		return "starting"
	case svc.StopPending:
		return "stopping"
	case svc.Running:
		return "running"
	case svc.Paused:
		return "paused"
	default:
		return "unknown"
	}
}

// Счётчики берутся у самой службы через её канал управления.
func readCounters(name string) (rx, tx uint64, handshake int64, err error) {
	path, err := services.PipePathOfTunnel(name)
	if err != nil {
		return 0, 0, 0, err
	}

	pipe, err := os.OpenFile(path, os.O_RDWR, 0)
	if err != nil {
		return 0, 0, 0, fmt.Errorf("служба не отвечает: %w", err)
	}
	defer pipe.Close()

	if _, err = pipe.Write([]byte("get=1\n\n")); err != nil {
		return 0, 0, 0, err
	}

	buffer := make([]byte, 64*1024)
	read, err := pipe.Read(buffer)
	if err != nil && read == 0 {
		return 0, 0, 0, err
	}

	for _, line := range strings.Split(string(buffer[:read]), "\n") {
		key, value, found := strings.Cut(strings.TrimSpace(line), "=")
		if !found {
			continue
		}
		number, convErr := strconv.ParseUint(value, 10, 64)
		if convErr != nil {
			continue
		}
		switch key {
		case "rx_bytes":
			rx += number
		case "tx_bytes":
			tx += number
		case "last_handshake_time_sec":
			if int64(number) > handshake {
				handshake = int64(number)
			}
		}
	}
	return rx, tx, handshake, nil
}
