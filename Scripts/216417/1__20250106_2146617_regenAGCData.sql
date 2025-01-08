/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/

/*
	Created: 20250106@Danny
	DB: DBLIC.bodb_licenseeReport
	Description: regen AGC data
*/

USE bodb_licenseeReport

DECLARE	@FromDate   DATE = '2024-09-01' 
	,@ToDate		DATE = '2024-09-30'
	,@RowNumber 	INT
	,@MaxRow 	    INT
	,@PartyIds		VARCHAR(MAX) = 14

BEGIN
	EXEC dbo.LA_GEN_LicPerformanceAnalysis_Report
		@FromDate		= @FromDate,
		@ToDate			= @ToDate,
		@Environment	= 'PRO',
		@PartyIds		= @PartyIds
		
END	





