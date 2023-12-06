/*<info serverAlias="DBLIC-bodb_licensee"></info>*/
/*
	Created: 20231204@Danny
	DB: DBLIC-bodb_Licensee
	Task: Regen data
*/
USE bodb_licensee
GO


EXEC [dbo].LA_GEN_LicPerformanceAnalysis_Report
	@FromDate		= '2023-10-01',
	@ToDate			= '2023-10-31',
	@ProductCodes	= 'SB',
	@Environment	= 'PRO',
	@IsOverwrite	= 1

