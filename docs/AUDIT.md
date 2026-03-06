# Аудит кодовой базы Piper

Дата: 2026-03-06
Охват: `go/core/`, `go/ffi/bridge.go`, `go/tui/model.go`, `flutter-app/lib/`

---

## Архитектура (краткое описание)

| Слой | Технология | Роль |
|------|-----------|------|
| Сетевое ядро | Go (core/) | P2P TCP-соединения, mDNS + UDP broadcast discovery, X25519 ECDH + ChaCha20-Poly1305 |
| FFI мост | Go (ffi/bridge.go) | Экспорт C-функций; Dart вызывает их через dart:ffi |
| Мобильный/десктоп клиент | Flutter/Dart | UI, звонки (WebRTC), SQLite, управление событиями |
| TUI (консоль) | Go (tui/) | BubbleTea-интерфейс для PC |

---

## КРИТИЧЕСКИЕ УЯЗВИМОСТИ

### C-1. Path Traversal при приёме файлов

**Файлы:** [go/core/node.go:1025](go/core/node.go), [flutter-app/lib/services/piper_service.dart:269](flutter-app/lib/services/piper_service.dart)

Go-сторона:
```go
destPath := filepath.Join(dlDir, msg.FileName)
f, err := os.Create(destPath)
```
Dart-сторона:
```dart
final filePath = e.fileName != null
    ? '$_downloadsDir${Platform.pathSeparator}${e.fileName}'
    : null;
```

`msg.FileName` поступает от удалённого пира без санитизации. Злоумышленник может выслать имя файла `../../.ssh/authorized_keys` или `../../etc/cron.d/evil`, и файл будет записан вне `downloadsDir`. На Android это может позволить перезаписать файлы приложения. На ПК — системные файлы текущего пользователя.

**Severity: CRITICAL**

---

### C-2. Нет аутентификации пиров — возможна MITM-атака

**Файл:** [go/core/node.go:802-831](go/core/node.go)

PeerID — самоизбранный UUID, отправляемый в Hello-сообщении. Никто не верифицирует, что отправитель действительно владеет этим ID. Протокол:

1. Пир A отправляет Hello с `peer_id=<uuid_A>` и своим публичным X25519 ключом.
2. Пир B не имеет никакой внешней точки доверия, чтобы проверить, что этот UUID действительно принадлежит A.

Это означает:
- **Спуфинг**: злоумышленник M может принять ID известного пира A и перехватить его сообщения.
- **MITM**: M встаёт между A и B, устанавливает отдельные ECDH-сессии с каждым. Оба думают, что общаются друг с другом, но шарят ключ с M.

Нет PKI, нет подписи PeerID публичным ключом, нет механизма верификации "fingerprint".

**Severity: CRITICAL**

---

### C-3. Спуфинг отправителя в глобальном чате

**Файл:** [go/core/node.go:853-856](go/core/node.go)

```go
case MsgTypeText:
    n.maybeUpdatePeerName(msg.PeerID, msg.Name)
    n.emit(Event{Msg: &msg})
```

Нет проверки, что `msg.PeerID == cn.peerID`. Любой подключённый пир может отправить сообщение типа `text` с произвольными `PeerID` и `Name`, выдавая себя за другого участника глобального чата.

**Severity: CRITICAL**

---

### C-4. Nil pointer dereference panic при передаче файла

**Файл:** [go/core/node.go:455](go/core/node.go)

```go
func (n *Node) streamFileChunks(t *Transfer, key [32]byte, cn *conn) {
    // ... ожидание accept ...
    defer t.file.Close()  // <-- ПРОБЛЕМА
    ...
    if err := EncryptBytes(...); err != nil {
        n.transfers.Fail(t.ID, "encrypt: "+err.Error())  // устанавливает t.file = nil
        return  // defer вызывается с t.file == nil → PANIC
    }
}
```

