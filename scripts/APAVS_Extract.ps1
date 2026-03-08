#Requires -Version 5.1
<#
.SYNOPSIS
    APAVS - Automated Pipeline and Visualisation System
    Data extraction pipeline for CSB tool load port qualification data.

.DESCRIPTION
    Connects to CSB tools via network shares, retrieves FI log files,
    parses mapping and robot config data, calculates offsets, and
    inserts results into SQL Server for Power BI visualisation.

.NOTES
    Author:  Vincent Byrne (20108898)
    Project: HDip Computer Science Capstone - SETU
    Version: 1.0
#>

# ============================================================
# 1. LOAD CONFIGURATION
# ============================================================

function Load-Config { 
    param(
        [string]$ConfigPath = ".\APAVS_Config.json"  <# Location of tool information #>
    )

    if (-not (Test-Path $ConfigPath)) { <# if config file not found#>

        Write-Error "Config file not found at: $ConfigPath" {         return $null
    }

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json <# Parsing info into object for PowerShell #>
    Write-Host "Config loaded: $($config.tools.Count) tools" -ForegroundColor Green
    return $config
}

# ============================================================
# 2. TOOL CONNECTION
# ============================================================

function Test-ToolConnection {
    param(
        [string]$ToolID,
        [string]$IPAddress
    )

    Write-Host "  Pinging $ToolID ($IPAddress)..." -NoNewline
    $ping = Test-Connection -ComputerName $IPAddress -Count 1 -Quiet -ErrorAction SilentlyContinue

    if ($ping) {
        Write-Host " Reachable" -ForegroundColor Green
        return $true
    }
    else {
        Write-Host " Unreachable" -ForegroundColor Red
        return $false
    }
}

function Connect-Tool {
    param(
        [string]$ToolID,
        [string]$IPAddress,
        [System.Management.Automation.PSCredential]$Credential
    )

    Write-Host "  Connecting to $ToolID..." -NoNewline

    try {
        # Disconnect any existing session first
        net use "\\$IPAddress" /delete /y 2>$null | Out-Null

        $username = $Credential.UserName
        $password = $Credential.GetNetworkCredential().Password
        $result = net use "\\$IPAddress" $password /USER:$username 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host " Connected" -ForegroundColor Green
            return $true
        }
        else {
            Write-Host " Failed: $result" -ForegroundColor Red
            return $false
        }
    }
    catch {
        Write-Host " Error: $_" -ForegroundColor Red
        return $false
    }
}

function Disconnect-Tool {
    param(
        [string]$IPAddress
    )
    net use "\\$IPAddress" /delete /y 2>$null | Out-Null
}

# ============================================================
# 3. FILE RETRIEVAL
# ============================================================

function Get-ToolFiles {
    <#
    .SYNOPSIS
        Finds the most recent FI logs zip and robot config on the tool,
        copies them to a local staging folder.
        Returns the staging path or $null on failure.
    #>
    param(
        [string]$ToolID,
        [string]$IPAddress,
        [string]$StagingRoot
    )

    $toolStaging = Join-Path $StagingRoot $ToolID
    if (-not (Test-Path $toolStaging)) {
        New-Item -ItemType Directory -Path $toolStaging -Force | Out-Null
    }

    # -- Find most recent zip --
    # Check both possible paths (legacy and CGA software)
    $zipSearchPaths = @(
        "\\$IPAddress\d$\export\cgafi",
        "\\$IPAddress\c$\ficlogs"
    )

    $mostRecentZip = $null
    foreach ($path in $zipSearchPaths) {
        if (Test-Path $path) {
            $zips = Get-ChildItem -Path $path -Filter "*.zip" -ErrorAction SilentlyContinue
            foreach ($zip in $zips) {
                if ($null -eq $mostRecentZip -or $zip.LastWriteTime -gt $mostRecentZip.LastWriteTime) {
                    $mostRecentZip = $zip
                }
            }
        }
    }

    if ($null -eq $mostRecentZip) {
        Write-Host "  No FI log zip files found on $ToolID" -ForegroundColor Red
        return $null
    }

    $zipAge = (New-TimeSpan -Start $mostRecentZip.LastWriteTime -End (Get-Date)).Days
    Write-Host "  Found zip: $($mostRecentZip.Name) ($zipAge days old)" -ForegroundColor Cyan

    # Copy zip locally
    Copy-Item $mostRecentZip.FullName -Destination $toolStaging -Force

    # -- Find robot config --
    # Check multiple known locations
    $robotConfigPaths = @(
        "\\$IPAddress\c$\RobotConfigs1.txt",
        "\\$IPAddress\c$\robot 1 config.txt",
        "\\$IPAddress\c$\ficlogs\RobotConfigs1.txt",
        "\\$IPAddress\c$\ficlogs\robot 1 config.txt"
    )

    $configFound = $false
    foreach ($path in $robotConfigPaths) {
        if (Test-Path $path) {
            Copy-Item $path -Destination (Join-Path $toolStaging "robot_config.txt") -Force
            Write-Host "  Robot config copied from: $(Split-Path $path -Leaf)" -ForegroundColor Cyan
            $configFound = $true
            break
        }
    }

    if (-not $configFound) {
        Write-Host "  Robot config not found on $ToolID" -ForegroundColor Yellow
    }

    # Return staging info
    return @{
        ToolID      = $ToolID
        StagingPath = $toolStaging
        ZipFile     = Join-Path $toolStaging $mostRecentZip.Name
        ZipAge      = $zipAge
        ConfigFound = $configFound
    }
}

