param(
    [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$script:ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$script:SensitiveValues = @()
$script:StartupTimeoutSeconds = 180

function Write-Title {
    param([string]$Text)
    Write-Host ''
    Write-Host ('=' * 62) -ForegroundColor DarkCyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host ('=' * 62) -ForegroundColor DarkCyan
}

function Protect-Text {
    param([string]$Text)

    foreach ($secret in $script:SensitiveValues) {
        if (-not [string]::IsNullOrEmpty($secret)) {
            $Text = $Text.Replace($secret, '[secreto omitido]')
        }
    }
    return $Text
}

function Invoke-Docker {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw 'No se encontro Docker CLI. Instala Docker Desktop y vuelve a intentarlo.'
    }

    Push-Location -LiteralPath $script:ProjectRoot
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(& docker @Arguments 2>&1)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
        Pop-Location
    }

    $text = ($output | ForEach-Object { "$_" }) -join [Environment]::NewLine
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        $detail = Protect-Text $text
        $command = 'docker ' + ($Arguments -join ' ')
        if ([string]::IsNullOrWhiteSpace($detail)) {
            throw "$command termino con codigo $exitCode."
        }
        throw "$command termino con codigo ${exitCode}:`n$detail"
    }
    return $text
}

function Test-DockerEngine {
    try {
        $version = Invoke-Docker -Arguments @('info', '--format', '{{.ServerVersion}}')
        return -not [string]::IsNullOrWhiteSpace($version)
    }
    catch {
        return $false
    }
}

function Wait-DockerEngine {
    while ($true) {
        Write-Host 'Verificando Docker...'
        if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
            Write-Host 'Docker CLI no esta instalado o no esta disponible en PATH.' -ForegroundColor Yellow
            Write-Host 'Instala Docker Desktop para Windows, abrelo y vuelve a intentarlo.'
        }
        elseif (Test-DockerEngine) {
            try {
                Invoke-Docker -Arguments @('compose', 'version') | Out-Null
                return $true
            }
            catch {
                Write-Host 'Docker funciona, pero Docker Compose no esta disponible.' -ForegroundColor Yellow
                Write-Host 'Actualiza o repara Docker Desktop y vuelve a intentarlo.'
            }
        }
        else {
            Write-Host 'Docker esta instalado, pero el motor no responde.' -ForegroundColor Yellow
            Write-Host 'Abre Docker Desktop, espera a que indique que esta funcionando y reintenta.'
        }

        $answer = Read-Host '¿Reintentar la comprobacion? (S/N)'
        if ($answer -notmatch '^(s|si)$') {
            return $false
        }
    }
}