`TransferManager.Fail()` и `TransferManager.Complete()` оба закрывают `t.file` и устанавливают его в `nil`:
```go
if t.file != nil {
    t.file.Close()
    t.file = nil
}
```

Когда `streamFileChunks` выходит после вызова `Fail()` или `Complete()`, отложенный `defer t.file.Close()` вызывается с `t.file == nil`, что вызывает **nil pointer dereference panic**. Это происходит при каждой ошибке шифрования, ошибке записи, ошибке чтения, ошибке сетевой отправки, и при нормальном завершении передачи (т.к. `Complete()` тоже зануляет `t.file`).

**Severity: CRITICAL** — крашит горутину передачи при каждой завершённой или неудачной передаче.

---

### C-5. Data race на Group.Members

**Файлы:** [go/core/node.go:236](go/core/node.go), [go/core/group.go:88](go/core/group.go)

`GroupManager.Get()` возвращает указатель на внутреннюю структуру `Group`:
```go
func (gm *GroupManager) Get(groupID string) *Group {
    gm.mu.RLock()
    defer gm.mu.RUnlock()
    return gm.groups[groupID]  // указатель на внутренние данные
}
```

После возврата блокировка снята, а `Group.Members` (тип `map[string]bool`) читается без блокировки:
```go
// node.go:236
for memberID := range g.Members {  // no lock
```

Параллельно `AddMember()` / `RemoveMember()` изменяют ту же карту под `gm.mu.Lock()`. Результат — **data race** (Go race detector обнаружит это).

**Severity: CRITICAL** — неопределённое поведение, возможен крэш.

---

### C-6. Data race на PeerInfo

**Файл:** [go/core/peer.go:136](go/core/peer.go)

Аналогично: `PeerManager.Get()` возвращает `*PeerInfo` — указатель на внутренние данные — без удержания блокировки. Вызывающий код затем читает `peer.SharedKey`, `peer.Name`, `peer.State` без какой-либо синхронизации, пока другие горутины могут изменять эти поля через `Upsert`, `SetSharedKey`, `SetState`.

**Severity: CRITICAL** — data race.

---

## ВЫСОКИЕ УЯЗВИМОСТИ

### H-1. Автоматическое принятие файлов без согласия пользователя

**Файл:** [go/core/node.go:1008-1050](go/core/node.go)

```go
func (n *Node) handleFileOffer(msg Message, cn *conn) {
    // Auto-accept: create download directory and destination file.
```

Любой подключённый пир может отправить произвольный файл, и он будет автоматически записан на диск. В сочетании с C-1 (Path Traversal) это позволяет записать вредоносный файл в произвольное место файловой системы.

**Severity: HIGH**

---

### H-2. Event channel silently drops events при переполнении

**Файл:** [go/core/node.go:1152-1158](go/core/node.go)

```go
func (n *Node) emit(e Event) {
    select {
    case n.eventCh <- e:
    default:
        // Drop if nobody is consuming (e.g. during shutdown).
    }
}
```

Буфер канала — 512 событий. При активной передаче файлов (множество `TransferProgress` событий) канал может переполниться, и сообщения чата будут **молча потеряны**. TUI и FFI-клиент никогда не узнают об этом.

**Severity: HIGH**

---

### H-3. Goroutine leak в mDNS browse

**Файл:** [go/core/discovery.go:136-146](go/core/discovery.go)

```go
for {
    if err := resolver.Browse(ctx, mdnsService, mdnsDomain, entries); err != nil {
        log.Printf("[discovery] mDNS browse: %v", err)
    }
    select {
    case <-ctx.Done():
        return
    case <-time.After(10 * time.Second):
        // retry
    }
}
```

`resolver.Browse()` запускает внутреннюю горутину, которая пишет в `entries`. При ошибке Browse цикл ждёт 10 секунд и вызывает `Browse()` снова с тем же каналом — создавая **новую горутину**, при этом предыдущая может ещё работать. Каждая ошибка добавляет ещё одну горутину-зомби.

