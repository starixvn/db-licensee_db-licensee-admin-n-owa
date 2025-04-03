/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[SH_Rpt_SabaPlayLicenseeSettlement]
	@OperatorID			INT
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@ProductIDs		VARCHAR(MAX)
	,@BaseCurrencyName	VARCHAR(10)		= 'GBP'
AS
/*  Created: 20250403@Danny
	Task : Report - SabaPlay Licensee Settlement Report
	DB: DBLIC.bodb_licensee
		
	Revisions:
		- 20250403@Danny: create new sp
	
	Param's Explanation:

	EXEC LA_Rpt_SabaPlayLicenseeSettlement @OperatorID = 721, @FromDate = '2025-02-01', @ToDate = '2025-02-28', @ProductIDs = '1,3', @BaseCurrencyName = 'EUR'
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE = @FromDate, @TDate DATE = @ToDate

	DECLARE @tmp_Product TABLE (ProductID INT)
	INSERT INTO @tmp_Product(ProductID)
	SELECT CAST(value AS INT) FROM STRING_SPLIT(@ProductIDs,',')

	DROP TABLE IF EXISTS #Exchange
	CREATE TABLE #Exchange
	(
		ExchangeDate			DATE,
		ExchangeId				INT,
		CurrencyCode			VARCHAR(65),
		Rate					FLOAT,
		BaseExchangeRate		FLOAT
	)
	INSERT INTO #Exchange(ExchangeDate, ExchangeId, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeId, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)



	SELECT @ToDate AS WinLostDate,
		    ex.CurrencyCode AS CurrencyName,
			ex.Rate			AS ExchangeRate,
			sp.ProductID    AS ProductID,
			sp.ProductName  AS ProductName,
			sp.LicenseeChargeRate AS LicenseeChargeRate,

			SUM(ISNULL(sp.BetCount,0)) AS Betcount,
			SUM(ISNULL(sp.MemberWinLoss,0)) AS GrossWin_CustomerWinloss,
			SUM(ISNULL(sp.LicenseeContribution,0)) AS GrossWin_Contribution,
			SUM(ISNULL(sp.LicenseeGrossWin,0)) AS GrossWin_Total,
			SUM(ISNULL(sp.LicenseeWinLoss,0)) AS LicenseeWinLoss,

			SUM(ISNULL(sp.LicenseeGrossWinAfterChargeRate,0)) AS GrossWin_ChargeRate,
			SUM(ISNULL(sp.LicenseeContribution,0)) AS LicenseeContribution,
			SUM(ISNULL(sp.LicenseeJackpot,0)) AS LicenseeJackpot,
			SUM(ISNULL(sp.LicenseePromotion,0)) AS LicenseePrommotion,
			SUM(ISNULL(sp.FinalLicensingFee,0)) AS LicenseeTotal,
			SUM(ISNULL(sp.FinalLicensingFee,0) * ex.Rate) AS Equivalent,

			SUM(ISNULL(sp.MemberWinLoss,0) * ex.Rate) AS GrossWin_CustomerWinlossBase,
			SUM(ISNULL(sp.LicenseeContribution,0) * ex.Rate) AS GrossWin_ContributionBase,
			SUM(ISNULL(sp.LicenseeGrossWin,0) * ex.Rate) AS GrossWin_TotalBase,
			SUM(ISNULL(sp.LicenseeWinLoss,0) * ex.Rate) AS LicenseeWinLossBase,

			SUM(ISNULL(sp.LicenseeGrossWinAfterChargeRate,0) * ex.Rate) AS GrossWin_ChargeRateBase,
			SUM(ISNULL(sp.LicenseeContribution,0) * ex.Rate) AS LicenseeContributionBase,
			SUM(ISNULL(sp.LicenseeJackpot,0) * ex.Rate) AS LicenseeJackpotBase,
			SUM(ISNULL(sp.LicenseePromotion,0) * ex.Rate) AS LicenseePrommotionBase,
			SUM(ISNULL(sp.FinalLicensingFee,0) * ex.Rate) AS LicenseeTotalBase

	FROM bodb_LicenseeReport.dbo.SabaPlayPerformance sp WITH(NOLOCK)
	INNER JOIN @tmp_Product p ON sp.ProductID = p.ProductID
	CROSS APPLY
	(	SELECT TOP 1 e.CurrencyCode, e.Rate
		FROM #Exchange e WHERE sp.RptDate = e.ExchangeDate AND sp.CurrencyCode = e.CurrencyCode
	 ) ex

	WHERE sp.DataType = 2 AND sp.RptDate = @TDate AND SiteID = @OperatorID
	GROUP BY  ex.CurrencyCode, ex.Rate, sp.ProductID, sp.ProductName, sp.LicenseeChargeRate
	ORDER BY sp.ProductID, sp.ProductName, sp.LicenseeChargeRate,  ex.CurrencyCode

END
GO
