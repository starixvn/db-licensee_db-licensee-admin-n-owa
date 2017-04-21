USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].LA_Rpt_LicenseeWinLossByProductAll
	@ProductIdString	VARCHAR(200),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(10) = 'EUR'
AS
/*	Header:
	Created: 2017.04.21 - Bruce
	Task : Get winloss report by all product
	DB: DB052.bodb_Licensee
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @Products TABLE(
		ProductId	INT,
		ProductCode	VARCHAR(20),
		ProductName	VARCHAR(100)
	)
	INSERT INTO @Products
	SELECT ProductID, ProductPrefix, ProductName
	FROM dbo.LA_f_Products3rd('')
	WHERE ProductID IN (SELECT val FROM dbo.strSplit(@ProductIdString, ','))

	DECLARE @Parties TABLE(
		PartyId		INT,
		PartyName	VARCHAR(100),
		LicenseeId	INT
	)
	INSERT INTO @Parties
	SELECT p.PartyId, p.PartyName, p.OldRefID
	FROM dbo.OAS_Party p
	INNER JOIN dbo.OAS_PartyDetail d ON p.PartyID = d.PartyID
	WHERE d.IsDeposit = 1 AND p.PartyType = 1 AND p.OldRefID IS NOT NULL

	DECLARE @ProductCodes VARCHAR(500) = (SELECT ProductCode + ',' FROM @Products FOR XML PATH (''))
	DECLARE @PartyIds VARCHAR(2000) = (SELECT CAST(PartyId AS VARCHAR(10)) + ',' FROM @Parties FOR XML PATH (''))

	-- insert data to temp table
	SELECT b.rptDate										AS WinLossDate,
		b.SiteId											AS SiteId,
		b.ProductId											AS ProductId,
		b.BetType											AS BetType,
		b.CurrencyId										AS CurrencyId,
		SUM(ISNULL(b.MemberWL * e.BaseCurrencyRate, 0))		AS Winloss,
		SUM(ISNULL(b.GrossWL * e.BaseCurrencyRate, 0))		AS GrossWinLoss,
		SUM(ISNULL(b.CommissionA * e.BaseCurrencyRate, 0))	AS Commission,
		SUM(b.Turnover)										AS Turnover,
		SUM(b.BetCount)										AS BetCount
	INTO #Data
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b
	INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName) e ON e.ExchangeId = b.CurrencyId
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate
		AND b.StatusId NOT IN (-1, 101, 102, 103)
		AND b.CurrencyID <> 20
		AND b.CustomerCategory NOT IN (27, 28)
		AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
	GROUP BY b.rptdate, b.SiteId, b.CurrencyID, b.ProductId, b.BetType

	-- get unkown parties
	INSERT INTO @Parties
	SELECT 5000 + d.SiteId, 'Unknown-' + CAST(d.SiteId AS VARCHAR(10)), d.SiteId
	FROM #Data d
	WHERE d.SiteId NOT IN (SELECT LicenseeId FROM @Parties)

	-- parties: default chargerate settings
	SELECT p.PartyId			AS PartyId,
		pp.ProductId			AS ProductId,
		p.LicenseeId			AS LicenseeId,
		ISNULL(b.Bettype, -1)	AS Bettype,
		CAST(1 AS DECIMAL)		AS Rate,
		@FromDate				AS FromDate,
		@ToDate					AS ToDate
	FROM @Parties p
	INNER JOIN @Products pp ON 1=1
	LEFT JOIN dbo.LA_Product3rdSub ps ON ps.Productid = pp.ProductId
	LEFT JOIN dbo.Sport_Bettype_Reference b ON b.BettypeRef = ISNULL(ps.BettypeRef, -1) AND b.IsActive = 1

	-- parties: charge rates
	SELECT c.PartyId			AS PartyId,
		c.ProductId				AS ProductId,
		c.LicenseeId			AS LicenseeId,
		ISNULL(b.Bettype, -1)	AS Bettype,
		c.DI_Rate				AS Rate,
		c.FromDate				AS FromDate,
		c.ToDate				AS ToDate
	FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) c
	LEFT JOIN dbo.Sport_Bettype_Reference b ON b.BettypeRef = c.Bettype AND IsActive = 1

	SELECT * FROM #Data

	DROP TABLE #Data
END
GO

GRANT EXECUTE ON [dbo].LA_Rpt_LicenseeWinLossByProductAll TO bodbAdminNet
GO