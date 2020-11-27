/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeWinLossByProduct]
	@PartyIdString		VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(10)
AS

/*	Header:
	Created: 2015.08.06 - Bravo.Tran
	Task : Create Invoice 
	DB: DB052.bodb_Licensee

	Revisions:
		+ 2015.08.06: Invoice Amount - Generate
		+ 2015.09.15: Get Amount by PartyId List.
		+ 2015.10.20@Bravo: Add Zelianta
		+ 2015.12.15@Bruce: Add MGCLC and MGCRNG
		+ 2016.05.05@Bravo: Add VB Data
		+ 2016.10.12@Bruce: Order result by group
		+ 2017.04.10@Scofield: Support AB and FW [#74738]
		+ 20170412: @Scofield - Removing Trading Bet Types [#73310]
		+ 20170605@Bruce: - Include Bettrade [#76131]
						  - Include Colossus bet [#76131]
						  - Include CashOut [#76131]
		- 20170704@Scofield: Add VS2 and LT into report [RedmineID: #79310]
		- 20171205@Bruce: fix partyid length [#87723]
		- 20180131@Scofield: Add BX [#87754]
		- 20180315@Bruce:Support Cozni licensees [#85681]
		- 20180419@Bruce: Implement Colossus Bets Freeplay(part 2) [#93907]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20180510@Bruce: Integrate Pragmatic [#94108]
		- 20181119@bruce: Integrate Bidme games (GD product) [#103695]
	    - 20190322@Parsons: Integrate-PP-Promotion-Prize [#109014]
	    - 20190725@Mason: Integrate-Card-Club [#116096]
		- 20191121@Mason: Setup_billing_terms_by_Currency  [#120005]
	    - 20191205@Parsons: PP tournament [#123958]
	    - 20200226@Mason: Spadegaming-integration [#123959]
	    - 20200316@Parsons: Integrate Virtual Games [#125222]
	    - 20200409@Parsons: Integrate SA Gaming [#129276]
		- 20200423@Parsons: Intergrate Indo 4D [#130910]
		- 20200411@Parsons: Integrate Table Games [#131166]
		- 20200423@Parsons: Integrate Saba.club [#132730]
		- 20200507@Parsons: Integrate Sexy Gaming for deposit licensees [#132665]
		- 20200722@Happy: Implement PP Jackpot [#137306]
		- 20200909@Parsons: Implement PG Soft [RedmineID: #138983] 
		- 20200930@Parsons: Implement Joker Games [RedmineID: #141421]
		- 20201023@Parsons: Arcadia Gaming Add Bonus [#143597]  
	    - 20201113@Parsons: Changing OddsSpread for licensee [#142345]
*/
		
