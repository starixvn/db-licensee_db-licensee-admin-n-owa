/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE dbo.LA_Rpt_LicPerformance_Alert
	@FromDate DATE,
	@ToDate DATE,
	@ProductCodes VARCHAR(500)
AS
/*	Created: 20181128@Parsons
	Task: LA-Licensee Performance Alert
	DB: DBLIC.bodb_licensee

	Revisions:
		- 20181128@Parsons: LA - Licensee Performance Alert [#104918]

	Param's Explanation:
	EXEC LA_Rpt_LicPerformance_Alert @FromDate = '2018-9-01', @ToDate = '2018-9-30', @ProductCodes = 'SB'
*/
BEGIN
	SET NOCOUNT ON;
	
	DECLARE @BaseCurrencyName VARCHAR(3) = 'EUR'
			,@PrevFromDate DATE = DATEADD(M, -1,  @FromDate)
			,@PrevToDate DATE = DATEADD(M, - 1, @ToDate)

	-- Region Get @Parties
	DECLARE @Parties TABLE(PartyId INT, PartyName VARCHAR(50), BrandName VARCHAR(50), ParentId INT)
	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC bodb_licensee.dbo.LA_PartyListSel

	DECLARE @PartyIds VARCHAR(4000) = (SELECT CAST(PartyId AS VARCHAR(10)) + ',' FROM @Parties WHERE ParentID NOT IN (0, 999) FOR XML PATH(''))
	-- Endregion Get @Parties

	-- Region Get charge info
	SELECT DISTINCT PartyID, LicenseeID, Fromdate, Todate, ProductID
	INTO #tmpChargeInfo
	FROM (
		SELECT PartyID, LicenseeID, Fromdate, Todate,DI_Rate,ChargeType,ProductID
		FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate,@ProductCodes,'OA',1)
		UNION ALL
		SELECT PartyID, LicenseeID, Fromdate, Todate,DI_Rate,ChargeType,ProductID
		FROM dbo.LA_f_ChargeInfo(@PartyIds, @PrevFromDate, @PrevToDate,@ProductCodes,'OA',1)
	) ci
	WHERE DI_Rate > 0 AND ChargeType = 1 -- Gross win only
	-- End region

	-- Region: Get exchange rate info
	-- *** Get Exchange info for @BaseCurrencyName in 2 periods (current period and previous period)
	-- *********************************************************************************************
	
	-- period 1
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	INTO #tmpExchange
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	-- period 2
	INSERT INTO #tmpExchange(ExchangeDate, ExchangeID, Code, BaseCurrencyRate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@PrevFromDate, @PrevToDate, @BaseCurrencyName)
	-- End region: Get exchange rate info
	
	-- Select Result	
	SELECT p.PartyId, p.PartyName,
		SUM((CASE WHEN MONTH(b.rptDate) = MONTH(@FromDate) THEN b.BetCount ELSE 0 END)) AS BetCount,
		SUM((CASE WHEN MONTH(b.rptDate) = MONTH(@FromDate) THEN 0 ELSE b.BetCount END)) AS PreviousBetCount,
		SUM((CASE WHEN MONTH(b.rptDate) = MONTH(@FromDate) THEN b.Turnover * e.BaseCurrencyRate ELSE 0 END)) AS Turnover,
		SUM((CASE WHEN MONTH(b.rptDate) = MONTH(@FromDate) THEN 0 ELSE b.Turnover * e.BaseCurrencyRate END)) AS PreviousTurnover
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
	INNER JOIN #tmpChargeInfo ci ON ci.LicenseeID = b.SiteID AND b.rptDate BETWEEN ci.Fromdate AND ci.Todate AND ci.ProductID=b.ProductID
	INNER JOIN @Parties p ON p.PartyId = ci.PartyID
	INNER JOIN #tmpExchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
	WHERE (b.rptDate BETWEEN @FromDate AND @ToDate OR b.rptDate BETWEEN @PrevFromDate AND @PrevToDate)
			AND b.customercategory NOT IN (27, 28)
			AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
	GROUP BY p.PartyId, p.PartyName

	DROP TABLE #tmpChargeInfo
	DROP TABLE #tmpExchange
END
GO