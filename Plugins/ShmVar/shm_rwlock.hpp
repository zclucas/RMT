#ifndef SHM_RWLOCK_HPP
#define SHM_RWLOCK_HPP

#include "shm_internal.hpp"
#include <windows.h>
#include <atomic>
#include <thread>
#include <chrono>

namespace shm {

// Cross-process synchronization handles
struct ShmSyncHandles {
    HANDLE hWriterMutex = nullptr;  // Named Mutex: serializes writers & blocks new readers
    HANDLE hNoReadersEvent = nullptr; // Named Manual-Reset Event: signaled when readerCount == 0
    HANDLE hNotifyEvent = nullptr;   // Named Auto-Reset Event: broadcast value change notifications
};

// RAII Exclusive (Write) Lock across all processes
class CrossProcessExclusiveLock {
public:
    CrossProcessExclusiveLock(ShmHeader* header, const ShmSyncHandles& handles, DWORD timeoutMs = INFINITE)
        : m_header(header), m_handles(handles), m_acquired(false) {
        if (!m_header || !m_handles.hWriterMutex || !m_handles.hNoReadersEvent) return;

        // 1. Acquire the cross-process writer mutex (only one writer at a time)
        DWORD res = WaitForSingleObject(m_handles.hWriterMutex, timeoutMs);
        if (res != WAIT_OBJECT_0 && res != WAIT_ABANDONED) {
            return;
        }

        // 2. Announce that a writer is waiting to prevent new readers from entering
        m_header->writerWaiting.fetch_add(1, std::memory_order_seq_cst);

        // 3. Wait until all active readers finish (readerCount drops to 0)
        while (m_header->readerCount.load(std::memory_order_seq_cst) > 0) {
            // Wait on the manual-reset hNoReadersEvent
            DWORD evtRes = WaitForSingleObject(m_handles.hNoReadersEvent, 50);
            if (evtRes == WAIT_OBJECT_0) {
                if (m_header->readerCount.load(std::memory_order_seq_cst) == 0) {
                    break;
                }
            }
            std::this_thread::yield();
        }

        m_acquired = true;
    }

    ~CrossProcessExclusiveLock() {
        if (m_acquired) {
            m_header->writerWaiting.fetch_sub(1, std::memory_order_seq_cst);
            ReleaseMutex(m_handles.hWriterMutex);
        }
    }

    bool isLocked() const noexcept { return m_acquired; }

private:
    ShmHeader* m_header;
    const ShmSyncHandles& m_handles;
    bool m_acquired;
};

// RAII Shared (Read) Lock across all processes
class CrossProcessSharedLock {
public:
    CrossProcessSharedLock(ShmHeader* header, const ShmSyncHandles& handles)
        : m_header(header), m_handles(handles), m_acquired(false) {
        if (!m_header || !m_handles.hWriterMutex || !m_handles.hNoReadersEvent) return;

        while (true) {
            // If a writer holds the mutex or is waiting, wait briefly on writer mutex
            if (m_header->writerWaiting.load(std::memory_order_relaxed) > 0) {
                DWORD res = WaitForSingleObject(m_handles.hWriterMutex, 50);
                if (res == WAIT_OBJECT_0 || res == WAIT_ABANDONED) {
                    // Writer done, release mutex immediately for other readers
                    ReleaseMutex(m_handles.hWriterMutex);
                }
            }

            // Tentatively register as an active reader
            m_header->readerCount.fetch_add(1, std::memory_order_seq_cst);

            // Double check if a writer started waiting right before our increment
            if (m_header->writerWaiting.load(std::memory_order_seq_cst) > 0) {
                // Yield to writer: decrement and retry
                uint32_t prev = m_header->readerCount.fetch_sub(1, std::memory_order_seq_cst);
                if (prev == 1) {
                    SetEvent(m_handles.hNoReadersEvent);
                }
                std::this_thread::yield();
                continue;
            }

            // Successfully joined reader pool, ensure no-readers event is reset
            ResetEvent(m_handles.hNoReadersEvent);
            m_acquired = true;
            break;
        }
    }

    ~CrossProcessSharedLock() {
        if (m_acquired) {
            uint32_t prev = m_header->readerCount.fetch_sub(1, std::memory_order_seq_cst);
            if (prev == 1) {
                // Last reader leaving signals the waiting writer
                SetEvent(m_handles.hNoReadersEvent);
            }
        }
    }

    bool isLocked() const noexcept { return m_acquired; }

private:
    ShmHeader* m_header;
    const ShmSyncHandles& m_handles;
    bool m_acquired;
};

} // namespace shm

#endif // SHM_RWLOCK_HPP
