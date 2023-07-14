/*<info serverAlias="DBLIC-bodb_LicenseeReport"></info>*/
/*
	Created: 20230620@Danny
	DB: DBLIC-bodb_LicenseeReport
	Task: Insert Data Saba Promotion
	ProductId = 37
*/
USE bodb_LicenseeReport
GO

SET NOCOUNT ON 

--UPDATE w
--SET w.IsBillingCurrency = x.IsBillingCurrency
--FROM rptLicPerformanceAnalysis_regen_UAT w WITH(ROWLOCK)
--INNER JOIN dbo.rptLicPerformanceAnalysis x WITH(NOLOCK) ON w.SiteID = x.SiteID AND w.reportDate = x.ReportDate AND w.CurrencyID = x.CurrencyId AND x.ProductId = 0

--UPDATE rptLicPerformanceAnalysis_regen_UAT  WITH(ROWLOCK)
--SET Turnover = ISNULL(Turnover,0),
--	TurnoverNoDraw = ISNULL(TurnoverNoDraw,0),
--	BetCount = ISNULL(BetCount,0),
--	LicenseeWinloss = ISNULL(LicenseeWinloss,0),
--	Discount = ISNULL(Discount,0),
--	Adjustment = ISNULL(Adjustment,0)


--UPDATE rptLicPerformanceAnalysis_regen_UAT  WITH(ROWLOCK)
--SET Rebate = ISNULL(Rebate,0)


--INSERT INTO rptLicPerformanceAnalysis (ReportDate, SiteId, ProductId, CurrencyId, LicensingFee, IsBillingCurrency)
--SELECT ReportDate, SiteId, ProductId, CurrencyId, LicensingFee, IsBillingCurrency FROM rptLicPerformanceAnalysis_regen_UAT WITH(NOLOCK)

--INSERT INTO rptLicPerformanceAnalysis_regen_UAT (ReportDate, SiteID, ProductId,  CurrencyID, Turnover, BetCount, LicenseeWinloss, LicensingFee, Discount, Rebate, TurnoverNoDraw, IsBillingCurrency, Adjustment)
--SELECT DISTINCT ReportDate, SiteID, ProductId, 142 AS CurrencyID, 0 AS Turnover, 0 AS Betcount, 0 AS LicenseeWinloss, 0 as LicensingFee,
--    0 AS Discount, 0 AS Rebate, 0 AS TurnoverNoDraw, 0 AS IsBillingCurrency, 0 AS Adjustment
--from rptLicPerformanceAnalysis_regen_UAT with(nolock) where ProductId = 37


-- Import data
-- ProductID = 37 ( Insert new)

IF @@SERVERNAME = 'DB053'
BEGIN
	INSERT INTO rptLicPerformanceAnalysis(ReportDate, SiteID, ProductId,  CurrencyID, Turnover, BetCount, LicenseeWinloss, LicensingFee, Discount, Rebate, TurnoverNoDraw, IsBillingCurrency, Adjustment)
	SELECT  ReportDate, SiteID, ProductId,  CurrencyID, Turnover, BetCount, LicenseeWinloss, LicensingFee, Discount, Rebate, TurnoverNoDraw, IsBillingCurrency, Adjustment 
	FROM rptLicPerformanceAnalysis_regen_UAT WITH(NOLOCK)
	WHERE ProductId = 37


	-- ProductID = 74 (Update LicensingFee value)
	UPDATE  r
	SET r.LicensingFee = t.LicensingFee
	FROM rptLicPerformanceAnalysis r WITH(ROWLOCK)
	INNER JOIN rptLicPerformanceAnalysis_regen_UAT t WITH(NOLOCK) 
		ON r.ReportDate = t.ReportDate 
			AND r.SiteID = t.SiteID 
			AND r.CurrencyID = t.CurrencyID 
			AND r.ProductId = t.ProductId
	WHERE r.ProductId = 74

END

IF @@SERVERNAME = 'DB052'
BEGIN
	INSERT INTO rptLicPerformanceAnalysis(ReportDate, SiteID, ProductId,  CurrencyID, Turnover, BetCount, LicenseeWinloss, LicensingFee, Discount, Rebate, TurnoverNoDraw, IsBillingCurrency, Adjustment)
	SELECT  ReportDate, SiteID, ProductId,  CurrencyID, Turnover, BetCount, LicenseeWinloss, LicensingFee, Discount, Rebate, TurnoverNoDraw, IsBillingCurrency, Adjustment 
	FROM DB053.bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis_regen_UAT WITH(NOLOCK)
	WHERE ProductId = 37


	-- ProductID = 74 (Update LicensingFee value)
	UPDATE  r
	SET r.LicensingFee = t.LicensingFee
	FROM rptLicPerformanceAnalysis r WITH(ROWLOCK)
	INNER JOIN DB053.bodb_LicenseeReport.dbo.rptLicPerformanceAnalysis_regen_UAT t WITH(NOLOCK) 
		ON r.ReportDate = t.ReportDate 
			AND r.SiteID = t.SiteID 
			AND r.CurrencyID = t.CurrencyID 
			AND r.ProductId = t.ProductId
	WHERE r.ProductId = 74

END