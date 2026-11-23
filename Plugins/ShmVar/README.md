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
- `shm_internal.h`: 內部 Header、節點結構、FNV-1a 哈希及相對偏移定義 (C++23)
- `shm_var.cpp`: 核心邏輯實現與 DLL 導出函式
- `CMakeLists.txt`: CMake 構建配置 (C++23)
- `test_shm.cpp`: 單元測試與真實多進程讀寫驗證程式
- `ShmVar.dll`: 原生動態鏈接庫
- `test_shm.exe`: 測試驗證執行檔

## 編譯方式 (g++ C++23)

```cmd
:: 編譯 DLL（啟用 Release 優化、去除斷言，靜態鏈接 C/C++ 運行庫）
g++ -std=c++23 -O3 -DNDEBUG -DSHMVAR_EXPORTS -shared ^
    -static-libgcc -static-libstdc++ ^
    -o Plugins/ShmVar/ShmVar.dll Plugins/ShmVar/shm_var.cpp

:: 編譯測試程式
g++ -std=c++23 -O3 -o Plugins/ShmVar/test_shm.exe Plugins/ShmVar/test_shm.cpp -LPlugins/ShmVar -lShmVar

```

## 測試驗證結果
執行 `test_shm.exe` 全數通過：
- [PASS] 基本類型存取 (Int64, Double, String, Binary Bytes)
- [PASS] 覆寫與覆蓋重用機制
- [PASS] Win32 具名 Event 跨線程/進程即時感知
- [PASS] 真實跨進程驗證（Subprocess 子進程讀取父進程寫入數據、子進程寫入數據父進程即時讀取）
- [PASS] 刪除與釋放清理
