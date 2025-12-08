# TermOS Control Center

Bash/Dialog scripts for hardware and system configuration on TermOS (Alpine Linux-based).

## Features

- **Audio**: Volume control and audio device management
- **Bluetooth**: Bluetooth device pairing and management
- **Display**: Brightness and display settings
- **Network**: Network and WiFi configuration
- **Power**: Power management options
- **Storage**: Storage device information
- **System Info**: System information dashboard
- **Updates**: System update management

## Requirements

- TermOS or Alpine Linux
- `dialog` package
- Bash shell

## Installation

```bash
apk add dialog
```

## Usage

```bash
./termos-cc.sh
```

## Project Structure

```
termos-cc/
├── termos-cc.sh      # Main entry point
├── modules/          # Feature modules
│   ├── audio.sh
│   ├── bluetooth.sh
│   ├── brightness.sh
│   ├── common.sh
│   ├── dashboard.sh
│   ├── display.sh
│   ├── help.sh
│   ├── network.sh
│   ├── power.sh
│   ├── storage.sh
│   ├── sysinfo.sh
│   ├── updates.sh
│   └── wifi.sh
└── help/             # Help documentation
    ├── audio.txt
    ├── bluetooth.txt
    ├── dashboard.txt
    ├── display.txt
    ├── main.txt
    └── network.txt
```

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Part of TermOS

This project is part of the [TermOS](https://github.com/alejandroqh/termos) ecosystem.
