<#
.SYNOPSIS
    APAVS Import - Reads extracted CSV data and inserts into SQL Server.
    Run this on the laptop after APAVS_Extract.ps1 has exported data
    from the CAD desktop to the network share.
 
.NOTES
    Author:  Vincent Byrne (20108898)
    Project: HDip Computer Science Capstone - SETU
#>
 
function Import-APAVSData {
    param(
        [string]$ImportFolder = "C:\APAVS\Import",
        [string]$SqlServer = "localhost\SQLEXPRESS",
        [string]$Database = "APAVS_DB"
    )
 
    $startTime = Get-Date
    Write-Host "============================================" -ForegroundColor White
    Write-Host "  APAVS Data Import" -ForegroundColor White
    Write-Host "  Source: $ImportFolder" -ForegroundColor White
    Write-Host "============================================" -ForegroundColor White
 
    # Find all result files in the import folder
    $resultFiles = Get-ChildItem -Path $ImportFolder -Filter "*_results.csv"
    if ($resultFiles.Count -eq 0) {
        Write-Host "No CSV files found in $ImportFolder" -ForegroundColor Red
        return
    }
    Write-Host "Found $($resultFiles.Count) tool export(s)" -ForegroundColor Green
 
    # Connect to SQL Server
    $conn = New-Object System.Data.SqlClient.SqlConnection("Server=$SqlServer;Database=$Database;Trusted_Connection=True;")
    try {
        $conn.Open()
        Write-Host "Database connected" -ForegroundColor Green
    }
    catch {
        Write-Host "Database connection failed: $_" -ForegroundColor Red
        return
    }
 
    $totalRuns = 0
    $totalSlots = 0
    $totalSkipped = 0
 
    foreach ($file in $resultFiles) {
        # Extract ToolID from filename (e.g. CSB231_results.csv -> CSB231)
        $toolID = $file.Name -replace "_results.csv", ""
        $slotFile = Join-Path $ImportFolder "$($toolID)_slots.csv"
 
        Write-Host "`n--- $toolID ---" -ForegroundColor Cyan
 
        # Import results CSV
        $results = Import-Csv $file.FullName
        Write-Host "  Runs in CSV: $($results.Count)"
 
        $insertedRuns = 0
        $skipped = 0
 
        foreach ($run in $results) {
            # Duplicate check
            $checkSql = "SELECT COUNT(*) FROM QualificationRuns WHERE ToolID = @ToolID AND PortName = @Port AND RunDateTime = @DT"
            $checkCmd = New-Object System.Data.SqlClient.SqlCommand($checkSql, $conn)
            $checkCmd.Parameters.AddWithValue("@ToolID", $toolID) | Out-Null
            $checkCmd.Parameters.AddWithValue("@Port", $run.PortDB) | Out-Null
            $checkCmd.Parameters.AddWithValue("@DT", [datetime]$run.Timestamp) | Out-Null
 
            if ($checkCmd.ExecuteScalar() -gt 0) {
                $skipped++
                continue
            }
 
            # Get next RunID
            $maxCmd = New-Object System.Data.SqlClient.SqlCommand("SELECT ISNULL(MAX(RunID), 0) + 1 FROM QualificationRuns", $conn)
            $newRunID = $maxCmd.ExecuteScalar()
 
            # Insert run
            $sql = "INSERT INTO QualificationRuns (RunID, ToolID, PortName, RunDateTime, TaughtZ, OverallResult) VALUES (@RunID, @ToolID, @PortName, @DT, @TaughtZ, @Result)"
            $cmd = New-Object System.Data.SqlClient.SqlCommand($sql, $conn)
            $cmd.Parameters.AddWithValue("@RunID", $newRunID) | Out-Null
            $cmd.Parameters.AddWithValue("@ToolID", $toolID) | Out-Null
            $cmd.Parameters.AddWithValue("@PortName", $run.PortDB) | Out-Null
            $cmd.Parameters.AddWithValue("@DT", [datetime]$run.Timestamp) | Out-Null
            $cmd.Parameters.AddWithValue("@TaughtZ", [decimal]$run.TaughtZ) | Out-Null
            $cmd.Parameters.AddWithValue("@Result", $run.OverallResult) | Out-Null
            $cmd.ExecuteNonQuery() | Out-Null
            $insertedRuns++
        }
 
        Write-Host "  Runs inserted: $insertedRuns  Skipped: $skipped" -ForegroundColor Green
        $totalRuns += $insertedRuns
        $totalSkipped += $skipped
 
        # Import slot data if file exists
        if (Test-Path $slotFile) {
            $slots = Import-Csv $slotFile
            Write-Host "  Importing $($slots.Count) slot measurements..."
 
            $lastKey = ""
            $slotRunID = 0
            $slotCount = 0
 
            foreach ($slot in $slots) {
                $key = "$($slot.Timestamp)|$($slot.PortDB)"
                if ($key -ne $lastKey) {
                    $lookupSql = "SELECT RunID FROM QualificationRuns WHERE ToolID = @ToolID AND PortName = @Port AND RunDateTime = @DT"
                    $lookupCmd = New-Object System.Data.SqlClient.SqlCommand($lookupSql, $conn)
                    $lookupCmd.Parameters.AddWithValue("@ToolID", $toolID) | Out-Null
                    $lookupCmd.Parameters.AddWithValue("@Port", $slot.PortDB) | Out-Null
                    $lookupCmd.Parameters.AddWithValue("@DT", [datetime]$slot.Timestamp) | Out-Null
                    $slotRunID = $lookupCmd.ExecuteScalar()
                    $lastKey = $key
                }
 
                if ($slotRunID) {
                    # Check if slot already exists
                    $slotCheckSql = "SELECT COUNT(*) FROM SlotMeasurements WHERE RunID = @RunID AND SlotNumber = @Slot"
                    $slotCheckCmd = New-Object System.Data.SqlClient.SqlCommand($slotCheckSql, $conn)
                    $slotCheckCmd.Parameters.AddWithValue("@RunID", $slotRunID) | Out-Null
                    $slotCheckCmd.Parameters.AddWithValue("@Slot", [int]$slot.SlotNumber) | Out-Null
 
                    if ($slotCheckCmd.ExecuteScalar() -eq 0) {
                        $sql = "INSERT INTO SlotMeasurements (RunID, SlotNumber, MeasuredZ) VALUES (@RunID, @Slot, @MZ)"
                        $cmd = New-Object System.Data.SqlClient.SqlCommand($sql, $conn)
                        $cmd.Parameters.AddWithValue("@RunID", $slotRunID) | Out-Null
                        $cmd.Parameters.AddWithValue("@Slot", [int]$slot.SlotNumber) | Out-Null
                        $cmd.Parameters.AddWithValue("@MZ", [decimal]$slot.MeasuredZ) | Out-Null
                        $cmd.ExecuteNonQuery() | Out-Null
                        $slotCount++
                    }
                }
            }
 
            Write-Host "  Slots inserted: $slotCount" -ForegroundColor Green
            $totalSlots += $slotCount
        }
        else {
            Write-Host "  No slot file found for $toolID" -ForegroundColor Yellow
        }
    }
 
    $conn.Close()
 
    $elapsed = (Get-Date) - $startTime
    Write-Host "`n============================================" -ForegroundColor White
    Write-Host "  Import Complete" -ForegroundColor White
    Write-Host "  Runs inserted:  $totalRuns" -ForegroundColor Green
    Write-Host "  Runs skipped:   $totalSkipped (duplicates)" -ForegroundColor Cyan
    Write-Host "  Slots inserted: $totalSlots" -ForegroundColor Green
    Write-Host "  Time elapsed:   $([math]::Round($elapsed.TotalMinutes, 1)) minutes" -ForegroundColor White
    Write-Host "============================================" -ForegroundColor White
}
 
# ============================================================
# HOW TO RUN
# ============================================================
<#
    1. Open PowerShell on your laptop
    2. cd C:\Users\vbyrne\Documents\APAVS
    3. . .\scripts\APAVS_Import.ps1
    4. Import-APAVSData
#>