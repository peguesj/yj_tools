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

function Discover-Envs {
    Log-Event -Level "INFO" -Namespace "Discover-Envs" -Message "Scanning environment roots..."
    $global:EnvCount = 0
    $global:EnvInfo = @()

    function Scan-Env {
        param($Name, $Path)
        if (Test-Path $Path -PathType Container) {
            $global:EnvCount++
            $spPath = Get-ChildItem -Path $Path -Recurse -Directory -Filter 'site-packages' -ErrorAction SilentlyContinue | Select-Object -First 1
            $spSize = if ($spPath) { (Get-ChildItem $spPath.FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum } else { 0 }
            $pcPaths = Get-ChildItem -Path $Path -Recurse -Directory -Filter '__pycache__' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notlike '*site-packages*' }
            $pcSize = 0
            foreach ($pc in $pcPaths) {
                $pcSize += (Get-ChildItem $pc.FullName -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            }
            $spSizeStr = if ($spSize) { [Math]::Round($spSize / 1MB, 2).ToString() + "MB" } else { "0B" }
            $pcSizeStr = if ($pcSize) { [Math]::Round($pcSize / 1MB, 2).ToString() + "MB" } else { "0B" }
            $global:EnvInfo += [PSCustomObject]@{
                ID = $global:EnvCount
                Type = $Name
                Path = $Path
                SitePackages = $spSizeStr
                Pycache = $pcSizeStr
            }
        }
    }

    Scan-Env "system" "C:\Python"
    Scan-Env "pyenv" "$env:USERPROFILE\.pyenv"
    Scan-Env "asdf" "$env:USERPROFILE\.asdf\installs\python"
    Scan-Env "miniconda" "$env:USERPROFILE\miniconda3"
    Scan-Env "anaconda" "$env:USERPROFILE\anaconda3"
    Scan-Env "pipx" "$env:USERPROFILE\.local\pipx"
    Scan-Env "poetry" "$env:USERPROFILE\AppData\Local\pypoetry\virtualenvs"

    Get-ChildItem -Path $env:USERPROFILE -Recurse -Directory -Filter "bin" -ErrorAction SilentlyContinue | Where-Object { $_.FullName -like "*\venv\bin" } | ForEach-Object {
        Scan-Env "venv" ($_.Parent.FullName)
    }

    Get-ChildItem -Path $env:USERPROFILE -Recurse -Directory -Filter "site-packages" -ErrorAction SilentlyContinue | ForEach-Object {
        $root = Split-Path -Path $_.FullName -Parent | Split-Path -Parent
        if ((Test-Path "$root\Scripts\activate") -or (Test-Path "$root\bin\activate")) {
            Scan-Env "venv" $root
        }
    }
}

function Add-Env {
    param($EnvObject)
    $global:EnvInfo += $EnvObject
}

function Load-Envs {
    $cachePath = "$env:USERPROFILE\.cache\python_env_registry.txt"
    if (Test-Path $cachePath) {
        $global:EnvInfo = @()
        $lines = Get-Content $cachePath
        foreach ($line in $lines) {
            $fields = $line -split '\|'
            $obj = [PSCustomObject]@{
                ID = $fields[0]
                Type = $fields[1]
                Path = $fields[2]
                SitePackages = $fields[3]
                Pycache = $fields[4]
            }
            $global:EnvInfo += $obj
        }
    } else {
        $global:EnvInfo = @()
    }
}

function List-Envs {
    Write-Host ""
    Write-Host ("{0,-4} | {1,-10} | {2,-40} | {3,-10} | {4,-10}" -f "ID", "Type", "Path", "Site-Pkgs", "Pycache")
    Write-Host ("-" * 90)
    foreach ($env in $global:EnvInfo) {
        Write-Host ("{0,-4} | {1,-10} | {2,-40} | {3,-10} | {4,-10}" -f $env.ID, $env.Type, $env.Path, $env.SitePackages, $env.Pycache)
    }
}

function Delete-EnvById {
    param($Id, $Mode)
    foreach ($env in $global:EnvInfo) {
        if ($env.ID -eq $Id) {
            Log-Event -Level "INFO" -Namespace "Delete-EnvById" -Message "Deleting $($env.Path) using $Mode mode"
            if ($Mode -eq "interactive") {
                Write-Host ""
                Write-Host "🧹 [$($env.ID)] Candidate for deletion:"
                Write-Host "   Type        : $($env.Type)"
                Write-Host "   Path        : $($env.Path)"
                Write-Host "   Site-Pkgs   : $($env.SitePackages)"
                Write-Host "   __pycache__ : $($env.Pycache)"
                $confirm = Read-Host "   ❓ Delete this environment? [y/N]"
                if ($confirm -ne "y" -and $confirm -ne "Y") {
                    Write-Host "   ❌ Skipped."
                    return
                }
            }
            Write-Host "🧹 Deleting ID $Id [$($env.Type)]..."
            if ($global:DryRun) {
                Write-Host "   💡 Dry-run: would delete $($env.Path)"
                return
            }
            switch ($Mode) {
                "native" { Remove-Item -Path $env.Path -Recurse -Force -ErrorAction SilentlyContinue }
                "interactive" { Remove-Item -Path $env.Path -Recurse -Force -ErrorAction SilentlyContinue }
                "cli" {
                    switch ($env.Type) {
                        "pyenv" { pyenv uninstall -f (Split-Path $env.Path -Leaf) }
                        "asdf" { asdf uninstall python (Split-Path $env.Path -Leaf) }
                        "miniconda" { conda env remove -n (Split-Path $env.Path -Leaf) }
                        "anaconda" { conda env remove -n (Split-Path $env.Path -Leaf) }
                        "pipx" { pipx uninstall (Split-Path $env.Path -Leaf) }
                        default { Remove-Item -Path $env.Path -Recurse -Force -ErrorAction SilentlyContinue }
                    }
                }
            }
            Write-Host "✅ Deleted $($env.Path)"
        }
    }
}

function Show-TUI {
    # Existing TUI implementation here
}

if ($args.Length -eq 0) {
    Show-TUI
} else {
    $mode = "interactive"
    $dryRun = $false
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
                    "--dry-run" { $dryRun = $true; $global:DryRun = $true }
                    default { Delete-EnvById $arg $mode }
                }
            }
        }
        default {
            Write-Host "Usage:"
            Write-Host "  ./dtf-cli.ps1 discover"
            Write-Host "  ./dtf-cli.ps1 list"
            Write-Host "  ./dtf-cli.ps1 delete <ID..> [--cli|--native|--interactive] [--dry-run]"
        }
    }
}