function ConvertFrom-SecureStringToPlainText {
    param([Security.SecureString]$Value)

    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

function Read-NewPassword {
    param([string]$Label)

    while ($true) {
        $firstSecure = Read-Host "$Label (minimo 20 caracteres; letras, numeros y . _ ! @ % + -)" -AsSecureString
        $secondSecure = Read-Host 'Repite la contrasena' -AsSecureString
        $first = ConvertFrom-SecureStringToPlainText $firstSecure
        $second = ConvertFrom-SecureStringToPlainText $secondSecure

        if ($first -cne $second) {
            Write-Host 'Las contrasenas no coinciden. Intentalo de nuevo.' -ForegroundColor Yellow
            continue
        }
        if ($first.Length -lt 20 -or $first -notmatch '^[A-Za-z0-9._!@%+-]+$') {
            Write-Host 'La contrasena no cumple el minimo o contiene caracteres que Compose interpreta.' -ForegroundColor Yellow
            continue
        }
        return $first
    }
}

function New-EnvironmentFile {
    $examplePath = Join-Path $script:ProjectRoot '.env.example'
    $environmentPath = Join-Path $script:ProjectRoot '.env'
    if (-not (Test-Path -LiteralPath $examplePath -PathType Leaf)) {
        Write-Host 'Falta .env.example; no se puede preparar la configuracion.' -ForegroundColor Red
        return $false
    }

    Write-Host 'No existe .env. Se creara sin modificar .env.example.'
    Write-Host 'Las contrasenas se solicitan ocultas y no se muestran en pantalla.'
    $databasePassword = Read-NewPassword 'Contrasena de la API (DB_PASSWORD)'
    $administratorPassword = Read-NewPassword 'Contrasena de PostgreSQL (POSTGRES_PASSWORD)'
    if ($databasePassword -ceq $administratorPassword) {
        Write-Host 'Usa dos contrasenas distintas. No se creo .env; volve a iniciar para reintentar.' -ForegroundColor Red
        return $false
    }

    $content = [IO.File]::ReadAllText($examplePath)
    foreach ($entry in @(
        @{ Key = 'DB_PASSWORD'; Value = $databasePassword },
        @{ Key = 'POSTGRES_PASSWORD'; Value = $administratorPassword }
    )) {
        $pattern = '(?m)^' + [regex]::Escape($entry.Key) + '=.*$'
        $matches = [regex]::Matches($content, $pattern)
        if ($matches.Count -ne 1) {
            Write-Host ".env.example debe contener una sola linea $($entry.Key)=..." -ForegroundColor Red
            return $false
        }
        $content = [regex]::Replace(
            $content,
            $pattern,
            [System.Text.RegularExpressions.MatchEvaluator]{
                param($match)
                $entry.Key + '=' + $entry.Value
            }.GetNewClosure()
        )
    }

    try {
        $encoding = New-Object System.Text.UTF8Encoding($false)
        $bytes = $encoding.GetBytes($content)
        $stream = [IO.File]::Open(
            $environmentPath,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None
        )
        try {
            $stream.Write($bytes, 0, $bytes.Length)
        }
        finally {
            $stream.Dispose()
        }
    }
    catch {
        Write-Host 'No se pudo crear .env; no se sobrescribio ningun archivo existente.' -ForegroundColor Red
        return $false
    }

    Write-Host '.env creado. No compartas ese archivo ni lo agregues al repositorio.' -ForegroundColor Green
    return $true
}

function Get-EnvironmentValues {
    param([string]$Path)

    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$') {
            $value = $Matches[2]
            if ($value.Length -ge 2 -and
                (($value.StartsWith('"') -and $value.EndsWith('"')) -or
                 ($value.StartsWith("'") -and $value.EndsWith("'")))) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $values[$Matches[1]] = $value
        }
    }
    return $values
}

