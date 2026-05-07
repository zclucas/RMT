# AutoHotkey Chinese Error Runtime

RMT packages a modified AutoHotkey v2.0.26 runtime so runtime errors shown by RMT and `Thread\Work1.exe` use Chinese error text and a Chinese help page.

## Tracked Runtime Files

The local toolchain is tracked under `.tools` even though the rest of `.tools` remains ignored:

- `.tools\AutoHotkey\v2\AutoHotkey64.exe`
- `.tools\AutoHotkey\v2\AutoHotkey32.exe`
- `.tools\AutoHotkey\v2\Unicode 64-bit.bin`
- `.tools\AutoHotkey\v2\Unicode 32-bit.bin`
- `.tools\AutoHotkey\Compiler\Ahk2Exe.exe`
- `.tools\AutoHotkey\Compiler\AutoHotkey64.exe`
- `.tools\AutoHotkey\Compiler\AutoHotkey32.exe`

`PackRMT.ps1` prefers these files before the system AutoHotkey install.

## Source And License

The runtime is based on AutoHotkey v2.0.26. AutoHotkey is GPL licensed.

- License copy: `docs\AutoHotkey-GPL-license.txt`
- Local modification patch: `docs\patches\AutoHotkey-v2.0.26-cn-error-localization.patch`
- Upstream source: `https://github.com/AutoHotkey/AutoHotkey/tree/v2.0`

The patch localizes core error strings, the error dialog buttons, and the error dialog Help button. The Help button generates a temporary Chinese HTML page with the current error, line/file information, likely causes, suggested fixes, and links to the Chinese AutoHotkey v2 documentation.

## Rebuilding The Runtime

Install Visual Studio Build Tools 2022 with the C++ workload and Windows SDK, then clone AutoHotkey v2.0.26:

```powershell
git clone --branch v2.0 https://github.com/AutoHotkey/AutoHotkey.git _source_repos\AutoHotkey-v2.0
cd _source_repos\AutoHotkey-v2.0
git apply ..\..\RMT-zclucas-v1.1.2\docs\patches\AutoHotkey-v2.0.26-cn-error-localization.patch
```

Build the four outputs:

```powershell
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" AutoHotkeyx.sln /t:Build /p:Configuration=Release /p:Platform=x64 /m
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" AutoHotkeyx.sln /t:Build /p:Configuration=Release /p:Platform=Win32 /m
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" AutoHotkeyx.sln /t:Build /p:Configuration=Self-contained /p:Platform=x64 /m
& "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe" AutoHotkeyx.sln /t:Build /p:Configuration=Self-contained /p:Platform=Win32 /m
```

Copy the rebuilt files back into `.tools\AutoHotkey\v2`, then run `PackRMT.ps1`.
