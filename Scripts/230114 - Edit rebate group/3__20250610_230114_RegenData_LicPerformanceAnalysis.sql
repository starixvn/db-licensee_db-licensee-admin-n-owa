/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/

/*
	Created: 20250610@Danny
	DB: DBLIC.bodb_licenseeReport
	Description: regen LicPerformanceAnalysis data
*/

USE bodb_licenseeReport



EXEC dbo.LA_GEN_LicPerformanceAnalysis_Report
	@FromDate		= '2025-03-01',
	@ToDate			= '2025-03-31',
	@Environment	= 'PRO',
	@PartyIds		= '852,506,1064,1122' 
		

EXEC dbo.LA_GEN_LicPerformanceAnalysis_Report
	@FromDate		= '2025-04-01',
	@ToDate			= '2025-04-30',
	@Environment	= 'PRO',
	@PartyIds		= '1276' 
		


EXEC dbo.LA_GEN_LicPerformanceAnalysis_Report
	@FromDate		= '2025-05-01',
	@ToDate			= '2025-05-31',
	@Environment	= 'PRO',
	@PartyIds		= '1296' 
		

