#include "shm_var.h"
#include <iostream>
#include <cassert>
#include <string>
#include <vector>
#include <thread>
#include <chrono>
#include <cstring>

void PrintResult(const char* testName, bool success) {
    std::cout << "[" << (success ? "PASS" : "FAIL") << "] " << testName << std::endl;
    if (!success) {
        std::exit(1);
    }
}

int main(int argc, char* argv[]) {
    // Check if worker child mode
    if (argc >= 3 && std::string(argv[1]) == "--child") {
        std::string mode = argv[2];
        int32_t rc = ShmVar_Init("TestShmUnit", 16 * 1024 * 1024);
        if (rc != SHMVAR_OK) return 101;

        if (mode == "read_verify") {
            int64_t val = 0;
            if (ShmVar_GetInt("test_int", &val) != SHMVAR_OK || val != 1234567890123LL) return 1;

            double dval = 0;
            if (ShmVar_GetDouble("test_double", &dval) != SHMVAR_OK || dval != 3.141592653589793) return 2;

            char buf[256];
            size_t len = 0;
            if (ShmVar_GetStr("test_str", buf, sizeof(buf), &len) != SHMVAR_OK || std::string(buf) != "Hello C++23 Multi-Process Shm!") return 3;

            return 0; // Success
        } else if (mode == "write_child") {
            ShmVar_SetInt("child_key", 99999);
            ShmVar_SetStr("child_msg", "Written from separate process");
            return 0;
        }
        return 99;
    }

    std::cout << "========================================" << std::endl;
    std::cout << "Starting ShmVar C++23 Single-Copy Shm Test" << std::endl;
    std::cout << "========================================" << std::endl;

    // Test 1: Init Shm
    int32_t rc = ShmVar_Init("TestShmUnit", 16 * 1024 * 1024);
    PrintResult("ShmVar_Init", rc == SHMVAR_OK);

    // Test 2: Integer set & get
    rc = ShmVar_SetInt("test_int", 1234567890123LL);
    PrintResult("ShmVar_SetInt", rc == SHMVAR_OK);
    int64_t intVal = 0;
    rc = ShmVar_GetInt("test_int", &intVal);
    PrintResult("ShmVar_GetInt", rc == SHMVAR_OK && intVal == 1234567890123LL);

    // Test 3: Double set & get
    rc = ShmVar_SetDouble("test_double", 3.141592653589793);
    PrintResult("ShmVar_SetDouble", rc == SHMVAR_OK);
    double doubleVal = 0.0;
    rc = ShmVar_GetDouble("test_double", &doubleVal);
    PrintResult("ShmVar_GetDouble", rc == SHMVAR_OK && doubleVal == 3.141592653589793);

    // Test 4: String set & get
    const char* sampleStr = "Hello C++23 Multi-Process Shm!";
    rc = ShmVar_SetStr("test_str", sampleStr);
    PrintResult("ShmVar_SetStr", rc == SHMVAR_OK);
    char strBuf[128] = {0};
    size_t outLen = 0;
    rc = ShmVar_GetStr("test_str", strBuf, sizeof(strBuf), &outLen);
    PrintResult("ShmVar_GetStr", rc == SHMVAR_OK && std::string(strBuf) == sampleStr && outLen == (std::strlen(sampleStr) + 1));

    // Test 5: Bytes set & get
    std::vector<uint8_t> binaryData = {0x00, 0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0xFF, 0x42};
    rc = ShmVar_SetBytes("test_bytes", binaryData.data(), binaryData.size());
    PrintResult("ShmVar_SetBytes", rc == SHMVAR_OK);
    std::vector<uint8_t> readBytes(binaryData.size());
    size_t bytesLen = 0;
    rc = ShmVar_GetBytes("test_bytes", readBytes.data(), readBytes.size(), &bytesLen);
    PrintResult("ShmVar_GetBytes", rc == SHMVAR_OK && bytesLen == binaryData.size() && readBytes == binaryData);

    // Test 6: Overwrite existing key
    rc = ShmVar_SetInt("test_int", 987654321LL);
    int64_t updatedVal = 0;
    ShmVar_GetInt("test_int", &updatedVal);
    PrintResult("ShmVar Overwrite", rc == SHMVAR_OK && updatedVal == 987654321LL);

    // Reset back for child test
    ShmVar_SetInt("test_int", 1234567890123LL);

    // Test 7: Event notification / WaitForChange in background thread
    std::atomic<bool> threadSignaled{false};
    std::thread watcher([&]() {
        int32_t waitRes = ShmVar_WaitForChange(2000);
        if (waitRes == SHMVAR_OK) {
            threadSignaled = true;
        }
    });

    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    ShmVar_SetInt("trigger_event", 42); // Should trigger event
    watcher.join();
    PrintResult("ShmVar_WaitForChange Event Notification", threadSignaled.load());

    // Test 8: Subprocess Verification (True Cross-Process Reading)
    std::cout << "Testing Multi-Process Cross-Process read/write..." << std::endl;
    std::string exePath = argv[0];
    std::string cmd1 = "\"" + exePath + "\" --child read_verify";
    int child1Ret = std::system(cmd1.c_str());
    PrintResult("Cross-Process Reader Verification", child1Ret == 0);

    std::string cmd2 = "\"" + exePath + "\" --child write_child";
    int child2Ret = std::system(cmd2.c_str());
    PrintResult("Cross-Process Writer Execution", child2Ret == 0);

    int64_t childKeyVal = 0;
    rc = ShmVar_GetInt("child_key", &childKeyVal);
    char childMsgBuf[128] = {0};
    ShmVar_GetStr("child_msg", childMsgBuf, sizeof(childMsgBuf), nullptr);
    PrintResult("Parent Read Child's Written Data", rc == SHMVAR_OK && childKeyVal == 99999 && std::string(childMsgBuf) == "Written from separate process");

    // Test 9: Delete key
    rc = ShmVar_Delete("test_int");
    PrintResult("ShmVar_Delete", rc == SHMVAR_OK);
    int64_t deletedVal = 0;
    rc = ShmVar_GetInt("test_int", &deletedVal);
    PrintResult("ShmVar_GetInt after Delete returns NOT_FOUND", rc == SHMVAR_ERR_NOT_FOUND);

    // Test 10: Close Shm
    rc = ShmVar_Close();
    PrintResult("ShmVar_Close", rc == SHMVAR_OK);

    std::cout << "========================================" << std::endl;
    std::cout << "ALL SHMVAR TESTS PASSED SUCCESSFULLY!" << std::endl;
    std::cout << "========================================" << std::endl;

    return 0;
}