**Severity: HIGH**

---

### H-4. TUI: бесконечный цикл при закрытии канала событий

**Файл:** [go/tui/model.go:147-152](go/tui/model.go)

```go
func listenForEvents(n *core.Node) tea.Cmd {
    return func() tea.Msg {
        e := <-n.Events()  // если канал закрыт, возвращает нулевое значение немедленно
        return nodeEventMsg(e)
    }
}
```

После вызова `node.Stop()` канал `eventCh` не закрывается явно — но если бы закрывался, `<-n.Events()` возвращал бы нулевое `core.Event{}` без блокировки, что создавало бы бесконечный поток нулевых событий в TUI.

Фактически: после остановки узла TUI продолжает блокироваться на `<-n.Events()` бесконечно (горутина не выходит), а BubbleTea не имеет возможности остановить её. **Goroutine leak** при каждом вызове `node.Stop()`.

**Severity: HIGH**

---

### H-5. FFI: race condition при замене event callback

**Файл:** [go/ffi/bridge.go:281-293](go/ffi/bridge.go)

```go
func PiperSetEventCallback(handle C.int, cb C.EventCallback) {
    if e.stopPump != nil {
        close(e.stopPump)  // сигнализируем старой горутине
    }
    e.cb = cb
    e.stopPump = make(chan struct{})
    go eventPump(e)  // запускаем новую горутину немедленно
}
```

Закрытие `stopPump` — это сигнал, а не синхронизация. Старая горутина `eventPump` может ещё не завершиться, когда новая уже запустилась. Обе горутины будут одновременно читать события из одного канала и вызывать callback. **Двойные события** — временно.

**Severity: HIGH**

---

## СРЕДНИЕ ПРОБЛЕМЫ

### M-1. Глобальный чат передаётся в открытом виде

**Файл:** [go/core/node.go:594-598](go/core/node.go)

`MsgTypeText` (глобальный чат) передаётся без шифрования. Пользователи могут не понимать разницу между "глобальным" и "личным" чатом. UI помечает директ и групповые чаты тегом `[E2E]`, но нигде явно не предупреждает, что глобальный чат — plaintext.

**Severity: MEDIUM**

---

### M-2. Panic при коротком PeerID / GroupID

**Файл:** [go/core/node.go](go/core/node.go) — множество мест

```go
log.Printf("[node] InviteToGroup: unknown group %s", groupID[:8])
log.Printf("[node] sendDirect: no shared key for %s", toPeerID[:8])
// и многие другие...
```

Если ID короче 8 символов (например, пустая строка), slice `[:8]` вызовет **panic: runtime error: slice bounds out of range**. PeerID — UUID (36 символов), так что в норме это не происходит, но злоумышленник может отправить Hello с коротким `peer_id`.

**Severity: MEDIUM**

---

### M-3. Collision Message ID в Dart клиенте

**Файл:** [flutter-app/lib/services/piper_service.dart:328](flutter-app/lib/services/piper_service.dart)

```dart
id: '${DateTime.now().millisecondsSinceEpoch}',
```

Два сообщения, отправленных в одну миллисекунду, получат одинаковый ID. При вставке в SQLite с `ConflictAlgorithm.replace` более раннее сообщение **будет удалено** из базы данных.

**Severity: MEDIUM**

---

### M-4. WebRTC без STUN/TURN — звонки работают только в LAN

**Файл:** [flutter-app/lib/services/call_service.dart:126](flutter-app/lib/services/call_service.dart)

```dart
static const _rtcConfig = {
    'iceServers': <Map<String, dynamic>>[],
    'iceTransportPolicy': 'all',
};
```

Без STUN-сервера невозможно определить внешний IP. Без TURN-сервера невозможен relay через NAT. Звонки будут работать только в одной локальной сети.

**Severity: MEDIUM** (ограничение функциональности, не безопасность)

---

### M-5. Device preferences сбрасываются после каждого звонка

