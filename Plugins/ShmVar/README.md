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
- `shm_core.hpp`: 內部核心邏輯與資料結構宣告
- `shm_core.cpp`: 哈希鏈表操作、二進制/字串安全配置與全生命週期資源釋放實作
- `shm_rwlock.hpp`: 跨進程讀寫鎖 (`CrossProcessSharedLock` / `CrossProcessExclusiveLock`) 實作
- `shm_allocator.hpp`: 跨行程 Buddy Allocator 封裝（基於相對偏移量 Offset）
- `buddy_alloc.hpp`: 嵌入式 Buddy Allocator 原生實現 (C++23)
- `shm_internal.hpp`: 內部 Header、節點結構、FNV-1a 哈希及結構體對齊定義
- `CMakeLists.txt`: CMake 構建配置 (C++23)
- `test_shm.cpp`: 單元測試、記憶體循環重用測試與多進程並發讀寫驗證程式
- `ShmVar.dll`: 原生動態鏈接庫
- `test_shm.exe`: 測試驗證執行檔

## 編譯方式

### MinGW（64 位，開發 / 測試）

```cmd
# Configure (once)
cmake -S Plugins/ShmVar -B build -G "MinGW Makefiles" -DCMAKE_BUILD_TYPE=Release

# Build DLL and test executable
cmake --build build --target ShmVar
cmake --build build --target test_shm

# Run tests
./build/test_shm.exe
```

### MSVC 雙架構（64 位 + 32 位）

需要安裝 Visual Studio 2022（含 C++ 桌面開發元件）。

```cmd
:: x64
cmake -S Plugins/ShmVar -B Test/build_msvc/x64 -G "Visual Studio 17 2022" -A x64
cmake --build Test/build_msvc/x64 --target ShmVar --config Release

:: x86
cmake -S Plugins/ShmVar -B Test/build_msvc/x86 -G "Visual Studio 17 2022" -A Win32
cmake --build Test/build_msvc/x86 --target ShmVar --config Release
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

`buddy_alloc.hpp` 驗證

| 測試                                                         | 結果   |
| ------------------------------------------------------------ | ------ |
| 2 MiB arena：與 C 對照 1,000,000 次隨機 allocate/free；比較成功狀態、offset、block size、free bytes、fragmentation | PASS   |
| 非 2 的次方 arena：與 C 對照 1,000,000 次隨機 allocate/free；相同比較欄位 | PASS   |
| 100,000 次隨機 realloc，含 shrink/grow/move 與 payload preservation | PASS   |
| 50,000 次 Reservation mark/release，期間穿插 allocate/free   | PASS   |
| Embedded create、byte-copy attach、resize_embedded 搬遷、Reservation 與 logical resize | PASS   |
| GCC 14.2 嚴格警告編譯（`-Wall -Wextra -Wpedantic -Wconversion -Wshadow -Werror`） | PASS   |
| Clang 17 嚴格警告編譯與核心測試                              | PASS   |
| ASan + UBSan：隨機配置／釋放、realloc、Reservation、embedded 搬遷 | PASS   |
| `statistics()` / `allocator_statistics` / `space_statistics` API 搜尋 | 未加入 |

