-- =============================================
-- APAVS Synthetic Data Script
-- Run this in SSMS against APAVS_DB
-- after the schema script has been executed
-- =============================================

USE APAVS_DB;
GO

-- =============================================
-- TOOLS
-- CSBca group: CSB201 CSB202 CSB203 CSB205 CSB208
-- CSBcd group: CSB221 CSB222 CSB225 CSB226 CSB227 CSB231
-- =============================================

INSERT INTO Tools (ToolID, CEID) VALUES
('CSB201', 'CSBca'),
('CSB202', 'CSBca'),
('CSB203', 'CSBca'),
('CSB205', 'CSBca'),
('CSB208', 'CSBca'),
('CSB221', 'CSBcd'),
('CSB222', 'CSBcd'),
('CSB225', 'CSBcd'),
('CSB226', 'CSBcd'),
('CSB227', 'CSBcd'),
('CSB231', 'CSBcd');
GO

-- =============================================
-- LOAD PORTS
-- CSBca tools: LP1, LP2 only (2 ports x 5 tools = 10 rows)
-- CSBcd tools: LP1, LP2, LP3  (3 ports x 6 tools = 18 rows)
-- =============================================

INSERT INTO LoadPorts (ToolID, PortName) VALUES
-- CSBca group
('CSB201', 'LP1'), ('CSB201', 'LP2'),
('CSB202', 'LP1'), ('CSB202', 'LP2'),
('CSB203', 'LP1'), ('CSB203', 'LP2'),
('CSB205', 'LP1'), ('CSB205', 'LP2'),
('CSB208', 'LP1'), ('CSB208', 'LP2'),
-- CSBcd group
('CSB221', 'LP1'), ('CSB221', 'LP2'), ('CSB221', 'LP3'),
('CSB222', 'LP1'), ('CSB222', 'LP2'), ('CSB222', 'LP3'),
('CSB225', 'LP1'), ('CSB225', 'LP2'), ('CSB225', 'LP3'),
('CSB226', 'LP1'), ('CSB226', 'LP2'), ('CSB226', 'LP3'),
('CSB227', 'LP1'), ('CSB227', 'LP2'), ('CSB227', 'LP3'),
('CSB231', 'LP1'), ('CSB231', 'LP2'), ('CSB231', 'LP3');
GO

-- =============================================
-- QUALIFICATION RUNS
--
-- TaughtZ reference values:
--   CSBca tools (CSB201-208): all ports share TaughtZ = 22.82
--   CSBcd tools (CSB221-231): LP1 = 25.34 | LP2 = 25.15 | LP3 = 25.23
--
-- Scenarios:
--   CSB203 LP2  : PASS Jan -> FAIL Feb 14  (active failure, needs attention)
--   CSB225 LP3  : PASS Jan -> FAIL Feb 15  (active failure, needs attention)
--   CSB227 LP1  : FAIL Jan 8 -> PASS Jan 9 (repaired and re-qualified successfully)
--   All others  : two clean PASS runs
--
-- 2 runs per load port = 56 runs total
-- =============================================

INSERT INTO QualificationRuns (RunID, ToolID, PortName, RunDateTime, TaughtZ, OverallResult) VALUES

-- -----------------------------------------------
-- CSBca GROUP (TaughtZ = 22.82 for all ports)
-- -----------------------------------------------

-- CSB201 : all PASS
(1,  'CSB201', 'LP1', '2026-01-05 06:30:00', 22.82, 'PASS'),
(2,  'CSB201', 'LP1', '2026-01-28 14:15:00', 22.82, 'PASS'),
(3,  'CSB201', 'LP2', '2026-01-05 08:45:00', 22.82, 'PASS'),
(4,  'CSB201', 'LP2', '2026-01-28 16:00:00', 22.82, 'PASS'),

-- CSB202 : all PASS
(5,  'CSB202', 'LP1', '2026-01-06 07:00:00', 22.82, 'PASS'),
(6,  'CSB202', 'LP1', '2026-01-29 09:30:00', 22.82, 'PASS'),
(7,  'CSB202', 'LP2', '2026-01-06 09:15:00', 22.82, 'PASS'),
(8,  'CSB202', 'LP2', '2026-01-29 11:45:00', 22.82, 'PASS'),

-- CSB203 : LP1 clean, LP2 passed Jan then FAILED Feb 14
(9,  'CSB203', 'LP1', '2026-01-07 06:30:00', 22.82, 'PASS'),
(10, 'CSB203', 'LP1', '2026-01-30 08:00:00', 22.82, 'PASS'),
(11, 'CSB203', 'LP2', '2026-01-07 08:30:00', 22.82, 'PASS'),
(12, 'CSB203', 'LP2', '2026-02-14 10:30:00', 22.82, 'FAIL'),  -- active failure

-- CSB205 : all PASS
(13, 'CSB205', 'LP1', '2026-01-08 07:15:00', 22.82, 'PASS'),
(14, 'CSB205', 'LP1', '2026-01-31 09:00:00', 22.82, 'PASS'),
(15, 'CSB205', 'LP2', '2026-01-08 09:30:00', 22.82, 'PASS'),
(16, 'CSB205', 'LP2', '2026-01-31 11:15:00', 22.82, 'PASS'),

-- CSB208 : all PASS
(17, 'CSB208', 'LP1', '2026-01-09 06:45:00', 22.82, 'PASS'),
(18, 'CSB208', 'LP1', '2026-02-01 08:30:00', 22.82, 'PASS'),
(19, 'CSB208', 'LP2', '2026-01-09 09:00:00', 22.82, 'PASS'),
(20, 'CSB208', 'LP2', '2026-02-01 10:45:00', 22.82, 'PASS'),