# ============================================================
# 4. ZIP EXTRACTION
# ============================================================

function Expand-ToolArchive {
    <#
    .SYNOPSIS
        Extracts the FI logs zip and locates the PodData and config files.
        Handles both legacy (ficlogs.tmp subfolder) and CGA (flat) structures.
    #>
    param(
        [hashtable]$ToolFiles
    )

    $extractPath = Join-Path $ToolFiles.StagingPath "extracted"
    Expand-Archive -Path $ToolFiles.ZipFile -DestinationPath $extractPath -Force

    # Determine if legacy (ficlogs.tmp subfolder) or CGA (flat)
    $ficlogsTmp = Join-Path $extractPath "ficlogs.tmp"
    if (Test-Path $ficlogsTmp) {
        $dataPath = $ficlogsTmp
        Write-Host "  Zip format: Legacy (ficlogs.tmp)" -ForegroundColor Cyan
    }
    else {
        $dataPath = $extractPath
        Write-Host "  Zip format: CGA (flat)" -ForegroundColor Cyan
    }

    $ToolFiles.DataPath = $dataPath
    return $ToolFiles
}

# ============================================================
# 5. PARSE PODDATA FILES
# ============================================================

function Parse-PodData {
    <#
    .SYNOPSIS
        Parses PodData1.txt / PodData2.txt / PodData3.txt to extract
        Z-position measurements. Combines MAP-POSA (slots 1-12) and
        MAP-POSB (slots 13-25) into single rows.
    .OUTPUTS
        Array of objects with: Timestamp, Port, SlotValues (array of 25 doubles)
    #>
    param(
        [string]$DataPath,
        [int]$PortCount,
        [int]$DaysBack = 60
    )

    $cutoffDate = (Get-Date).AddDays(-$DaysBack)
    $allRuns = @()

    # Port mapping: PodData1=P1, PodData2=P2, PodData3=P3
    for ($p = 1; $p -le $PortCount; $p++) {
        $podFile = Join-Path $DataPath "PodData$p.txt"
        if (-not (Test-Path $podFile)) {
            Write-Host "  PodData$p.txt not found - skipping port P$p" -ForegroundColor Yellow
            continue
        }

        $lines = Get-Content $podFile
        $port = "P$p"
        $posA = $null
        $runCount = 0

        foreach ($line in $lines) {
            if ($line -match "MAP-POSA") {
                $posA = $line
            }
            elseif ($line -match "MAP-POSB" -and $posA) {
                $partsA = $posA.Split(",")
                $partsB = $line.Split(",")

                # Build timestamp and check date filter
                $timestamp = "$($partsA[0]) $($partsA[1].Split('.')[0])"
                try {
                    $runDate = [datetime]::ParseExact($timestamp, "yyyy-MM-dd HH:mm:ss", $null)
                }
                catch {
                    $posA = $null
                    continue
                }

                if ($runDate -lt $cutoffDate) {
                    $posA = $null
                    continue
                }

                # Extract Z values: POSA gives slots 1-12, POSB gives slots 13-25
                $zA = $partsA[11..22]
                $zB = $partsB[11..23]
                $allSlots = $zA + $zB

                # Convert to doubles
                $slotValues = @()
                foreach ($val in $allSlots) {
                    try { $slotValues += [double]$val }
                    catch { $slotValues += 0.0 }
                }

                $allRuns += [PSCustomObject]@{
                    Timestamp  = $runDate
                    Port       = $port
                    PortDB     = "LP$p"    # Database format
                    SlotValues = $slotValues
                }
                $runCount++
                $posA = $null
            }
        }
        Write-Host "  Parsed $runCount runs for $port (last $DaysBack days)" -ForegroundColor Green
    }

    return $allRuns
}

