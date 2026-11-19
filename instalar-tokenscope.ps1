param()

$ErrorActionPreference = 'Stop'
$configDir = Join-Path $HOME '.config\opencode'
$pluginDir = Join-Path $configDir 'plugins\tokenscope'
$commandFile = Join-Path $configDir 'command\tokenscope.md'
$repository = 'https://github.com/MariangelaNM/opencode-tokenscope'
$branch = 'main'
$packageName = '@mariangelanm/opencode-tokenscope'
$installedPackageNames = @($packageName, '@ramtinj95/opencode-tokenscope')

if (-not (Get-Command node.exe -ErrorAction SilentlyContinue) -or -not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
    throw 'Instala Node.js y npm antes de ejecutar este instalador.'
}
$legacyDir = Join-Path $configDir 'plugin'
$legacyPackage = Join-Path $legacyDir 'package.json'
$legacyTokenscope = $false
if (Test-Path $legacyPackage) {
    try {
        $legacyTokenscope = (Get-Content -Raw $legacyPackage | ConvertFrom-Json).name -in $installedPackageNames
    } catch { throw 'No se pudo verificar la instalacion existente en plugin.' }
}
if ($legacyTokenscope -and (Test-Path $pluginDir)) {
    throw 'Hay dos instalaciones de TokenScope; revisalas antes de continuar para evitar duplicados.'
}
$existingPluginDir = if ($legacyTokenscope) { $legacyDir } else { $pluginDir }
if (Test-Path $pluginDir) {
    $existingPackage = Join-Path $pluginDir 'package.json'
    if (-not (Test-Path $existingPackage)) { throw "No se puede identificar el plugin existente: $pluginDir" }
    try { $existingName = (Get-Content -Raw $existingPackage | ConvertFrom-Json).name }
    catch { throw "No se puede leer el plugin existente: $pluginDir" }
    if ($existingName -notin $installedPackageNames) { throw "El directorio pertenece a otro plugin: $pluginDir" }
}
$legacyCommand = $false
if (Test-Path -LiteralPath $commandFile -PathType Leaf) {
    $commandText = Get-Content -Raw -LiteralPath $commandFile
    $legacyCommand = $commandText -match '(?m)^description: Show the current session''s total token usage\r?$' -and
        $commandText -match '(?m)^Call the tokenscope tool directly without delegating to other agents\.\r?$'
}

$stage = Join-Path ([IO.Path]::GetTempPath()) ('tokenscope-installer-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $stage | Out-Null
$zip = Join-Path $stage 'tokenscope.zip'
Write-Host "Descargando TokenScope desde $repository (rama $branch)..."
Invoke-WebRequest -UseBasicParsing -Uri "$repository/archive/refs/heads/$branch.zip" -OutFile $zip
Expand-Archive -Path $zip -DestinationPath $stage
$source = Join-Path $stage "opencode-tokenscope-$branch\plugin"
$packageFile = Join-Path $source 'package.json'
if (-not (Test-Path -LiteralPath $packageFile -PathType Leaf)) {
    throw 'No se encontro el paquete de TokenScope en el ZIP del repositorio.'
}
$package = Get-Content -Raw $packageFile | ConvertFrom-Json
$serverEntry = $package.exports.'.'.import
$tuiEntry = $package.exports.'./tui'
if ($package.name -ne $packageName -or $serverEntry -ne './dist/v2/tokenscope.js' -or $tuiEntry -ne './dist/v2/tui.js') {
    throw 'El ZIP no contiene el paquete esperado de TokenScope para OpenCode V2.'
}

Write-Host 'Instalando dependencias y compilando...'
Push-Location $source
try {
    $ErrorActionPreference = 'Continue'
    & npm.cmd install --no-fund --no-audit
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) { throw 'No se pudieron instalar las dependencias.' }
    & .\node_modules\.bin\tsc.cmd
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar el plugin.' }
    if (Get-Command bun.exe -ErrorAction SilentlyContinue) {
        & bun.exe scripts/build-tui.ts
    } else {
        & npm.cmd exec --yes --package=bun@1.4.5 -- bun scripts/build-tui.ts
    }
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo compilar el panel de TokenScope.' }
} finally { Pop-Location }

foreach ($entry in @($serverEntry, $tuiEntry)) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $entry) -PathType Leaf)) {
        throw "No se genero la entrada de TokenScope para OpenCode V2: $entry"
    }
}
Write-Host 'Cerrando los procesos opencode-cli.exe y opencode.exe...'
$processes = @(Get-Process -Name 'opencode-cli', 'opencode' -ErrorAction SilentlyContinue)
if ($processes.Count -gt 0) {
    $processes | Stop-Process -Force -ErrorAction Stop
    $processes | Wait-Process -ErrorAction Stop
}
New-Item -ItemType Directory -Force -Path (Split-Path $pluginDir) | Out-Null
if (Test-Path -LiteralPath $existingPluginDir) {
    Write-Host 'Reemplazando la instalacion existente de TokenScope...'
    Move-Item -LiteralPath $existingPluginDir -Destination (Join-Path $stage 'instalacion-anterior')
}
Move-Item -Path $source -Destination $pluginDir
if ($legacyCommand) {
    Move-Item -LiteralPath $commandFile -Destination (Join-Path $stage 'comando-anterior.md')
}
Write-Host 'Instalacion terminada. Ejecuta /reload y luego /tokenscope-total para ver solo el total.'
Write-Host 'En la terminal de OpenCode, /tokenscope abre el panel.'
Write-Host "Archivos temporales y respaldo de la instalacion anterior: $stage"
