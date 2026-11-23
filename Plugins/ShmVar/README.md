# ShmVar - 高性能純內存多進程單一副本共享變量模組 (C++23)

## 概述
`ShmVar` 為多進程架構提供極致性能的零複製 (Zero-Copy) / 單一副本共享變量存取庫：
- **純 RAM 存儲**：採用 Win32 `CreateFileMappingA(INVALID_HANDLE_VALUE, ...)` 與 `MapViewOfFile`，無磁盤 I/O 負擔。
- **相對偏移尋址**：指針完全採用相對於共享內存基地址的 `uint32_t offset`，完美兼容多進程中 `MapViewOfFile` 映射基地址不一致的問題。
- **可回收 Buddy Allocator**：整合嵌入式 `buddy_alloc`，支援 Key、Node 與 Blob 的動態回收與合併，覆寫與刪除零記憶體洩漏。
- **真正跨進程讀寫鎖 (RWLock)**：採用共享內存原子計數器 (`readerCount`, `writerWaiting`) 搭配 Win32 具名 Mutex 與 Manual-Reset Event，實現**多行程並發無鎖讀取**與**排他獨佔寫入**（具抗寫入飢餓機制）。
- **零 IPC 傳輸**：單一副本多進程共享，支持動態 Key-Value 存儲（支持 `int64`、`double`、`string`、任意二進制 `bytes`）。
- **事件廣播感知**：具名 Event 實現毫秒級變更即時感知 (`ShmVar_WaitForChange`)。
- **原生 C-Style 導出 API**：提供極簡的 C-Style 導出接口，便於 C++、C#、Python、AutoHotkey 等多種進程無縫調用。

## 目錄結構
- `shm_var.h`: C-Style 導出 API 頭文件
- `shm_var.cpp`: `extern "C"` 導出函數薄適配層 (DLL Entrypoint，負責參數校驗與讀寫鎖派發)
- `shm_core.h`: 內部核心邏輯與資料結構宣告
- `shm_core.cpp`: 哈希鏈表操作、二進制/字串安全配置與全生命週期資源釋放實作
- `shm_rwlock.h`: 真正跨進程讀寫鎖 (`CrossProcessSharedLock` / `CrossProcessExclusiveLock`) 實作
- `shm_allocator.h`: 跨行程 Buddy Allocator 封裝（基於相對偏移量 Offset）
- `buddy_alloc.h`: 嵌入式 Buddy Allocator 原生實現 (spaskalev/buddy_alloc，0BSD 授權)
- `shm_internal.h`: 內部 Header、節點結構、FNV-1a 哈希及結構體對齊定義
- `CMakeLists.txt`: CMake 構建配置 (C++23)
- `test_shm.cpp`: 單元測試、記憶體循環重用測試與多進程並發讀寫驗證程式
- `ShmVar.dll`: 原生動態鏈接庫
- `test_shm.exe`: 測試驗證執行檔

## 編譯方式

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
```text
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
[PASS] ShmVar_Concurrent_RWLock_4Readers_1Writer
[PASS] ShmVar_Close
========================================
ALL SHMVAR TESTS PASSED SUCCESSFULLY!
========================================
```