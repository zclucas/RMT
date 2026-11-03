/* Older Windows 10 builds have no api-ms-win-core-path-l1-1-0 API set.
   When the OS provides it, the loader uses the system contract and ignores this DLL. */
#include <windows.h>

typedef long (__stdcall *PathCchFn)(wchar_t *, size_t);

static PathCchFn Resolve(const char *name) {
    HMODULE kernel = GetModuleHandleW(L"KERNELBASE.dll");
    if (!kernel)
        kernel = LoadLibraryW(L"KERNELBASE.dll");
    if (!kernel)
        return 0;
    return (PathCchFn)GetProcAddress(kernel, name);
}

__declspec(dllexport) long __stdcall PathCchRemoveBackslash(wchar_t *path, size_t cch) {
    PathCchFn fn = Resolve("PathCchRemoveBackslash");
    return fn ? fn(path, cch) : (long)0x80004001L;
}

__declspec(dllexport) long __stdcall PathCchRemoveFileSpec(wchar_t *path, size_t cch) {
    PathCchFn fn = Resolve("PathCchRemoveFileSpec");
    return fn ? fn(path, cch) : (long)0x80004001L;
}
