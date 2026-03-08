# =============================
# LOADING CONFIGURATION
# =============================

function Load-Config { 
    param(
        [string]$ConfigPath = ".\APAVS_Config.json" <# Location of tool information #>
    )

    if (-not (Test-Path $ConfigPath)) { <# if config file not found#>
        Write-Error "Config file not found at: $ConfigPath"
        return $null
    }

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json <# Parsing info into object for PowerShell #>
    Write-Host "Config loaded: $($config.tools.Count) tools" -ForegroundColor Green
    return $config
}