/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/
/*
	Created: 20250224@Danny
	DB: DBLIC-bodb_licenseeReport
	Task: Regen data
*/
USE bodb_licenseeReport
GO

EXEC [dbo].LA_GEN_LicPerformanceAnalysis_Report
	@FromDate		= '2025-01-01',
	@ToDate			= '2025-01-31',
	@ProductCodes	= 'SB',
	@Environment	= 'PRO',
	@IsOverwrite	= 1,
	@PartyIds		= '168,619,644,724,776,876,922'


