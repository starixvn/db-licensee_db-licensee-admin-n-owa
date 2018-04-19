/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].LA_Rpt_LicenseeWinLossByDynamicProduct
	@ProductIdString	VARCHAR(200),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(10) = 'EUR'
AS
/*	Header:
	Created: 2017.04.21 - Bruce
	Task : Get winloss report by dynamic product
	DB: DB052.bodb_Licensee

	Revisions:
		- 20170630@Bruce: include BT/CO/CB, remove LC, VG [RedmineID: #79309]
		- 20171205@Bruce: fix partyid length [#87723]
		- 20171220@Parsons: increase length for variables [#88197]
		- 20180131@Scofield: Add BX [#87754]
		- 20180419@Bruce: Implement Colossus Bets Freeplay(part 2) [#93907]
*/
BEGIN
	SET NOCOUNT ON

	SELECT * INTO #Exchange FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	DECLARE @Products TABLE(
		ProductId	INT,
		ProductCode	VARCHAR(20),
		ProductName	VARCHAR(100)
	)
	INSERT INTO @Products
	SELECT ProductID, ProductPrefix, ProductName
	FROM dbo.LA_f_Products3rd('')
	WHERE ProductID IN (SELECT val FROM dbo.strSplit(@ProductIdString, ','))

	CREATE TABLE #Parties (
		PartyId		INT,
		PartyName	VARCHAR(100),
		LicenseeId	INT
	)
	INSERT INTO #Parties(PartyId,PartyName,LicenseeId)
	(
		SELECT p.PartyId, p.PartyName, p.OldRefID
		FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID = d.PartyID
		WHERE d.IsDeposit = 1 AND p.PartyType = 1 AND p.OldRefID IS NOT NULL
	)

	DECLARE @PartyIds VARCHAR(4000) = (SELECT CAST(PartyId AS VARCHAR(10)) + ',' FROM #Parties FOR XML PATH (''))
	
	DECLARE @CreditLicenee TABLE(LicenseeId INT)
	INSERT INTO @CreditLicenee(LicenseeId)
	(
		SELECT LabelID
		FROM dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID=d.PartyID
		INNER JOIN dbo.Labels l WITH(NOLOCK) ON l.LicenseeID=p.OldRefID
		WHERE ISNULL(d.IsDeposit,0)=0 AND OldRefID IS NOT NULL
	)

	-- insert data to temp table
	SELECT b.rptDate														AS WinLossDate,
		b.SiteId															AS LicenseeId,
		b.ProductId															AS ProductId,
		ISNULL(sbr.BettypeRef, -1)											AS Bettype,
		CAST(SUM(ISNULL(b.MemberWL * e.BaseCurrencyRate, 0)) AS MONEY)		AS Winloss,
		CAST(SUM(ISNULL(b.GrossWL * e.BaseCurrencyRate, 0)) AS MONEY)		AS GrossWinLoss,
		CAST(SUM(ISNULL(b.CommissionA * e.BaseCurrencyRate, 0)) AS MONEY)	AS Commission,
		CAST(SUM(ISNULL(b.CommissionP * e.BaseCurrencyRate, 0)) AS MONEY)	AS CommissionP,
		CAST(0 AS MONEY)	AS ActualStake,
		CAST(0 AS MONEY)	AS BuyBackAmount,
		CAST(0 AS MONEY)	AS Turnover,
		CAST(0 AS MONEY)	AS CashOut,
		CAST(0 AS MONEY)	AS WinningPrize,
		CAST(0 AS MONEY)	AS BuyBackAmountBA,
		CAST(0 AS MONEY)	AS TicketsPayout
	INTO #Data
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH(NOLOCK)
	INNER JOIN #Exchange e ON e.ExchangeId = b.CurrencyId and e.exchangedate = b.rptDate
	LEFT JOIN dbo.Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.Bettype = b.Bettype
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate
		AND b.StatusId NOT IN (-1, 101, 102, 103)
		AND b.CurrencyID <> 20
		AND b.CustomerCategory NOT IN (27, 28)
		AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
		AND b.SiteID NOT IN (SELECT c.LicenseeId FROM @CreditLicenee c)
		AND b.ProductID IN (SELECT p.ProductId FROM @Products p)
		AND b.ProductID NOT IN (13,15,25) -- exclude BT, CB, CO
	GROUP BY b.rptdate, b.SiteId, b.ProductId, ISNULL(sbr.BettypeRef, -1)

	-- BT
	IF EXISTS (SELECT 1 FROM @Products WHERE ProductId=13)
	BEGIN
		INSERT INTO #Data(WinLossDate,LicenseeId,ProductId,Bettype,ActualStake,BuyBackAmount,Commission,Winloss)
		SELECT b.RptDate, b.SiteId, 13, -1
			, SUM(CASE WHEN b.Bettype = 901 THEN (b.BuyBackAmount - b.MemberWL)*e.BaseCurrencyRate ELSE 0 END)
			, SUM(CASE WHEN b.Bettype = 901 THEN b.BuyBackAmount*e.BaseCurrencyRate ELSE 0 END)
			, SUM(CASE WHEN b.Bettype = 901 AND b.CustomerCategory = 1001 THEN -b.BuyBackAmount*e.BaseCurrencyRate ELSE 0 END)
			, SUM(CASE WHEN b.ProductID <> 13 THEN b.MemberWL*e.BaseCurrencyRate ELSE 0 END)
		FROM bodb_licenseereport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN #Exchange e ON e.ExchangeId = b.CurrencyId and e.exchangedate = b.rptDate
		WHERE b.RptDate BETWEEN @FromDate AND @ToDate
			AND b.CurrencyID <> 20
			AND b.StatusId NOT IN (-1, 101, 102, 103)
			AND b.CustomerCategory IN (1001, 1002)
			AND b.ProductID IN (0, 3, 13) -- include original and Bettrade tickets
			AND b.SiteID NOT IN (SELECT c.LicenseeId FROM @CreditLicenee c)
		GROUP BY b.RptDate, b.SiteId
	END

	-- CB
	IF EXISTS (SELECT 1 FROM @Products WHERE ProductId=15)
	BEGIN
		INSERT INTO #Data(WinLossDate,LicenseeId,ProductId,Bettype,Turnover,ActualStake,WinningPrize,CashOut,BuyBackAmount)
		SELECT b.rptDate,b.SiteId,15,-1,
			SUM(Turnover * e.BaseCurrencyRate),
			SUM(CASE WHEN TicketType=0 THEN Turnover ELSE ISNULL(ExtraAmount,0) END * e.BaseCurrencyRate),
			SUM(ISNULL(WinPrizeAmount * e.BaseCurrencyRate,0)) ,
			SUM(ISNULL(CashOutAmount * e.BaseCurrencyRate,0)),
			SUM(ISNULL(BuyBackAmount * e.BaseCurrencyRate,0))
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN #Exchange e ON e.ExchangeID=b.CurrencyId AND e.ExchangeDate = b.rptDate
		WHERE b.ProductID = 15
			AND b.CustomerCategory NOT IN (27, 28)
			AND b.StatusId NOT IN (-1, 101, 102, 103)
			AND b.CurrencyId <> 20
			AND b.SiteID NOT IN (SELECT c.LicenseeId FROM @CreditLicenee c)
		GROUP BY b.rptDate, b.SiteId
	END

	-- CO
	IF EXISTS (SELECT 1 FROM @Products WHERE ProductId=25)
	BEGIN
		INSERT INTO #Data(WinLossDate,LicenseeId,ProductId,Bettype,BuyBackAmount,BuyBackAmountBA,TicketsPayout)
		SELECT b.Winlostdate,b.SiteId,25,-1,
			SUM(b.BuyBackAmt * e.BaseCurrencyRate),
			SUM(b.BABuyBackAmt * e.BaseCurrencyRate),
			SUM(b.TicketPayout * e.BaseCurrencyRate)
		FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)
			INNER JOIN #Exchange e ON e.ExchangeID=b.Currency AND e.ExchangeDate = b.Winlostdate
		WHERE b.Winlostdate BETWEEN @FromDate AND @ToDate									
			AND b.Currency <> 20
			AND b.RoleID = 1 -- Member
			AND b.SiteID NOT IN (SELECT c.LicenseeId FROM @CreditLicenee c) 
		GROUP BY b.Winlostdate,b.SiteId
	END

	-- get unknown parties
	INSERT INTO #Parties(PartyId, PartyName, LicenseeId)
	SELECT DISTINCT 0, 'Unknown-' + CAST(d.LicenseeId AS VARCHAR(10)), d.LicenseeId
	FROM #Data d
	WHERE d.LicenseeId NOT IN (SELECT LicenseeId FROM #Parties)

	-- remove duplicate
	INSERT #Parties
	SELECT DISTINCT -1, STUFF((SELECT '-' + p3.PartyName FROM #Parties p3 WHERE p3.LicenseeId=p1.LicenseeId FOR XML PATH('')), 1, 1, '') AS PartyName, p1.LicenseeId
	FROM #Parties p1
	WHERE p1.LicenseeId IN (
		SELECT p2.LicenseeId 
		FROM #Parties p2
		GROUP BY p2.LicenseeId HAVING COUNT(p2.LicenseeId)>1
	)
	DELETE #Parties WHERE LicenseeId IN (SELECT p.LicenseeId FROM #Parties p WHERE p.PartyId = -1) AND PartyId > 0

	-- parties: charge rates
	DECLARE @ProductCodes VARCHAR(500) = (SELECT ProductCode + ',' FROM @Products FOR XML PATH (''))
	SELECT c.ProductId			AS ProductId,
		c.LicenseeId			AS LicenseeId,
		ISNULL(b.Bettype, -1)	AS Bettype,
		c.DI_Rate				AS Rate,
		c.FromDate				AS FromDate,
		c.ToDate				AS ToDate,
		CASE WHEN c.ProductID=15 THEN ChargeType ELSE 1 END AS ChargeType
	INTO #ChargeRates
	FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) c
	LEFT JOIN dbo.Sport_Bettype_Reference b WITH(NOLOCK) ON b.BettypeRef = c.Bettype AND IsActive = 1
	WHERE c.DI_Rate > 0

	SELECT * FROM @Products
	SELECT * FROM #Parties
	SELECT * FROM #Chargerates
	SELECT * FROM #Data

	DROP TABLE #Data
	DROP TABLE #Chargerates
	DROP TABLE #Exchange
	DROP TABLE #Parties
END
GO

GRANT EXECUTE ON [dbo].LA_Rpt_LicenseeWinLossByDynamicProduct TO bodbAdminNet
GO