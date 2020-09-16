/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet,bodbLicenseeNet" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeWinloss]
	  @PartyIDs				VARCHAR(4000)	= ''
	, @Currency				INT				= 0
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME
	, @ProductCodes			VARCHAR(1000)
	, @DrawFilter			SMALLINT		= 1
	, @IsConvert			BIT				= 0
	, @BaseCurrencyName		VARCHAR(10)		= 'GBP'
WITH RECOMPILE
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
	- 20200916@Parsons: Fix bug duplicate data in case of product having multiple setting rate [#138984]
	
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
	DECLARE @GD_Tip SMALLINT = 1706, @SAG_Tip SMALLINT = 3007, 
			@PP_Contribution SMALLINT = 4297,
			@PP_JackpotPrize SMALLINT = 4298,
			@PPTournament SMALLINT = 4299,
			@PromotionPrize SMALLINT = 4300
	DECLARE @CurrencyTest INT = 20

	CREATE TABLE #Report (PartyID INT, ReportDate DATE, CurrencyID INT, Turnover MONEY, Winlost MONEY, LicenseeWL MONEY, 
						AmtDueToBA MONEY, CommBA MONEY, Company MONEY, Betcount INT)

	CREATE TABLE #Exchange(ExchangeId INT, ExchangeDate DATE, Code VARCHAR(20), USD FLOAT, EUR FLOAT, MYR FLOAT, GBP FLOAT, CNY FLOAT, Base FLOAT)
	
	DECLARE @ChargeInfo TABLE(PartyID INT, LicenseeID INT, ProductID INT,BetTypeId INT ,Rate MONEY, Fromdate DATE, Todate DATE, ChargeType TINYINT, ChargeId INT)
	
	CREATE TABLE #Data (rptDate DATE, PartyID INT, ProductID INT, Currency INT,BetTypeId INT, Turnover MONEY, Winloss MONEY, AWinloss MONEY, AComm MONEY, PComm MONEY, Betcount BIGINT)
	
	INSERT INTO @ChargeInfo(PartyID, LicenseeID, ProductID, BetTypeId, Rate, Fromdate, Todate, ChargeType, ChargeId)
	SELECT DISTINCT PartyID, LicenseeID, ProductID, Bettype,
			CASE WHEN ISNULL(isDeposit, 0) = 1 THEN DI_Rate ELSE 0 END,
			Fromdate, Todate,
			CASE WHEN ProductID IN(11, 39) THEN ChargeType ELSE 1 END, -- include Tip charge type
			ChargeID
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
	
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
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
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
	
	/* Microgaming Live Casino Product Id = 14, Microgaming RNG Casino Product Id = 17 */
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID IN (14, 17)) > 0
	BEGIN
		DELETE #Data
		
		CREATE TABLE #GameTypes (ProductId INT, BettypeRef INT, BettypeId INT)
		CREATE TABLE #MicrogamingChargeInfo(PartyID INT, LicenseeID INT, ProductID INT,BetTypeId INT ,Rate MONEY, Fromdate DATE, Todate DATE)

		INSERT INTO #GameTypes (ProductId, BettypeId, BettypeRef)
		SELECT CASE WHEN sp.Sporttype = 203 THEN 14
					WHEN sp.Sporttype = 205 THEN 17 ELSE 0 END AS ProductId, sp.Bettype, pr.BettypeRef
		FROM bodb_licensee.dbo.Sport_Bettype_Reference sp WITH (NOLOCK)
			LEFT JOIN bodb_licensee.dbo.LA_Product3rdSub pr WITH (NOLOCK) ON sp.BettypeRef = pr.BettypeRef
		GROUP BY sp.Sporttype, sp.Bettype, pr.BettypeRef
		
		INSERT INTO #MicrogamingChargeInfo(PartyID, LicenseeID, ProductID, BetTypeId, Rate, Fromdate, Todate)
		SELECT PartyID, LicenseeID, ci.ProductID, gt.BetTypeId, Rate, Fromdate, Todate 
		FROM @ChargeInfo ci
		INNER JOIN #GameTypes gt ON ci.ProductID = gt.ProductId AND ci.BetTypeId = gt.BettypeRef
		
		DROP TABLE #GameTypes
			
		CREATE TABLE #MicrogamingProducts (ProductId INT)
		
		IF EXISTS (SELECT * FROM @ChargeInfo WHERE ProductID = 14)
		BEGIN
			INSERT INTO #MicrogamingProducts VALUES(14)
		END
		
		IF EXISTS (SELECT * FROM @ChargeInfo WHERE ProductID = 17)
		BEGIN
			INSERT INTO #MicrogamingProducts VALUES(17)
		END
		
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, BetTypeId, Turnover, Winloss, AWinloss, AComm, Betcount)
		(
			SELECT b.rptDate, ci.PartyID, b.ProductID, b.currencyID, ci.BetTypeId
				, SUM(b.turnover) Turnover
				, SUM(b.MemberWL)
				, 0
				, 0
				, SUM(b.betcount) BetCount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN (SELECT DISTINCT PartyID, LicenseeID, ProductID, BetTypeId FROM #MicrogamingChargeInfo) ci ON b.SiteID = ci.LicenseeID AND ci.BetTypeId = b.Bettype AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID IN (SELECT ProductId FROM #MicrogamingProducts)
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR b.CurrencyID = @Currency)
				AND (b.CurrencyID <> @CurrencyTest)
			GROUP BY ci.PartyID, b.rptDate, b.ProductID, currencyID, ci.BetTypeId
		)
			
		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Turnover, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company, Betcount)
		(
			SELECT ci.PartyID, b.rptDate, b.currency
				, SUM(b.turnover) Turnover
				, SUM(b.Winloss) Winloss
				, -SUM(b.Winloss) AS LicenseeWL
				, 0 AS AmountDueToBA
				, 0 AS CommBA
				, -SUM(b.Winloss * ci.Rate) AS Company
				, SUM(b.betcount) AS betcount
			FROM #Data b
				INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, BetTypeId, Rate FROM #MicrogamingChargeInfo WHERE ProductID IN(SELECT ProductId FROM #MicrogamingProducts)) ci 
				ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID AND ci.BetTypeId = b.BetTypeId			
			WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			GROUP BY ci.PartyID, b.rptDate, b.Currency
		)
		
		DROP TABLE #MicrogamingChargeInfo
		DROP TABLE #MicrogamingProducts
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

		SELECT  b.rptDate, ci.PartyID, b.ProductID, b.CurrencyId
			, SUM(b.turnover * 
				CASE WHEN @drawfilter IN (2, 3) THEN 
						CASE WHEN b.StatusId = 111 THEN 0
								WHEN b.StatusId IN (114, 115)	THEN 0.5 
								ELSE 1	
						END
						ELSE 1
				END) Turnover 
			, SUM(CASE WHEN b.Bettype = @PP_Contribution THEN 0 ELSE b.MemberWL END) Winloss
			, SUM(CASE WHEN b.ProductID=31 THEN b.CommissionP ELSE 0 END) PComm
			, SUM(CASE WHEN b.ProductID=31 THEN b.CommissionA ELSE 0 END) AComm
			, SUM(b.betcount * CASE WHEN (@drawfilter = 2 AND b.StatusId = 111) OR b.Bettype = @PP_Contribution THEN 0 ELSE 1 END) BetCount 
			, SUM(CASE WHEN b.Bettype = @PP_Contribution THEN ISNULL(-b.GrossWL, 0) ELSE 0 END) Contribution
		INTO #TmpData
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN (
				SELECT DISTINCT PartyId, LicenseeId, ProductID 
				FROM @ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)
			) ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.StatusId NOT IN (- 1, 101, 102, 103)
			AND (@Currency = 0 OR b.CurrencyID = @Currency)
			AND (b.CurrencyID <> @CurrencyTest)
			AND b.customercategory NOT IN (27,28)
			AND b.Bettype NOT IN (901,902,903,904,911,912,913,914,@SAG_Tip,@PromotionPrize,@PPTournament,@PP_JackpotPrize)
		GROUP BY b.rptDate, ci.PartyID, b.ProductID, b.CurrencyID

		;WITH cte_ChargInfo AS
		(
		    SELECT TOP(1) WITH TIES PartyID, Fromdate, Todate, ci.ProductID, Rate, ChargeType, ChargeId
			FROM @ChargeInfo ci
			LEFT JOIN @ExcludedProductIds p ON ci.ProductID = p.ProductID
			WHERE p.ProductId IS NULL
			ORDER BY ROW_NUMBER() OVER(PARTITION BY PartyID, Fromdate, Todate, ci.ProductID, Rate, ChargeType ORDER BY ChargeId)
		)
		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Turnover, Winlost, LicenseeWL,Company, Betcount)
		SELECT ci.PartyID, rptDate, b.CurrencyId
			, SUM(b.turnover) Turnover
			, SUM(b.Winloss + CASE WHEN b.ProductID=31 THEN b.PComm ELSE 0 END) AS Winloss
			, SUM(-b.Winloss + CASE WHEN b.ProductID=31 THEN b.PComm ELSE 0 END) AS LicenseeWL
			, SUM((-b.Winloss - Contribution) * ISNULL(cc.Rate,ci.Rate) - CASE WHEN b.ProductID=31 THEN (b.AComm + b.PComm) ELSE 0 END) AS Company
			, SUM(b.betcount) AS betcount
		FROM #TmpData b WITH (NOLOCK)
			INNER JOIN cte_ChargInfo ci	ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID
			LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cc WITH (NOLOCK) ON cc.ChargeID=ci.ChargeId AND cc.CurrencyID=b.CurrencyId
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

	INSERT INTO #Exchange(ExchangeDate, ExchangeId, Code, USD, EUR, MYR, GBP, CNY)
	SELECT DISTINCT ExchangeDate, ExchangeId, Code, USD, EUR, MYR, GBP, CNY
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
						ELSE 1 
					 END)
	END
	ELSE IF @IsConvert = 0 AND @Currency <> 0
	BEGIN
		UPDATE #Exchange
		SET Base = 1
	END

	SELECT b.PartyID
		, CASE p.PartyName
		 	WHEN '18bb' THEN 'PIH'
		 	WHEN 'IBC'	THEN 'FDL'
		 	ELSE p.PartyName
		 	END AS PartyName
		, CONVERT(VARCHAR(6), b.ReportDate, 112) AS ReportDate
		, SUM(Betcount) AS TotalTransaction
		, CAST(SUM(Turnover * e.Base) AS MONEY) AS Turnover
		, CAST(SUM(Winlost * e.Base) AS MONEY) AS CustomerWinLoss
		, CAST(SUM(LicenseeWL * e.Base) AS MONEY) AS LicenseeWinLoss
		, CAST(SUM(AmtDueToBA * e.Base) AS MONEY) AS AmountDueToBA
		, CAST(SUM(CommBA * e.Base) AS MONEY) AS BACommission
		, CAST(SUM(Company * e.Base) AS MONEY) AS AmountCompany
		--MYR
		, CAST(SUM(Turnover * e.MYR) AS MONEY) AS TurnoverMYR
		, CAST(SUM(Winlost * e.MYR) AS MONEY) AS CustomerWinLossMYR
		, CAST(SUM(LicenseeWL * e.MYR) AS MONEY) AS LicenseeWinLossMYR
		, CAST(SUM(AmtDueToBA * e.MYR) AS MONEY) AS AmountDueToBAMYR
		, CAST(SUM(CommBA * e.MYR) AS MONEY) AS BACommissionMYR
		, CAST(SUM(Company * e.MYR) AS MONEY) AS AmountCompanyMYR
		--USD
		, CAST(SUM(Turnover * e.USD) AS MONEY) AS TurnoverUSD
		, CAST(SUM(Winlost * e.USD) AS MONEY) AS CustomerWinLossUSD
		, CAST(SUM(LicenseeWL * e.USD) AS MONEY) AS LicenseeWinLossUSD
		, CAST(SUM(AmtDueToBA * e.USD) AS MONEY) AS AmountDueToBAUSD
		, CAST(SUM(CommBA * e.USD) AS MONEY) AS BACommissionUSD
		, CAST(SUM(Company * e.USD) AS MONEY) AS AmountCompanyUSD
		--EUR
		, CAST(SUM(Turnover * e.EUR) AS MONEY) AS TurnoverEUR
		, CAST(SUM(Winlost * e.EUR) AS MONEY) AS CustomerWinLossEUR
		, CAST(SUM(LicenseeWL * e.EUR) AS MONEY) AS LicenseeWinLossEUR
		, CAST(SUM(AmtDueToBA * e.EUR) AS MONEY) AS AmountDueToBAEUR
		, CAST(SUM(CommBA * e.EUR) AS MONEY) AS BACommissionEUR
		, CAST(SUM(Company * e.EUR) AS MONEY) AS AmountCompanyEUR
		--GBP
		, CAST(SUM(Turnover * e.GBP) AS MONEY) AS TurnoverGBP
		, CAST(SUM(Winlost * e.GBP) AS MONEY) AS CustomerWinLossGBP
		, CAST(SUM(LicenseeWL * e.GBP) AS MONEY) AS LicenseeWinLossGBP
		, CAST(SUM(AmtDueToBA * e.GBP) AS MONEY) AS AmountDueToBAGBP
		, CAST(SUM(CommBA * e.GBP) AS MONEY) AS BACommissionGBP
		, CAST(SUM(Company * e.GBP) AS MONEY) AS AmountCompanyGBP
		--CNY
		, CAST(SUM(Turnover * e.CNY) AS MONEY) AS TurnoverCNY
		, CAST(SUM(Winlost * e.CNY) AS MONEY) AS CustomerWinLossCNY
		, CAST(SUM(LicenseeWL * e.CNY) AS MONEY) AS LicenseeWinLossCNY
		, CAST(SUM(AmtDueToBA * e.CNY) AS MONEY) AS AmountDueToBACNY
		, CAST(SUM(CommBA * e.CNY) AS MONEY) AS BACommissionCNY
		, CAST(SUM(Company * e.CNY) AS MONEY) AS AmountCompanyCNY
	FROM #Report b
		INNER JOIN #Exchange e ON e.ExchangeDate = b.ReportDate AND e.ExchangeId = b.CurrencyID
		INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK) ON p.PartyID = b.PartyID
	GROUP BY b.PartyID, p.PartyName ,CONVERT(VARCHAR(6), b.ReportDate, 112)
	ORDER BY ReportDate ASC, CASE p.PartyName WHEN '18bb' THEN 'PIH' WHEN 'IBC' THEN 'FDL' ELSE p.PartyName END
	
	DROP TABLE #Exchange
	DROP TABLE #Report
	DROP TABLE #Data
END
GO