[CmdletBinding()]
param(
    [string]$BlenderPath,
    [string]$PythonPath,
    [string]$PymeshioPath,
    [ValidatePattern('^[A-Za-z0-9_-]+$')]
    [string]$WorkspaceName = 'RuoMengTuMMD-Rebuild',
    [switch]$SkipPmx
)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$testRoot = [IO.Path]::GetFullPath((Join-Path $repo 'Test'))
$workspace = [IO.Path]::GetFullPath((Join-Path $testRoot $WorkspaceName))
if (-not $workspace.StartsWith($testRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Authoring output must remain in the repository Test directory.'
}
if ($PythonPath -and $BlenderPath) { throw 'Choose BlenderPath or PythonPath, not both.' }
if (-not $PythonPath -and -not $BlenderPath) {
    $BlenderPath = (Get-Command blender -ErrorAction Stop).Source
}
New-Item -ItemType Directory -Path (Join-Path $workspace 'logs') -Force | Out-Null
$previousWorkspace = $env:RMT_MODEL_WORKSPACE
$previousLibrary = $env:RMT_MODEL_PYMESHIO
try {
    $env:RMT_MODEL_WORKSPACE = $workspace
    if ($PymeshioPath) { $env:RMT_MODEL_PYMESHIO = [IO.Path]::GetFullPath($PymeshioPath) }
    $steps = @('prepare_source.py', 'model_geometry.py', 'gaze_morphs.py', 'bind_model.py', 'flat_materials.py')
    if (-not $SkipPmx) { $steps += 'export_pmx.py' }
    foreach ($step in $steps) {
        $script = Join-Path $PSScriptRoot $step
        $log = Join-Path $workspace ('logs/' + $step + '.log')
        Write-Host "Authoring: $step"
        if ($PythonPath) {
            & $PythonPath -B $script *> $log
        } else {
            & $BlenderPath --background --python-exit-code 1 --python $script *> $log
        }
        if ($LASTEXITCODE -ne 0) {
            Get-Content -LiteralPath $log -Tail 25
            throw "$step failed. See $log"
        }
    }
    Write-Host "Models written to: $(Join-Path $workspace 'output/route-a/rigged')"
} finally {
    $env:RMT_MODEL_WORKSPACE = $previousWorkspace
    $env:RMT_MODEL_PYMESHIO = $previousLibrary
}
