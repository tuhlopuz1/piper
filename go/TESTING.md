# Piper - Руководство по тестированию

## Быстрый старт

```bash
cd go
go mod download
go test ./core/ -v -count=1 -timeout 60s
```

## Структура тестов

| Файл | Что тестирует | Кол-во тестов | Сеть |
|------|--------------|---------------|------|
| `core/crypto_test.go` | X25519 ECDH, ChaCha20-Poly1305 шифрование/дешифрование | 10 | Нет |
| `core/message_test.go` | Сериализация/десериализация, конструкторы, relay payload, граничные случаи | 12 | Нет |
| `core/peer_test.go` | PeerManager CRUD, коллизии DisplayName, конкурентный доступ | 10 | Нет |
| `core/group_test.go` | GroupManager CRUD, членство, конкурентный доступ | 9 | Нет |
| `core/transfer_test.go` | TransferManager жизненный цикл (Start/Progress/Complete/Fail) | 9 | Нет |
| `core/node_test.go` | Интеграция: подключение нод, broadcast/direct, flood dedup, relay, группы | 15 | **Да** |

**Итого: 65 тестов**

## Покрытие по модулям

### crypto_test.go
- Генерация X25519 ключевых пар (уникальность)
- Симметричность shared secret (Alice->Bob == Bob->Alice)
- Различие shared secret для разных пиров
- Encrypt/Decrypt строк (round-trip)
- EncryptBytes/DecryptBytes бинарных данных
- Дешифрование с неверным ключом (должно упасть)
- Дешифрование с поврежденным nonce (должно упасть)
- Уникальность nonce при повторном шифровании
- Пустые строки
- Большие данные (1 МБ)

### message_test.go
- Конструкторы: `NewHelloMessage`, `NewTextMessage`, `NewDirectMessage`
- WriteMsg/ReadMsg round-trip (одиночные и множественные сообщения)
- Relay payload (`MsgTypeRelay` + `RelayPayload` field)
- Граничные случаи: нулевая длина, превышение 4 МБ, обрезанное тело, пустой reader
- Все поля протокола (file transfer, peer records, groups)
- Юникод (кириллица, эмодзи)
- Невалидный JSON

### peer_test.go
- Upsert: вставка нового пира, обновление существующего
- Автоматические суффиксы DisplayName (#2, #3) при коллизиях
- Get, List, Remove
- SetSharedKey, SetPubKey, SetState
- Конкурентный доступ (100 горутин)

### group_test.go
- Create, AddMember, RemoveMember, Delete
- IsMember (позитивные и негативные сценарии)
- MemberIDs (сортировка)
- List
- Конкурентный доступ (100 горутин)

### transfer_test.go
- Start (sending/receiving, проверка accepted канала)
- Get, UpdateProgress, Complete, Fail, Remove, List
- Progress = FileSize после Complete
- Конкурентный доступ (100 горутин)

### node_test.go
- Создание ноды (NewNode, NewNodeWithID)
- SetName, SetDownloadsDir
- CreateGroup, LeaveGroup
- LocalEndpoint (после Start)
- markSeen flood deduplication
- **Интеграция**: две ноды на localhost:
  - Подключение через InjectPeers (без mDNS/UDP)
  - X25519 handshake
  - Broadcast сообщения
  - Encrypted direct сообщения (в обе стороны)
  - Broadcast flood dedup (проверка что сообщение получено ровно 1 раз)
- Утилиты: `isZeroKey`, `parseCallMeta`

## Настройка Windows Firewall

Интеграционные тесты (`TestTwoNodes_*`, `TestNode_LocalEndpoint`) открывают TCP-порты на localhost. Windows Firewall может показать диалог "Allow access". Чтобы тесты запускались стабильно без ручного подтверждения:

### Вариант 1: Правило для Go (рекомендуется)

Выполните **один раз** от имени администратора в PowerShell:

```powershell
# Разрешить Go принимать входящие TCP-соединения
New-NetFirewallRule -DisplayName "Go Test Runner" `
  -Direction Inbound -Protocol TCP `
  -Program "$(go env GOROOT)\bin\go.exe" `
  -Action Allow -Profile Private,Domain
```

> **Примечание:** Windows Firewall не поддерживает wildcard (`*`) в параметре `-Program`.
> Если тест-бинарник собирается в другое место, узнайте путь через
> `go test ./core/ -c -o test.exe` и добавьте правило для конкретного файла.

### Вариант 2: Разрешить loopback (минимальный риск)

```powershell
# Разрешить все TCP на loopback-интерфейсе
New-NetFirewallRule -DisplayName "Allow Loopback TCP" `
  -Direction Inbound -Protocol TCP `
  -LocalAddress 127.0.0.0/8 `
  -Action Allow
```

### Вариант 3: Временное отключение (только для тестирования)

```powershell
# Отключить firewall для частной сети
Set-NetFirewallProfile -Profile Private -Enabled False

# После тестов -- включить обратно
Set-NetFirewallProfile -Profile Private -Enabled True
```

## Зависимости

Все зависимости зафиксированы в `go.mod` / `go.sum`. Для загрузки:

```bash
cd go
go mod download
```

Тесты не требуют дополнительных зависимостей за пределами стандартной библиотеки Go и зависимостей проекта.

## Запуск подмножества тестов

```bash
# Только криптография
go test ./core/ -run TestEncrypt -v

# Только PeerManager
go test ./core/ -run TestPeerManager -v

# Только интеграционные тесты (две ноды)
go test ./core/ -run TestTwoNodes -v

# С race detector
go test ./core/ -race -v -timeout 120s

# С замером покрытия
go test ./core/ -cover -coverprofile=coverage.out
go tool cover -html=coverage.out
```

## CI/CD

Для GitHub Actions (Windows runner):

```yaml
- name: Run tests
  run: |
    cd go
    go test ./core/ -v -count=1 -timeout 60s -race
```

На CI-серверах firewall обычно не блокирует loopback-соединения, поэтому дополнительная настройка не требуется.

## Известные особенности

1. **mDNS/UDP discovery не тестируется** -- интеграционные тесты используют `InjectPeers()` для прямого подключения нод, обходя broadcast discovery. Это делает тесты детерминированными и не зависящими от сетевой конфигурации.

2. **Логирование** -- тесты выводят log-сообщения от ноды (prefixed `[node]`). Это нормально и помогает при отладке. Для чистого вывода: `go test ./core/ -count=1 2>/dev/null`.

3. **Закрытие соединений** -- при остановке нод в тестах появляются сообщения `read from ...: use of closed network connection`. Это ожидаемое поведение graceful shutdown.