# ============================================================
# 6. PARSE ROBOT CONFIG
# ============================================================

function Parse-RobotConfig {
    <#
    .SYNOPSIS
        Extracts TaughtZ values per port from the robot config file.
        Lines starting with P1/P2/P3 contain Z:nn.nn values.
    .OUTPUTS
        Hashtable: @{ "P1" = 23.71; "P2" = 23.61 }
    #>
    param(
        [string]$ConfigFilePath
    )

    $taughtZ = @{}

    if (-not (Test-Path $ConfigFilePath)) {
        Write-Host "  Robot config not found: $ConfigFilePath" -ForegroundColor Red
        return $taughtZ
    }

    $lines = Get-Content $ConfigFilePath

    foreach ($line in $lines) {
        if ($line -match "^(P[1-4])\s.*Z:([0-9]+\.[0-9]+)") {
            $port = $Matches[1]
            $z = [double]$Matches[2]
            $taughtZ[$port] = $z
        }
    }

    foreach ($key in $taughtZ.Keys) {
        Write-Host "  $key TaughtZ = $($taughtZ[$key])" -ForegroundColor Cyan
    }

    return $taughtZ
}

# ============================================================
# 7. CALCULATE OFFSETS
# ============================================================

function Calculate-Offsets {
    <#
    .SYNOPSIS
        Applies the offset formula to each run:
        Offset = MeasuredZ - (TaughtZ + 10 * (SlotNumber - 1))
        Determines pass/fail per slot and overall per run.
    .OUTPUTS
        Array of objects with: all run info + Offsets, FailedSlots,
        SensorFails, OverallResult
    #>
    param(
        [array]$Runs,
        [hashtable]$TaughtZ
    )

    $results = @()

    foreach ($run in $Runs) {
        $taught = $TaughtZ[$run.Port]
        if ($null -eq $taught) {
            Write-Host "  No TaughtZ for $($run.Port) - skipping run" -ForegroundColor Yellow
            continue
        }

        $offsets = @()
        $failedSlots = 0
        $sensorFails = 0
        $warningSlots = 0

        for ($slot = 1; $slot -le 25; $slot++) {
            $measured = $run.SlotValues[$slot - 1]

            if ($measured -eq 0) {
                $sensorFails++
                $offsets += 0.0
                continue
            }

            $expected = $taught + (10 * ($slot - 1))
            $offset = [math]::Round($measured - $expected, 2)
            $offsets += $offset

            if ([math]::Abs($offset) -gt 1.0) { $failedSlots++ }
            elseif ([math]::Abs($offset) -gt 0.4) { $warningSlots++ }
        }

        if ($failedSlots -gt 0) { $overallResult = "FAIL" } elseif ($sensorFails -gt 0) { $overallResult = "INCOMPLETE" } else { $overallResult = "PASS" }


        $results += [PSCustomObject]@{
            Timestamp     = $run.Timestamp
            Port          = $run.Port
            PortDB        = $run.PortDB
            TaughtZ       = $taught
            SlotValues    = $run.SlotValues
            Offsets       = $offsets
            FailedSlots   = $failedSlots
            WarningSlots  = $warningSlots
            SensorFails   = $sensorFails
            OverallResult = $overallResult
        }
    }

    # Summary
    $passes     = ($results | Where-Object { $_.OverallResult -eq "PASS" }).Count
    $fails      = ($results | Where-Object { $_.OverallResult -eq "FAIL" }).Count
    $incomplete = ($results | Where-Object { $_.OverallResult -eq "INCOMPLETE" }).Count
    Write-Host "  Offsets: $($results.Count) runs ($passes PASS, $fails FAIL, $incomplete INCOMPLETE)" -ForegroundColor Green

    return $results
}

# ============================================================
# 8. SQL SERVER INSERTION
# ============================================================

