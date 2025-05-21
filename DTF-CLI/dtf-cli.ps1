<#
.SYNOPSIS
DTF-CLI - Delete Temp Files (Python Env Pruner)
.DESCRIPTION
Discovers Python environments and allows interactive or CLI-based deletion
.AUTHOR
YUNG Standard Utility
#>

$envCacheFile = "$HOME\.cache\python_env_registry.txt"
$dryRun = $false
$mode = "interactive"

function Print-Header {
    Write-Host "`n🧰 DTF-CLI — PYTHON ENVIRONMENT MANAGER"
    Write-Host "-----------------------------"
}

function Discover-Envs {
    $script:envs = @()
    $script:id = 0
    function Add-Env($name, $path) {
        if (Test-Path $path) {
            $script:id++
            $sp = Get-ChildItem -Path $path -Recurse -Directory -Filter site-packages -ErrorAction SilentlyContinue | Select-Object -First 1
            $spSize = if ($sp) { (Get-ChildItem -Recurse -Force -Path $sp.FullName | Measure-Object -Property Length -Sum).Sum / 1MB } else { 0 }
            $pycacheSize = (Get-ChildItem -Path $path -Recurse -Directory -Filter __pycache__ -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -notmatch "site-packages" } |
                ForEach-Object { Get-ChildItem -Recurse -Force -Path $_.FullName } | Measure-Object -Property Length -Sum).Sum / 1MB
            $envs += [PSCustomObject]@{
                ID = $script:id
                Type = $name
                Path = $path
                SitePackagesMB = "{0:N1} MB" -f $spSize
                PycacheMB = "{0:N1} MB" -f $pycacheSize
            }
        }
    }

    Add-Env "system" "$env:ProgramFiles\Python"
    Add-Env "pyenv" "$HOME\.pyenv"
    Add-Env "asdf" "$HOME\.asdf\installs\python"
    Add-Env "miniconda" "$HOME\miniconda3"
    Add-Env "anaconda" "$HOME\anaconda3"
    Add-Env "pipx" "$HOME\.local\pipx"
    Add-Env "poetry" "$HOME\AppData\Local\pypoetry\Cache\virtualenvs"
    Get-ChildItem -Path $HOME -Recurse -Directory -Filter venv -ErrorAction SilentlyContinue | ForEach-Object {
        Add-Env "venv" $_.FullName
    }

    $envs | ForEach-Object { "$($_.ID)|$($_.Type)|$($_.Path)|$($_.SitePackagesMB)|$($_.PycacheMB)" } | Set-Content -Path $envCacheFile
    Write-Host "`n📦 Environment registry saved to: $envCacheFile"
    $envs
}

function Load-Envs {
    $script:envs = Get-Content $envCacheFile | ForEach-Object {
        $parts = $_ -split '\|'
        [PSCustomObject]@{
            ID = $parts[0]
            Type = $parts[1]
            Path = $parts[2]
            SitePackagesMB = $parts[3]
            PycacheMB = $parts[4]
        }
    }
}

function List-Envs {
    $envs | Format-Table -AutoSize
}

function Delete-EnvById($id, $mode) {
    $env = $envs | Where-Object { $_.ID -eq $id }
    if ($null -ne $env) {
        if ($mode -eq "interactive") {
            Write-Host "`n🧹 [$($env.ID)] Candidate for deletion:"
            Write-Host "   Type        : $($env.Type)"
            Write-Host "   Path        : $($env.Path)"
            Write-Host "   Site-Pkgs   : $($env.SitePackagesMB)"
            Write-Host "   __pycache__ : $($env.PycacheMB)"
            $confirm = Read-Host "   ❓ Delete this environment? [y/N]"
            if ($confirm -ne "y") { Write-Host "   ❌ Skipped."; return }
        }

        Write-Host "🧹 Deleting ID $($env.ID) [$($env.Type)]..."
        if ($dryRun) {
            Write-Host "   💡 Dry-run: would delete $($env.Path)"
            return
        }

        switch ($mode) {
            "cli" {
                switch ($env.Type) {
                    "pyenv"     { pyenv uninstall -f (Split-Path $env.Path -Leaf) }
                    "asdf"      { asdf uninstall python (Split-Path $env.Path -Leaf) }
                    "miniconda" { conda env remove -n (Split-Path $env.Path -Leaf) }
                    "anaconda"  { conda env remove -n (Split-Path $env.Path -Leaf) }
                    "pipx"      { pipx uninstall (Split-Path $env.Path -Leaf) }
                    default     { Remove-Item -Recurse -Force $env.Path }
                }
            }
            default {
                Remove-Item -Recurse -Force $env.Path
            }
        }

        Write-Host "✅ Deleted $($env.Path)"
    }
}

Print-Header

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
