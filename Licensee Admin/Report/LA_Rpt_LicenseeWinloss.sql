/*<info serverAlias="DBEXT-bodb02" executers="wsv_nap,wsv_lap" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeWinloss]
	 @PartyIDs			 VARCHAR(MAX) = ''
	,@Currency			 INT = 0
	,@FromDate			 DATETIME
	,@ToDate			 DATETIME
	,@ProductCodes		 VARCHAR(MAX)
	,@DrawFilter		 SMALLINT = 1
	,@IsConvert			 BIT = 0
	,@BaseCurrencyName	 VARCHAR(10) = 'GBP'
	,@LicenseeStatusIds	 VARCHAR(100) 
	,@PlatformId		 TINYINT = 0
AS

/*  Created:  Forrest.Nguyen
	Date: 20151020
	Original: LA_Rpt_LicenseeWinloss
	Feature: 44873
	DB: DB052.bodb02  
	Revisions:
	- 20160316: @Forrest - Change SporttypeRef to Sporttype for Microgaming  
	- 20170412: @Scofield - Removing Trading Bet Types [#73310]
	- 20171205@Bruce: fix partyid length [#87723]
	- 20171211: @Scofield - Support Colossus Bet, Bet Trade, Cashout [#87038]
	- 20180130@Bruce: integrate Exchange product [#87754]
	- 20180419@Bruce: Implement Colossus Bets Freeplay(part 2) [#93907]
	- 20180716@bruce: add new group TEST for credit [#98126]
	- 20180703@Parsons: Integrate Pragmatic Win Loss [#94108]
	- 20180815@Scofield: Remove "Exclude Test Data" checkbox [#98623]
	- 20181119@bruce: Integrate Bidme games (GD product) [#103695]
	- 20190321@Parsons: Integrate-PP-Promotion-Prize [#109014]
	- 20191204@Bruce: PP tournament [#123958]
	- 20191225@Bruce: billing term by currency [#120005]
						- @Mason: Correct SP
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
	- 20210824@Danny: filter licensee status from OIC [#159296]
	- 20220110@Danny: SG - Jackpot prize integration [#167089]
	- 20201003@Danny: Support USDT as base currency [RedmineID: #177718]
	- 20221209@Danny: Show USD (USDT) instead of USD only [RedmineID: #180313]	
	- 20221226@Danny: Fiat currency Base to USDT = 0 [RedmineID: #180703]
	- 20221003@Malcolm: Add platform filter [RedmineID: #165707]
	- 20220227@Danny: Incorporate USDTJP currency [RedmineID: #183461]
	- 20230217@Danny: Remove hard-code bettype And ProductID [#183739]
	- 20230510@Danny: New commercial terms for 12B [RedmineID: #186543]
	- 20240911@Sally: Support Odds Boost Voucher [#209884]
	
	Param's Explanation:  
		+ @PartyIDs	: a string of list PartyID, separate by ','
		+ @Currency	:  0- All Currencies
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

	-- Handle Licensee status
	SELECT @PartyIds = PartyIDs FROM bodb_Licensee.dbo.LA_f_PartyListByStatusSel(@PartyIDs, @LicenseeStatusIds)
	-- End Handle licensee status

	SELECT @ExchangeTerm_CutOffDate = f.CutoffDate FROM bodb_licensee.dbo.LA_f_GetCutOffDate() f WHERE f.TypeName = 'ExchangeTerms'

	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ',')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
		    INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END

	DECLARE @BaseCurrencyId INT

	CREATE TABLE #PartyList (PartyId INT, BaseCurrencyId INT, BaseCurrencyName VARCHAR(10))
	DECLARE @BaseCurrency TABLE (BaseCurrencyId INT, BaseCurrencyName VARCHAR(10))

	CREATE TABLE #Report (PartyID INT, ReportDate DATE, CurrencyID INT, Turnover MONEY, Winlost MONEY, LicenseeWL MONEY, 
						AmtDueToBA MONEY, CommBA MONEY, Company MONEY, Betcount INT, OddsSpreadCost MONEY, OddsBoostBonus MONEY)

	CREATE TABLE #Exchange (BaseCurrencyId INT, ExchangeId INT, ExchangeDate DATE, Code VARCHAR(65), USD FLOAT, EUR FLOAT, MYR FLOAT, GBP FLOAT, CNY FLOAT, Base FLOAT, USDT FLOAT)
	
	DECLARE @ChargeInfo TABLE(PartyID INT, LicenseeID INT, ProductID INT,BetTypeId INT ,Rate MONEY, Fromdate DATE, Todate DATE, ChargeType TINYINT, ChargeId INT)
	
	CREATE TABLE #Data (rptDate DATE, PartyID INT, ProductID INT, Currency INT,BetTypeId INT, Turnover MONEY, Winloss MONEY, AWinloss MONEY, AComm MONEY, PComm MONEY, Betcount BIGINT)
	
	CREATE TABLE #Products (GroupProductId INT, ProductId INT, ProductName VARCHAR(50), ProductCode VARCHAR(20), FromDate DATE, ToDate DATE)
	INSERT INTO #Products (GroupProductId, ProductId, ProductName, ProductCode, FromDate, ToDate)
	SELECT GroupProductId, ProductId, ProductName, ProductCode, FromDate, Todate 
	FROM bodb_Licensee.dbo.LA_f_GroupProduct(@ProductCodes, @FromDate, @ToDate) g

	SET @ProductCodes = NULL
	SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM #Products

	INSERT INTO @ChargeInfo(PartyID, LicenseeID, ProductID, BetTypeId, Rate, Fromdate, Todate, ChargeType, ChargeId)
	SELECT DISTINCT PartyID, LicenseeID, ProductID, Bettype,
			CASE WHEN ISNULL(isDeposit, 0) = 1 THEN DI_Rate ELSE 0 END,
			Fromdate, Todate,
			CASE WHEN ProductID IN(11, 39) THEN ChargeType ELSE 1 END, -- include Tip charge type
			ChargeID
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', 1)

	INSERT INTO #PartyList (PartyId)
	SELECT DISTINCT PartyId FROM @ChargeInfo

	UPDATE p
	SET p.BaseCurrencyId = ISNULL(bc.BaseCurrencyId, 6), p.BaseCurrencyName = ISNULL(e.Code, 'EUR')
	FROM #PartyList p
		LEFT JOIN bodb_licensee.dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK) ON p.PartyId = bc.PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate
		LEFT JOIN dbo.Exchange e WITH (NOLOCK) ON bc.BaseCurrencyId = e.ExchangeId

	INSERT INTO @BaseCurrency (BaseCurrencyId, BaseCurrencyName)
	SELECT DISTINCT BaseCurrencyId, BaseCurrencyName FROM #PartyList
	
	/* BA Product Id = 3 */
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = 3) > 0
	BEGIN
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, Turnover, Winloss, AWinloss, AComm, Betcount)
		(
			SELECT b.rptDate, ci.PartyID, b.ProductID, b.currencyID
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
				INNER JOIN @ChargeInfo ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID = 3
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR b.CurrencyID = @Currency)
				AND (b.CurrencyID <> @CurrencyTest)
			GROUP BY ci.PartyID, b.rptDate, b.ProductID, currencyID
		)
		
		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Turnover, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company, Betcount)
		(
			SELECT ci.PartyID, b.rptDate, b.currency
				, SUM(b.turnover) Turnover
				, SUM(b.winloss) Winloss
				, 0 AS LicenseeWL
				, -SUM((b.winloss * ci.Rate ) + b.AComm) AS AmountDueToBA
				, SUM(b.AComm) AS CommBA
				, 0 AS Company
				, SUM(betcount) BetCount
			FROM #Data b
				INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, Rate FROM @ChargeInfo WHERE ProductID = 3) ci ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID				
			WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			GROUP BY ci.PartyID, b.rptDate, b.Currency
		)
	END
	
	-- Colossus Bets
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = 15) > 0
	BEGIN
		-- Region: Local variables
		DECLARE @CBProductId INT = 15
		DECLARE @CommChargeType INT = 6
		DECLARE @CashInShareChargeType INT = 7		

		-- Region: Commision and Cash in share Rates
		DECLARE @CBShare AS TABLE(PartyId INT, LicenseeId INT, Rate MONEY, TypeId SMALLINT, FromDate DATETIME, ToDate DATETIME)

		INSERT INTO @CBShare(PartyId, LicenseeId, Rate, TypeId, FromDate, ToDate)
		SELECT PartyID,LicenseeID,DI_Rate,ChargeType,Fromdate,Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs,@FromDate,@ToDate,'CB','OA',1)		
		-- End Region: Commision and Cash in share Rates

		-- Region: Get Winloss Data
		CREATE TABLE #TempData (
			PartyId							INT,
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

		INSERT INTO #TempData (PartyId, rptDate, CurrencyId, Turnover, TurnoverForCommission, WinningPrize, CashOut, CashInAmount)
		SELECT	cb.PartyId,
				rptDate,
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
				(@Currency = 0 OR (@Currency <> 0 AND CurrencyId = @Currency)) AND
				cb.TypeId = @CommChargeType -- to remove duplicate we use one of (6,7)
		GROUP BY cb.PartyId, rptdate, CurrencyId
		-- End Region: Get Winloss Data

		UPDATE #TempData
		SET CommisionShare = td.TurnoverForCommission * cm.Rate,
			CashInShare = td.CashInAmount * ci.Rate
		FROM #TempData td
		INNER JOIN @CBShare AS cm ON cm.TypeId = @CommChargeType AND (td.rptDate BETWEEN cm.FromDate AND cm.ToDate) AND cm.PartyId = td.PartyId
		INNER JOIN @CBShare AS ci ON ci.TypeId = @CashInShareChargeType AND (td.rptDate BETWEEN ci.FromDate AND ci.ToDate) AND ci.PartyId = td.PartyId
		-- End Region: Calculate Commision, Cash In Share

		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Company, Turnover, Winlost, LicenseeWL, AmtDueToBA, CommBA, Betcount)
		SELECT td.PartyId, td.rptDate, td.CurrencyId, 
			Turnover - WinningPrize - Cashout - CommisionShare - CashInShare,
			0, 0, 0, 0, 0, 0
		FROM #TempData td
		
		DROP TABLE #TempData
	END

	-- Cashout
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = 25) > 0
	BEGIN		
		DECLARE @COProductId INT = 25

		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Company, Turnover, Winlost, LicenseeWL, AmtDueToBA, CommBA, Betcount)
		(
			SELECT
				d.PartyId,
				d.Winlostdate,
				d.Currency,				
				SUM(TicketsPayout - BuyBackAmountSB - BuyBackAmountBA - CashoutCommission) AS Company,
				0, 0, 0, 0, 0, 0
			FROM (
					SELECT ci.PartyId, b.Winlostdate, b.Currency,											
							SUM(b.BuyBackAmt) AS BuyBackAmountSB,
							SUM(b.BABuyBackAmt) AS BuyBackAmountBA,
							SUM(b.TicketPayout) AS TicketsPayout,					
							SUM(b.BuyBackAmt * ci.Rate) AS CashoutCommission	
					FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)
						INNER JOIN @ChargeInfo ci ON b.SiteId = ci.LicenseeID AND b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate AND b.ProductID = ci.ProductId					
					WHERE b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate									
						AND (b.Currency <> @CurrencyTest)
						AND(@Currency = 0 OR (@Currency <> 0 AND b.Currency = @Currency))
						AND b.ProductID = @COProductId
						AND b.RoleID = 1 -- Member
					GROUP BY ci.PartyId, b.Winlostdate, b.Currency			
			) d
			GROUP BY d.PartyId, d.Winlostdate, d.Currency
		)
	END

	-- BetTrade
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = 13) > 0
	BEGIN
		DECLARE @BTProductId INT = 13
	
		CREATE TABLE #Bettype ( Bettype INT, ProductId INT)
		INSERT INTO #Bettype (Bettype, ProductId)		
	    SELECT Bettype, ProductID
	    FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, 'BT,SB,BA')		

		CREATE NONCLUSTERED INDEX IDX_Index_Bettype ON #Bettype(Bettype)
		
		CREATE TABLE #BTChargeInfo (PartyID INT, LicenseeID INT, FromDate DATE, ToDate DATE, Rate MONEY)
		INSERT INTO #BTChargeInfo
		        ( PartyID ,
		          LicenseeID ,
		          FromDate ,
		          ToDate , 
				  Rate
		        )
		SELECT DISTINCT PartyID, LicenseeID, Fromdate, Todate, Rate
		FROM @ChargeInfo
		WHERE ProductID = @BTProductId	   

		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Company, Turnover, Winlost, LicenseeWL, AmtDueToBA, CommBA, Betcount)
		(
			SELECT
				d.PartyId,
				d.RptDate,
				d.CurrencyID,
				SUM ((d.BTWinLoss + d.BettradeComm + d.Actual_stake - d.BuyBackAmountTotal)) AS Company,
				0, 0, 0, 0, 0, 0
			FROM (				
				SELECT ci.PartyId, b.RptDate, b.CurrencyId
					, SUM(CASE WHEN b.Bettype = 901 THEN (b.BuyBackAmount - b.WinLoss) ELSE 0 END) AS Actual_stake
					, SUM(CASE WHEN b.Bettype = 901 THEN b.BuyBackAmount ELSE 0 END) AS BuyBackAmountTotal
					, SUM(CASE WHEN bt.ProductId = 0 THEN b.WinLoss ELSE 0 END) AS BTWinLoss
					, SUM (CASE WHEN b.Bettype = 901 AND b.CustomerCategory = 1001 THEN - b.BuyBackAmount * ci.Rate ELSE 0 END) AS BettradeComm
				FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
					INNER JOIN #BTChargeInfo ci ON b.SiteId = ci.LicenseeID
					INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
				WHERE b.RptDate BETWEEN ci.FromDate AND ci.ToDate
					AND (@Currency = 0 OR b.CurrencyID = @Currency)
					AND (b.CurrencyID <> @CurrencyTest)
					AND b.Status NOT IN (-1, 101, 102, 103)
					AND b.CustomerCategory IN (1001, 1002)					
					AND bt.ProductId IN (0, @BTProductId)
				GROUP BY b.RptDate, b.CurrencyId, ci.PartyId
				
				UNION ALL 
				
				-- rpt_betting_BA only contain original ticket, SOLD BOUGHT COMM ticket will be in rpt_betting
				SELECT ci.PartyId, b.RptDate, b.CurrencyId
					, 0 AS Actual_stake
					, 0 AS BuyBackAmountTotal
					, SUM(b.WinLoss) AS BTWinLoss
					, 0 AS BettradeComm
				FROM bodb_licenseereport.dbo.rpt_Betting_BA b WITH (NOLOCK)		
					INNER JOIN #BTChargeInfo ci ON b.SiteId = ci.LicenseeID 
					INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
				WHERE b.RptDate BETWEEN ci.FromDate AND ci.ToDate 					
					AND (@Currency = 0 OR b.CurrencyID = @Currency)
					AND (b.CurrencyID <> @CurrencyTest)
					AND b.Status NOT IN (-1, 101, 102, 103)
					AND b.CustomerCategory = 1002 -- for BT BA	
					AND bt.ProductId = 3				
				GROUP BY b.RptDate, b.CurrencyId, ci.PartyId
			) d
			GROUP BY d.RptDate, d.CurrencyID, d.PartyId
		)

		DROP TABLE #Bettype
		DROP TABLE #BTChargeInfo
	END

	-- GD
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = 11) > 0
	BEGIN
		DELETE #Data

		INSERT INTO #Data(rptDate, PartyID, Currency, BetTypeId, Turnover, Winloss, Betcount)
		(
			SELECT b.rptDate, b.SiteID, b.CurrencyID,b.Bettype
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
				AND b.SiteID IN (SELECT DISTINCT o.LicenseeID FROM @ChargeInfo o WHERE o.ProductID=11)
			GROUP BY b.rptDate, b.SiteID, b.CurrencyID,b.Bettype
		)

		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Turnover, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company, Betcount)
		(
			-- licensing fee
			SELECT ci.PartyID, b.rptDate, b.Currency
				, SUM(b.Turnover)
				, SUM(b.Winloss)
				, SUM(-b.Winloss)
				, 0,0
				, SUM(-b.Winloss * ISNULL(cc.Rate,ci.Rate))
				, SUM(b.Betcount)
			FROM #Data b WITH (NOLOCK)
				INNER JOIN @ChargeInfo ci ON ci.LicenseeID = b.PartyID AND b.rptDate BETWEEN ci.Fromdate AND ci.Todate
				LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cc WITH (NOLOCK) ON cc.ChargeID=ci.ChargeId AND cc.CurrencyID=b.Currency
			WHERE ci.ProductID=11 
				AND b.BetTypeId <> @GD_Tip 
				AND ci.ChargeType=1 -- gross win
			GROUP BY ci.PartyID, b.rptDate, b.Currency

			UNION ALL
			-- tip amount
			SELECT ci.PartyID, b.rptDate, b.Currency,0,0,0,0,0
				, SUM(-b.Winloss * ci.Rate)
				, 0
			FROM #Data b WITH (NOLOCK)
				INNER JOIN @ChargeInfo ci ON ci.LicenseeID = b.PartyID AND b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			WHERE ci.ProductID=11 
				AND b.BetTypeId = @GD_Tip 
				AND ci.ChargeType=12 -- GD tip
			GROUP BY ci.PartyID, b.rptDate, b.Currency
		)
	END

	DECLARE @ExcludedProductIds TABLE(ProductId INT)
	INSERT INTO @ExcludedProductIds(ProductId) VALUES (1), (3), (14), (17), (15), (25), (13), (11)

	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) > 0
	BEGIN
		DELETE #Data

		SELECT  b.rptDate, ci.PartyID, p.GroupProductId AS ProductId, b.CurrencyId
			, SUM(CASE WHEN g.TypeId IN (7, 11) THEN 0 ELSE b.turnover * 
				(CASE WHEN @drawfilter IN (2, 3) THEN 
						CASE WHEN b.StatusId = 111 THEN 0
								WHEN b.StatusId IN (114, 115)	THEN 0.5 
								ELSE 1	
						END
						ELSE 1 END)
				END) Turnover 
			, SUM(CASE WHEN g.TypeId IN (2,7,11) THEN 0 ELSE b.MemberWL END) Winloss
			, SUM(CASE WHEN b.ProductID=31 THEN b.CommissionP ELSE 0 END) PComm
			, SUM(CASE WHEN b.ProductID=31 THEN b.CommissionA ELSE 0 END) AComm
			, SUM(b.betcount * CASE WHEN (@drawfilter = 2 AND b.StatusId = 111) OR g.TypeId IN (2,7,11) THEN 0 ELSE 1 END) BetCount 
			, SUM(CASE WHEN g.TypeId IN (2,7) THEN ISNULL(-b.GrossWL, 0) ELSE 0 END) AWinloss
			, SUM(CASE WHEN g.TypeId = 11 THEN ISNULL(b.ValidBetAmount, 0) ELSE 0 END) OddsBoostBonus
		INTO #TmpData
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #Products p ON b.ProductId = p.ProductId AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			INNER JOIN (
				SELECT DISTINCT PartyId, LicenseeId, ProductID 
				FROM @ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)
			) ci ON b.SiteID = ci.LicenseeID AND p.GroupProductId = ci.ProductID
			LEFT JOIN bodb_licensee.dbo.LA_f_GroupBettype() eb ON b.Bettype = eb.Bettype AND eb.TypeID NOT IN (7,2,11) -- 7:OddsSpread Adjustment, 2:Jackpot Contribution, 11:Odds Boost Adjustment
			LEFT JOIN bodb_licensee.dbo.LA_f_GroupBettype() g ON b.Bettype = g.Bettype  AND g.TypeID  IN (7,2,11)
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.StatusId NOT IN (- 1, 101, 102, 103)
			AND (@Currency = 0 OR b.CurrencyID = @Currency)
			AND (b.CurrencyID <> @CurrencyTest)
			AND b.customercategory NOT IN (27,28)
			AND eb.Bettype IS NULL
			AND	ISNULL(b.TicketType,0) <> 2 -- Free_Bets_TicketType
		GROUP BY b.rptDate, ci.PartyID, p.GroupProductId, b.CurrencyID

		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Turnover, Winlost, LicenseeWL,Company, Betcount, OddsSpreadCost, OddsBoostBonus)
		SELECT ci.PartyID, rptDate, b.CurrencyId
			, SUM(b.turnover) Turnover
			, SUM(b.Winloss + CASE WHEN b.ProductID=31 THEN b.PComm ELSE 0 END) AS Winloss
			, SUM(-b.Winloss - CASE WHEN b.ProductID=31 THEN b.PComm ELSE 0 END) AS LicenseeWL
			, SUM(
					CASE WHEN b.ProductID=31 THEN CASE WHEN b.rptDate < @ExchangeTerm_CutOffDate THEN -b.Winloss * ISNULL(cc.Rate,ci.Rate) - (b.AComm + b.PComm)
												  ELSE  -(b.Winloss + PComm) * ISNULL(cc.Rate,ci.Rate) END
					ELSE (-b.Winloss - CASE WHEN p.ProductID IS NOT NULL THEN AWinloss ELSE 0  END + b.OddsBoostBonus) * ISNULL(cc.Rate,ci.Rate) END -- (Licensee WL + Odds Boost Bonus) * SB charge rate
				 ) Company
			, SUM(b.betcount) AS betcount
			, SUM(CASE WHEN b.ProductID = 0 THEN AWinloss ELSE 0 END) AS OddsSpreadCost
			, SUM(CASE WHEN b.ProductID = 0 THEN b.OddsBoostBonus ELSE 0 END) OddsBoostBonus
		FROM #TmpData b WITH (NOLOCK)
			INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, Rate, ChargeId, ChargeType FROM @ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) ci ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID				
			LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cc WITH (NOLOCK) ON cc.ChargeID=ci.ChargeId AND cc.CurrencyID=b.CurrencyId
			LEFT JOIN @ProductOfferContribList p ON b.ProductId = p.ProductID
		WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate AND ci.ChargeType = 1 -- Gross Win
		GROUP BY ci.PartyID, b.rptDate, b.CurrencyId

		DROP TABLE #TmpData
	END
	
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

	INSERT INTO #Exchange(ExchangeDate, ExchangeId, Code, USD, EUR, MYR, GBP, CNY, USDT)
	SELECT DISTINCT ExchangeDate, ExchangeId, Code, USD, EUR, MYR, GBP, CNY, USDT
	FROM dbo.Lrf_f_GetExchangeDaily(@FromDate, @Todate)
	WHERE ExchangeId IN (SELECT CurrencyID FROM #Report)
	
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
	ELSE IF @IsConvert = 0 AND @Currency <> 0
	BEGIN
		UPDATE #Exchange
		SET Base = 1
	END

	-- Result
	BEGIN
		CREATE TABLE #Result (PartyId INT, PartyName VARCHAR(50), ReportDate VARCHAR(6), TotalTransaction INT
			,Turnover MONEY, CustomerWinLoss MONEY, LicenseeWinLoss MONEY, AmountDueToBA MONEY, BACommission MONEY, AmountCompany MONEY, OddsSpreadCost MONEY, OddsBoostBonus MONEY
			,TurnoverMYR MONEY, CustomerWinLossMYR MONEY, LicenseeWinLossMYR MONEY, AmountDueToBAMYR MONEY, BACommissionMYR MONEY, AmountCompanyMYR MONEY, OddsSpreadCostMYR MONEY, OddsBoostBonusMYR MONEY
			,TurnoverUSD MONEY, CustomerWinLossUSD MONEY, LicenseeWinLossUSD MONEY, AmountDueToBAUSD MONEY, BACommissionUSD MONEY, AmountCompanyUSD MONEY, OddsSpreadCostUSD MONEY, OddsBoostBonusUSD MONEY
			,TurnoverEUR MONEY, CustomerWinLossEUR MONEY, LicenseeWinLossEUR MONEY, AmountDueToBAEUR MONEY, BACommissionEUR MONEY, AmountCompanyEUR MONEY, OddsSpreadCostEUR MONEY, OddsBoostBonusEUR MONEY
			,TurnoverGBP MONEY, CustomerWinLossGBP MONEY, LicenseeWinLossGBP MONEY, AmountDueToBAGBP MONEY, BACommissionGBP MONEY, AmountCompanyGBP MONEY, OddsSpreadCostGBP MONEY, OddsBoostBonusGBP MONEY
			,TurnoverCNY MONEY, CustomerWinLossCNY MONEY, LicenseeWinLossCNY MONEY, AmountDueToBACNY MONEY, BACommissionCNY MONEY, AmountCompanyCNY MONEY, OddsSpreadCostCNY MONEY, OddsBoostBonusCNY MONEY
			,TurnoverUSDT MONEY, CustomerWinLossUSDT MONEY, LicenseeWinLossUSDT MONEY, AmountDueToBAUSDT MONEY, BACommissionUSDT MONEY, AmountCompanyUSDT MONEY, OddsSpreadCostUSDT MONEY, OddsBoostBonusUSDT MONEY
			,IsShowOddsSpread BIT
			,IsShowOddsBoostBonus BIT)
		
		INSERT INTO #Result (PartyId, PartyName, ReportDate, TotalTransaction
			,Turnover, CustomerWinLoss, LicenseeWinLoss, AmountDueToBA, BACommission, AmountCompany, OddsSpreadCost, OddsBoostBonus
			,TurnoverMYR, CustomerWinLossMYR, LicenseeWinLossMYR, AmountDueToBAMYR, BACommissionMYR, AmountCompanyMYR, OddsSpreadCostMYR, OddsBoostBonusMYR
			,TurnoverUSD, CustomerWinLossUSD, LicenseeWinLossUSD, AmountDueToBAUSD, BACommissionUSD, AmountCompanyUSD, OddsSpreadCostUSD, OddsBoostBonusUSD
			,TurnoverEUR, CustomerWinLossEUR, LicenseeWinLossEUR, AmountDueToBAEUR, BACommissionEUR, AmountCompanyEUR, OddsSpreadCostEUR, OddsBoostBonusEUR
			,TurnoverGBP, CustomerWinLossGBP, LicenseeWinLossGBP, AmountDueToBAGBP, BACommissionGBP, AmountCompanyGBP, OddsSpreadCostGBP, OddsBoostBonusGBP
			,TurnoverCNY, CustomerWinLossCNY, LicenseeWinLossCNY, AmountDueToBACNY, BACommissionCNY, AmountCompanyCNY, OddsSpreadCostCNY, OddsBoostBonusCNY
			,TurnoverUSDT, CustomerWinLossUSDT, LicenseeWinLossUSDT, AmountDueToBAUSDT, BACommissionUSDT, AmountCompanyUSDT, OddsSpreadCostUSDT, OddsBoostBonusUSDT)
		SELECT b.PartyId
			,CASE p.PartyName
		 		WHEN '18bb' THEN 'PIH'
		 		WHEN 'IBC'	THEN 'FDL'
		 		ELSE p.PartyName
		 	END AS PartyName
			,CONVERT(VARCHAR(6), b.ReportDate, 112) AS ReportDate
			,SUM(Betcount) AS TotalTransaction
			-- Base Currency
			,SUM(Turnover * e.Base) AS Turnover
			,SUM(Winlost * e.Base) AS CustomerWinLoss
			,SUM(LicenseeWL * e.Base) AS LicenseeWinLoss
			,SUM(AmtDueToBA * e.Base) AS AmountDueToBA
			,SUM(CommBA * e.Base) AS BACommission
			,SUM(Company * e.Base) AS AmountCompany
			,SUM(OddsSpreadCost * e.Base) AS OddsSpreadCost
			,SUM(OddsBoostBonus * e.Base) AS OddsBoostBonus
			-- MYR
			,SUM(Turnover * e.MYR) AS TurnoverMYR
			,SUM(Winlost * e.MYR) AS CustomerWinLossMYR
			,SUM(LicenseeWL * e.MYR) AS LicenseeWinLossMYR
			,SUM(AmtDueToBA * e.MYR) AS AmountDueToBAMYR
			,SUM(CommBA * e.MYR) AS BACommissionMYR
			,SUM(Company * e.MYR) AS AmountCompanyMYR
			,SUM(OddsSpreadCost * e.MYR) AS OddsSpreadCostMYR
			,SUM(OddsBoostBonus * e.MYR) AS OddsBoostBonusMYR
			-- USD
			,SUM(Turnover * e.USD) AS TurnoverUSD
			,SUM(Winlost * e.USD) AS CustomerWinLossUSD
			,SUM(LicenseeWL * e.USD) AS LicenseeWinLossUSD
			,SUM(AmtDueToBA * e.USD) AS AmountDueToBAUSD
			,SUM(CommBA * e.USD) AS BACommissionUSD
			,SUM(Company * e.USD) AS AmountCompanyUSD
			,SUM(OddsSpreadCost * e.USD) AS OddsSpreadCostUSD
			,SUM(OddsBoostBonus * e.USD) AS OddsBoostBonusUSD
			-- EUR
			,SUM(Turnover * e.EUR) AS TurnoverEUR
			,SUM(Winlost * e.EUR) AS CustomerWinLossEUR
			,SUM(LicenseeWL * e.EUR) AS LicenseeWinLossEUR
			,SUM(AmtDueToBA * e.EUR) AS AmountDueToBAEUR
			,SUM(CommBA * e.EUR) AS BACommissionEUR
			,SUM(Company * e.EUR) AS AmountCompanyEUR
			,SUM(OddsSpreadCost * e.EUR) AS OddsSpreadCostEUR
			,SUM(OddsBoostBonus * e.EUR) AS OddsBoostBonusEUR
			-- GBP
			,SUM(Turnover * e.GBP) AS TurnoverGBP
			,SUM(Winlost * e.GBP) AS CustomerWinLossGBP
			,SUM(LicenseeWL * e.GBP) AS LicenseeWinLossGBP
			,SUM(AmtDueToBA * e.GBP) AS AmountDueToBAGBP
			,SUM(CommBA * e.GBP) AS BACommissionGBP
			,SUM(Company * e.GBP) AS AmountCompanyGBP
			,SUM(OddsSpreadCost * e.EUR) AS OddsSpreadCostGBP
			,SUM(OddsBoostBonus * e.GBP) AS OddsBoostBonusGBP
			-- CNY
			,SUM(Turnover * e.CNY) AS TurnoverCNY
			,SUM(Winlost * e.CNY) AS CustomerWinLossCNY
			,SUM(LicenseeWL * e.CNY) AS LicenseeWinLossCNY
			,SUM(AmtDueToBA * e.CNY) AS AmountDueToBACNY
			,SUM(CommBA * e.CNY) AS BACommissionCNY
			,SUM(Company * e.CNY) AS AmountCompanyCNY
			,SUM(OddsSpreadCost * e.CNY) AS OddsSpreadCostCNY
			,SUM(OddsBoostBonus * e.CNY) AS OddsBoostBonusCNY
			-- USDT
			,SUM(Turnover * e.USDT) AS TurnoverUSDT
			,SUM(Winlost * e.USDT) AS CustomerWinLossUSDT
			,SUM(LicenseeWL * e.USDT) AS LicenseeWinLossUSDT
			,SUM(AmtDueToBA * e.USDT) AS AmountDueToBAUSDT
			,SUM(CommBA * e.USDT) AS BACommissionUSDT
			,SUM(Company * e.USDT) AS AmountCompanyUSDT
			,SUM(OddsSpreadCost * e.USDT) AS OddsSpreadCostUSDT
			,SUM(OddsBoostBonus * e.USDT) AS OddsBoostBonusUSDT
		FROM #Report b
			INNER JOIN #Exchange e ON e.ExchangeDate = b.ReportDate AND e.ExchangeId = b.CurrencyID
			INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK) ON p.PartyID = b.PartyID
		GROUP BY
			b.PartyId
			,CASE p.PartyName
		 		WHEN '18bb' THEN 'PIH'
		 		WHEN 'IBC'	THEN 'FDL'
		 		ELSE p.PartyName
		 	END
			,CONVERT(VARCHAR(6), b.ReportDate, 112)

		-- Set OddsSpreadCost = 0 if value is negative
		DELETE #Exchange
		
		WHILE EXISTS (SELECT 1 FROM @BaseCurrency)
		BEGIN
			SELECT @BaseCurrencyId = NULL, @BaseCurrencyName = NULL
			SELECT TOP 1 @BaseCurrencyId = BaseCurrencyId, @BaseCurrencyName = BaseCurrencyName FROM @BaseCurrency
			
			INSERT INTO #Exchange (BaseCurrencyId, ExchangeDate, ExchangeId, Base)
			SELECT DISTINCT @BaseCurrencyId, ExchangeDate, ExchangeId, BaseCurrencyRate
			FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
			WHERE ExchangeId IN (SELECT CurrencyID FROM #Report)

			DELETE @BaseCurrency WHERE BaseCurrencyId = @BaseCurrencyId
		END

		UPDATE r
		SET -- OddsSpreadCost update
			r.OddsSpreadCost = CASE WHEN t.IsShowOddsSpread = 1 THEN r.OddsSpreadCost ELSE 0 END
			,r.OddsSpreadCostMYR = CASE WHEN t.IsShowOddsSpread = 1 THEN r.OddsSpreadCostMYR ELSE 0 END
			,r.OddsSpreadCostUSD = CASE WHEN t.IsShowOddsSpread = 1 THEN r.OddsSpreadCostUSD ELSE 0 END
			,r.OddsSpreadCostEUR = CASE WHEN t.IsShowOddsSpread = 1 THEN r.OddsSpreadCostEUR ELSE 0 END
			,r.OddsSpreadCostGBP = CASE WHEN t.IsShowOddsSpread = 1 THEN r.OddsSpreadCostGBP ELSE 0 END
			,r.OddsSpreadCostCNY = CASE WHEN t.IsShowOddsSpread = 1 THEN r.OddsSpreadCostCNY ELSE 0 END
			,r.OddsSpreadCostUSDT = CASE WHEN t.IsShowOddsSpread = 1 THEN r.OddsSpreadCostUSDT ELSE 0 END
			,r.IsShowOddsSpread = t.IsShowOddsSpread
			-- OddsBoostBonus update
			,r.OddsBoostBonus = CASE WHEN t.IsShowOddsBoostBonus = 1 THEN r.OddsBoostBonus ELSE 0 END
			,r.OddsBoostBonusMYR = CASE WHEN t.IsShowOddsBoostBonus = 1 THEN r.OddsBoostBonusMYR ELSE 0 END
			,r.OddsBoostBonusUSD = CASE WHEN t.IsShowOddsBoostBonus = 1 THEN r.OddsBoostBonusUSD ELSE 0 END
			,r.OddsBoostBonusEUR = CASE WHEN t.IsShowOddsBoostBonus = 1 THEN r.OddsBoostBonusEUR ELSE 0 END
			,r.OddsBoostBonusGBP = CASE WHEN t.IsShowOddsBoostBonus = 1 THEN r.OddsBoostBonusGBP ELSE 0 END
			,r.OddsBoostBonusCNY = CASE WHEN t.IsShowOddsBoostBonus = 1 THEN r.OddsBoostBonusCNY ELSE 0 END
			,r.OddsBoostBonusUSDT = CASE WHEN t.IsShowOddsBoostBonus = 1 THEN r.OddsBoostBonusUSDT ELSE 0 END		
			,r.IsShowOddsBoostBonus = t.IsShowOddsBoostBonus
		FROM #Result r
			INNER JOIN (
				SELECT r.PartyId, CASE WHEN SUM(r.OddsSpreadCost * e.Base) <= 0 THEN 0 ELSE 1 END AS IsShowOddsSpread
					,CASE WHEN SUM(r.OddsBoostBonus * e.Base) = 0 THEN 0 ELSE 1 END AS IsShowOddsBoostBonus
				FROM #Report r
					INNER JOIN #PartyList p ON r.PartyId = p.PartyId
					INNER JOIN #Exchange e ON p.BaseCurrencyId = e.BaseCurrencyId AND r.CurrencyId = e.ExchangeId AND r.ReportDate = e.ExchangeDate
				GROUP BY r.PartyId
			) t ON r.PartyId = t.PartyId
	END

	-- Return data
	SELECT PartyId, PartyName, ReportDate, TotalTransaction
		,Turnover, CustomerWinLoss, LicenseeWinLoss, AmountDueToBA, BACommission, AmountCompany, OddsSpreadCost, OddsBoostBonus
		,TurnoverMYR, CustomerWinLossMYR, LicenseeWinLossMYR, AmountDueToBAMYR, BACommissionMYR, AmountCompanyMYR, OddsSpreadCostMYR, OddsBoostBonusMYR
		,TurnoverUSD, CustomerWinLossUSD, LicenseeWinLossUSD, AmountDueToBAUSD, BACommissionUSD, AmountCompanyUSD, OddsSpreadCostUSD, OddsBoostBonusUSD
		,TurnoverEUR, CustomerWinLossEUR, LicenseeWinLossEUR, AmountDueToBAEUR, BACommissionEUR, AmountCompanyEUR, OddsSpreadCostEUR, OddsBoostBonusEUR
		,TurnoverGBP, CustomerWinLossGBP, LicenseeWinLossGBP, AmountDueToBAGBP, BACommissionGBP, AmountCompanyGBP, OddsSpreadCostGBP, OddsBoostBonusGBP
		,TurnoverCNY, CustomerWinLossCNY, LicenseeWinLossCNY, AmountDueToBACNY, BACommissionCNY, AmountCompanyCNY, OddsSpreadCostCNY, OddsBoostBonusCNY
		,TurnoverUSDT, CustomerWinLossUSDT, LicenseeWinLossUSDT, AmountDueToBAUSDT, BACommissionUSDT, AmountCompanyUSDT, OddsSpreadCostUSDT, OddsBoostBonusUSDT
		,IsShowOddsSpread
		,IsShowOddsBoostBonus
	FROM #Result
	ORDER BY ReportDate, PartyName

	DROP TABLE #Data
	DROP TABLE #Exchange
	DROP TABLE #PartyList
	DROP TABLE #Products
	DROP TABLE #Report
	DROP TABLE #Result
END
GO