-- -----------------------------------------------
-- CSBcd GROUP (TaughtZ per port: LP1=25.34 LP2=25.15 LP3=25.23)
-- -----------------------------------------------

-- CSB221 : all PASS
(21, 'CSB221', 'LP1', '2026-01-10 07:00:00', 25.34, 'PASS'),
(22, 'CSB221', 'LP1', '2026-02-02 09:15:00', 25.34, 'PASS'),
(23, 'CSB221', 'LP2', '2026-01-10 09:30:00', 25.15, 'PASS'),
(24, 'CSB221', 'LP2', '2026-02-02 11:30:00', 25.15, 'PASS'),
(25, 'CSB221', 'LP3', '2026-01-10 11:45:00', 25.23, 'PASS'),
(26, 'CSB221', 'LP3', '2026-02-02 14:00:00', 25.23, 'PASS'),

-- CSB222 : all PASS
(27, 'CSB222', 'LP1', '2026-01-12 06:30:00', 25.34, 'PASS'),
(28, 'CSB222', 'LP1', '2026-02-03 08:15:00', 25.34, 'PASS'),
(29, 'CSB222', 'LP2', '2026-01-12 08:45:00', 25.15, 'PASS'),
(30, 'CSB222', 'LP2', '2026-02-03 10:30:00', 25.15, 'PASS'),
(31, 'CSB222', 'LP3', '2026-01-12 11:00:00', 25.23, 'PASS'),
(32, 'CSB222', 'LP3', '2026-02-03 13:00:00', 25.23, 'PASS'),

-- CSB225 : LP1 LP2 clean, LP3 passed Jan then FAILED Feb 15
(33, 'CSB225', 'LP1', '2026-01-13 07:15:00', 25.34, 'PASS'),
(34, 'CSB225', 'LP1', '2026-02-04 09:00:00', 25.34, 'PASS'),
(35, 'CSB225', 'LP2', '2026-01-13 09:30:00', 25.15, 'PASS'),
(36, 'CSB225', 'LP2', '2026-02-04 11:15:00', 25.15, 'PASS'),
(37, 'CSB225', 'LP3', '2026-01-13 11:45:00', 25.23, 'PASS'),
(38, 'CSB225', 'LP3', '2026-02-15 10:00:00', 25.23, 'FAIL'),  -- active failure

-- CSB226 : all PASS
(39, 'CSB226', 'LP1', '2026-01-14 06:45:00', 25.34, 'PASS'),
(40, 'CSB226', 'LP1', '2026-02-05 08:30:00', 25.34, 'PASS'),
(41, 'CSB226', 'LP2', '2026-01-14 09:00:00', 25.15, 'PASS'),
(42, 'CSB226', 'LP2', '2026-02-05 10:45:00', 25.15, 'PASS'),
(43, 'CSB226', 'LP3', '2026-01-14 11:15:00', 25.23, 'PASS'),
(44, 'CSB226', 'LP3', '2026-02-05 13:00:00', 25.23, 'PASS'),

-- CSB227 : LP1 FAILED Jan 8, repaired and re-qualified PASS Jan 9. LP2 LP3 clean.
(45, 'CSB227', 'LP1', '2026-01-08 07:30:00', 25.34, 'FAIL'),  -- failure found
(46, 'CSB227', 'LP1', '2026-01-09 14:00:00', 25.34, 'PASS'),  -- repaired, re-qual passed
(47, 'CSB227', 'LP2', '2026-01-15 08:15:00', 25.15, 'PASS'),
(48, 'CSB227', 'LP2', '2026-02-06 10:00:00', 25.15, 'PASS'),
(49, 'CSB227', 'LP3', '2026-01-15 10:30:00', 25.23, 'PASS'),
(50, 'CSB227', 'LP3', '2026-02-06 12:15:00', 25.23, 'PASS'),

-- CSB231 : all PASS
(51, 'CSB231', 'LP1', '2026-01-16 07:00:00', 25.34, 'PASS'),
(52, 'CSB231', 'LP1', '2026-02-07 09:00:00', 25.34, 'PASS'),
(53, 'CSB231', 'LP2', '2026-01-16 09:15:00', 25.15, 'PASS'),
(54, 'CSB231', 'LP2', '2026-02-07 11:30:00', 25.15, 'PASS'),
(55, 'CSB231', 'LP3', '2026-01-16 11:30:00', 25.23, 'PASS'),
(56, 'CSB231', 'LP3', '2026-02-07 14:00:00', 25.23, 'PASS');
GO

-- =============================================
-- VERIFY: Full joined view
-- =============================================

SELECT
    t.CEID,
    t.ToolID,
    qr.PortName,
    qr.RunID,
    qr.RunDateTime,
    qr.TaughtZ,
    qr.OverallResult
FROM QualificationRuns qr
JOIN LoadPorts lp  ON qr.ToolID   = lp.ToolID
                  AND qr.PortName  = lp.PortName
JOIN Tools t       ON lp.ToolID   = t.ToolID
ORDER BY t.CEID, t.ToolID, qr.PortName, qr.RunDateTime;
GO

-- =============================================
-- SUMMARY: Pass/fail count per tool
-- =============================================

SELECT
    t.CEID,
    t.ToolID,
    COUNT(*)                                                        AS TotalRuns,
    SUM(CASE WHEN qr.OverallResult = 'PASS' THEN 1 ELSE 0 END)     AS Passes,
    SUM(CASE WHEN qr.OverallResult = 'FAIL' THEN 1 ELSE 0 END)     AS Failures
FROM QualificationRuns qr
JOIN LoadPorts lp ON qr.ToolID  = lp.ToolID
                 AND qr.PortName = lp.PortName
JOIN Tools t      ON lp.ToolID  = t.ToolID
GROUP BY t.CEID, t.ToolID
ORDER BY t.CEID, t.ToolID;
GO