function Test-Environment {
    $environmentPath = Join-Path $script:ProjectRoot '.env'
    $examplePath = Join-Path $script:ProjectRoot '.env.example'

    if (-not (Test-Path -LiteralPath $environmentPath -PathType Leaf)) {
        if (-not (New-EnvironmentFile)) {
            return $false
        }
    }

    try {
        $values = Get-EnvironmentValues $environmentPath
        $exampleValues = Get-EnvironmentValues $examplePath
    }
    catch {
        Write-Host "No se pudo leer .env: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }

    foreach ($key in @('DB_NAME', 'DB_USER', 'DB_PASSWORD', 'POSTGRES_PASSWORD')) {
        if (-not $values.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($values[$key])) {
            Write-Host "Falta $key en .env. Configuralo manualmente; el archivo existente no se modificara." -ForegroundColor Red
            return $false
        }
    }

    foreach ($key in @('DB_PASSWORD', 'POSTGRES_PASSWORD')) {
        $value = $values[$key]
        $isExample = $exampleValues.ContainsKey($key) -and $value -ceq $exampleValues[$key]
        $isPlaceholder = $value -match '(?i)^(reemplazar|change.?me|changeme|example|your[_ -]?password)'
        if ($isExample -or $isPlaceholder) {
            Write-Host "$key todavia contiene una credencial de ejemplo." -ForegroundColor Red
            Write-Host 'Edita .env con una contrasena propia y segura; no se modificara automaticamente.'
            return $false
        }
    }

    if ($values['DB_PASSWORD'] -ceq $values['POSTGRES_PASSWORD']) {
        Write-Host 'DB_PASSWORD y POSTGRES_PASSWORD deben ser distintas.' -ForegroundColor Red
        return $false
    }
    if ($values['DB_NAME'] -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        Write-Host 'DB_NAME debe ser un identificador PostgreSQL formado por letras, numeros y guion bajo.' -ForegroundColor Red
        return $false
    }

    $script:SensitiveValues = @($values['DB_PASSWORD'], $values['POSTGRES_PASSWORD'])
    return $true
}

function Test-ComposeFile {
    $composePath = Join-Path $script:ProjectRoot 'docker-compose.yml'
    if (-not (Test-Path -LiteralPath $composePath -PathType Leaf)) {
        Write-Host 'No se encontro docker-compose.yml en la raiz del proyecto.' -ForegroundColor Red
        return $false
    }
    return $true
}

function Test-ProjectFiles {
    if (-not (Test-Environment)) {
        return $false
    }

    Write-Host 'Comprobando la configuracion...'
    try {
        Invoke-Docker -Arguments @('compose', 'config', '--quiet') | Out-Null
        return $true
    }
    catch {
        Write-Host 'La configuracion de Docker Compose no es valida. Revisa .env y docker-compose.yml.' -ForegroundColor Red
        Write-Host (Protect-Text $_.Exception.Message)
        return $false
    }
}

function Prepare-Project {
    if (-not (Test-ComposeFile)) {
        return $false
    }
    if (-not (Wait-DockerEngine)) {
        return $false
    }
    return (Test-ProjectFiles)
}

function Get-ServiceStatus {
    $servicesText = Invoke-Docker -Arguments @('compose', 'config', '--services')
    $services = @($servicesText -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $results = @()

    foreach ($service in $services) {
        $containerText = Invoke-Docker -Arguments @('compose', 'ps', '-q', $service)
        $containers = @($containerText -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($containers.Count -eq 0) {
            $results += [pscustomobject]@{ Service = $service; Ready = $false; State = 'no iniciado' }
            continue
        }

        $serviceReady = $true
        $states = @()
        foreach ($container in $containers) {
            $inspection = Invoke-Docker -Arguments @(
                'inspect', '--format',
                '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}sin_healthcheck{{end}}',
                $container
            )
            $parts = $inspection.Trim() -split '\|', 2
            $running = $parts.Count -eq 2 -and $parts[0] -eq 'running'
            $healthy = $parts.Count -eq 2 -and ($parts[1] -eq 'healthy' -or $parts[1] -eq 'sin_healthcheck')
            if (-not ($running -and $healthy)) {
                $serviceReady = $false
            }
            $states += $inspection.Trim()
        }

        $results += [pscustomobject]@{
            Service = $service
            Ready = $serviceReady
            State = $states -join ', '
        }
    }

    return [pscustomobject]@{
        Services = $results
        Ready = $results.Count -gt 0 -and @($results | Where-Object { -not $_.Ready }).Count -eq 0
    }
}

function Test-Frontend {
    foreach ($uri in @('http://127.0.0.1:8081/', 'http://127.0.0.1:8081/api/salud')) {
        try {
            $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 4
            if ($response.StatusCode -ne 200) {
                return $false
            }
        }
        catch {
            return $false
        }
    }
    return $true
}

function Write-ServiceStatus {
    param($Status)

    foreach ($service in $Status.Services) {
        $label = switch ($service.Service) {
            'db' { 'PostgreSQL' }
            'api' { 'API' }
            'frontend' { 'Interfaz web' }
            default { $service.Service }
        }
        $color = if ($service.Ready) { 'Green' } else { 'Yellow' }
        Write-Host ("{0}: {1} ({2})" -f $label, $service.State, $(if ($service.Ready) { 'listo' } else { 'pendiente' })) -ForegroundColor $color
    }
}

function Wait-ForApplication {
    param([int]$TimeoutSeconds = $script:StartupTimeoutSeconds)

    $timer = [Diagnostics.Stopwatch]::StartNew()
    $lastState = ''
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $status = Get-ServiceStatus
        $stateText = ($status.Services | ForEach-Object { $_.Service + ':' + $_.State }) -join '; '
        if ($stateText -ne $lastState) {
            Write-ServiceStatus $status
            $lastState = $stateText
        }
        if ($status.Ready -and (Test-Frontend)) {
            return $true
        }
        Start-Sleep -Seconds 5
    }
    return $false
}

function Write-StartupDiagnostics {
    Write-Host 'No se alcanzo el estado listo dentro del tiempo esperado. Estado de Compose:'
    try {
        Invoke-Docker -Arguments @('compose', 'ps') | Write-Host
        foreach ($service in @('db', 'api', 'frontend')) {
            Write-Host ("`nUltimos registros de " + $service + ':')
            Invoke-Docker -Arguments @('compose', 'logs', '--tail', '30', $service) -AllowFailure | Write-Host
        }
    }
    catch {
        Write-Host (Protect-Text $_.Exception.Message) -ForegroundColor Yellow
    }
    Write-Host 'Revisa que los puertos 8000 y 8081 esten libres y que Docker Desktop tenga recursos disponibles.'
}

function Start-Project {
    Write-Title 'Iniciar Bodegas del Atuel'
    if (-not (Prepare-Project)) {
        return
    }

    try {
        $status = Get-ServiceStatus
        if ($status.Ready) {
            Write-Host 'Los servicios ya estan en ejecucion; no se recrearan ni reiniciaran.'
        }
        else {
            Write-Host 'Iniciando PostgreSQL...'
            Write-Host 'Iniciando la API...'
            Write-Host 'Iniciando la interfaz web...'
            Write-Host 'Construyendo y levantando los servicios...'
            Invoke-Docker -Arguments @('compose', 'up', '-d', '--build') | Write-Host
        }

        Write-Host 'Esperando a que PostgreSQL, la API y la interfaz web esten disponibles...'
        if (-not (Wait-ForApplication)) {
            Write-StartupDiagnostics
            return
        }

        Write-Host ''
        Write-Host 'Sistema iniciado correctamente.' -ForegroundColor Green
        Write-Host 'Abriendo Bodegas del Atuel...'
        Start-Process 'http://127.0.0.1:8081'
    }
    catch {
        Write-Host 'No se pudo iniciar el sistema.' -ForegroundColor Red
        Write-Host (Protect-Text $_.Exception.Message)
        Write-Host 'Comprueba Docker Desktop, la configuracion .env y que los puertos requeridos esten libres.'
    }
}

function Stop-Project {
    Write-Title 'Detener Bodegas del Atuel'
    if (-not (Prepare-Project)) {
        return
    }
    try {
        Invoke-Docker -Arguments @('compose', 'down') | Write-Host
        Write-Host 'Sistema detenido. Los volumenes y los datos de PostgreSQL se conservaron.' -ForegroundColor Green
    }
    catch {
        Write-Host 'No se pudo detener el sistema.' -ForegroundColor Red
        Write-Host (Protect-Text $_.Exception.Message)
    }
}

function Restart-Project {
    Write-Title 'Reiniciar Bodegas del Atuel'
    if (-not (Prepare-Project)) {
        return
    }
    try {
        $status = Get-ServiceStatus
        if (-not $status.Ready) {
            Write-Host 'Hay servicios detenidos o no saludables; se iniciaran sin eliminar volumenes.'
            Start-Project
            return
        }
        Invoke-Docker -Arguments @('compose', 'restart') | Write-Host
        Write-Host 'Esperando a que los servicios vuelvan a estar disponibles...'
        if (Wait-ForApplication) {
            Write-Host 'Sistema reiniciado correctamente.' -ForegroundColor Green
        }
        else {
            Write-StartupDiagnostics
        }
    }
    catch {
        Write-Host 'No se pudo reiniciar el sistema.' -ForegroundColor Red
        Write-Host (Protect-Text $_.Exception.Message)
        Write-Host 'Si el proyecto estaba detenido, elige la opcion Iniciar el sistema.'
    }
}

function Show-ProjectStatus {
    Write-Title 'Estado de los servicios'
    if (-not (Prepare-Project)) {
        return
    }
    try {
        $status = Get-ServiceStatus
        Write-ServiceStatus $status
        if ($status.Ready -and (Test-Frontend)) {
            Write-Host 'Aplicacion disponible en http://127.0.0.1:8081' -ForegroundColor Green
        }
        elseif ($status.Ready) {
            Write-Host 'Los contenedores estan activos, pero la interfaz no responde en el puerto 8081.' -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host 'No se pudo consultar el estado.' -ForegroundColor Red
        Write-Host (Protect-Text $_.Exception.Message)
    }
}

function Open-Frontend {
    Start-Process 'http://127.0.0.1:8081'
}

function Open-ApiDocs {
    Start-Process 'http://127.0.0.1:8081/docs'
}

function Show-DockerLogs {
    Write-Title 'Registros de Docker'
    if (-not (Prepare-Project)) {
        return
    }
    $service = Read-Host 'Servicio (db, api, frontend o todos)'
    if ($service -notin @('db', 'api', 'frontend', 'todos')) {
        Write-Host 'Servicio no reconocido.' -ForegroundColor Yellow
        return
    }
    $arguments = @('compose', 'logs', '--tail', '100')
    if ($service -ne 'todos') {
        $arguments += $service
    }
    try {
        Invoke-Docker -Arguments $arguments | Write-Host
    }
    catch {
        Write-Host 'No se pudieron consultar los registros.' -ForegroundColor Red
        Write-Host (Protect-Text $_.Exception.Message)
    }
}

function Show-DatabaseCounts {
    Write-Title 'Conteos de PostgreSQL'
    if (-not (Prepare-Project)) {
        return
    }
    $database = (Get-EnvironmentValues (Join-Path $script:ProjectRoot '.env'))['DB_NAME']
    $query = @'
DO $$
DECLARE
    registro record;
    cantidad bigint;
BEGIN
    FOR registro IN
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'bodegas_atuel'
        ORDER BY tablename
    LOOP
        EXECUTE format('SELECT count(*) FROM bodegas_atuel.%I', registro.tablename)
            INTO cantidad;
        RAISE NOTICE '%: % filas', registro.tablename, cantidad;
    END LOOP;
END
$$;
'@
    try {
        Write-Host "Conteos exactos de la base $database (consulta de solo lectura):"
        Invoke-Docker -Arguments @(
            'compose', 'exec', '-T', 'db', 'psql', '-X', '-U', 'postgres',
            '-d', $database, '-c', $query
        ) | Write-Host
    }
    catch {
        Write-Host 'No se pudieron consultar los conteos. Comprueba que PostgreSQL este iniciado.' -ForegroundColor Red
        Write-Host (Protect-Text $_.Exception.Message)
    }
}

function Show-Menu {
    Write-Host ''
    Write-Host '1. Iniciar el sistema'
    Write-Host '2. Detener el sistema'
    Write-Host '3. Reiniciar el sistema'
    Write-Host '4. Verificar estado de los servicios'
    Write-Host '5. Abrir la interfaz web'
    Write-Host '6. Abrir la documentacion de FastAPI'
    Write-Host '7. Consultar los registros de Docker'
    Write-Host '8. Consultar los conteos de PostgreSQL'
    Write-Host '9. Salir'
    return (Read-Host 'Elige una opcion')
}

if ($MyInvocation.InvocationName -ne '.') {
    Start-Project
    while ($true) {
        $choice = Show-Menu
        switch ($choice) {
            '1' { Start-Project }
            '2' { Stop-Project }
            '3' { Restart-Project }
            '4' { Show-ProjectStatus }
            '5' { Open-Frontend }
            '6' { Open-ApiDocs }
            '7' { Show-DockerLogs }
            '8' { Show-DatabaseCounts }
            '9' { break }
            default { Write-Host 'Opcion no valida. Elige un numero del 1 al 9.' -ForegroundColor Yellow }
        }
        if ($choice -eq '9') {
            break
        }
    }
}