function Insert-ToDatabase {
    <#
    .SYNOPSIS
        Inserts qualification runs and slot measurements into SQL Server.
        Uses duplicate detection based on ToolID + PortName + RunDateTime
        so re-running the script won't create duplicate rows.
    #>
    param(
        [string]$ToolID,
        [array]$Results,
        [string]$SqlServer,
        [string]$Database
    )

    $connString = "Server=$SqlServer;Database=$Database;Trusted_Connection=True;"
    $conn = New-Object System.Data.SqlClient.SqlConnection($connString)

    try {
        $conn.Open()
        Write-Host "  Database connected" -ForegroundColor Green
    }
    catch {
        Write-Host "  Database connection failed: $_" -ForegroundColor Red
        return
    }

    $insertedRuns = 0
    $skippedRuns = 0

    foreach ($run in $Results) {
        # Check for duplicate: same tool, port, and timestamp
        $checkSql = @"
            SELECT COUNT(*) FROM QualificationRuns
            WHERE ToolID = @ToolID AND PortName = @PortName
            AND RunDateTime = @RunDateTime
"@
        $checkCmd = New-Object System.Data.SqlClient.SqlCommand($checkSql, $conn)
        $checkCmd.Parameters.AddWithValue("@ToolID", $ToolID) | Out-Null
        $checkCmd.Parameters.AddWithValue("@PortName", $run.PortDB) | Out-Null
        $checkCmd.Parameters.AddWithValue("@RunDateTime", $run.Timestamp) | Out-Null
        $exists = $checkCmd.ExecuteScalar()

        if ($exists -gt 0) {
            $skippedRuns++
            continue
        }

        # Get next RunID
        $maxIdCmd = New-Object System.Data.SqlClient.SqlCommand("SELECT ISNULL(MAX(RunID), 0) + 1 FROM QualificationRuns", $conn)
        $newRunID = $maxIdCmd.ExecuteScalar()

        # Insert QualificationRun
        $insertRunSql = @"
            INSERT INTO QualificationRuns (RunID, ToolID, PortName, RunDateTime, TaughtZ, OverallResult)
            VALUES (@RunID, @ToolID, @PortName, @RunDateTime, @TaughtZ, @OverallResult)
"@
        $insertCmd = New-Object System.Data.SqlClient.SqlCommand($insertRunSql, $conn)
        $insertCmd.Parameters.AddWithValue("@RunID", $newRunID) | Out-Null
        $insertCmd.Parameters.AddWithValue("@ToolID", $ToolID) | Out-Null
        $insertCmd.Parameters.AddWithValue("@PortName", $run.PortDB) | Out-Null
        $insertCmd.Parameters.AddWithValue("@RunDateTime", $run.Timestamp) | Out-Null
        $insertCmd.Parameters.AddWithValue("@TaughtZ", $run.TaughtZ) | Out-Null
        $insertCmd.Parameters.AddWithValue("@OverallResult", $run.OverallResult) | Out-Null
        $insertCmd.ExecuteNonQuery() | Out-Null

        # Insert SlotMeasurements
        for ($slot = 1; $slot -le 25; $slot++) {
            $insertSlotSql = @"
                INSERT INTO SlotMeasurements (RunID, SlotNumber, MeasuredZ)
                VALUES (@RunID, @SlotNumber, @MeasuredZ)
"@
            $slotCmd = New-Object System.Data.SqlClient.SqlCommand($insertSlotSql, $conn)
            $slotCmd.Parameters.AddWithValue("@RunID", $newRunID) | Out-Null
            $slotCmd.Parameters.AddWithValue("@SlotNumber", $slot) | Out-Null
            $slotCmd.Parameters.AddWithValue("@MeasuredZ", $run.SlotValues[$slot - 1]) | Out-Null
            $slotCmd.ExecuteNonQuery() | Out-Null
        }

        $insertedRuns++
    }

    $conn.Close()
    Write-Host "  Inserted: $insertedRuns new runs, Skipped: $skippedRuns duplicates" -ForegroundColor Green
}

# ============================================================
# 9. ORCHESTRATOR - SINGLE TOOL
# ============================================================

