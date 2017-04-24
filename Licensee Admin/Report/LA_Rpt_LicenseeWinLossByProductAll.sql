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
	FROM dbo.OAS_Party p WITH(NOLOCK)
	INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID = d.PartyID
	WHERE d.IsDeposit = 1 AND p.PartyType = 1 AND p.OldRefID IS NOT NULL

	DECLARE @ProductCodes VARCHAR(500) = (SELECT ProductCode + ',' FROM @Products FOR XML PATH (''))
	DECLARE @PartyIds VARCHAR(2000) = (SELECT CAST(PartyId AS VARCHAR(10)) + ',' FROM @Parties FOR XML PATH (''))

	-- insert data to temp table
	;WITH CreditLicensees AS (
		SELECT LabelID
		FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID=d.PartyID
		INNER JOIN dbo.Labels l WITH(NOLOCK) ON l.LicenseeID=p.OldRefID
		WHERE ISNULL(d.IsDeposit,0)=0 AND OldRefID IS NOT NULL
	)
	SELECT b.rptDate										AS WinLossDate,
		b.SiteId											AS LicenseeId,
		b.ProductId											AS ProductId,
		b.BetType											AS Bettype,
		b.CurrencyId										AS CurrencyId,
		SUM(ISNULL(b.MemberWL * e.BaseCurrencyRate, 0))		AS Winloss,
		SUM(ISNULL(b.GrossWL * e.BaseCurrencyRate, 0))		AS GrossWinLoss,
		SUM(ISNULL(b.CommissionA * e.BaseCurrencyRate, 0))	AS Commission,
		SUM(b.Turnover)										AS Turnover,
		SUM(b.BetCount)										AS BetCount
	INTO #Data
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH(NOLOCK)
	INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName) e ON e.ExchangeId = b.CurrencyId
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate
		AND b.StatusId NOT IN (-1, 101, 102, 103)
		AND b.CurrencyID <> 20
		AND b.CustomerCategory NOT IN (27, 28)
		AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
		AND b.SiteID NOT IN (SELECT LabelID FROM CreditLicensees)
		AND b.ProductID IN (SELECT p.ProductId FROM @Products p)
	GROUP BY b.rptdate, b.SiteId, b.CurrencyID, b.ProductId, b.BetType

	-- get unkown parties
	INSERT INTO @Parties
	SELECT DISTINCT 0, 'Unknown-' + CAST(d.LicenseeId AS VARCHAR(10)), d.LicenseeId
	FROM #Data d
	WHERE d.LicenseeId NOT IN (SELECT LicenseeId FROM @Parties)

	-- remove duplicate
	INSERT @Parties
	SELECT DISTINCT 0, STUFF((SELECT '-' + p3.PartyName FROM @Parties p3 WHERE p3.LicenseeId=p1.LicenseeId FOR XML PATH('')), 1, 1, '') AS PartyName, p1.LicenseeId
	FROM @Parties p1
	WHERE p1.LicenseeId IN (
		SELECT p2.LicenseeId 
		FROM @Parties p2
		GROUP BY p2.LicenseeId HAVING COUNT(p2.LicenseeId)>1
	)
	DELETE @Parties WHERE LicenseeId IN (SELECT p.LicenseeId FROM @Parties p WHERE p.PartyId = 0) AND PartyId > 0

	-- parties: charge rates
	SELECT c.ProductId				AS ProductId,
		c.LicenseeId			AS LicenseeId,
		ISNULL(b.Bettype, -1)	AS Bettype,
		c.DI_Rate				AS Rate,
		c.FromDate				AS FromDate,
		c.ToDate				AS ToDate,
		CAST(1 AS BIT)			AS IsOriginal
	INTO #ChargeRates
	FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) c
	LEFT JOIN dbo.Sport_Bettype_Reference b WITH(NOLOCK) ON b.BettypeRef = c.Bettype AND IsActive = 1

	INSERT INTO #ChargeRates
	SELECT pp.ProductId			AS ProductId,
		p.LicenseeId			AS LicenseeId,
		ISNULL(b.Bettype, -1)	AS Bettype,
		CAST(1 AS DECIMAL)		AS Rate,
		@FromDate				AS FromDate,
		@ToDate					AS ToDate,
		0						AS IsOriginal
	FROM @Parties p
	INNER JOIN @Products pp ON 1=1
	LEFT JOIN dbo.LA_Product3rdSub ps WITH(NOLOCK) ON ps.Productid = pp.ProductId
	LEFT JOIN dbo.Sport_Bettype_Reference b WITH(NOLOCK) ON b.BettypeRef = ISNULL(ps.BettypeRef, -1) AND b.IsActive = 1
	WHERE p.LicenseeId IN (SELECT d.LicenseeId FROM #Data d)

	SELECT * FROM @Products
	SELECT * FROM @Parties
	SELECT * FROM #Chargerates
	SELECT * FROM #Data

	DROP TABLE #Data
	DROP TABLE #Chargerates
END
GO

GRANT EXECUTE ON [dbo].LA_Rpt_LicenseeWinLossByProductAll TO bodbAdminNet
GO