**Файл:** [flutter-app/lib/services/call_service.dart:885](flutter-app/lib/services/call_service.dart)

```dart
selectedMicId = null;
selectedCameraId = null;
selectedSpeakerId = null;
```

`_clearSessionForIdle()` сбрасывает выбранные устройства в `null`. SharedPreferences обновляется только через `saveDevicePreferences()`, но сам сервис теряет настройки. После каждого звонка следующий звонок начнётся с устройствами по умолчанию, игнорируя сохранённые настройки, пока не будет вызван `loadDevicePreferences()` (который вызывается только при старте следующего звонка — поздно, т.к. сеанс уже инициирован).

**Severity: MEDIUM**

---

### M-6. UDP payload размером >512 байт молча игнорируется

**Файл:** [go/core/discovery.go:188](go/core/discovery.go)

```go
buf := make([]byte, 512)
n, raddr, err := d.udpConn.ReadFromUDP(buf)
```

Если UDP-датаграмма больше 512 байт (например, имя пира >400 символов UTF-8), пакет будет обрезан и `json.Unmarshal` вернёт ошибку — пир не будет обнаружен. Нет предупреждения.

**Severity: MEDIUM**

---

### M-7. mDNS TXT-записи не экранируются

**Файл:** [go/core/discovery.go:92](go/core/discovery.go)

```go
txt := []string{
    "id=" + d.peerID,
    "name=" + d.name,
}
```

Имя пира с символами `=` или пустым значением может нарушить парсинг TXT-записей другими пирами:
```go
if len(txt) > 3 && txt[:3] == "id=" {
    id = txt[3:]
}
```
Имя `id=evil_id` в поле `name` может быть распознано как PeerID.

**Severity: MEDIUM**

---

### M-8. handleFileAccept: повторное закрытие accepted канала

**Файл:** [go/core/node.go:1060](go/core/node.go)

```go
func (n *Node) handleFileAccept(msg Message) {
    t := n.transfers.Get(msg.TransferID)
    if t == nil || !t.Sending {
        return
    }
    close(t.accepted)  // PANIC если уже закрыт
}
```

Если получены два `FileAccept` сообщения для одного `TransferID` (дублирование сетевого пакета или злонамеренная повторная отправка), `close()` вызовется дважды — **panic: close of closed channel**.

**Severity: MEDIUM**

---

### M-9. getEntry использует write lock вместо read lock

**Файл:** [go/ffi/bridge.go:346](go/ffi/bridge.go)

```go
func getEntry(handle C.int) *nodeEntry {
    handleMu.Lock()      // должен быть RLock для read-only операции
    defer handleMu.Unlock()
    return nodes[handle]
}
```

Все операции сериализуются через write lock, хотя `getEntry` только читает. При большой нагрузке создаёт излишнее ожидание.

**Severity: LOW** (производительность)

---

### M-10. nextHandle integer overflow в FFI

**Файл:** [go/ffi/bridge.go:24](go/ffi/bridge.go)

```go
nextHandle C.int = 1
```

`C.int` — 32-битное знаковое целое. После 2^31−1 вызовов `PiperCreateNode` происходит переполнение. Маловероятно на практике, но стоит использовать атомарный счётчик или map с автоматической генерацией ключей.

**Severity: LOW**

---

### M-11. Отсутствует проверка порядка чанков при приёме файла

**Файл:** [go/core/node.go:1063](go/core/node.go)

`handleFileChunk` не проверяет `msg.ChunkSeq` и записывает данные последовательно. Хотя TCP гарантирует порядок, нет защиты от replay-атаки (повторная отправка чанка), что приведёт к повреждению файла.

**Severity: LOW** (в контексте TCP-only транспорта)

---

### M-12. Отсутствует проверка X25519 low-order points

**Файл:** [go/core/crypto.go:48](go/core/crypto.go)

```go
func SharedSecret(myPriv [32]byte, theirPub []byte) ([32]byte, error) {
    shared, err := curve25519.X25519(myPriv[:], theirPub)
```