/*	Example:
	USE bodb_Licensee
	DECLARe @PartyIdString	VARCHAR(500)	= '14,15,29,25,30'
	DECLARE @FromDate		DATETIME		= '2015-8-1'
	DECLARE @ToDate			DATETIME		= '2015-8-31'
	DECLARe @BaseCurrencyName	VARCHAR(10)		= 'GBP'
			
	EXEC [LA_Rpt_LicenseeWinLossByProduct] @PartyIdString, @FromDate, @ToDate, @BaseCurrencyName
	
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @GD_Tip SMALLINT = 1706 
	DECLARE @PragmaticID INT = 32

	-- Region: Get party charge rate info 
	DECLARE @ProductCode VARCHAR(500)= 'SB,NG,RB,VS,LC,CS,KN,AGC,GD,VG,MGCLC,MGCRNG,VB,AB,FW,BT,CB,CO,VS2,LT,BX,PP,CC,SG,VRG,SAG,I4D,TG,SBC,SXG,PGS,JK'
	
	-- Region: Get Party ID
	DECLARE @PartyIdTable TABLE (Id INT NOT NULL)
	DECLARE @Delimiter CHAR(1)=','

	INSERT @PartyIdTable (Id)
	SELECT val
	FROM dbo.strSplit(@PartyIdString, @Delimiter)
	-- End Region
	
	DECLARE @PartyChargeInfo AS TABLE (
			ChargeId	INT,
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			BettypeRef	INT,
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME)

	INSERT INTO @PartyChargeInfo(ChargeId, PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate, BettypeRef)
	(
		SELECT	ChargeId, PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate, 
				CASE
					WHEN ProductId = 11 AND ChargeType = 12 THEN @GD_Tip
					WHEN ProductId = 39 AND ChargeType = 12 THEN 3007 --SAG_Tip
				ELSE Bettype
			END
		FROM	dbo.LA_f_ChargeInfo(@PartyIdString, @FromDate, @ToDate, @ProductCode, 'OA', 1)
		WHERE	DI_Rate > 0 AND ProductId <> 1 --exclude RB
	)
	-- End region

	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange (
			ExchangeDate	DATE,
			ExchangeID		INT,
			CurrencyCode	VARCHAR(10),
			Rate			FLOAT)
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	-- End region
	
	-- Region: Get Winloss data
	CREATE	TABLE #TempData (
			LicenseeId	INT,
			rptDate		DATETIME,
			CurrencyId	INT,
			MemberWL	MONEY,
			AWinLoss	MONEY,
			AComm		MONEY,
			PComm		MONEY,
			ProductId	TINYINT,
			BettypeRef	INT)
	
	INSERT INTO #TempData (LicenseeId,rptDate,CurrencyId,MemberWL,AWinLoss,AComm,PComm,ProductId,BettypeRef)
	(
		SELECT	b.SiteID,
				b.rptDate,
				b.CurrencyID,
				SUM(ISNULL(b.MemberWL, 0)) Winloss,
				SUM(ISNULL(b.GrossWL, 0)) AS AWinLoss,
				SUM(ISNULL(b.CommissionA, 0)) AS AComm,
				SUM(ISNULL(b.CommissionP, 0)) AS PComm,
				b.ProductId,
				CASE
					WHEN b.Bettype = @GD_Tip THEN b.Bettype
					ELSE ISNULL(sbr.BettypeRef, -1)
				END
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON b.SiteID = p.OldRefID AND p.PartyType = 1
				LEFT JOIN dbo.Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.Bettype = b.Bettype
				LEFT JOIN LA_f_ExcludedBettypeListSel('','1706') eb ON b.Bettype = eb.BettypeID
		WHERE	b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.StatusId NOT IN (-1, 101, 102, 103)
				AND b.customercategory NOT IN (27, 28)
				AND eb.BettypeID IS NULL
				AND b.ProductID NOT IN (13,15,25,@PragmaticID)
		GROUP BY b.rptdate, b.SiteId, b.CurrencyID, b.ProductId,
			CASE
				WHEN b.Bettype = @GD_Tip THEN b.Bettype
				ELSE ISNULL(sbr.BettypeRef, -1)
			END
	)
	-- EndRegion

	-- Region: Generate licensee name & group
	DECLARE @TempPartyList AS TABLE(
		PartyId		INT,
		PartyName	VARCHAR(200),
		BranchName	VARCHAR(200),
		ParentId	INT
	)
	INSERT INTO @TempPartyList
	EXECUTE dbo.LA_PartyListSel
	
	CREATE TABLE #LicenseeAmount(
		GroupName	VARCHAR(200),
		GroupId		INT,
		LicenseeId	INT,
		PartyId		INT,
		PartyName	VARCHAR(200),
		SB			MONEY, -- Sportsbook
		RB			MONEY, -- Racing
		NG			MONEY, -- Number Game	
		BA			MONEY, -- BA
		LC			MONEY, -- Live Casino
		VS			MONEY, -- Virtual Sports
		CS			MONEY, -- RNG Casino
		KN			MONEY, -- Keno
		AGC			MONEY, -- AG Casino
		GD			MONEY, -- Gold Deluxe
		VG			MONEY, -- Vegas games
		MGCLC		MONEY, -- Microgaming - Live Casino
		MGCRNG		MONEY, -- Microgaming - RNG Casino
		VB			MONEY, -- Macau Games
		AB			MONEY, -- Allbet
		FW			MONEY, -- Fishing World
		BT			MONEY, -- BetTrade
		CB			MONEY, -- Colossus bet
		CO			MONEY, -- CashOut
		BRVS		MONEY, -- Bet Radar
		LT			MONEY, -- Lottery
		BX			MONEY, -- Exchange
		PP			MONEY, -- Pragmatic
		CC			MONEY, -- Card Club
		SG			MONEY, -- Spadegaming
		VRG			MONEY, -- Virtual Games
		SAG			MONEY, -- SA Gaming
		I4D			MONEY, -- Indo 4D
		TG			MONEY, -- Table Games
		SBC			MONEY, -- Saba.club
		SXG			MONEY, -- Sexy Gaming 
		PGS			MONEY, -- PG Soft
		JK			MONEY -- Joker
	)						  
	INSERT INTO #LicenseeAmount(GroupName, GroupId, LicenseeId, PartyId,PartyName)
	SELECT	REPLACE(p.PartyName,' Licensees','') AS PartyName,
			p.PartyId,
			op.OldRefID,
			t.PartyId, 
			t.PartyName
	FROM	@TempPartyList t INNER JOIN @TempPartyList p ON t.ParentId = p.PartyId
			INNER JOIN dbo.OAS_Party op WITH (NOLOCK) ON op.PartyID = t.PartyId
	WHERE	t.ParentId != 0
			AND t.PartyId IN (SELECT Id FROM @PartyIdTable)

	-- BA
	;WITH AmountDueBA AS
	(
		SELECT	d.LicenseeId,
				SUM(-(MemberWL + AComm) * e.Rate) Amount
		FROM	#TempData d
				INNER JOIN #Exchange e ON d.rptDate = e.ExchangeDate AND d.CurrencyId = e.ExchangeID
		WHERE	d.ProductId = 3
		GROUP	BY d.LicenseeId
	)
	UPDATE	d
	SET		BA = a.Amount
	FROM	#LicenseeAmount d INNER JOIN AmountDueBA a ON a.LicenseeId = d.LicenseeId
	-- End BA

	-- RB
	;WITH AmountDueRacing AS
	(
		SELECT	d.LicenseeId,
				SUM(-(MemberWL + AWinloss + AComm) * e.Rate) Amount
		FROM	#TempData d
				INNER JOIN #Exchange e ON d.rptDate = e.ExchangeDate AND d.CurrencyId = e.ExchangeID
		WHERE	d.ProductId = 1 --RB
		GROUP	BY d.LicenseeId
	)
	UPDATE	d
	SET		RB = a.Amount
	FROM	#LicenseeAmount d INNER JOIN AmountDueRacing a ON a.LicenseeId = d.LicenseeId
	-- End RB

	-- BT
	DECLARE @BTWinLoss AS TABLE (LicenseeId INT, Amount MONEY)
	;WITH t AS (
		SELECT b.RptDate, b.SiteId, b.CurrencyId
			, SUM(CASE WHEN b.Bettype = 901 THEN (b.BuyBackAmount - b.MemberWL) ELSE 0 END) AS ActualStake
			, SUM(CASE WHEN b.Bettype = 901 THEN b.BuyBackAmount ELSE 0 END) AS BuyBackAmountTotal
			, SUM(CASE WHEN b.Bettype = 901 AND b.CustomerCategory = 1001 THEN -b.BuyBackAmount * p.Rate ELSE 0 END) AS BettradeComm
			, SUM(CASE WHEN b.ProductID <> 13 THEN b.MemberWL ELSE 0 END) AS BettradeWinLoss
		FROM bodb_licenseereport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN @PartyChargeInfo p ON b.SiteId = p.LicenseeID AND p.ProductID = 13
		WHERE b.RptDate BETWEEN p.FromDate AND p.ToDate
			AND b.CurrencyID <> 20
			AND b.StatusId NOT IN (-1, 101, 102, 103)
			AND b.CustomerCategory IN (1001, 1002)
			AND b.ProductID IN (0, 3, 13) -- include original and Bettrade tickets
		GROUP BY b.RptDate, b.SiteId, b.CurrencyId
	)
	INSERT INTO @BTWinLoss
	SELECT t.SiteId, SUM ((t.BettradeWinLoss + t.BettradeComm + t.ActualStake - t.BuyBackAmountTotal) * e.Rate)
	FROM t INNER JOIN #Exchange e ON t.RptDate = e.ExchangeDate AND t.CurrencyId = e.ExchangeId
	GROUP BY t.SiteID

	UPDATE	d
	SET		BT = a.Amount
	FROM	#LicenseeAmount d INNER JOIN @BTWinLoss a ON a.LicenseeId = d.LicenseeId 
	-- End BT

	-- CB
	DECLARE @CommChargeType INT = 6
	DECLARE @CashInShareChargeType INT = 7

	DECLARE @CBChargeRates AS TABLE (
		PartyId			INT,
		LicenseeId		INT,
		Rate			MONEY,
		TypeId			SMALLINT,
		FromDate		DATETIME,
		ToDate			DATETIME
	)

	INSERT INTO @CBChargeRates(PartyId, LicenseeId, Rate, TypeId, FromDate, ToDate)
	SELECT PartyID,LicenseeID,DI_Rate,ChargeType,Fromdate,Todate
	FROM dbo.LA_f_ChargeInfo(@PartyIdString,@FromDate,@ToDate,'CB','OA',1)

	DECLARE @CBWinLoss AS TABLE (LicenseeId INT, Amount MONEY)
	;WITH t AS (
		SELECT b.SiteId, b.rptDate,
			SUM(Turnover* e.Rate) Turnover,
			SUM(CASE WHEN ISNULL(TicketType,0)=0 THEN Turnover ELSE ISNULL(ExtraAmount,0) END * e.Rate) TurnoverForCommission,
			SUM(ISNULL(WinPrizeAmount * e.Rate,0)) WinningPrize,
			SUM(ISNULL(CashOutAmount * e.Rate,0)) CashOut,
			SUM(ISNULL(BuyBackAmount * e.Rate,0)) CashInAmount
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN @CBChargeRates cb ON b.SiteID = cb.LicenseeId AND b.rptDate BETWEEN cb.FromDate AND cb.ToDate
		INNER JOIN #Exchange e ON e.ExchangeID=b.CurrencyId AND e.ExchangeDate = b.rptDate
		WHERE b.ProductID = 15
			AND b.CustomerCategory NOT IN (27, 28)
			AND b.StatusId NOT IN (-1, 101, 102, 103)
			AND b.CurrencyId <> 20
			AND cb.TypeId = @CommChargeType -- to remove duplicate we use one of (6,7)
		GROUP BY b.rptDate, b.SiteId
	)
	INSERT INTO @CBWinLoss
	SELECT t.SiteId, SUM(t.Turnover) - SUM(t.WinningPrize) - SUM(t.CashOut) - SUM(t.TurnoverForCommission * cm.Rate) - SUM(t.CashInAmount * ci.Rate)
	FROM t
	INNER JOIN @CBChargeRates AS cm ON cm.TypeId = @CommChargeType AND (t.rptDate BETWEEN cm.FromDate AND cm.ToDate) AND cm.LicenseeId=t.SiteID
	INNER JOIN @CBChargeRates AS ci ON ci.TypeId = @CashInShareChargeType AND (t.rptDate BETWEEN ci.FromDate AND ci.ToDate) AND ci.LicenseeId=t.SiteID
	GROUP BY t.SiteId

	UPDATE	d
	SET		CB = a.Amount
	FROM	#LicenseeAmount d INNER JOIN @CBWinLoss a ON a.LicenseeId = d.LicenseeId
	-- End CB

	-- CO
	DECLARE @COWinLoss AS TABLE (LicenseeId INT, Amount MONEY)
	;WITH t AS (
		SELECT b.SiteId,
			SUM(b.BuyBackAmt * e.Rate) AS BuyBackAmountSB,
			SUM(b.BABuyBackAmt * e.Rate) AS BuyBackAmountBA,
			SUM(b.TicketPayout * e.Rate) AS TicketsPayout,					
			SUM(b.BuyBackAmt * p.Rate * e.Rate) AS CashoutCommission	
		FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)
			INNER JOIN @PartyChargeInfo p ON b.SiteId = p.LicenseeID AND b.Winlostdate BETWEEN p.FromDate AND p.ToDate AND p.ProductID = b.ProductID
			INNER JOIN #Exchange e ON e.ExchangeID = b.Currency AND e.ExchangeDate = b.Winlostdate
		WHERE b.Winlostdate BETWEEN p.FromDate AND p.ToDate									
			AND b.Currency <> 20
			AND b.RoleID = 1 -- Member
		GROUP BY b.SiteId
	)
	INSERT INTO @COWinLoss
	SELECT SiteId, SUM(TicketsPayout - BuyBackAmountSB - BuyBackAmountBA - CashoutCommission)
	FROM t
	GROUP BY t.SiteId

	UPDATE	d
	SET		CO = a.Amount
	FROM	#LicenseeAmount d INNER JOIN @COWinLoss a ON a.LicenseeId = d.LicenseeId
	-- End CO
	
	-- Pragmatic
	DECLARE @PPContribution SMALLINT = 4297,
			@PPJackpotPrize SMALLINT = 4298,
			@PPTournament SMALLINT = 4299,
			@PromotionPrize SMALLINT = 4300 
	;WITH cte_PPWinLossData AS 
	(
		SELECT b.SiteId, b.rptDate, b.CurrencyID,
			SUM(CASE WHEN b.Bettype IN (@PPTournament, @PromotionPrize, @PPContribution, @PPJackpotPrize) THEN 0 ELSE (ISNULL(-b.MemberWL, 0) * e.Rate) END) AS LicenseeWL,
			SUM(CASE WHEN b.Bettype = @PPContribution THEN ISNULL(-b.GrossWL, 0) ELSE 0 END * e.Rate) AS Contribution,
			SUM(CASE WHEN b.Bettype = @PPJackpotPrize THEN ISNULL(b.MemberWL, 0) ELSE 0 END * e.Rate) AS JackpotPrize,
			SUM(CASE WHEN b.Bettype IN (@PromotionPrize, @PPTournament) THEN ISNULL(b.MemberWL, 0) ELSE 0 END * e.Rate) AS PromotionPrize
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH(NOLOCK)
		INNER JOIN #Exchange e ON e.ExchangeID = b.CurrencyId AND e.ExchangeDate = b.rptDate
		WHERE b.ProductID = @PragmaticID
			AND b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.CustomerCategory NOT IN (27, 28)
			AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject, Void, Refund
		GROUP BY b.rptdate, b.SiteId, b.CurrencyID
	), cte_PPLicensingWL AS
	(
		SELECT p.PartyId, SUM((LicenseeWL - Contribution) * ISNULL(cr.Rate, p.Rate)) LiceningFee, SUM(d.Contribution) Contribution, SUM(d.JackpotPrize) JackpotPrize, SUM(d.PromotionPrize) PromotionPrize
		FROM cte_PPWinLossData d
		INNER JOIN @PartyChargeInfo p ON p.LicenseeId = d.SiteId AND (d.rptDate BETWEEN p.FromDate AND p.ToDate) 
		LEFT JOIN LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = p.ChargeID AND d.CurrencyId = cr.CurrencyID
		WHERE p.ProductID = @PragmaticID AND d.rptDate BETWEEN p.Fromdate AND p.Todate
		GROUP BY p.PartyId
	)
	UPDATE	l
	SET		l.PP = CASE WHEN LiceningFee < 0 THEN 0 ELSE LiceningFee END + Contribution - JackpotPrize - PromotionPrize
	FROM #LicenseeAmount l
	INNER JOIN cte_PPLicensingWL cte ON l.PartyId = cte.PartyId 
	-- End PP

	-- SportsBook
	DECLARE @SB_Product INT = 0, 
			@SB_AdjustedOdds SMALLINT = 999
	;WITH cte_SBWinLost AS 
	(
		SELECT  ci.PartyID
		, SUM(CASE WHEN b.Bettype = @SB_AdjustedOdds THEN 0 ELSE ISNULL(-b.MemberWL, 0) END * ISNULL(cr.Rate, ci.Rate) * e.Rate) AS LicencingFeeAdjustedOdds
		, SUM(CASE WHEN b.Bettype = @SB_AdjustedOdds THEN ISNULL(-b.GrossWL, 0) ELSE 0 END * e.Rate) AS OddsSpreadCost
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN @PartyChargeInfo ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID AND b.rptDate BETWEEN ci.Fromdate AND ci.Todate
		INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND b.CurrencyId = cr.CurrencyID
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.ProductID = @SB_Product
			AND b.StatusId NOT IN (- 1, 101, 102, 103)
			AND (b.CurrencyID <> 20)
			AND b.customercategory NOT IN (27,28)
		GROUP BY ci.PartyID
	)
	UPDATE	l
	SET		l.SB = LicencingFeeAdjustedOdds + OddsSpreadCost
	FROM #LicenseeAmount l
	INNER JOIN cte_SBWinLost cte ON l.PartyId = cte.PartyId 
	-- End SportsBook

	-- Calculate amount for products 
	-- For SB, NG, VS, CS, KN, AGC, GD, VB, AB, FW, LT, PP, CC, SG, VRG, SAG, I4D, TG, SBC, SXG, PGS, JK: charge rate is affected by currency
	DECLARE @AmountDueByProduct AS TABLE (
		LicenseeId INT,
		SB MONEY,
		NG MONEY,
		VS MONEY,
		CS MONEY,
		KN MONEY,
		AGC MONEY,
		GD MONEY,
		AB MONEY,
		VB MONEY,
		FW MONEY,
		LT MONEY,
		PP MONEY,
		CC MONEY,
		LC MONEY,
		VG MONEY,
		MGCLC MONEY,
		MGCRNG MONEY,
		BRVS MONEY,
		BX MONEY,
		SG MONEY,
		VRG MONEY,
		SAG MONEY,
		I4D MONEY,
		TG MONEY,
		SBC MONEY,
		SXG MONEY,
		PGS MONEY,
		JK	MONEY
	)
	
	INSERT INTO @AmountDueByProduct(LicenseeId,  NG, VS, CS, KN, AGC, GD, VB, AB, FW, LT, CC, BRVS, LC, VG, MGCLC, MGCRNG, BX, SG, VRG, SAG, I4D, TG, SBC, SXG, PGS, JK)
	SELECT d.LicenseeId,
			ISNULL(SUM(CASE WHEN d.ProductId = 2  THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS NG,
			ISNULL(SUM(CASE WHEN d.ProductId = 5  THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS VS,
			ISNULL(SUM(CASE WHEN d.ProductId = 6  THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS CS,
			ISNULL(SUM(CASE WHEN d.ProductId = 8  THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS KN,
			ISNULL(SUM(CASE WHEN d.ProductId = 10 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS AGC,
			ISNULL(SUM(CASE WHEN d.ProductId = 11 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS GD,
			ISNULL(SUM(CASE WHEN d.ProductId = 22 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS VB,
			ISNULL(SUM(CASE WHEN d.ProductId = 21 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS AB,
			ISNULL(SUM(CASE WHEN d.ProductId = 24 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS FW,
			ISNULL(SUM(CASE WHEN d.ProductId = 28 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS LT,
			ISNULL(SUM(CASE WHEN d.ProductId = 34 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS CC,
			ISNULL(SUM(CASE WHEN d.ProductId = 27 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS BRVS,
			ISNULL(SUM(CASE WHEN d.ProductId = 4  THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS LC,
			ISNULL(SUM(CASE WHEN d.ProductId = 12 THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS VG,
			ISNULL(SUM(CASE WHEN d.ProductId = 14 THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS MGCLC,
			ISNULL(SUM(CASE WHEN d.ProductId = 17 THEN -MemberWL * ci.Rate * e.Rate ELSE 0 END),0) AS MGCRNG,
			ISNULL(SUM(CASE WHEN d.ProductId = 31 THEN (-MemberWL * ci.Rate - (AComm + PComm)) * e.Rate ELSE 0 END),0) AS BX,
			ISNULL(SUM(CASE WHEN d.ProductId = 36 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS SG,
			ISNULL(SUM(CASE WHEN d.ProductId = 38 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS VRG,
			ISNULL(SUM(CASE WHEN d.ProductId = 39 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS SAG,
			ISNULL(SUM(CASE WHEN d.ProductId = 43 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS I4D,
			ISNULL(SUM(CASE WHEN d.ProductId = 40 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS TG,
			ISNULL(SUM(CASE WHEN d.ProductId = 42 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS SBC,
			ISNULL(SUM(CASE WHEN d.ProductId = 45 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS SXG,
			ISNULL(SUM(CASE WHEN d.ProductId = 55 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS PGS,
			ISNULL(SUM(CASE WHEN d.ProductId = 56 THEN -MemberWL * ISNULL(cm.Rate, ci.Rate) * e.Rate ELSE 0 END),0) AS JK
	FROM	#TempData d
				INNER JOIN @PartyChargeInfo ci ON	d.LicenseeId = ci.LicenseeId
													AND ci.ProductId = d.ProductId
													AND d.rptDate BETWEEN ci.FromDate AND ci.ToDate
													AND d.BettypeRef = ci.BettypeRef
				LEFT JOIN dbo.LA_ChargeRateByCurrency cm WITH (NOLOCK) ON ci.ChargeId = cm.ChargeId AND d.CurrencyId = cm.CurrencyId
				INNER JOIN #Exchange e ON d.rptDate = e.ExchangeDate AND d.CurrencyId = e.ExchangeID
		GROUP BY d.LicenseeId
	-- End calculate amount

	UPDATE	l
	SET		NG = a.NG,
			VS = a.VS,
			CS = a.CS,
			KN = a.KN,
			AGC = a.AGC,
			GD = a.GD,
			VB = a.VB,
			AB = a.AB,
			FW = a.FW,
			LT = a.LT,
			CC = a.CC,
			LC = a.LC,
			VG = a.VG,
			MGCLC = a.MGCLC,
			MGCRNG = a.MGCRNG,
			BRVS = a.BRVS,
			BX = a.BX,
			SG = a.SG,
			VRG = a.VRG,
			SAG = a.SAG,
			I4D = a.I4D,
			TG = a.TG,
			SBC = a.SBC,
			SXG = a.SXG,
			PGS = a.PGS,
			JK = a.JK
	FROM	#LicenseeAmount l
			INNER JOIN @AmountDueByProduct a ON a.LicenseeId = l.LicenseeId
	
	DELETE	FROM #LicenseeAmount
	WHERE	SB IS NULL
			AND RB IS NULL
			AND NG IS NULL
			AND BA IS NULL
			AND LC IS NULL
			AND VS IS NULL
			AND CS IS NULL
			AND KN IS NULL
			AND AGC IS NULL
			AND GD IS NULL
			AND VG IS NULL
			AND MGCLC IS NULL
			AND MGCRNG IS NULL
			AND VB IS NULL
			AND AB IS NULL
			AND FW IS NULL
			AND BT IS NULL
			AND CB IS NULL
			AND CO IS NULL
			AND BRVS IS NULL
			AND LT IS NULL
			AND BX IS NULL
			AND PP IS NULL
			AND CC IS NULL
			AND SG IS NULL
			AND VRG IS NULL
			AND SAG IS NULL
			AND I4D IS NULL
			AND SBC IS NULL
			AND SXG IS NULL
			AND PGS IS NULL
			AND JK IS NULL

	-- Result
	SELECT l.GroupName,l.PartyName,l.SB,l.RB,l.NG,l.BA,l.LC,l.VS,l.CS, l.KN,l.AGC,l.GD,l.VG,l.MGCLC,l.MGCRNG,l.VB, l.AB, l.FW, l.BT, l.CB, l.CO, l.BRVS, l.LT, l.BX, l.PP, l.CC, l.SG, l.VRG, l.SAG, l.I4D, l.TG, l.SBC, l.SXG, l.PGS, l.JK
	FROM #LicenseeAmount l
	ORDER BY l.GroupId, l.PartyId
	-- EndRegion

	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #LicenseeAmount
END
GO