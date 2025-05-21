#!/usr/bin/env pwsh

# --- DTF Environment Classes ---
class DTFPythonEnvManager {
    [string]$Name
    [string]$Executable
    [string]$RootPath
    [string]$Version
    [string]$Scope
}

class DTFPythonEnv {
    [string]$Id
    [string]$Name
    [string]$PythonVersion
    [string]$EnvManager
    [string]$ExecutablePath
    [string]$PackagesPath
    [string[]]$PycachePaths
    [string]$PackagesSize
    [string]$PycacheSize
    [string]$Scope
    [datetime]$LastModified
}
function Show-SplashScreen {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║                         DTF-CLI v1.0.0                            ║" -ForegroundColor Cyan
    Write-Host "║     Delete Temp Files - Python Environment Manager (PowerShell)  ║" -ForegroundColor Cyan
    Write-Host "║     Author: YUNG Standard Utility                                ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Log-Event {
    param (
        [Parameter(Mandatory)][string]$Level,
        [Parameter(Mandatory)][string]$Namespace,
        [Parameter(Mandatory)][string]$Message
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $output = "[$timestamp] [$Level] [$Namespace] $Message"
    switch ($Level.ToUpper()) {
        "INFO"    { Write-Host $output -ForegroundColor Green }
        "WARN"    { Write-Host $output -ForegroundColor Yellow }
        "ERROR"   { Write-Host $output -ForegroundColor Red }
        "DEBUG"   { Write-Host $output -ForegroundColor Blue }
        "VERBOSE" { Write-Host $output -ForegroundColor Cyan }
        default   { Write-Host $output }
    }
}


# Global variable to hold environments cache
$global:Envs = @()

# Global variable to persist discovered environments across Discover-Envs invocations
$global:DiscoveredEnvs = @()
$global:EnvManagers = @{}

# List-EnvManagers: Show summary of environment managers
function List-EnvManagers {
    if ($global:EnvManagers.Count -eq 0) {
        Write-Host "No environment managers detected."
        return
    }
    $global:EnvManagers.Values |
        Select-Object Name, Version, Scope, RootPath, Executable |
        Format-Table -AutoSize
}

function Discover-Envs {
    <#
    Discover Python environments using various environment managers and heuristics.
    Detects conda, pyenv, pipenv, poetry, and virtualenv environments.
    Also inspects shell history for sourced environments.
    Each environment is classified by scope: user, system, or local.
    #>
    Log-Event -Level "INFO" -Namespace "Discover-Envs" -Message "Starting environment discovery..."
    $global:DiscoveredEnvs = @()
    $seenPaths = @{}

    # Helper: Deduplicate by real path
    function Add-Env-If-Valid {
        param($Path, $Type, $Name, $Scope)
        # Trace mode: show path being evaluated
        if ($global:TraceMode) {
            Log-Event -Level "DEBUG" -Namespace "Discover-Envs" -Message ("📍 Trace Mode Enabled - Path: {0}" -f $Path)
        }
        Log-Event -Level "DEBUG" -Namespace "Discover-Envs" -Message ("👁️ Evaluating candidate path: {0}" -f $Path)
        if ([string]::IsNullOrWhiteSpace($Path)) { return }
        $realPath = (Resolve-Path -Path $Path -ErrorAction SilentlyContinue | Select-Object -First 1).Path
        if (-not $realPath -and (Test-Path $Path)) {
            $realPath = (Get-Item $Path).FullName
        }
        if (-not $realPath) { $realPath = $Path }
        if ($seenPaths.ContainsKey($realPath)) {
            if ($global:TraceMode) {
                Log-Event -Level "DEBUG" -Namespace "Discover-Envs" -Message ("⛔ Excluded path '{0}' — already seen (deduplication)." -f $realPath)
            }
            return
        }
        if (-not (Test-Path $realPath)) {
            if ($global:TraceMode) {
                Log-Event -Level "DEBUG" -Namespace "Discover-Envs" -Message ("⛔ Excluded path '{0}' — path does not exist." -f $realPath)
            }
            return
        }
        # Improved detection: look for python binaries or activation scripts in common places
        $hasPython = @(
            "python", "python3", "python.exe", "bin/python", "bin/python3",
            "Scripts/python.exe", "Scripts/python", "bin/activate", "Scripts/activate"
        ) | ForEach-Object {
            Test-Path (Join-Path $realPath $_)
        } | Where-Object { $_ } | Measure-Object | Select-Object -ExpandProperty Count
        if ($hasPython -eq 0) {
            Log-Event -Level "DEBUG" -Namespace "Discover-Envs" -Message ("⛔ Excluded path '{0}' — no Python binaries or activation scripts found." -f $realPath)
            return
        }

        # Extract python version from binary
        $pythonBin = Get-ChildItem -Path $realPath -Recurse -File -Include "python", "python3", "python.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        $pyVersion = ""
        if ($pythonBin) {
            try {
                $output = & "$($pythonBin.FullName)" --version 2>&1
                if ($output -match "Python\s+([\d\.]+)") {
                    $pyVersion = $Matches[1]
                }
            } catch { }
        }

        # --- DTFPythonEnv details ---
        # Find executable
        $execPath = $pythonBin?.FullName
        # Find site-packages path (first hit only)
        $sitePackages = Get-ChildItem -Path $realPath -Recurse -Directory -Filter "site-packages" -ErrorAction SilentlyContinue | Select-Object -First 1
        $pkgPath = $sitePackages?.FullName
        $pkgSize = if ($pkgPath) {
            (Get-ChildItem -Path $pkgPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        } else { 0 }
        $pkgSizeStr = [Math]::Round($pkgSize / 1MB, 2).ToString() + " MB"

        # Find pycache folders, excluding those nested in site-packages
        $pycacheDirs = Get-ChildItem -Path $realPath -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue | Where-Object { $pkgPath -and $_.FullName -notlike "$pkgPath*" }
        $pycachePaths = $pycacheDirs.FullName
        $pycacheSize = 0
        foreach ($dir in $pycacheDirs) {
            $pycacheSize += (Get-ChildItem -Path $dir.FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        }
        $pycacheSizeStr = [Math]::Round($pycacheSize / 1MB, 2).ToString() + " MB"

        $env = [DTFPythonEnv]::new()
        $env.Id = [guid]::NewGuid().ToString()
        $env.Name = $Name
        $env.PythonVersion = $pyVersion
        $env.EnvManager = $Type
        $env.ExecutablePath = $execPath
        $env.PackagesPath = $pkgPath
        $env.PycachePaths = $pycachePaths
        $env.PackagesSize = $pkgSizeStr
        $env.PycacheSize = $pycacheSizeStr
        $env.Scope = $Scope
        $env.LastModified = (Get-Item $realPath).LastWriteTime

        $global:DiscoveredEnvs += $env
        # Add EnvManager if not present
        if (-not $global:EnvManagers.ContainsKey($Type)) {
            $manager = [DTFPythonEnvManager]::new()
            $manager.Name = $Type
            $manager.RootPath = (Split-Path $realPath -Parent)
            $manager.Executable = $pythonBin?.FullName
            $manager.Version = $pyVersion
            $manager.Scope = $Scope
            $global:EnvManagers[$Type] = $manager
        }
        $seenPaths[$realPath] = $true
    }

    # --- BEGIN: VSCode Trace/Regex Environment Discovery ---
    function Parse-Trace-Output-For-Envs {
        param(
            [Parameter(Mandatory=$true)][string[]]$TraceLines
        )
        $envRegex = [regex] '(?<!node_modules[\\/][^/]*|site-packages[\\/][^/]*|lib[\\/][^/]*)([A-Za-z]:)?([\\/][^:;,\s"''\[\]\(\)<>\\?*|]+)+([\\/](\.venv|venv|env|ENV)|[\\/](envs|virtualenvs)[\\/][^\\/]+|[\\/]\.pyenv[\\/][^\\/]+|[\\/][^\\/]+)?'
        $envCandidates = @()
        for ($i = 0; $i -lt $TraceLines.Count; $i++) {
            $line = $TraceLines[$i]
            if ($envRegex.IsMatch($line)) {
                $matches = $envRegex.Matches($line)
                foreach ($match in $matches) {
                    $envPath = $match.Value.Trim()
                    if ($envPath -match '\.venv|venv|env|virtualenvs|envs|\.pyenv') {
                        # Search 10 lines before/after for PWD or project root
                        $start = [Math]::Max(0, $i-10)
                        $end = [Math]::Min($TraceLines.Count-1, $i+10)
                        $contextLines = $TraceLines[$start..$end]
                        $pwdLine = $contextLines | Where-Object { $_ -match 'PWD|project root|workspace|cwd' } | Select-Object -First 1
                        $pwd = $null
                        if ($pwdLine) {
                            if ($pwdLine -match '(PWD|cwd|workspace|project root)[\s:=]+([^\s]+)') {
                                $pwd = $Matches[2]
                            }
                        }
                        # Backtrack to identify project directory (look for .venv, site-packages, known patterns)
                        $projectDir = $null
                        if ($envPath -match '(.*?)([\\/](\.venv|venv|env|virtualenvs|envs)[\\/][^\\/]+)?$') {
                            $projectDir = $Matches[1]
                        }
                        $candidate = [PSCustomObject]@{
                            Path = $envPath
                            Context = $contextLines
                            PWD = $pwd
                            ProjectDir = $projectDir
                            SourceLine = $line
                        }
                        $envCandidates += $candidate
                        # Verbose logging
                        Log-Event -Level "VERBOSE" -Namespace "Trace-Parse" -Message ("Matched env line: {0}" -f $line)
                        Log-Event -Level "VERBOSE" -Namespace "Trace-Parse" -Message ("Context lines: {0}" -f ($contextLines -join "`n"))
                        Log-Event -Level "VERBOSE" -Namespace "Trace-Parse" -Message ("Inferred PWD: {0}" -f $pwd)
                        Log-Event -Level "VERBOSE" -Namespace "Trace-Parse" -Message ("ProjectDir: {0}" -f $projectDir)
                        Log-Event -Level "VERBOSE" -Namespace "Trace-Parse" -Message ("Final env path: {0}" -f $envPath)
                    }
                }
            }
        }
        return $envCandidates
    }
    # Example: If VSCode trace output is available, parse it here
    $traceFile = $env:VSCODE_PYTHON_ENV_TRACE_FILE
    if ($traceFile -and (Test-Path $traceFile)) {
        $traceLines = Get-Content $traceFile -Raw -ErrorAction SilentlyContinue -Encoding UTF8 | Out-String | Select-String -Pattern '.' | ForEach-Object { $_.Line }
        $parsedEnvs = Parse-Trace-Output-For-Envs -TraceLines $traceLines
        foreach ($envObj in $parsedEnvs) {
            # Use Add-Env-If-Valid but never discard for missing validation markers (e.g., pyvenv.cfg)
            $type = "vscode-trace"
            $name = Split-Path $envObj.Path -Leaf
            $scope = if ($envObj.PWD) { "project" } else { "unverified" }
            Log-Event -Level "DEBUG" -Namespace "VSCode-Trace" -Message ("Appending env from trace: {0}" -f $envObj.Path)
            Add-Env-If-Valid -Path $envObj.Path -Type $type -Name $name -Scope $scope
        }
    }
    # --- END: VSCode Trace/Regex Environment Discovery ---

    # Helper: Classify scope by path
    function Get-Scope-From-Path {
        param($Path)
        if ($Path -like "$HOME/*" -or $Path -like "$env:USERPROFILE\*") { return "user" }
        if ($Path -like "/usr/*" -or $Path -like "C:\Python*") { return "system" }
        # Local/project: inside current dir or known dev dirs
        $cwd = (Get-Location).Path
        if ($Path -like "$cwd*" -or $Path -like "$HOME/Developer*" -or $Path -like "$HOME/tools*") { return "local" }
        return "user"
    }

    # Check for conda (Miniconda/Anaconda)
    $condaPath = (Get-Command conda -ErrorAction SilentlyContinue)?.Source
    if ($condaPath) {
        Log-Event -Level "INFO" -Namespace "Discover-Envs" -Message "Conda detected. Querying environments..."
        try {
            $condaJson = conda env list --json 2>$null | ConvertFrom-Json
            foreach ($envPath in $condaJson.envs) {
                # Only include envs under envs/ subdir, not pkgs or base
                if ($envPath -match "envs[\\/][^\\/]+$") {
                    Log-Event -Level "DEBUG" -Namespace "Discover-Envs" -Message ("👁️ Evaluating $envPath...")
                    $name = Split-Path $envPath -Leaf
                    $scope = Get-Scope-From-Path $envPath
                    Add-Env-If-Valid -Path $envPath -Type "conda" -Name $name -Scope $scope
                }
            }
        } catch { Log-Event -Level "WARN" -Namespace "Discover-Envs" -Message "Failed to parse conda environments." }
    }

    # Check for pyenv
    $pyenvCmd = (Get-Command pyenv -ErrorAction SilentlyContinue)?.Source
    if ($pyenvCmd) {
        Log-Event -Level "INFO" -Namespace "Discover-Envs" -Message "pyenv detected. Enumerating versions..."
        try {
            $pyenvRoot = pyenv root 2>$null
            $versionsDir = Join-Path $pyenvRoot "versions"
            if (Test-Path $versionsDir) {
                Get-ChildItem -Path $versionsDir -Directory | ForEach-Object {
                    $envPath = $_.FullName
                    Log-Event -Level "DEBUG" -Namespace "Discover-Envs" -Message ("👁️ Evaluating $envPath...")
                    $name = $_.Name
                    $scope = Get-Scope-From-Path $envPath
                    Add-Env-If-Valid -Path $envPath -Type "pyenv" -Name $name -Scope $scope
                }
            }
        } catch { Log-Event -Level "WARN" -Namespace "Discover-Envs" -Message "Failed to parse pyenv environments." }
    }

    # Check for pipenv
    $pipenvCmd = (Get-Command pipenv -ErrorAction SilentlyContinue)?.Source
    if ($pipenvCmd) {
        Log-Event -Level "INFO" -Namespace "Discover-Envs" -Message "pipenv detected. Searching for Pipfile files..."
        # Search for Pipfile in home and dev dirs
        $pipfileRoots = @("$HOME", "$HOME/Developer", "$HOME/tools")
        foreach ($root in $pipfileRoots) {
            if (-not (Test-Path $root)) { continue }
            Get-ChildItem -Path $root -Recurse -File -Filter "Pipfile" -ErrorAction SilentlyContinue | ForEach-Object {
                $pipfileDir = Split-Path $_.FullName -Parent
                try {
                    $venvPath = pipenv --venv 2>$null
                    if ($LASTEXITCODE -eq 0 -and $venvPath) {
                        Log-Event -Level "DEBUG" -Namespace "Discover-Envs" -Message ("👁️ Evaluating $venvPath...")
                        $scope = Get-Scope-From-Path $venvPath
                        Add-Env-If-Valid -Path $venvPath -Type "pipenv" -Name (Split-Path $venvPath -Leaf) -Scope $scope
                    }
                } catch { }
            }
        }
    }

    # Check for poetry
    $poetryCmd = (Get-Command poetry -ErrorAction SilentlyContinue)?.Source
    if ($poetryCmd) {
        Log-Event -Level "INFO" -Namespace "Discover-Envs" -Message "poetry detected. Searching for pyproject.toml files..."
        $pyprojRoots = @("$HOME", "$HOME/Developer", "$HOME/tools")
        foreach ($root in $pyprojRoots) {
            if (-not (Test-Path $root)) { continue }
            Get-ChildItem -Path $root -Recurse -File -Filter "pyproject.toml" -ErrorAction SilentlyContinue | ForEach-Object {
                $projDir = Split-Path $_.FullName -Parent
                try {
                    $venvPath = & poetry env info -p 2>$null
                    if ($LASTEXITCODE -eq 0 -and $venvPath) {
                        Log-Event -Level "DEBUG" -Namespace "Discover-Envs" -Message ("👁️ Evaluating $venvPath...")
                        $scope = Get-Scope-From-Path $venvPath
                        Add-Env-If-Valid -Path $venvPath -Type "poetry" -Name (Split-Path $venvPath -Leaf) -Scope $scope
                    }
                } catch { }
            }
        }
    }

    # Check for virtualenvs (.venv, venv, env, etc.)
    Log-Event -Level "INFO" -Namespace "Discover-Envs" -Message "Searching for virtualenv/venv directories..."
    $venvNames = @(".venv", "venv", "env", "ENV")
    $venvRoots = @("$HOME", "$HOME/Developer", "$HOME/tools")
    foreach ($root in $venvRoots) {
        if (-not (Test-Path $root)) { continue }
        foreach ($venvName in $venvNames) {
            Get-ChildItem -Path $root -Recurse -Directory -Filter $venvName -ErrorAction SilentlyContinue | ForEach-Object {
                $venvPath = $_.FullName
                Log-Event -Level "DEBUG" -Namespace "Discover-Envs" -Message ("👁️ Evaluating $venvPath...")
                $scope = Get-Scope-From-Path $venvPath
                Add-Env-If-Valid -Path $venvPath -Type "virtualenv" -Name $venvName -Scope $scope
            }
        }
    }
    # Also check for virtualenvs in .local/share/virtualenvs and poetry cache
    $extraVenvRoots = @(
        "$HOME/.local/share/virtualenvs",
        "$HOME/Library/Caches/pypoetry/virtualenvs"
    )
    foreach ($root in $extraVenvRoots) {
        if (Test-Path $root) {
            Get-ChildItem -Path $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $venvPath = $_.FullName
                Log-Event -Level "DEBUG" -Namespace "Discover-Envs" -Message ("👁️ Evaluating $venvPath...")
                $scope = Get-Scope-From-Path $venvPath
                Add-Env-If-Valid -Path $venvPath -Type "virtualenv" -Name ($_.Name) -Scope $scope
            }
        }
    }

    # Inspect shell history for source commands
    Log-Event -Level "INFO" -Namespace "Discover-Envs" -Message "Inspecting shell history for sourced environments..."
    $historyFiles = @("$HOME/.bash_history", "$HOME/.zsh_history", "$HOME/.zhistory")
    foreach ($histFile in $historyFiles) {
        if (Test-Path $histFile) {
            try {
                Get-Content $histFile -ErrorAction SilentlyContinue | Select-String -Pattern "source\s+([^\s]+/activate)" | ForEach-Object {
                    $line = $_.Line
                    if ($line -match "source\s+([^\s]+/activate)") {
                        $activatePath = $Matches[1]
                        $venvPath = Split-Path $activatePath -Parent
                        Log-Event -Level "DEBUG" -Namespace "Discover-Envs" -Message ("👁️ Evaluating $venvPath...")
                        $scope = Get-Scope-From-Path $venvPath
                        Add-Env-If-Valid -Path $venvPath -Type "history" -Name (Split-Path $venvPath -Leaf) -Scope $scope
                    }
                }
            } catch { }
        }
    }

    # Final deduplication and result
    $global:Envs = $global:DiscoveredEnvs
    Save-Envs
    Log-Event -Level "INFO" -Namespace "Discover-Envs" -Message ("Discovered {0} environments." -f $global:DiscoveredEnvs.Count)
    if ($global:DiscoveredEnvs.Count -gt 0) {
        Write-Host ""
        Write-Host ("Found {0} environments:" -f $global:DiscoveredEnvs.Count)
        foreach ($env in $global:DiscoveredEnvs) {
            $extra = ""
            if ($env.Scope -eq "project") { $extra = "(traced from project root)" }
            elseif ($env.Scope -eq "unverified") { $extra = "(unverified)" }
            elseif ($env.Scope -eq "user" -or $env.Scope -eq "system") { $extra = "(context matched)" }
            Write-Host ("- {0,-45} {1}" -f $env.Path, $extra)
        }
        Write-Host ""
    }
    return $global:DiscoveredEnvs
}

function Add-Env {
    param (
        [Parameter(Mandatory)][string]$Path
    )
    if (-not (Test-Path $Path)) {
        Log-Event -Level "ERROR" -Namespace "Add-Env" -Message "Path '$Path' does not exist."
        return
    }
    $env = [PSCustomObject]@{
        Id = [guid]::NewGuid().ToString()
        Path = (Get-Item $Path).FullName
        Name = (Get-Item $Path).Name
        LastModified = (Get-Item $Path).LastWriteTime
    }
    $global:Envs += $env
    Log-Event -Level "INFO" -Namespace "Add-Env" -Message ("Added environment '{0}'." -f $env.Path)
}

# Save-Envs caches the discovered environments to a local file for persistence
function Save-Envs {
    $baseCache = if ($env:USERPROFILE) { Join-Path $env:USERPROFILE ".cache" } else { Join-Path $env:HOME ".cache" }
    if (-not (Test-Path $baseCache)) {
        New-Item -ItemType Directory -Path $baseCache -Force | Out-Null
    }
    $cachePath = Join-Path $baseCache "python_env_registry.txt"
    $lines = @()
    foreach ($env in $global:Envs) {
        # Support missing fields for backward compatibility
        $id = $env.Id
        $type = $env.Type
        $path = $env.Path
        $sitePackages = $env.SitePackages
        $pycache = $env.Pycache
        $pyVersion = if ($env.PSObject.Properties["PythonVersion"]) { $env.PythonVersion } else { "" }
        $exec = if ($env.PSObject.Properties["ExecutablePath"]) { $env.ExecutablePath } else { "" }
        $scope = if ($env.PSObject.Properties["Scope"]) { $env.Scope } else { "" }
        $line = "$id|$type|$path|$sitePackages|$pycache|$pyVersion|$exec|$scope"
        $lines += $line
    }
    Set-Content -Path $cachePath -Value $lines
}

function Load-Envs {
    # Load from cache file if present, otherwise discover
    $baseCache = if ($env:USERPROFILE) { Join-Path $env:USERPROFILE ".cache" } else { Join-Path $env:HOME ".cache" }
    $cachePath = Join-Path $baseCache "python_env_registry.txt"
    if (Test-Path $cachePath) {
        $global:Envs = @()
        $global:EnvManagers = @{}
        $lines = Get-Content $cachePath
        foreach ($line in $lines) {
            $fields = $line -split '\|'
            $obj = [PSCustomObject]@{
                Id = $fields[0]
                Type = $fields[1]
                Path = $fields[2]
                SitePackages = if ($fields.Count -gt 3) { $fields[3] } else { $null }
                Pycache = if ($fields.Count -gt 4) { $fields[4] } else { $null }
                PythonVersion = if ($fields.Count -gt 5) { $fields[5] } else { $null }
                ExecutablePath = if ($fields.Count -gt 6) { $fields[6] } else { $null }
                Scope = if ($fields.Count -gt 7) { $fields[7] } else { $null }
            }
            $global:Envs += $obj
            # Rebuild EnvManagers from every $obj, unconditionally
            if (-not $global:EnvManagers.ContainsKey($obj.Type)) {
                $manager = [DTFPythonEnvManager]::new()
                $manager.Name = $obj.Type
                $manager.RootPath = if ($obj.Path) { Split-Path -Path $obj.Path -Parent } else { "(unknown)" }
                $manager.Executable = $obj.ExecutablePath
                $manager.Version = $obj.PythonVersion
                $manager.Scope = $obj.Scope
                $global:EnvManagers[$obj.Type] = $manager
            }
        }
        Log-Event -Level "INFO" -Namespace "Load-Envs" -Message ("Loaded {0} cached environments." -f $global:Envs.Count)
    } else {
        Log-Event -Level "WARN" -Namespace "Load-Envs" -Message "No cached environments found. Discovering..."
        Discover-Envs | Out-Null
    }
}

function List-Envs {
    param (
        [Parameter(ValueFromPipeline)][object]$EnvsToList = $null
    )
    $list = $null
    if ($null -ne $EnvsToList) {
        $list = $EnvsToList
    } elseif ($global:Envs) {
        $list = $global:Envs
    } else {
        Log-Event -Level "WARN" -Namespace "List-Envs" -Message "No environments to list."
        return
    }

    $list |
        Select-Object Id, Name, PythonVersion, PackagesSize, EnvManager, Scope, Path |
        Format-Table -AutoSize
}

function Delete-EnvById {
    param (
        [Parameter(Mandatory)][string]$Id,
        [string]$Mode = "cli",
        [switch]$DeletePackages,
        [switch]$DeleteCaches
    )
    $env = $global:Envs | Where-Object { $_.Id -eq $Id }
    if (-not $env) {
        Log-Event -Level "ERROR" -Namespace "Delete-EnvById" -Message ("Environment with ID '{0}' not found." -f $Id)
        return
    }
    try {
        Log-Event -Level "INFO" -Namespace "Delete-EnvById" -Message ("Deleting environment '{0}' at '{1}' in mode '{2}'." -f $env.Name, $env.Path, $Mode)

        if ($DeletePackages) {
            $sitePackages = Get-ChildItem -Path $env.Path -Recurse -Directory -Filter "site-packages" -ErrorAction SilentlyContinue
            foreach ($pkgDir in $sitePackages) {
                Log-Event -Level "INFO" -Namespace "Delete-EnvById" -Message ("Deleting packages: {0}" -f $pkgDir.FullName)
                Remove-Item -Recurse -Force -Path $pkgDir.FullName -ErrorAction SilentlyContinue
            }
        } elseif ($DeleteCaches) {
            $pycacheDirs = Get-ChildItem -Path $env.Path -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch "site-packages" }
            foreach ($cacheDir in $pycacheDirs) {
                Log-Event -Level "INFO" -Namespace "Delete-EnvById" -Message ("Deleting cache: {0}" -f $cacheDir.FullName)
                Remove-Item -Recurse -Force -Path $cacheDir.FullName -ErrorAction SilentlyContinue
            }
        } else {
            switch ($Mode) {
                "cli" {
                    switch ($env.Type) {
                        "conda" { conda env remove -p "$($env.Path)" -y }
                        "pyenv" { pyenv uninstall -f "$($env.Name)" }
                        "pipenv" { pipenv --rm }
                        "poetry" { Set-Location (Split-Path $env.Path -Parent); poetry env remove "$($env.Python)" }
                        default { Remove-Item -Recurse -Force -Path $env.Path -ErrorAction SilentlyContinue }
                    }
                }
                "native" {
                    Remove-Item -Recurse -Force -Path $env.Path -ErrorAction SilentlyContinue
                }
                default {
                    Remove-Item -Recurse -Force -Path $env.Path -ErrorAction SilentlyContinue
                }
            }
            $global:Envs = $global:Envs | Where-Object { $_.Id -ne $Id }
            Log-Event -Level "INFO" -Namespace "Delete-EnvById" -Message ("Successfully deleted environment '{0}'." -f $env.Name)
        }
    } catch {
        Log-Event -Level "ERROR" -Namespace "Delete-EnvById" -Message ("Failed to delete environment '{0}': {1}" -f $env.Name, $_.Exception.Message)
    }
}

#region Interactive TUI
function Show-TUI {
    do {
        $mode = "interactive"
        Clear-Host
        Show-SplashScreen
        # Updated menu section:
        Write-Host ""
        Write-Host "╔══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
        Write-Host "║    Select an action:                                                    ║" -ForegroundColor Magenta
        Write-Host "║    [1] Discover Environments                                             ║" -ForegroundColor Magenta
        Write-Host "║    [2] List Cached Environments                                          ║" -ForegroundColor Magenta
        Write-Host "║    [3] Browse by Scope/Manager                                           ║" -ForegroundColor Magenta
        Write-Host "║    [4] Delete Environment(s) by ID                                       ║" -ForegroundColor Magenta
        Write-Host "║    [5] List Detected Environment Managers                                ║" -ForegroundColor Magenta
        Write-Host "║    [6] Utilities (Detect other runtimes: Node, Ruby, Nix, etc.)         ║" -ForegroundColor Magenta
        Write-Host "║    [7] Exit                                                              ║" -ForegroundColor Magenta
        Write-Host "╚══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
        $choice = Read-Host "Enter choice"
        switch ($choice) {
            "1" {
                $discovered = Discover-Envs
                if (-not $discovered -or $discovered.Count -eq 0) {
                    Log-Event -Level "WARN" -Namespace "Show-TUI" -Message "No environments were discovered."
                    Write-Host "`n⚠️  No environments were discovered. Consider checking:"
                    Write-Host "   - Your `$HOME path and environment roots"
                    Write-Host "   - That Python environment managers (conda, pyenv, etc.) are installed and accessible"
                    Write-Host "   - That environment folders are not excluded by Spotlight or file permissions"
                }
                List-Envs
                Read-Host "Press Enter to continue..."
            }
            "2" {
                Load-Envs
                List-Envs
                Read-Host "Press Enter to continue..."
            }
            "3" {
                Load-Envs
                List-EnvManagers
                Write-Host ""
                $filter = Read-Host "Enter manager name or scope to filter (e.g., pyenv or user)"
                $filtered = $global:Envs | Where-Object {
                    $_.EnvManager -like "*$filter*" -or $_.Scope -like "*$filter*"
                }
                if (-not $filtered) {
                    Write-Host "No environments found for filter: $filter"
                } else {
                    $filtered | Select-Object Id, Name, PythonVersion, PackagesSize, PycacheSize, EnvManager, Scope | Format-Table -AutoSize
                    $totalPkg = ($filtered | Measure-Object -Property PackagesSize -Sum).Sum
                    $totalPc  = ($filtered | Measure-Object -Property PycacheSize -Sum).Sum
                    Write-Host ("Total Site-Packages Size: {0}" -f $totalPkg)
                    Write-Host ("Total __pycache__ Size: {0}" -f $totalPc)
                }
                Read-Host "Press Enter to continue..."
            }
            "4" {
                Load-Envs
                List-Envs
                Write-Host ""
                Write-Host "Delete Options:"
                Write-Host "[1] Delete entire environment"
                Write-Host "[2] Delete only site-packages"
                Write-Host "[3] Delete only __pycache__"
                $delChoice = Read-Host "Enter delete mode"
                $toDelete = Read-Host "Enter ID(s) to delete (comma separated)"
                $ids = $toDelete -split "," | ForEach-Object { $_.Trim() }
                foreach ($id in $ids) {
                    switch ($delChoice) {
                        "1" { Delete-EnvById -Id $id -Mode $mode }
                        "2" { Delete-EnvById -Id $id -Mode $mode -DeletePackages }
                        "3" { Delete-EnvById -Id $id -Mode $mode -DeleteCaches }
                        default {
                            Write-Host "Invalid delete option. Skipping $id."
                        }
                    }
                }
                Read-Host "Press Enter to continue..."
            }
            "5" {
                Load-Envs
                List-EnvManagers
                Read-Host "Press Enter to continue..."
            }
            "6" {
                Write-Host "`n🔍 Detecting other dev runtimes..."
                $tools = @("node", "npm", "npx", "ruby", "rbenv", "nix", "cargo", "go", "deno", "pnpm")
                foreach ($tool in $tools) {
                    $path = Get-Command $tool -ErrorAction SilentlyContinue
                    if ($path) {
                        Write-Host ("✅ {0,-10} : {1}" -f $tool, $path.Source)
                    } else {
                        Write-Host ("❌ {0,-10} : Not found" -f $tool)
                    }
                }
                Read-Host "Press Enter to continue..."
            }
            "7" { exit }
            default { Write-Host "Invalid choice."; Read-Host "Press Enter to continue..." }
        }
        # Bottom-sticky progress line (placeholder, not dynamic yet)
        Write-Host "`nProgress: [==========>             ] 45% (12/27)" -ForegroundColor Cyan
    } while ($true)
}
#endregion

if ($args.Length -eq 0) {
    Show-TUI
} else {
    $mode = "cli"
    $deletePackages = $false
    $deleteCaches = $false
    $global:TraceMode = $false
    foreach ($arg in $args) {
        switch ($arg) {
            "--trace" { $global:TraceMode = $true }
        }
    }
    switch ($args[0]) {
        "discover" {
            Discover-Envs | List-Envs
        }
        "list" {
            Load-Envs
            List-Envs
        }
        "delete" {
            Load-Envs
            $args = $args[1..$args.Length]
            foreach ($arg in $args) {
                switch ($arg) {
                    "--cli" { $mode = "cli" }
                    "--native" { $mode = "native" }
                    "--interactive" { $mode = "interactive" }
                    "--dry-run" { $dryRun = $true }
                    "--delete-packages" { $deletePackages = $true }
                    "--delete-caches"   { $deleteCaches = $true }
                    "--trace" { $global:TraceMode = $true }
                    default {
                        Delete-EnvById -Id $arg -Mode $mode -DeletePackages:$deletePackages -DeleteCaches:$deleteCaches
                    }
                }
            }
        }
        "managers" {
            Load-Envs
            List-EnvManagers
        }
        default {
            Write-Host "Usage:"
            Write-Host "  ./dtf-cli.ps1 discover [--trace]"
            Write-Host "  ./dtf-cli.ps1 list"
            Write-Host "  ./dtf-cli.ps1 delete <ID..> [--cli|--native|--interactive] [--dry-run] [--delete-packages] [--delete-caches] [--trace]"
            Write-Host "  ./dtf-cli.ps1 managers"
        }
    }
}
