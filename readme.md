# APAVS — Automated Pipeline and Visualisation System

**Student:** Vincent Byrne (20108898)  
**Programme:** HDip Computer Science, SETU Waterford  

-------------------------------------------------------

## Project Overview

APAVS addresses a real operational inefficiency in qualification of load ports at Intel. Technicians must manually export log files from CSB tools, run Excel macros, and visually inspect qualification plots one load port at a time with no fleet visibility.

APAVS automates this workflow and delivers a Power BI dashboard providing fleet-wide qualification status at a glance.

### The Problem

- Manual export of FI log files from each tool's Millenium software
- Manual retrieval of Robot Configuration files (taught Z-positions)
- Manual execution of an Excel macro per tool per session
- No historical tracking, no alerting, no cross-fleet comparison
- Analysis is ephemeral — no persistence between sessions

### The Solution

A PowerShell extraction pipeline feeding a SQL Server database, visualised through a Power BI dashboard.

- Fleet-wide KPI cards (total tools, pass rate, run count)
- Pass/fail/incomplete status per tool and load port
- Filtering by tool ID, port, slot number, and result
- Slot-level drill-down to individual measurements
- Trend analysis with ±1mm OOC and ±0.4mm warning reference lines
- Automated PowerShell extraction pipeline across the tool fleet

-------------------------------------------------------

## Offset Calculation

The core qualification metric, validated against the existing Excel macro:

Offset_n = Measured_n − (TaughtZ + 10 × (n − 1))

Where `n` is the slot number (1–25). A load port **passes** if all absolute offsets are within **±1mm**. A warning is flagged if any offset exceeds **±0.4mm**. Runs where one or more sensors return 0.00 are classified as **incomplete** rather than failures.

-------------------------------------------------------

## Repository Structure
```
APAVS/
├── dashboard/
│   └── APAVS_Dashboard.pbix
├── data/
│   └── synthetic/
├── scripts/
│   ├── APAVS_Extract.ps1
│   └── APAVS_Import.ps1
├── docs/
│   └── index.html
├── APAVS_Config.example.json
├── .gitignore
└── README.md
```

-------------------------------------------------------

## Data Model

Four-table relational model with one-to-many relationships:

Tools (1) ──► LoadPorts (M) ──► QualificationRuns (M) ──► SlotMeasurements (M)

|       Table         |                    Key Fields                                |
|---------------------|--------------------------------------------------------------|
| Tools               | ToolID, CEID                                                 |
| LoadPorts           | ToolID, PortName (composite key)                             |
| QualificationRuns   | RunID, ToolID, PortName, RunDateTime, TaughtZ, OverallResult |
| SlotMeasurements    | RunID, SlotNumber, MeasuredZ                                 |

`TaughtZ` is stored per run (not per tool) to preserve historical reference values — an improvement over the existing Excel-based approach which cannot compare against past taught positions.

-------------------------------------------------------

## Technology Stack

|       Tool         |               Purpose                  |
|--------------------|----------------------------------------|
| Power BI Desktop   | Dashboard development and DAX measures |
| SQL Server Express | Database backend                       |
| PowerShell         | Automated data extraction pipeline     |
| JSON               | Tool fleet configuration               |
| GitHub             | Version control                        |
| GitHub Pages       | Project landing page                   |

-------------------------------------------------------

## Running the Dashboard

1. Clone this repository
2. Install SQL Server Express and create the APAVS_DB database
3. Open `dashboard/APAVS_Dashboard.pbix` in Power BI Desktop
4. Connect to `localhost\SQLEXPRESS` when prompted

## Running the Extraction Pipeline

1. Copy `APAVS_Config.example.json` to `APAVS_Config.json` and add real tool IP addresses
2. On the CAD remote desktop (Tool Netowrk):
```powershell
   cd C:\Users\vbyrne\Documents\APAVS
   . .\scripts\APAVS_Extract.ps1
   Run-FullExtraction -DaysBack 365
```
3. On the development laptop:
```powershell
   cd C:\Users\vbyrne\Documents\APAVS
   . .\scripts\APAVS_Import.ps1
   Import-APAVSData
4. Refresh Power BI to see the new data

-------------------------------------------------------

## Ethical Compliance

All data used in the development phases of this project is **synthetic**, generated to represent realistic CSB tool qualification scenarios while complying with SETU ethical guidelines and Intel data protection requirements. Phase 4 testing was conducted against live tool data on the Intel network. Real IP addresses and credentials are excluded from this repository via .gitignore. No wafer data or personally identifiable information is included in this repository. This projectt excludes intel top secret information