/*<info serverAlias="DBEXT-bodb02" executers="wsv_nap,wsv_lap" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeWinloss_Details] 
	  @PartyID				INT
	, @Currency				INT				= 0
	, @FromDate				DATETIME	
	, @ToDate				DATETIME	
	, @ProductCodes			VARCHAR(MAX)	
	, @ReportBy				TINYINT			= 1
	, @DrawFilter			SMALLINT		= 1
	, @IsConvert			BIT				= 0
	, @BaseCurrencyName		VARCHAR(10)		= 'EUR'
AS
/*  Created:  Forrest.Nguyen
	Date: 20151020
	Original: LA_Rpt_LicenseeWinloss_Details
	Feature: 44873
	DB: DB052.bodb02  
	Revisions:  
	- 20160316: @Forrest - Change SporttypeRef to Sporttype for Microgaming
	- 20170412: @Scofield - Removing Trading Bet Types [#73310]
	- 20171205@Bruce: fix partyid length [#87723]
	- 20171211: @Scofield - Support Colossus Bet, Cashout, Bet Trade [#87038]
	- 20180130@Bruce: integrate Exchange product [#87754]
	- 20180419@Bruce: Implement Colossus Bets Freeplay(part 2) [#93907]
	- 20180515@Scofield: Incorporate 9wickets data [#94950]
	- 20180716@bruce: add new group TEST for credit [#98126]
	- 20180703@Parsons: Integrate Pragmatic Win Loss [#94108]
	- 20180815@Scofield: Remove "Exclude Test Data" checkbox [#98623]
	- 20181119@bruce: Integrate Bidme games (GD product) [#103695]
	- 20190322@Parsons: Integrate-PP-Promotion-Prize [#109014]
	- 20191204@Bruce: PP tournament [#123958]
	- 20191225@Bruce: billing term by currency [#120005]
	- 20200228@Parsons: Support-HID-currency [#128856]
	- 20200325@Parsons: Integrate SA Gaming [#129276]
	- 20200707@Parsons: Calculate Margin and remove Racing related data field [#137171]
	- 20200818@Parsons: Implement PP JP Changes In Reports Phase 2 [#139055]
	- 20201021@Mason: Arcadia Gaming - Add Bonus feature [#143597]
	- 20201111@Happy: Changing OddsSpread for Licensee [#142345]
	- 20201209@Mason: Saba.club - Offer Freebet tickets [#141423]
	- 20210108@Happy: Saba.club - Integrate Slot Game [#147977]
	- 20210712@Danny: Vgaming - Free bets and Jackpot prize integration [#156185]
	- 20210812@Percy: Integrate Bitcoin - apply core function GroupProduct [RedmineID: #159691]
	- 20211115@Percy: Return IsShowOddsSpread [RedmineID: #164411]
	- 20211026@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
	- 20211212@Percy: Set OddsSpread = 0 if negative value [RedmineID: #165849]
	- 20220110@Danny: SG - Jackpot prize integration [#167089]
	- 20201003@Danny: Support USDT as base currency [RedmineID: #177718]
	- 20221209@Danny: Show USD (USDT) instead of USD only [RedmineID: #180313]
	- 20221226@Danny: Fiat currency Base to USDT = 0 [RedmineID: #180703]
	- 20230217@Danny: Remove hard-code bettype And ProductID [#183739]
	- 20230510@Danny: New commercial terms for 12B [RedmineID: #186543]
	- 20230713@Danny: Incorporate USDT2 currency [RedmineID: #191165]
	- 20230919@Danny: Support Jollysport licensees [RedmineID: #193214]
	- 20231003@Danny: Integrate boost bonus for mix parlay ticket [#191662]

	Param's Explanation:  
		+ @PartyIDs	: a string of list PartyID, separate by ','
		+ @Currency	:  0- All Currencies
		+ @ReportBy: 1-Daily; 2-Monthly;  
		+ @DrawFilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
		+ @ProductCodes	: Products code :
				. SB _ SportBook
				. NG _ Number Game
				...
		+ @IsConvert: 0-No Convert, 1-Convert
		+ @BaseCurrencyName: GBP, CNY, USD, EUR, MYR
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @GD_Tip			SMALLINT	= 1706,	
			@CurrencyTest	INT			= 20,
			@ExchangeTerm_CutOffDate SMALLDATETIME

	DECLARE @ProductOfferContribList TABLE (ProductID INT)
	INSERT INTO @ProductOfferContribList(ProductID)
	SELECT DISTINCT ProductID FROM bodb_licensee.dbo.LA_f_GroupBettype() WHERE TypeId = 2

	SELECT @ExchangeTerm_CutOffDate = f.CutoffDate FROM bodb_licensee.dbo.LA_f_GetCutOffDate() f WHERE f.TypeName = 'ExchangeTerms'

	CREATE TABLE #Report (ReportDate DATE, CurrencyID INT, ProductID INT, Turnover MONEY, Winlost MONEY, LicenseeWL MONEY,
						AmtDueToBA MONEY, CommBA MONEY, Company MONEY, Betcount INT, OddsSpreadCost MONEY, FullParlayBoostBonus MONEY, LicenseeParlayBoostBonus MONEY)
	CREATE TABLE #Exchange (ExchangeId INT, ExchangeDate DATE, Code VARCHAR(65), USD FLOAT, EUR FLOAT, MYR FLOAT, GBP FLOAT, CNY FLOAT, Base FLOAT, USDT FLOAT)
	CREATE TABLE #Data (PartyID INT, rptDate DATE,ProductID INT, Currency INT,BetTypeId INT, Turnover MONEY, Winloss MONEY, AWinloss MONEY, AComm MONEY, PComm MONEY, Betcount BIGINT)
	CREATE TABLE #Products (GroupProductId INT, ProductId INT, ProductName VARCHAR(50), ProductCode VARCHAR(20), FromDate DATE, ToDate DATE)
	CREATE TABLE #ChargeInfo (PartyID INT, LicenseeID INT, ProductID INT, BetTypeID INT, Rate MONEY, Fromdate DATE , Todate DATE, ChargeType TINYINT, ChargeID INT)

	INSERT INTO #Products (GroupProductId, ProductId, ProductName, ProductCode, FromDate, ToDate)
	SELECT GroupProductId, ProductId, ProductName, ProductCode, FromDate, ToDate
	FROM bodb_Licensee.dbo.LA_f_GroupProduct(@ProductCodes, @FromDate, @ToDate) g

	SET @ProductCodes = NULL
	SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM #Products
	
	INSERT INTO #ChargeInfo (PartyID, LicenseeID, ProductID, BetTypeID, Rate, Fromdate, Todate, ChargeType, ChargeID)
	SELECT DISTINCT PartyID, LicenseeID, ProductID, Bettype, 
			CASE WHEN ISNULL(isDeposit, 0) = 1 THEN DI_Rate ELSE 0 END,
			Fromdate, Todate,
			CASE WHEN ProductID IN(11,39) THEN ChargeType ELSE 1 END, -- include GD tip charge type
			ChargeID
	FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyID, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
	
	/* BA Product Id = 3 */
	IF (SELECT COUNT(*) FROM #ChargeInfo WHERE ProductID = 3) > 0
	BEGIN
		INSERT INTO #Data(rptDate, ProductID, Currency, Turnover, Winloss, AWinloss, AComm, Betcount)
		(
			SELECT b.rptDate, b.ProductID, b.currencyID
				, SUM(b.turnover * 
					CASE WHEN @drawfilter IN (2, 3) 
						THEN CASE WHEN b.StatusId = 111 THEN 0
							WHEN b.StatusId IN (114, 115)	THEN 0.5 ELSE 1	END
						ELSE 1
					END) Turnover
				, SUM(b.MemberWL) Winloss
				, 0 AS AWinloss
				, SUM(b.CommissionA) CommBA
				, SUM(b.BetCount * CASE WHEN @drawfilter = 2 AND b.StatusId = 111 THEN 0 ELSE 1 END) BetCount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #ChargeInfo ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID = 3
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR b.CurrencyID = @Currency)
				AND (b.CurrencyID <> @CurrencyTest)
			GROUP BY b.rptDate, b.ProductID, currencyID
		)
		
		INSERT INTO #Report (ReportDate, CurrencyID, ProductID, Turnover, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company, Betcount)
		(
			SELECT b.rptDate, b.currency, b.ProductID
				, SUM(b.turnover) Turnover
				, SUM(b.winloss) Winloss
				, 0 AS LicenseeWL
				, -SUM((b.winloss * ci.Rate ) + b.AComm) AS AmountDueToBA
				, SUM(b.AComm) AS CommBA
				, 0 AS Company
				, SUM(betcount) BetCount
			FROM #Data b
				INNER JOIN (SELECT DISTINCT Fromdate, Todate, ProductID, Rate FROM #ChargeInfo WHERE ProductID = 3) ci ON b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			GROUP BY b.rptDate, b.Currency, b.ProductID
		)
	END
	
	-- Colossus Bets
	IF (SELECT COUNT(*) FROM #ChargeInfo WHERE ProductID = 15) > 0
	BEGIN
		-- Region: Local variables
		DECLARE @CBProductId INT = 15
		DECLARE @CommChargeType INT = 6
		DECLARE @CashInShareChargeType INT = 7

		-- Region: Commision and Cash in share Rates
		DECLARE @CBShare AS TABLE(LicenseeId INT, Rate MONEY, TypeId SMALLINT, FromDate DATETIME, ToDate DATETIME)

		INSERT INTO @CBShare(LicenseeId, Rate, TypeId, FromDate, ToDate)
		SELECT LicenseeID,DI_Rate,ChargeType,Fromdate,Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyID,@FromDate,@ToDate,'CB','OA',1)		
		-- End Region: Commision and Cash in share Rates

		-- Region: Get Winloss Data
		CREATE TABLE #TempData (
			rptDate							DATETIME,
			CurrencyId						INT,
			Turnover						MONEY,
			TurnoverForCommission			MONEY,
			WinningPrize					MONEY,
			CashOut							MONEY,
			CommisionShare					MONEY,
			CashInShare						MONEY,
			CashInAmount					MONEY
		)

		INSERT INTO #TempData (rptDate, CurrencyId, Turnover, TurnoverForCommission, WinningPrize, CashOut, CashInAmount)
		SELECT	rptDate,
				CurrencyId,
				SUM(Turnover) Turnover,
				SUM(CASE WHEN ISNULL(TicketType,0)=0 THEN Turnover ELSE ISNULL(ExtraAmount,0) END) TurnoverForCommission,
				SUM(ISNULL(WinPrizeAmount,0)) WinningPrize,
				SUM(ISNULL(CashOutAmount,0)) CashOut,
				SUM(ISNULL(BuyBackAmount,0)) CashInAmount
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN @CBShare cb ON b.SiteID = cb.LicenseeId AND b.rptDate BETWEEN cb.FromDate AND cb.ToDate
		WHERE	ProductID = @CBProductId AND
				CustomerCategory NOT IN (27, 28) AND
				b.StatusId NOT IN (-1, 101, 102, 103) AND
				(b.CurrencyID <> @CurrencyTest) AND
				(@Currency = 0 OR CurrencyId = @Currency) AND
				cb.TypeId = @CommChargeType -- to remove duplicate we use one of (6,7)
		GROUP BY rptdate, CurrencyId
		-- End Region: Get Winloss Data

		UPDATE #TempData
		SET CommisionShare = td.TurnoverForCommission * cm.Rate,
			CashInShare = td.CashInAmount * ci.Rate
		FROM #TempData td
		INNER JOIN @CBShare AS cm ON cm.TypeId = @CommChargeType AND (td.rptDate BETWEEN cm.FromDate AND cm.ToDate)
		INNER JOIN @CBShare AS ci ON ci.TypeId = @CashInShareChargeType AND (td.rptDate BETWEEN ci.FromDate AND ci.ToDate)
		-- End Region: Calculate Commision, Cash In Share		
		
		INSERT INTO #Report (ReportDate, CurrencyID, ProductID, Company, Turnover, Winlost, LicenseeWL, AmtDueToBA, CommBA, Betcount)
		SELECT td.rptDate, td.CurrencyId, @CBProductId,
			Turnover - WinningPrize - Cashout - CommisionShare - CashInShare,
			0, 0, 0, 0, 0, 0
		FROM #TempData td
		
		DROP TABLE #TempData
	END

	-- Cashout
	IF (SELECT COUNT(*) FROM #ChargeInfo WHERE ProductID = 25) > 0
	BEGIN
		DECLARE @COProductId INT = 25

		INSERT INTO #Report (ReportDate, CurrencyID, ProductID, Company, Turnover, Winlost, LicenseeWL, AmtDueToBA, CommBA, Betcount)
		(
			SELECT
				d.Winlostdate,
				d.Currency,		
				@COProductId,
				SUM(TicketsPayout - BuyBackAmountSB - BuyBackAmountBA - CashoutCommission) AS Company,
				0, 0, 0, 0, 0, 0
			FROM (
					SELECT b.Winlostdate, b.Currency,
							SUM(b.BuyBackAmt) AS BuyBackAmountSB,
							SUM(b.BABuyBackAmt) AS BuyBackAmountBA,
							SUM(b.TicketPayout) AS TicketsPayout,					
							SUM(b.BuyBackAmt * ci.Rate) AS CashoutCommission	
					FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)
						INNER JOIN #ChargeInfo ci ON b.SiteId = ci.LicenseeID AND b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate AND b.ProductID = ci.ProductId					
					WHERE b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate									
						AND (b.Currency <> @CurrencyTest)
						AND(@Currency = 0 OR b.Currency = @Currency)
						AND b.ProductID = @COProductId
						AND b.RoleID = 1 -- Member
					GROUP BY b.Winlostdate, b.Currency			
			) d
			GROUP BY d.Winlostdate, d.Currency
		)
	END

	-- BetTrade
	IF (SELECT COUNT(*) FROM #ChargeInfo WHERE ProductID = 13) > 0
	BEGIN
		DECLARE @BTProductId INT = 13
		DECLARE @Bettype AS TABLE(Bettype INT, ProductId INT)
		
		INSERT INTO @Bettype (Bettype, ProductId)		
		SELECT Bettype, ProductID
		FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, 'BT,SB,BA')		

		INSERT INTO #Report (ReportDate, CurrencyID, ProductId, Company, Turnover, Winlost, LicenseeWL, AmtDueToBA, CommBA, Betcount)
		(
			SELECT
				d.RptDate,
				d.CurrencyID,
				@BTProductId,
				SUM ((d.BTWinLoss + d.BettradeComm + d.Actual_stake - d.BuyBackAmountTotal)) AS Company,
				0, 0, 0, 0, 0, 0
			FROM (
				SELECT b.RptDate, b.CurrencyId
					, SUM(CASE WHEN b.Bettype = 901 THEN (b.BuyBackAmount - b.WinLoss) ELSE 0 END) AS Actual_stake
					, SUM(CASE WHEN b.Bettype = 901 THEN b.BuyBackAmount ELSE 0 END) AS BuyBackAmountTotal
					, SUM(CASE WHEN bt.ProductID = 0 THEN b.WinLoss ELSE 0 END) AS BTWinLoss
					, SUM (CASE WHEN b.Bettype = 901 AND b.CustomerCategory = 1001 THEN - b.BuyBackAmount * ci.Rate ELSE 0 END) AS BettradeComm
				FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
					INNER JOIN #ChargeInfo ci ON b.SiteId = ci.LicenseeID AND ci.ProductId = @BTProductId
					INNER JOIN @Bettype bt ON b.Bettype = bt.Bettype AND bt.ProductId IN (0, @BTProductId)
				WHERE b.RptDate BETWEEN ci.FromDate AND ci.ToDate
					AND (@Currency = 0 OR b.CurrencyID = @Currency)
					AND (b.CurrencyID <> @CurrencyTest)
					AND b.Status NOT IN (-1, 101, 102, 103)
					AND b.CustomerCategory IN (1001, 1002)
				GROUP BY b.RptDate, b.CurrencyId
				
				UNION ALL 
				
				-- rpt_betting_BA only contain original ticket, SOLD BOUGHT COMM ticket will be in rpt_betting
				SELECT b.RptDate, b.CurrencyId
					, 0 AS Actual_stake
					, 0 AS BuyBackAmountTotal
					, SUM(b.WinLoss) AS BTWinLoss
					, 0 AS BettradeComm
				FROM bodb_licenseereport.dbo.rpt_Betting_BA b WITH (NOLOCK)
					INNER JOIN #ChargeInfo ci ON b.SiteId = ci.LicenseeID AND ci.ProductId = @BTProductId
					INNER JOIN @Bettype bt ON b.Bettype = bt.Bettype AND bt.ProductID IN (3)
				WHERE b.RptDate BETWEEN ci.FromDate AND ci.ToDate
					AND (@Currency = 0 OR b.CurrencyID = @Currency)
					AND (b.CurrencyID <> @CurrencyTest)
					AND b.Status NOT IN (-1, 101, 102, 103)
					AND b.CustomerCategory = 1002 -- for BT BA
				GROUP BY b.RptDate, b.CurrencyId

			) d
			GROUP BY d.RptDate, d.CurrencyID
		)
	END
	
	-- GD
	IF (SELECT COUNT(*) FROM #ChargeInfo WHERE ProductID = 11) > 0
	BEGIN
		DELETE #Data

		INSERT INTO #Data(rptDate, Currency, BetTypeId, Turnover, Winloss, Betcount)
		(
			SELECT b.rptDate, b.CurrencyID,b.Bettype
				, SUM(b.turnover * 
					CASE WHEN @drawfilter IN (2, 3) 
						THEN CASE WHEN b.StatusId = 111 THEN 0
							WHEN b.StatusId IN (114, 115)	THEN 0.5 ELSE 1	END
						ELSE 1
					END) Turnover
				, SUM(b.MemberWL)
				, SUM(b.betcount * CASE WHEN @drawfilter = 2 AND b.StatusId = 111 THEN 0 ELSE 1 END) BetCount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR b.CurrencyID = @Currency)
				AND (b.CurrencyID <> @CurrencyTest)
				AND b.customercategory NOT IN (27,28)
				AND b.ProductID = 11
				AND b.SiteID IN (SELECT TOP 1 o.LicenseeID FROM #ChargeInfo o)
			GROUP BY b.rptDate,b.CurrencyID,b.Bettype
		)

		INSERT INTO #Report (ReportDate, CurrencyID, ProductID, Turnover, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company, Betcount)
		(
			-- licensing fee
			SELECT b.rptDate, b.Currency, 11 -- GD = 11
				, SUM(b.Turnover)
				, SUM(b.Winloss)
				, SUM(-b.Winloss)
				, 0,0
				, SUM(-b.Winloss * ISNULL(cc.Rate,ci.Rate))
				, SUM(b.Betcount)
			FROM #Data b WITH (NOLOCK)
				INNER JOIN #ChargeInfo ci ON b.rptDate BETWEEN ci.Fromdate AND ci.Todate
				LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cc WITH (NOLOCK) ON cc.ChargeID=ci.ChargeId AND b.Currency=cc.CurrencyID
			WHERE ci.ProductID=11 
				AND b.BetTypeId <> @GD_Tip 
				AND ci.ChargeType=1 -- gross win
			GROUP BY b.rptDate, b.Currency

			UNION ALL
			-- tip amount
			SELECT b.rptDate, b.Currency, 11,0,0,0,0,0
				, SUM(-b.Winloss * ci.Rate)
				, 0 AS Betcount
			FROM #Data b WITH (NOLOCK)
				INNER JOIN #ChargeInfo ci ON b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			WHERE ci.ProductID=11 
				AND b.BetTypeId = @GD_Tip 
				AND ci.ChargeType=12 -- GD tip
			GROUP BY b.rptDate, b.Currency
		)
	END

	DECLARE @ExcludedProductIds TABLE(ProductId INT)
	INSERT INTO @ExcludedProductIds(ProductId) VALUES (1), (3), (14), (17), (15), (25), (13), (11)
	
	IF (SELECT COUNT(*) FROM #ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) > 0
	BEGIN
		DELETE #Data
		
		SELECT ci.PartyID, b.rptDate, p.GroupProductId AS ProductId, b.CurrencyId
			, SUM(CASE WHEN eb.TypeId = 7 THEN 0 ELSE b.turnover * 
				CASE WHEN b.bettype = 33 AND b.StatusId IN (114, 115) THEN 0.5 ELSE 1 END * 
				CASE WHEN @drawfilter IN (2, 3)	
						THEN CASE WHEN b.StatusId = 111 THEN 0 
						          WHEN b.StatusId IN (114, 115) AND b.Bettype != 33 THEN 0.5 
								  ELSE 1
							  END	
						ELSE 1 END
				END) Turnover
			, SUM(CASE WHEN eb.TypeId IN (2,7) THEN 0 ELSE b.MemberWL END) Winloss
			, SUM(CASE WHEN b.ProductID=31 THEN b.CommissionP ELSE 0 END) PComm
			, SUM(CASE WHEN b.ProductID=31 THEN b.CommissionA ELSE 0 END) AComm
			, SUM(b.betcount * CASE WHEN (@drawfilter = 2 AND b.StatusId = 111) OR eb.TypeId IN (2,7,9) THEN 0 ELSE 1 END) BetCount 
			, SUM(CASE WHEN eb.TypeId IN (2,7) THEN ISNULL(-b.GrossWL, 0) ELSE 0 END) AWinloss
			, SUM(CASE WHEN eb.TypeId = 9 THEN ISNULL(-b.ValidBetAmount, 0) ELSE 0 END) FullParlayBoostBonus
			, SUM(CASE WHEN eb.TypeId = 9 THEN ISNULL(-b.ExtraAmount, 0) ELSE 0 END) LicenseeParlayBoostBonus
		INTO #TmpData
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #Products p ON b.ProductId = p.ProductId AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			INNER JOIN (SELECT DISTINCT PartyID, LicenseeId, ProductID FROM #ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) ci ON b.SiteID = ci.LicenseeID AND p.GroupProductId = ci.ProductID
			LEFT JOIN bodb_licensee.dbo.LA_f_GroupBettype() eb ON b.Bettype = eb.Bettype 

		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.StatusId NOT IN (- 1, 101, 102, 103)
			AND (@Currency = 0 OR b.CurrencyID = @Currency)
			AND (b.CurrencyID <> @CurrencyTest)
			AND b.customercategory NOT IN (27,28)
			AND (eb.Bettype IS NULL OR eb.TypeId IN (7,2,9)) -- 7:OddsSpread Adjustment, 2:Jackpot Contribution, 9: Parlay Boost Adjustment
			AND	ISNULL(b.TicketType,0) <> 2 -- Free_Bets_TicketType
		GROUP BY ci.PartyID, b.rptDate, p.GroupProductId, b.CurrencyID

		INSERT INTO #Report (ReportDate, CurrencyID, ProductID, Turnover, Winlost, LicenseeWL, Company, Betcount, OddsSpreadCost, FullParlayBoostBonus, LicenseeParlayBoostBonus)
		SELECT rptDate, b.CurrencyId, b.ProductID
			, SUM(b.turnover) Turnover
			, SUM(b.Winloss + CASE WHEN b.ProductID=31 THEN b.PComm ELSE 0 END) AS Winloss
			, SUM(-b.Winloss - CASE WHEN b.ProductID=31 THEN b.PComm ELSE 0 END) AS LicenseeWL
			, SUM(
					CASE WHEN b.ProductID=31 THEN CASE WHEN b.rptDate < @ExchangeTerm_CutOffDate THEN -b.Winloss * ISNULL(cc.Rate,ci.Rate) - (b.AComm + b.PComm)
												  ELSE  -(b.Winloss + PComm) * ISNULL(cc.Rate,ci.Rate) END
					ELSE (-b.Winloss - CASE WHEN p.ProductID IS NOT NULL THEN AWinloss ELSE 0 END - b.FullParlayBoostBonus) * ISNULL(cc.Rate,ci.Rate) END
				 ) Company
			, SUM(b.betcount) AS betcount
			, SUM(CASE WHEN b.ProductID = 0 THEN AWinloss ELSE 0 END) AS OddsSpreadCost
			, SUM(FullParlayBoostBonus) FullParlayBoostBonus
			, SUM(LicenseeParlayBoostBonus) LicenseeParlayBoostBonus
		FROM #TmpData b WITH (NOLOCK)
			INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, Rate, ChargeID, ChargeType FROM #ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) ci ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID				
			LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cc WITH (NOLOCK) ON cc.ChargeID=ci.ChargeId AND b.CurrencyId=cc.CurrencyID
			LEFT JOIN @ProductOfferContribList p ON b.ProductId = p.ProductID
		WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate AND ci.ChargeType = 1 -- Gross Win
		GROUP BY b.rptDate, b.CurrencyId, b.ProductID
		
		DROP TABLE #TmpData
	END

	INSERT INTO #Exchange(ExchangeDate, ExchangeId, Code, USD, EUR, MYR, GBP, CNY, USDT)
	SELECT DISTINCT ExchangeDate, ExchangeId, 
			CASE WHEN ExchangeId = 142 THEN 'USDT'
				WHEN ExchangeId IN (96,206) THEN 'USD (USDT)'
				WHEN ExchangeId = 202 THEN 'USD (USDTJP)'
				WHEN ExchangeId = 209 THEN 'MP'
			ELSE Code END Code, 
			USD, EUR, MYR, GBP, CNY, USDT
	FROM dbo.Lrf_f_GetExchangeDaily(@FromDate, @Todate)
	WHERE ExchangeId IN (SELECT CurrencyID FROM #Report)

	-- treat NULL as zero
	--
	UPDATE #Report SET
		Betcount = ISNULL(Betcount,0),
		Turnover = ISNULL(Turnover,0),
		Winlost = ISNULL(Winlost,0),
		LicenseeWL = ISNULL(LicenseeWL,0),
		AmtDueToBA = ISNULL(AmtDueToBA,0),
		CommBA = ISNULL(CommBA,0),
		Company = ISNULL(Company,0)

	IF @IsConvert = 1
	BEGIN
		UPDATE #Exchange
		SET Base = ( CASE @BaseCurrencyName
						WHEN 'MYR' THEN MYR
						WHEN 'USD' THEN USD
						WHEN 'EUR' THEN EUR
						WHEN 'GBP' THEN GBP
						WHEN 'CNY' THEN CNY
						WHEN 'USDT' THEN USDT
						ELSE 1 
					 END)

		-- Fiat to Crypto
		UPDATE e
		SET USDT = 0
		FROM #Exchange e 
		INNER JOIN bodb02.dbo.Exchange ex WITH (NOLOCK) ON e.ExchangeId = ex.ExchangeId AND ex.CurrencyType = 0
		END
	ELSE IF @IsConvert = 0
	BEGIN
		UPDATE #Exchange
		SET Base = 1
	END

	--Update Currency Name
	DECLARE @CurrencyTable AS TABLE (currency INT, CurrencyName VARCHAR(20), CurrencyCode VARCHAR(65))
	INSERT INTO @CurrencyTable(currency, CurrencyName, CurrencyCode)
	SELECT t.CurrencyID, e.currency, e.Code Code
	FROM (SELECT DISTINCT CurrencyID FROM #Report) t
	INNER JOIN dbo.Exchange e WITH (NOLOCK) ON t.CurrencyID = e.exchangeid
	
	UPDATE @CurrencyTable
	SET CurrencyCode = (CASE currency
					WHEN 51 THEN 'INH'
					WHEN 75 THEN 'PTU'
					WHEN 76 THEN 'PS'
					WHEN 77 THEN 'PTH'
					WHEN 92 THEN 'HID'
					WHEN 142 THEN 'USDT'
					WHEN 96 THEN 'USD (USDT)'
					WHEN 202 THEN 'USD (USDTJP)'
					WHEN 206 THEN 'USD (USDT)'
					WHEN 208 THEN 'USD (US$KH)'
					WHEN 209 THEN 'MP'
					ELSE CurrencyCode
				END)
	WHERE currency IN (51, 75, 76, 77, 92, 202, 209, 142, 96, 206, 208)	

	UPDATE t1
	SET CurrencyCode = t1.CurrencyCode + ' (' + CurrencyName + ')' 
	FROM @CurrencyTable t1
	INNER JOIN (
	   SELECT CurrencyCode
		FROM @CurrencyTable
		WHERE currency NOT IN (51, 75, 76, 77, 92, 202, 209, 142, 96, 206, 208)
		GROUP BY CurrencyCode
		HAVING COUNT(1) > 1
	) t2 ON t1.CurrencyCode = t2.CurrencyCode
	WHERE t1.currency NOT IN (51, 75, 76, 77, 92,202, 209, 142, 96, 206, 208)
	

	-- Result
	BEGIN
		CREATE TABLE #Result (ProductId INT, ProductName VARCHAR(50), ReportDate VARCHAR(8), CurrencyId INT, CurrencyName VARCHAR(20), TotalTransaction INT
			,Turnover MONEY, CustomerWinLoss MONEY, LicenseeWinLoss MONEY, AmountDueToBA MONEY, BACommission MONEY, AmountCompany MONEY, OddsSpreadCost MONEY, FullParlayBoostBonus MONEY, LicenseeParlayBoostBonus MONEY
			,TurnoverMYR MONEY, CustomerWinLossMYR MONEY, LicenseeWinLossMYR MONEY, AmountDueToBAMYR MONEY, BACommissionMYR MONEY, AmountCompanyMYR MONEY, OddsSpreadCostMYR MONEY, FullParlayBoostBonusMYR MONEY, LicenseeParlayBoostBonusMYR MONEY
			,TurnoverUSD MONEY, CustomerWinLossUSD MONEY, LicenseeWinLossUSD MONEY, AmountDueToBAUSD MONEY, BACommissionUSD MONEY, AmountCompanyUSD MONEY, OddsSpreadCostUSD MONEY, FullParlayBoostBonusUSD MONEY, LicenseeParlayBoostBonusUSD MONEY
			,TurnoverEUR MONEY, CustomerWinLossEUR MONEY, LicenseeWinLossEUR MONEY, AmountDueToBAEUR MONEY, BACommissionEUR MONEY, AmountCompanyEUR MONEY, OddsSpreadCostEUR MONEY, FullParlayBoostBonusEUR MONEY, LicenseeParlayBoostBonusEUR MONEY
			,TurnoverGBP MONEY, CustomerWinLossGBP MONEY, LicenseeWinLossGBP MONEY, AmountDueToBAGBP MONEY, BACommissionGBP MONEY, AmountCompanyGBP MONEY, OddsSpreadCostGBP MONEY, FullParlayBoostBonusGBP MONEY, LicenseeParlayBoostBonusGBP MONEY
			,TurnoverCNY MONEY, CustomerWinLossCNY MONEY, LicenseeWinLossCNY MONEY, AmountDueToBACNY MONEY, BACommissionCNY MONEY, AmountCompanyCNY MONEY, OddsSpreadCostCNY MONEY, FullParlayBoostBonusCNY MONEY, LicenseeParlayBoostBonusCNY MONEY
			,TurnoverUSDT MONEY, CustomerWinLossUSDT MONEY, LicenseeWinLossUSDT MONEY, AmountDueToBAUSDT MONEY, BACommissionUSDT MONEY, AmountCompanyUSDT MONEY, OddsSpreadCostUSDT MONEY, FullParlayBoostBonusUSDT MONEY, LicenseeParlayBoostBonusUSDT MONEY
			,IsShowOddsSpread BIT)

		INSERT INTO #Result (ProductId, ProductName, ReportDate, CurrencyId, CurrencyName, TotalTransaction
			,Turnover, CustomerWinLoss, LicenseeWinLoss, AmountDueToBA, BACommission, AmountCompany, OddsSpreadCost, FullParlayBoostBonus, LicenseeParlayBoostBonus
			,TurnoverMYR, CustomerWinLossMYR, LicenseeWinLossMYR, AmountDueToBAMYR, BACommissionMYR, AmountCompanyMYR, OddsSpreadCostMYR, FullParlayBoostBonusMYR, LicenseeParlayBoostBonusMYR
			,TurnoverUSD, CustomerWinLossUSD, LicenseeWinLossUSD, AmountDueToBAUSD, BACommissionUSD, AmountCompanyUSD, OddsSpreadCostUSD, FullParlayBoostBonusUSD, LicenseeParlayBoostBonusUSD
			,TurnoverEUR, CustomerWinLossEUR, LicenseeWinLossEUR, AmountDueToBAEUR, BACommissionEUR, AmountCompanyEUR, OddsSpreadCostEUR, FullParlayBoostBonusEUR, LicenseeParlayBoostBonusEUR
			,TurnoverGBP, CustomerWinLossGBP, LicenseeWinLossGBP, AmountDueToBAGBP, BACommissionGBP, AmountCompanyGBP, OddsSpreadCostGBP, FullParlayBoostBonusGBP, LicenseeParlayBoostBonusGBP
			,TurnoverCNY, CustomerWinLossCNY, LicenseeWinLossCNY, AmountDueToBACNY, BACommissionCNY, AmountCompanyCNY, OddsSpreadCostCNY, FullParlayBoostBonusCNY, LicenseeParlayBoostBonusCNY
			,TurnoverUSDT, CustomerWinLossUSDT, LicenseeWinLossUSDT, AmountDueToBAUSDT, BACommissionUSDT, AmountCompanyUSDT, OddsSpreadCostUSDT, FullParlayBoostBonusUSDT, LicenseeParlayBoostBonusUSDT)
		SELECT p.ProductId, p.ProductName
			,CASE
				WHEN @ReportBy = 1 THEN CONVERT(VARCHAR(8), b.ReportDate, 112)
				WHEN @ReportBy = 2 THEN CONVERT(VARCHAR(6), b.ReportDate, 112)
				ELSE '0'
			END AS ReportDate
			,b.CurrencyId
			,CASE WHEN b.CurrencyId = 20 THEN 'UUS' ELSE ISNULL(t.CurrencyCode, e.Code) END AS CurrencyName
			,SUM(Betcount) AS TotalTransaction
			-- Base Currency
			,SUM(Turnover * e.Base) AS Turnover
			,SUM(Winlost * e.Base) AS CustomerWinLoss
			,SUM(LicenseeWL * e.Base) AS LicenseeWinLoss
			,SUM(AmtDueToBA * e.Base) AS AmountDueToBA
			,SUM(CommBA * e.Base) AS BACommission
			,SUM(Company * e.Base) AS AmountCompany
			,SUM(OddsSpreadCost * e.Base) AS OddsSpreadCost
			,SUM(FullParlayBoostBonus* e.Base) AS FullParlayBoostBonus
			,SUM(LicenseeParlayBoostBonus* e.Base) AS LicenseeParlayBoostBonus
			-- MYR
			,SUM(Turnover * e.MYR) AS TurnoverMYR
			,SUM(Winlost * e.MYR) AS CustomerWinLossMYR
			,SUM(LicenseeWL * e.MYR) AS LicenseeWinLossMYR
			,SUM(AmtDueToBA * e.MYR) AS AmountDueToBAMYR
			,SUM(CommBA * e.MYR) AS BACommissionMYR
			,SUM(Company * e.MYR) AS AmountCompanyMYR
			,SUM(OddsSpreadCost * e.MYR) AS OddsSpreadCostMYR
			,SUM(FullParlayBoostBonus* e.MYR) AS FullParlayBoostBonusMYR
			,SUM(LicenseeParlayBoostBonus* e.MYR) AS LicenseeParlayBoostBonusMYR
			-- USD
			,SUM(Turnover * e.USD) AS TurnoverUSD
			,SUM(Winlost * e.USD) AS CustomerWinLossUSD
			,SUM(LicenseeWL * e.USD) AS LicenseeWinLossUSD
			,SUM(AmtDueToBA * e.USD) AS AmountDueToBAUSD
			,SUM(CommBA * e.USD) AS BACommissionUSD
			,SUM(Company * e.USD) AS AmountCompanyUSD
			,SUM(OddsSpreadCost * e.USD) AS OddsSpreadCostUSD
			,SUM(FullParlayBoostBonus* e.USD) AS FullParlayBoostBonusUSD
			,SUM(LicenseeParlayBoostBonus* e.USD) AS LicenseeParlayBoostBonusUSD
			-- EUR
			,SUM(Turnover * e.EUR) AS TurnoverEUR
			,SUM(Winlost * e.EUR) AS CustomerWinLossEUR
			,SUM(LicenseeWL * e.EUR) AS LicenseeWinLossEUR
			,SUM(AmtDueToBA * e.EUR) AS AmountDueToBAEUR
			,SUM(CommBA * e.EUR) AS BACommissionEUR
			,SUM(Company * e.EUR) AS AmountCompanyEUR
			,SUM(OddsSpreadCost * e.EUR) AS OddsSpreadCostEUR
			,SUM(FullParlayBoostBonus* e.EUR) AS FullParlayBoostBonusEUR
			,SUM(LicenseeParlayBoostBonus* e.EUR) AS LicenseeParlayBoostBonusEUR
			-- GBP
			,SUM(Turnover * e.GBP) AS TurnoverGBP
			,SUM(Winlost * e.GBP) AS CustomerWinLossGBP
			,SUM(LicenseeWL * e.GBP) AS LicenseeWinLossGBP
			,SUM(AmtDueToBA * e.GBP) AS AmountDueToBAGBP
			,SUM(CommBA * e.GBP) AS BACommissionGBP
			,SUM(Company * e.GBP) AS AmountCompanyGBP
			,SUM(OddsSpreadCost * e.GBP) AS OddsSpreadCostGBP
			,SUM(FullParlayBoostBonus* e.GBP) AS FullParlayBoostBonusGBP
			,SUM(LicenseeParlayBoostBonus* e.GBP) AS LicenseeParlayBoostBonusGBP
			-- CNY
			,SUM(Turnover * e.CNY) AS TurnoverCNY
			,SUM(Winlost * e.CNY) AS CustomerWinLossCNY
			,SUM(LicenseeWL * e.CNY) AS LicenseeWinLossCNY
			,SUM(AmtDueToBA * e.CNY) AS AmountDueToBACNY
			,SUM(CommBA * e.CNY) AS BACommissionCNY
			,SUM(Company * e.CNY) AS AmountCompanyCNY
			,SUM(OddsSpreadCost * e.CNY) AS OddsSpreadCostCNY
			,SUM(FullParlayBoostBonus* e.CNY) AS FullParlayBoostBonusCNY
			,SUM(LicenseeParlayBoostBonus* e.CNY) AS LicenseeParlayBoostBonusCNY
				-- USDT
			,SUM(Turnover * e.USDT) AS TurnoverUSDT
			,SUM(Winlost * e.USDT) AS CustomerWinLossUSDT
			,SUM(LicenseeWL * e.USDT) AS LicenseeWinLossUSDT
			,SUM(AmtDueToBA * e.USDT) AS AmountDueToBAUSDT
			,SUM(CommBA * e.USDT) AS BACommissionUSDT
			,SUM(Company * e.USDT) AS AmountCompanyUSDT
			,SUM(OddsSpreadCost * e.USDT) AS OddsSpreadCostUSDT
			,SUM(FullParlayBoostBonus* e.USDT) AS FullParlayBoostBonusUSDT
			,SUM(LicenseeParlayBoostBonus* e.USDT) AS LicenseeParlayBoostBonusUSDT
		FROM #Report b
			INNER JOIN #Exchange e ON e.ExchangeDate = b.ReportDate AND e.ExchangeId = b.CurrencyID
			INNER JOIN #Products p ON b.ProductID = p.ProductID AND b.ReportDate BETWEEN p.FromDate AND p.ToDate
			LEFT JOIN @CurrencyTable t ON b.CurrencyID = t.currency
		GROUP BY p.ProductId, p.ProductName
			,CASE
				WHEN @ReportBy = 1 THEN CONVERT(VARCHAR(8), b.ReportDate, 112)
				WHEN @ReportBy = 2 THEN CONVERT(VARCHAR(6), b.ReportDate, 112)
				ELSE '0'
			END
			,b.CurrencyId
			,CASE WHEN b.CurrencyId = 20 THEN 'UUS' ELSE ISNULL(t.CurrencyCode, e.Code) END

		-- Set OddsSpreadCost = 0 if value is negative
		SET @BaseCurrencyName = NULL
		SELECT @BaseCurrencyName = e.Code
		FROM bodb_Licensee.dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK)
			INNER JOIN dbo.Exchange e WITH (NOLOCK) ON bc.BaseCurrencyId = e.ExchangeId
		WHERE bc.PartyId = @PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate

		SELECT @BaseCurrencyName = ISNULL(@BaseCurrencyName, 'EUR')

		DELETE #Exchange
		INSERT INTO #Exchange (ExchangeDate, ExchangeId, Base)
		SELECT DISTINCT ExchangeDate, ExchangeId, BaseCurrencyRate
		FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
		WHERE ExchangeId IN (SELECT CurrencyID FROM #Report)
		
		IF EXISTS (
			SELECT 1
			FROM (
				SELECT CASE WHEN SUM(r.OddsSpreadCost * e.Base) <= 0 THEN 0 ELSE 1 END AS IsShowOddsSpread
				FROM #Report r
					INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND r.ReportDate = e.ExchangeDate
			) t
			WHERE IsShowOddsSpread = 1
		)
		BEGIN
			UPDATE #Result SET IsShowOddsSpread = 1
		END
		ELSE
		BEGIN
			UPDATE #Result
			SET IsShowOddsSpread = 0
				,OddsSpreadCost = 0
				,OddsSpreadCostMYR = 0
				,OddsSpreadCostUSD = 0
				,OddsSpreadCostEUR = 0
				,OddsSpreadCostGBP = 0
				,OddsSpreadCostCNY = 0
				,OddsSpreadCostUSDT = 0
		END
	END

	-- Return data
	SELECT ProductId, ProductName, ReportDate, CurrencyId, CurrencyName, TotalTransaction
		,Turnover, CustomerWinLoss, LicenseeWinLoss, AmountDueToBA, BACommission, AmountCompany, OddsSpreadCost, FullParlayBoostBonus, LicenseeParlayBoostBonus
		,TurnoverMYR, CustomerWinLossMYR, LicenseeWinLossMYR, AmountDueToBAMYR, BACommissionMYR, AmountCompanyMYR, OddsSpreadCostMYR, FullParlayBoostBonusMYR, LicenseeParlayBoostBonusMYR
		,TurnoverUSD, CustomerWinLossUSD, LicenseeWinLossUSD, AmountDueToBAUSD, BACommissionUSD, AmountCompanyUSD, OddsSpreadCostUSD, FullParlayBoostBonusUSD, LicenseeParlayBoostBonusUSD
		,TurnoverEUR, CustomerWinLossEUR, LicenseeWinLossEUR, AmountDueToBAEUR, BACommissionEUR, AmountCompanyEUR, OddsSpreadCostEUR, FullParlayBoostBonusEUR, LicenseeParlayBoostBonusEUR
		,TurnoverGBP, CustomerWinLossGBP, LicenseeWinLossGBP, AmountDueToBAGBP, BACommissionGBP, AmountCompanyGBP, OddsSpreadCostGBP, FullParlayBoostBonusGBP, LicenseeParlayBoostBonusGBP
		,TurnoverCNY, CustomerWinLossCNY, LicenseeWinLossCNY, AmountDueToBACNY, BACommissionCNY, AmountCompanyCNY, OddsSpreadCostCNY, FullParlayBoostBonusCNY, LicenseeParlayBoostBonusCNY
		,TurnoverUSDT, CustomerWinLossUSDT, LicenseeWinLossUSDT, AmountDueToBAUSDT, BACommissionUSDT, AmountCompanyUSDT, OddsSpreadCostUSDT, FullParlayBoostBonusUSDT, LicenseeParlayBoostBonusUSDT
		,IsShowOddsSpread
	FROM #Result
	ORDER BY ReportDate

	DROP TABLE #ChargeInfo
	DROP TABLE #Data
	DROP TABLE #Exchange
	DROP TABLE #Products
	DROP TABLE #Report
	DROP TABLE #Result
END
GO