Не выполняется явная проверка на low-order points публичного ключа пира. Пакет `golang.org/x/crypto/curve25519` внутренне защищает от некоторых degenerate keys, но рекомендуется явная проверка: результирующий shared secret не должен быть all-zeros.

**Severity: LOW**

---

### M-13. Неограниченный рост earlyIceByCall при отсутствии совпадений

**Файл:** [flutter-app/lib/services/call_service.dart:951-958](flutter-app/lib/services/call_service.dart)

```dart
void _stashEarlyIce(String callId, Map<String, dynamic> data) {
    ...
    _earlyIceByCall.putIfAbsent(callId, () => <Map<String, dynamic>>[]);
    _earlyIceByCall[callId]!.add(...);
}
```

Ограничение 128 кандидатов на callId корректно. Но сам `_earlyIceByCall` может накапливать записи для произвольного числа callId от злонамеренных пиров, которые шлют `call_ice` с несуществующими callId. Утечка памяти при атаке.

**Severity: LOW/MEDIUM**

---

## НИЗКИЕ ПРОБЛЕМЫ

| # | Описание | Файл |
|---|---------|------|
| L-1 | `markChatAsRead` не обрабатывает `_unreadCounts[chatId] == null` корректно (map miss) | piper_service.dart:118 |
| L-2 | `fileExt` формируется через `.last` без проверки — файл без расширения вызовет `.last` на пустом списке | piper_service.dart:280 |
| L-3 | Глобальный broadcast не ограничен по скорости — возможен спам | node.go |
| L-4 | `piper.log` создаётся в CWD без возможности настройки пути | main.go:26 |
| L-5 | `defaultName()` использует `filepath.Base(hostname)` — на Linux/macOS basename hostname = FQDN без домена, что может быть пустым | main.go:50 |
| L-6 | `udpBroadcastPort = 47821` жёстко задан — нет механизма обнаружения конфликта портов | discovery.go:26 |
| L-7 | `colorForPeer` использует сумму кодов символов как хэш — очень плохое распределение, коллизии частые | piper_service.dart:413 |
| L-8 | `_seenSignals` ограничен 512 записями — при интенсивном использовании старые записи удаляются, возможны повторы | call_service.dart:927 |
| L-9 | Нет timeout на `handleFileChunk` — зависший отправитель может держать открытый файловый дескриптор бесконечно | node.go:1063 |
| L-10 | SQLite `getAllMessages()` загружает всю историю в память без пагинации | database_service.dart:110 |
| L-11 | `initialsFor()` берёт `name.substring(0, 2)` — может разрезать многобайтовый UTF-8 символ | piper_service.dart:423 |

---

## Резюме по приоритетам

| Критичность | Количество | Главные риски |
|------------|-----------|--------------|
| CRITICAL | 6 | Path traversal, отсутствие auth, спуфинг, nil deref panic, data races |
| HIGH | 5 | Автоприём файлов, потеря событий, goroutine leaks, race в callback |
| MEDIUM | 8 | Нет STUN/TURN, коллизия ID, mDNS injection, double-close panic |
| LOW | 11 | UX-проблемы, слабый хэш, ограничения производительности |

---

## Приоритеты для исправления

1. **[C-1]** Санитизировать FileName: `filepath.Base(msg.FileName)` + проверка на `..`
2. **[C-4]** Убрать `defer t.file.Close()` из `streamFileChunks`, или проверять nil перед вызовом
3. **[C-5, C-6]** `GroupManager.Get()` и `PeerManager.Get()` должны возвращать копии, а не указатели
4. **[C-3]** В обработчике `MsgTypeText` проверять `msg.PeerID == cn.peerID`
5. **[H-1]** Добавить подтверждение пользователя перед приёмом файла
6. **[C-2]** Долгосрочно: ввести аутентификацию пиров (подписать PeerID публичным ключом)