function Extract-SingleTool {
    <#
    .SYNOPSIS
        Runs the full pipeline for one tool:
        Connect -> Copy files -> Extract -> Parse -> Calculate -> Insert
    #>
    param(
        [PSCustomObject]$Tool,
        [System.Management.Automation.PSCredential]$Credential,
        [string]$StagingFolder,
        [string]$SqlServer,
        [string]$Database,
        [int]$DaysBack = 60
    )

    Write-Host "`n=== Processing $($Tool.id) ($($Tool.ceid)) ===" -ForegroundColor Cyan

    # Step 1: Ping
    if (-not (Test-ToolConnection -ToolID $Tool.id -IPAddress $Tool.ip)) {
        Write-Host "  Skipping $($Tool.id) - unreachable" -ForegroundColor Yellow
        return
    }

    # Step 2: Connect
    if (-not (Connect-Tool -ToolID $Tool.id -IPAddress $Tool.ip -Credential $Credential)) {
        Write-Host "  Skipping $($Tool.id) - auth failed" -ForegroundColor Yellow
        return
    }

    try {
        # Step 3: Copy files
        $toolFiles = Get-ToolFiles -ToolID $Tool.id -IPAddress $Tool.ip -StagingRoot $StagingFolder
        if ($null -eq $toolFiles) {
            Write-Host "  Skipping $($Tool.id) - no files found" -ForegroundColor Yellow
            return
        }

        # Step 4: Extract zip
        $toolFiles = Expand-ToolArchive -ToolFiles $toolFiles

        # Step 5: Parse PodData
        $runs = Parse-PodData -DataPath $toolFiles.DataPath -PortCount $Tool.ports -DaysBack $DaysBack

        if ($runs.Count -eq 0) {
            Write-Host "  No runs found in last $DaysBack days" -ForegroundColor Yellow
            return
        }

        # Step 6: Parse robot config
        $configPath = Join-Path $toolFiles.StagingPath "robot_config.txt"
        $taughtZ = Parse-RobotConfig -ConfigFilePath $configPath

        if ($taughtZ.Count -eq 0) {
            Write-Host "  No TaughtZ values found - cannot calculate offsets" -ForegroundColor Red
            return
        }

        # Step 7: Calculate offsets
        $results = Calculate-Offsets -Runs $runs -TaughtZ $taughtZ

        # Step 8: Insert to database
        Insert-ToDatabase -ToolID $Tool.id -Results $results -SqlServer $SqlServer -Database $Database
    }
    finally {
        # Always disconnect
        Disconnect-Tool -IPAddress $Tool.ip
    }

    Write-Host "=== $($Tool.id) complete ===" -ForegroundColor Cyan
}

# ============================================================
# 10. ORCHESTRATOR - FULL FLEET
# ============================================================

function Run-FullExtraction {
    <#
    .SYNOPSIS
        Runs the extraction pipeline across all tools in the config.
    #>
    param(
        [string]$ConfigPath = ".\APAVS_Config.json",
        [int]$DaysBack = 60
    )

    $startTime = Get-Date
    Write-Host "============================================" -ForegroundColor White
    Write-Host "  APAVS Data Extraction" -ForegroundColor White
    Write-Host "  Started: $startTime" -ForegroundColor White
    Write-Host "============================================" -ForegroundColor White

    # Load config
    $config = Load-Config -ConfigPath $ConfigPath
    if ($null -eq $config) { return }

    # Create staging folder
    if (-not (Test-Path $config.stagingFolder)) {
        New-Item -ItemType Directory -Path $config.stagingFolder -Force | Out-Null
    }

    # Prompt for credentials once
    Write-Host "`nEnter tool credentials:" -ForegroundColor Yellow
    $cred = Get-Credential -Message "Enter tool login (e.g. amat / amat)"

    # Process each tool
    $processed = 0
    $failed = 0

    foreach ($tool in $config.tools) {
        try {
            Extract-SingleTool `
                -Tool $tool `
                -Credential $cred `
                -StagingFolder $config.stagingFolder `
                -SqlServer $config.sqlServer `
                -Database $config.database `
                -DaysBack $DaysBack
            $processed++
        }
        catch {
            Write-Host "  ERROR on $($tool.id): $_" -ForegroundColor Red
            $failed++
        }
    }

    # Summary
    $elapsed = (Get-Date) - $startTime
    Write-Host "`n============================================" -ForegroundColor White
    Write-Host "  Extraction Complete" -ForegroundColor White
    Write-Host "  Tools processed: $processed" -ForegroundColor Green
    Write-Host "  Tools failed:    $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
    Write-Host "  Time elapsed:    $([math]::Round($elapsed.TotalMinutes, 1)) minutes" -ForegroundColor White
    Write-Host "============================================" -ForegroundColor White
}

# ============================================================
# QUICK TEST FUNCTIONS
# ============================================================

