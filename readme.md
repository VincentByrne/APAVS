# APAVS — Automated Pipeline and Visualisation System

**Student:** Vincent Byrne (20108898)  
**Programme:** HDip Computer Science, SETU Waterford  

-------------------------------------------------------

## Project Overview

APAVS addresses a real operational inefficiency in Qualificaiton of load ports in Intel. Technicians must manually export log files from CSB tools, run Excel macros, and visually inspect qualification plots one load port at a time with no fleet viability.

APAVS automates this workflow and delivers a Power BI dashboard providing fleet-wide qualification status at a glance.

### The Problem

- Manual export of FI log files from each tool's Millenium software
- Manual retrieval of Robot Configuration files (taught Z-positions)
- Manual execution of an Excel macro per tool per session
- No historical tracking, no alerting, no cross-fleet comparison
- Analysis is ephemeral — no persistence between sessions

### The Solution

A relational data model backed by CSV files and onto a database.
- Fleet-wide KPI cards (total tools, pass rate, run count)
- Pass/fail status per tool and load port
- Filtering by tool ID and result
- Planned: slot-level drill-down, trend analysis, automated data extraction

-------------------------------------------------------

## Offset Calculation

The core qualification metric, validated against the existing Excel macro:

Offset_n = Measured_n − (TaughtZ + 10 × (n − 1))

Where `n` is the slot number (1–25). A load port **passes** if all absolute offsets are within **±1mm**. A warning is flagged if any offset exceeds **±0.4mm**.

-------------------------------------------------------

## Repository Structure

APAVS/
├── dashboard/
│   └── APAVS_Dashboard.pbix       # Power BI dashboard file
│
├── data/ # Synthetic CSV data (ethical compliance)
│    ├── Tools.csv
│    ├── LoadPorts.csv
│    └── QualificationRuns.csv
├── scripts/                       # PowerShell / Python automation scripts
├── docs/                          # Project documentation
│   └── interim_report.pdf
└── README.md

-------------------------------------------------------

## Data Model

Three-table relational model with one-to-many relationships:

Tools (1) ──► LoadPorts (M) ──► QualificationRuns (M)

|       Table       |                    Key Fields                          |
|-------------------|--------------------------------------------------------|
| Tools             | ToolID, ToolName, Location                             |
| LoadPorts         | LoadPortID, ToolID, PortName                           |
| QualificationRuns | RunID, LoadPortID, RunDateTime, TaughtZ, OverallResult |

`TaughtZ` is stored per run (not per tool) to preserve historical reference values — an improvement over the existing Excel-based approach which cannot compare against past taught positions.

-------------------------------------------------------

## Technology Stack

|       Tool         |               Purpose                  |
|--------------------|----------------------------------------|
| Power BI Desktop   | Dashboard development and DAX measures |
| CSV files          | Data source (MVP phase)                |
| SQL Server Express | Planned migration (Phase 3+)           |
| PowerShell         | Planned automated data extraction      |
| GitHub             | Version control                        |
| Trello             | Sprint planning and progress tracking  |

-------------------------------------------------------

## Running the Dashboard
1. Clone this repository
2. Open `dashboard/APAVS_Dashboard.pbix` in Power BI Desktop
3. When prompted to locate data sources, point to `data`

-------------------------------------------------------

## Ethical Compliance

All data used in this project is **synthetic**, generated to represent realistic CSB tool qualification scenarios while complying with SETU ethical guidelines and Intel data protection requirements. No real tool data, wafer data, or personally identifiable information is included in this repository.


