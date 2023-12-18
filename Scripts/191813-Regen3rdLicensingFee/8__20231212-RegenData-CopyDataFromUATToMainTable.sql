/*<info serverAlias="DBLIC-bodb_licensee"></info>*/
/*
	Created: 20231121@Danny
	DB: DBLIC-bodb_LicenseeReport
	Task: Insert Data 3rd products [#191813]
	-- Run DB053, DB052 only
*/
USE bodb_LicenseeReport
GO

SET NOCOUNT ON 

-- Regen data using exec SP
DECLARE 
	@FromDate		DATE = '2020-01-01'


WHILE @FromDate <= '2023-11-01'
BEGIN
	print 'running -----: ' + CAST (@FromDate AS VARCHAR(50))

	DELETE FROM rptLicPerformanceAnalysis WITH(ROWLOCK, UPDLOCK) WHERE ReportDate = @FromDate
	
	INSERT INTO rptLicPerformanceAnalysis 
	(
		[ReportDate],
		[SiteId] ,
		[ProductId],
		[CurrencyId],
		[Turnover],
		[BetCount],
		[LicenseeWinloss],
		[LicensingFee],
		[Discount],
		[Rebate],
		[TurnoverNoDraw],
		[IsBillingCurrency],
		[Adjustment]
	)
	SELECT
		[ReportDate],
		[SiteId] ,
		[ProductId],
		[CurrencyId],
		[Turnover],
		[BetCount],
		[LicenseeWinloss],
		[LicensingFee],
		[Discount],
		[Rebate],
		[TurnoverNoDraw],
		[IsBillingCurrency],
		[Adjustment]
	FROM rptLicPerformanceAnalysis_regen_UAT WITH(NOLOCK)
	WHERE ReportDate = @FromDate

	SELECT @FromDate = DATEADD(MONTH,1,@FromDate)
END

GO


