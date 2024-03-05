/*<info serverAlias="DBLIC-bodb_licensee"></info>*/
/*
	Created: 20240304@Danny
	DB: DBLIC-bodb_Licensee
	Task: Regen data
*/
USE bodb_licensee
GO

EXEC [dbo].LA_GEN_LicPerformanceAnalysis_Report
	@FromDate		= '2024-01-01',
	@ToDate			= '2024-01-31',
	@Environment	= 'PRO',
	@IsOverwrite	= 1

