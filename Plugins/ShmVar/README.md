# ShmVar - 高性能純內存多進程單一副本共享變量模組 (C++23)

## 概述
`ShmVar` 為多進程架構提供極致性能的零複製 (Zero-Copy) / 單一副本共享變量存取庫：
- **純 RAM 存儲**：採用 Win32 `CreateFileMappingA(INVALID_HANDLE_VALUE, ...)` 與 `MapViewOfFile`，無磁盤 I/O 負擔。
- **相對偏移尋址**：指針完全採用相對於共享內存基地址的 `uint32_t offset`，完美兼容多進程中 `MapViewOfFile` 映射基地址不一致的問題。
- **零 IPC 傳輸**：單一副本多進程共享，支持動態 Key-Value 存儲（支持 `int64`、`double`、`string`、任意二進制 `bytes`）。
- **併發與事件廣播**：具名 Mutex 保護寫入/動態內存分配安全，搭配具名 Event 實現毫秒級變更即時感知 (`ShmVar_WaitForChange`)。
- **原生 C-Style 導出 API**：提供極簡的 C-Style 導出接口，便於 C++、C#、Python、AutoHotkey 等多種進程無縫調用。

## 目錄結構
- `shm_var.h`: C-Style 導出 API 頭文件
- `shm_var.cpp`: `extern "C"` 導出函數薄適配層 (DLL Entrypoint)
- `shm_core.h`: 內部核心邏輯與輔助函式宣告 (C++23)
- `shm_core.cpp`: 哈希鏈表操作、二進制/字串安全配置與資源釋放實作
- `shm_allocator.h`: 跨行程 Buddy Allocator 封裝（基於相對偏移量 Offset）
- `buddy_alloc.h`: 嵌入式 Buddy Allocator 原生實現 (spaskalev/buddy_alloc)
- `shm_internal.h`: 內部 Header、節點結構、FNV-1a 哈希及結構體對齊定義
- `CMakeLists.txt`: CMake 構建配置 (C++23)
- `test_shm.cpp`: 單元測試與真實多進程讀寫驗證程式
- `ShmVar.dll`: 原生動態鏈接庫
- `test_shm.exe`: 測試驗證執行檔

## 編譯方式 (g++ C++23)

在 `Plugins/ShmVar` 目錄下執行：

```cmd
:: 編譯 DLL（啟用 Release 優化、去除斷言，靜態鏈接 C/C++ 運行庫）
g++ -std=c++23 -O3 -DNDEBUG -DSHMVAR_EXPORTS -shared ^
    -static-libgcc -static-libstdc++ ^
    -o Plugins/ShmVar/ShmVar.dll Plugins/ShmVar/shm_var.cpp Plugins/ShmVar/shm_core.cpp


:: 編譯測試程式
g++ -std=c++23 -O3 -o Plugins/ShmVar/test_shm.exe Plugins/ShmVar/test_shm.cpp -LPlugins/ShmVar -lShmVar
```

## 測試驗證結果
執行 `test_shm.exe` 全數通過：
```
========================================
Starting ShmVar C++23 Single-Copy Shm Test
========================================
[PASS] ShmVar_Init
[PASS] ShmVar_SetInt
[PASS] ShmVar_GetInt
[PASS] ShmVar_SetDouble
[PASS] ShmVar_GetDouble
[PASS] ShmVar_SetStr
[PASS] ShmVar_GetStr
[PASS] ShmVar_SetBytes
[PASS] ShmVar_GetBytes
[PASS] ShmVar Overwrite
[PASS] ShmVar_WaitForChange Event Notification
Testing Multi-Process Cross-Process read/write...
[PASS] Cross-Process Reader Verification
[PASS] Cross-Process Writer Execution
[PASS] Parent Read Child's Written Data
[PASS] ShmVar_Delete
[PASS] ShmVar_GetInt after Delete returns NOT_FOUND
[PASS] ShmVar_Recycle_50x256KB_MemoryReused
[PASS] ShmVar_Close
========================================
ALL SHMVAR TESTS PASSED SUCCESSFULLY!
========================================
```