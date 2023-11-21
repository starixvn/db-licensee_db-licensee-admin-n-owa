/*<info serverAlias="DBLIC-bodb_licensee"></info>*/
/*
	Created: 20231121@Danny
	DB: DBLIC-bodb_Licensee
	Task: Insert Data 3rd products [#191813]
	-- Run DB053 only
*/
USE bodb_Licensee
GO

SET NOCOUNT ON 

DELETE FROM bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis_regen_UAT WITH(ROWLOCK)
WHERE ProductID = 0

INSERT INTO bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis_regen_UAT (
		ReportDate, SiteId, ProductId, CurrencyId, IsBillingCurrency
		,BetCount, Turnover, TurnoverNoDraw, LicenseeWinloss, LicensingFee, Discount, Rebate, Adjustment
		)
SELECT ReportDate, SiteId, ProductId, CurrencyId, IsBillingCurrency
		,BetCount, Turnover, TurnoverNoDraw, LicenseeWinloss, LicensingFee, Discount, Rebate, Adjustment
FROM bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis WITH(NOLOCK)
WHERE ReportDate >= '2020-01-01'


GO


