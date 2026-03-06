шаг 1: подготовка окружения
```Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser```
```Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression```
```scoop install mingw```
```$env:CGO_ENABLED = "1" ```

шаг 2: запуск юнит тестов
```go test ./core/... -v -run "TestGenerate|TestEncrypt|TestDecrypt|TestShared|TestWrite|TestRead|TestNew|TestMessage|TestPeer|TestGroup|TestTransfer"```