function Test-SingleTool {
    <#
    .SYNOPSIS
        Test the full pipeline on one tool without inserting to database.
        Good for verifying everything works before a full run.
    #>
    param(
        [string]$ConfigPath = ".\APAVS_Config.json",
        [string]$ToolID = "CSB201",
        [int]$DaysBack = 60
    )

    $config = Load-Config -ConfigPath $ConfigPath
    if ($null -eq $config) { return }

    $tool = $config.tools | Where-Object { $_.id -eq $ToolID }
    if ($null -eq $tool) {
        Write-Host "Tool $ToolID not found in config" -ForegroundColor Red
        return
    }

    if (-not (Test-Path $config.stagingFolder)) {
        New-Item -ItemType Directory -Path $config.stagingFolder -Force | Out-Null
    }

    Write-Host "`nEnter tool credentials:" -ForegroundColor Yellow
    $cred = Get-Credential -Message "Enter tool login (e.g. amat / amat)"

    Write-Host "`n=== Testing $ToolID ===" -ForegroundColor Cyan

    # Connect
    if (-not (Test-ToolConnection -ToolID $tool.id -IPAddress $tool.ip)) { return }
    if (-not (Connect-Tool -ToolID $tool.id -IPAddress $tool.ip -Credential $cred)) { return }

    try {
        # Get files
        $toolFiles = Get-ToolFiles -ToolID $tool.id -IPAddress $tool.ip -StagingRoot $config.stagingFolder
        if ($null -eq $toolFiles) { return }

        # Extract
        $toolFiles = Expand-ToolArchive -ToolFiles $toolFiles

        # Parse
        $runs = Parse-PodData -DataPath $toolFiles.DataPath -PortCount $tool.ports -DaysBack $DaysBack
        $configPath = Join-Path $toolFiles.StagingPath "robot_config.txt"
        $taughtZ = Parse-RobotConfig -ConfigFilePath $configPath

        # Calculate
        $results = Calculate-Offsets -Runs $runs -TaughtZ $taughtZ
	
	# Export summary
        $csvPath = Join-Path $config.stagingFolder "$($tool.id)_results.csv"
        $results | Select-Object Timestamp, PortDB, TaughtZ, FailedSlots, WarningSlots, SensorFails, OverallResult | Export-Csv -Path $csvPath -NoTypeInformation

        # Export slot-level data
        $slotPath = Join-Path $config.stagingFolder "$($tool.id)_slots.csv"
        $slotRows = @()
        foreach ($run in $results) {
            for ($s = 0; $s -lt 25; $s++) {
                $slotRows += [PSCustomObject]@{
                    Timestamp  = $run.Timestamp
                    PortDB     = $run.PortDB
                    TaughtZ    = $run.TaughtZ
                    SlotNumber = ($s + 1)
                    MeasuredZ  = $run.SlotValues[$s]
                    Offset     = $run.Offsets[$s]
                }
            }
        }
        $slotRows | Export-Csv -Path $slotPath -NoTypeInformation
        Write-Host "  Exported to: $csvPath" -ForegroundColor Green
        Write-Host "  Slot data:   $slotPath" -ForegroundColor Green

        # Show last 5 results instead of inserting
        Write-Host "`n  Last 5 runs:" -ForegroundColor White
        $results | Select-Object -Last 5 | ForEach-Object {
            $colour = if ($_.OverallResult -eq "PASS") { "Green" } elseif ($_.OverallResult -eq "INCOMPLETE") { "Yellow" } else { "Red" }
            Write-Host "    $($_.Timestamp.ToString('yyyy-MM-dd HH:mm'))  $($_.PortDB)  $($_.OverallResult)  (Failed:$($_.FailedSlots) Warn:$($_.WarningSlots) Sensor:$($_.SensorFails))" -ForegroundColor $colour
        }
    }
    finally {
        Disconnect-Tool -IPAddress $tool.ip
    }

    Write-Host "`n=== Test complete ===" -ForegroundColor Cyan
}

# ============================================================
# HOW TO RUN
# ============================================================
<#
    1. Open PowerShell on the CAD remote desktop
    2. Navigate to the APAVS folder:
         cd C:\Users\vbyrne\Documents\APAVS

    3. Load the script:
         . .\scripts\APAVS_Extract.ps1

    4. Test one tool (no database insertion):
         Test-SingleTool -ToolID "CSB201"

    5. Run full extraction across all tools:
         Run-FullExtraction

    6. Run with custom date range (e.g. last 30 days):
         Run-FullExtraction -DaysBack 30
#>