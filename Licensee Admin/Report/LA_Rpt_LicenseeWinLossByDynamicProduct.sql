/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeWinLossByDynamicProduct]
	@ProductIdString	VARCHAR(MAX),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(10) = 'EUR'
AS
/*	Header:
	Created: 2017.04.21 - Bruce
	Task : Get winloss report by dynamic product
	DB: DBLIC-bodb_Licensee

	Revisions:
		- 20170630@Bruce: include BT/CO/CB, remove LC, VG [RedmineID: #79309]
		- 20171205@Bruce: fix partyid length [#87723]
		- 20171220@Parsons: increase length for variables [#88197]
		- 20180131@Scofield: Add BX [#87754]
		- 20180419@Bruce: Implement Colossus Bets Freeplay(part 2) [#93907]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20181119@bruce: Integrate Bidme games (GD product) [#103695]
	    - 20190322@Parsons: Integrate-PP-Promotion-Prize [#109014]
	    - 20191205@Mason: PP tournament [#123958]
	    - 20200409@Parsons: Integrate SA Gaming [#129276]
	    - 20200820@Happy: Implement PP JP Changes In Reports Phase 2 [#139055]
	    - 20201026@Happy: Arcadia Gaming Add Bonus [#143597]
	    - 20201118@Happy: Changing OddsSpread for licensee [#142345]
	    - 20201209@Happy: Saba.club - Offer Freebet tickets [#141423]
	    - 20210108@Happy: Saba.club - Integrate Slot Game [#147977]
		- 20210712@Danny: Vgaming - Free bets and Jackpot prize integration [#156185]
		- 20210812@Percy: Integrate Bitcoin - apply core function GroupProduct [RedmineID: #159691]
		- 20211026@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
		- 20220110@Danny: SG - Jackpot prize integration [#167089]
*/

BEGIN
	SET NOCOUNT ON
	
	DECLARE @GD_Tip				SMALLINT = 1706,
			@PP_Contribution	SMALLINT = 4297,
			@SBC_Contribution	SMALLINT = 1698,
			@VGA_Contribution	SMALLINT = 3898,
			@SG_Contribution	SMALLINT = 4599

	SELECT * INTO #Exchange FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	DECLARE @Products TABLE (GroupProductId INT, ProductId INT, ProductCode VARCHAR(20), ProductName VARCHAR(100))
	INSERT INTO @Products (GroupProductId, ProductId, ProductCode, ProductName)
	SELECT	GroupProductId,ProductId,ProductCode, ProductName 
	FROM	dbo.LA_f_GroupProduct('',@FromDate,@ToDate)
	WHERE	GroupProductId IN (select CAST(x.val AS INT) AS ProductId FROM strSplit(@ProductIdString,',') x)

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
		p.GroupProductId													AS ProductId,
		CASE
			WHEN b.Bettype = @GD_Tip THEN b.Bettype
			ELSE ISNULL(sbr.BettypeRef, -1)
		END																	AS Bettype, 
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
		CAST(0 AS MONEY)	AS TicketsPayout,
		CAST(0 AS MONEY)    AS Contribution
	INTO #Data
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH(NOLOCK)
	INNER JOIN @Products p ON b.ProductId = p.ProductId
	INNER JOIN #Exchange e ON e.ExchangeId = b.CurrencyId and e.exchangedate = b.rptDate
	LEFT JOIN dbo.Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.Bettype = b.Bettype
	LEFT JOIN LA_f_ExcludedBettypeListSel('','999') eb ON b.Bettype = eb.BettypeID
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate
		AND b.StatusId NOT IN (-1, 101, 102, 103)
		AND b.CurrencyID <> 20
		AND b.CustomerCategory NOT IN (27, 28)
		AND eb.BettypeID IS NULL
		AND b.SiteID NOT IN (SELECT c.LicenseeId FROM @CreditLicenee c)
		AND b.ProductID NOT IN (13,15,25,32,42, 66, 36) -- exclude BT, CB, CO, PP, SBC
	GROUP BY b.rptdate, b.SiteId, p.GroupProductId, 
		CASE WHEN b.Bettype = @GD_Tip THEN b.Bettype
			 ELSE ISNULL(sbr.BettypeRef, -1)
		END

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
			SUM(CASE WHEN ISNULL(TicketType,0)=0 THEN Turnover ELSE ISNULL(ExtraAmount,0) END * e.BaseCurrencyRate),
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

	-- PP and SBC and VGA
	IF EXISTS (SELECT TOP 1 1 FROM @Products WHERE ProductId IN (32, 42, 66, 36))
	BEGIN
		INSERT INTO #Data(WinLossDate,LicenseeId,ProductId,Bettype,Winloss,Contribution)
		SELECT b.rptDate, b.SiteId, b.ProductId, -1, 
		CAST(SUM((CASE WHEN b.Bettype IN (@PP_Contribution, @SBC_Contribution, @VGA_Contribution, @SG_Contribution) THEN 0 ELSE ISNULL(b.MemberWL, 0) END) * e.BaseCurrencyRate) AS MONEY),
		CAST(SUM((CASE WHEN b.Bettype IN (@PP_Contribution, @SBC_Contribution, @VGA_Contribution, @SG_Contribution) THEN ISNULL(-b.GrossWL, 0) ELSE 0 END) * e.BaseCurrencyRate) AS MONEY)
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH(NOLOCK)
		INNER JOIN #Exchange e ON e.ExchangeId = b.CurrencyId and e.exchangedate = b.rptDate
		LEFT JOIN LA_f_ExcludedBettypeListSel('','4297,1698,3898,4599') eb ON b.Bettype = eb.BettypeID
		INNER JOIN @Products p ON p.ProductId = b.ProductID AND p.ProductId IN (32, 42, 66, 36)
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.StatusId NOT IN (-1, 101, 102, 103)
			AND b.CurrencyID <> 20
			AND b.CustomerCategory NOT IN (27, 28)
			AND eb.BettypeID IS NULL
			AND ISNULL(b.TicketType, 0) <> 2 --Free_Bets_TicketType
		GROUP BY b.rptDate, b.SiteId, b.ProductId
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
		CASE WHEN c.ProductId = 11 AND ChargeType = 12 THEN @GD_Tip ELSE ISNULL(b.Bettype, -1) END AS Bettype,
		c.DI_Rate				AS Rate,
		c.FromDate				AS FromDate,
		c.ToDate				AS ToDate,
		CASE WHEN c.ProductID =15 THEN ChargeType ELSE 1 END AS ChargeType
	INTO #ChargeRates
	FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) c
	LEFT JOIN dbo.Sport_Bettype_Reference b WITH(NOLOCK) ON b.BettypeRef = c.Bettype AND IsActive = 1
	WHERE c.DI_Rate > 0

	SELECT ProductId, ProductCode, ProductName FROM @Products WHERE GroupProductId = ProductId -- main product
	SELECT * FROM #Parties
	SELECT * FROM #Chargerates
	SELECT * FROM #Data

	DROP TABLE #Data
	DROP TABLE #Chargerates
	DROP TABLE #Exchange
	DROP TABLE #Parties
END
GO