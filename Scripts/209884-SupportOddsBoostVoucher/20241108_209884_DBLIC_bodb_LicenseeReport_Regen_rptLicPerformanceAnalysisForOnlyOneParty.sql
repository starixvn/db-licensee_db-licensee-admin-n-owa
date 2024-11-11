/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/
/*
	Created: 20241106@Sally
	DB: DBLIC.bodb_licenseeReport
	Task: Support Odds Boost Voucher [#209884]
	- Regen data partyId 1039 table rptLicPerformanceAnalysis 
*/
USE bodb_licenseeReport
GO

	DECLARE	@FromDate   DATE = '2024-07-01' 
		,@ToDate		DATE = '2024-07-31'
		,@RowNumber 	INT
		,@MaxRow 	    INT
		,@PartyIds		VARCHAR(MAX) = 1039

	BEGIN
		EXEC dbo.LA_GEN_LicPerformanceAnalysis_Report
			@FromDate		= @FromDate,
			@ToDate			= @ToDate,
			@Environment	= 'PRO',
			@PartyIds		= @PartyIds
		
	END	

