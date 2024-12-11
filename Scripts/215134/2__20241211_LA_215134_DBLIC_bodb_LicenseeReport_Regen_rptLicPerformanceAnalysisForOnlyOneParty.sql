/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/
/*
	Created: 20241211@Danny
	DB: DBLIC.bodb_licenseeReport
	Task: Support Odds Boost Voucher [#215134]
	- Regen data partyId 1185 table rptLicPerformanceAnalysis 
*/
USE bodb_licenseeReport
GO

	DECLARE	@FromDate   DATE = '2024-11-01' 
		,@ToDate		DATE = '2024-11-30'
		,@RowNumber 	INT
		,@MaxRow 	    INT
		,@PartyIds		VARCHAR(MAX) = 1185

	BEGIN
		EXEC dbo.LA_GEN_LicPerformanceAnalysis_Report
			@FromDate		= @FromDate,
			@ToDate			= @ToDate,
			@Environment	= 'PRO',
			@PartyIds		= @PartyIds
		
	END	

