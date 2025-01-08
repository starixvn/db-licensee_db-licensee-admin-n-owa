/*<info serverAlias="DBLIC-bodb_licenseeReport"></info>*/

/*
	Created: 20250106@Danny
	DB: DBLIC.bodb_licenseeReport
	Description: Run on Db052 only
*/

USE bodb_licenseeReport



GO

-- 18 rows
DELETE FROM rptLicPerformanceAnalysis WITH(ROWLOCK, UPDLOCK) WHERE SiteID IN (1,19, 63) AND ProductID = 10 AND ReportDate = '2022-07-01'


-- 18 rows
INSERT INTO rptLicPerformanceAnalysis(
ReportDate,	SiteId,	ProductId,	CurrencyId,	Turnover,	BetCount,	LicenseeWinloss,	LicensingFee,	Discount,	Rebate,	TurnoverNoDraw,	IsBillingCurrency,	Adjustment	
)

SELECT ReportDate,	SiteId,	ProductId,	CurrencyId,	Turnover,	BetCount,	LicenseeWinloss,	LicensingFee,	Discount,	Rebate,	TurnoverNoDraw,	IsBillingCurrency,	Adjustment	
FROM Db053.bodb_licenseeReport.dbo.rptLicPerformanceAnalysis with(nolock)   WHERE SiteID IN (1,19, 63) AND ProductID = 10 AND ReportDate = '2022-07-01'
		





