# Кросскомпиляция с Windows

На Windows можно кросскомпилировать Go FFI библиотеки для macOS и Linux с помощью PowerShell скриптов.

## Быстрый старт

```powershell
# macOS (amd64 и arm64)
make macos

# Linux x64
make linux

# Linux i686 (32-bit)
make linux-i686
```

Или напрямую через PowerShell:

```powershell
# macOS
.\scripts\build-macos.ps1

# Linux x64
.\scripts\build-linux.ps1

# Linux i686
.\scripts\build-linux-i686.ps1
```

## Что собирается

Скрипты собирают только Go FFI библиотеки:
- **macOS**: `flutter-app/macos/Frameworks/libpiper.dylib` (amd64 и arm64)
- **Linux x64**: `flutter-app/linux/bundle/lib/libpiper.so`
- **Linux i686**: `flutter-app/linux/bundle/lib/libpiper.so` (32-bit)

## Ограничения

### CGO и кросскомпиляция

Go с CGO требует C компилятор целевой платформы:

1. **macOS**: Требуется macOS SDK (недоступен на Windows)
   - Решения: использовать macOS машину, osxcross, или CI/CD

2. **Linux**: Требуется Linux C компилятор
   - Решения: WSL, Docker, или CI/CD

### Flutter кросскомпиляция

Flutter не поддерживает кросскомпиляцию с Windows на macOS/Linux напрямую.

Для полной сборки используйте:

#### Вариант 1: WSL (рекомендуется для Linux)
```bash
# Установите WSL и Ubuntu
wsl --install

# В WSL
cd /mnt/c/Git/Hackatons/piper
make linux
```

#### Вариант 2: Docker
```bash
docker run -v ${PWD}:/app -w /app golang:latest bash scripts/build-linux.sh
```

#### Вариант 3: CI/CD (GitHub Actions)
Создайте `.github/workflows/build.yml`:
```yaml
name: Build
on: [push]
jobs:
  linux:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-go@v4
      - run: make linux
  macos:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-go@v4
      - run: make macos
```

#### Вариант 4: Нативная сборка
Скопируйте собранную Go библиотеку на целевую платформу и запустите Flutter build там.

## Примеры использования

### Только Go библиотека (для разработки)
```powershell
.\scripts\build-linux.ps1 lib
```

### Все библиотеки для macOS
```powershell
.\scripts\build-macos.ps1 all
```

### Очистка
```powershell
.\scripts\build-linux.ps1 clean
.\scripts\build-macos.ps1 clean
```

## Требования

- Go 1.22+
- PowerShell 5.1+ (встроен в Windows 10+)
- Для Linux: WSL или Docker (для полной сборки)
- Для macOS: macOS машина или CI/CD (для полной сборки)

## Устранение проблем

### Ошибка "CGO cross-compilation requires macOS SDK"
Это нормально для macOS. Используйте macOS машину или CI/CD для полной сборки.

### Ошибка "Go build failed" для Linux
Установите WSL или используйте Docker:
```bash
# WSL
wsl --install

# Docker
docker pull golang:latest
```

### Flutter build не работает
Flutter требует нативной сборки. Используйте WSL для Linux или macOS для macOS.
