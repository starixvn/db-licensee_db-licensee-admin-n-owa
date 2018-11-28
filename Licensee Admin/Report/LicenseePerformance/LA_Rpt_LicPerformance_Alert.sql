/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/

USE [bodb02]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE dbo.LA_Rpt_LicPerformance_Alert
	@FromDate DATE,
	@ToDate DATE
AS
/*	Created: 20181128@Parsons
	Task: LA-Licensee Performance Alert
	DB: DB052.bodb02

	Revisions:
		- 20181128@Parsons: LA - Licensee Performance Alert [#104918]

	Param's Explanation:
	EXEC LA_Rpt_LicPerformance_Alert @FromDate = '2018-11-01', @ToDate = '2018-11-30'
*/

BEGIN
	SET NOCOUNT ON;
	
	DECLARE @BaseCurrencyName VARCHAR(3) = 'EUR',
			@ProductCodes VARCHAR(2) = 'SB', 
			@PrevFromDate DATE = DATEADD(M, -1,  @FromDate)
			,@PrevToDate DATE = DATEADD(M, - 1, @ToDate)

	-- Region Get @PartyIDs
	DECLARE @Parties TABLE(PartyId INT, PartyName VARCHAR(50), BrandName VARCHAR(50), ParentId INT)
	INSERT INTO @Parties (PartyId, PartyName, BrandName, ParentId)
	EXEC bodb_licensee.dbo.LA_PartyListSel

	DECLARE @PartyIDs VARCHAR(4000)
	SELECT @PartyIDs = COALESCE(@PartyIDs + ', ', '') + CAST(PartyId AS VARCHAR)
	FROM @Parties  
	WHERE ParentId in (1, 9, 11, 98)

	-- Endregion Get @PartyIDs

	-- Region: Party charge info
	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			Rate		DECIMAL(7,5),
			FromDate	DATE,
			ToDate		DATE)

	-- ***********************************************************************************************
	-- *** Get ChargeInfo for @PartyIDs in 2 period: FromDate-ToDate, PreviousFromDate-PreviousToDate
	-- ***********************************************************************************************
	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
	(
		SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
	)
	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
	(
		SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @PrevFromDate, @PrevToDate, @ProductCodes, 'OA', 1) ci
	)
	-- End region

	-- **********************************************************************************************
	-- *** Get Exchange info for @BaseCurrencyName in 2 periods (current period and previous period)
	-- **********************************************************************************************
	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange (
			ExchangeDate	DATE,
			ExchangeID		INT,
			CurrencyCode	VARCHAR(10),
			Rate			FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@PrevFromDate, @PrevToDate, @BaseCurrencyName)

	CREATE NONCLUSTERED INDEX Idx_Exchange ON #Exchange (ExchangeDate, ExchangeID)
	-- End region
	
	-- Region: Select Data	
	;WITH cte_Data AS
	(
		SELECT	p.PartyId,
				b.rptDate,
				SUM(b.BetCount) AS BetCount,
				SUM(ISNULL(b.Turnover, 0) * e.Rate) AS Turnover
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
		WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate OR b.rptDate BETWEEN @PrevFromDate AND @PrevToDate)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
		GROUP BY p.PartyId, b.rptDate
	)
	SELECT	d.PartyId,
			(CASE p.PartyName WHEN '18bb' THEN 'PIH' WHEN 'IBC' THEN 'FDL' ELSE p.PartyName END) AS PartyName,
			SUM((CASE WHEN MONTH(d.rptDate) = MONTH(@FromDate) THEN d.BetCount ELSE 0 END)) AS BetCount,
			SUM((CASE WHEN MONTH(d.rptDate) = MONTH(@FromDate) THEN 0 ELSE d.BetCount END)) AS PreviousBetCount,
			SUM((CASE WHEN MONTH(d.rptDate) = MONTH(@FromDate) THEN d.Turnover ELSE 0 END)) AS Turnover,
			SUM((CASE WHEN MONTH(d.rptDate) = MONTH(@FromDate) THEN 0 ELSE d.Turnover END)) AS PreviousTurnover
	FROM	cte_Data d
	INNER JOIN bodb_licensee.dbo.OAS_Party (NOLOCK) p ON d.PartyId = p.PartyID
	GROUP BY d.PartyId, (CASE p.PartyName WHEN '18bb' THEN 'PIH' WHEN 'IBC' THEN 'FDL' ELSE p.PartyName END)
	-- End region

	DROP TABLE #Exchange
END
GO