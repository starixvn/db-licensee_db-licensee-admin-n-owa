/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet,bodbLicenseeNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeWinloss_Details] 
	  @PartyID				INT
	, @Currency				INT				= 0
	, @FromDate				SMALLDATETIME	
	, @ToDate				SMALLDATETIME	
	, @ProductCodes			VARCHAR(1000)	
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
	DECLARE @GD_Tip SMALLINT = 1706,
			@PP_Contribution SMALLINT = 4297,
			@OddsSpread_BetType SMALLINT = 999
	DECLARE @CurrencyTest INT = 20

	CREATE TABLE #Report (ReportDate DATE, CurrencyID INT, ProductID INT, Turnover MONEY, Winlost MONEY, LicenseeWL MONEY,
						AmtDueToBA MONEY, CommBA MONEY, Company MONEY, Betcount INT, OddsSpreadCost MONEY)
	CREATE TABLE #Exchange (ExchangeId INT, ExchangeDate DATE, Code VARCHAR(20), USD FLOAT, EUR FLOAT, MYR FLOAT, GBP FLOAT, CNY FLOAT, Base FLOAT)
	CREATE TABLE #Data (PartyID INT, rptDate DATE,ProductID INT, Currency INT,BetTypeId INT, Turnover MONEY, Winloss MONEY, AWinloss MONEY, AComm MONEY, PComm MONEY, Betcount BIGINT)
	CREATE TABLE #Products(ProductID INT, ProductName VARCHAR(50))
	CREATE TABLE #ChargeInfo (PartyID INT, LicenseeID INT, ProductID INT, BetTypeID INT, Rate MONEY, Fromdate DATE , Todate DATE, ChargeType TINYINT, ChargeID INT)

	INSERT INTO #ChargeInfo (PartyID, LicenseeID, ProductID, BetTypeID, Rate, Fromdate, Todate, ChargeType, ChargeID)
	SELECT DISTINCT PartyID, LicenseeID, ProductID, Bettype, 
			CASE WHEN ISNULL(isDeposit, 0) = 1 THEN DI_Rate ELSE 0 END,
			Fromdate, Todate,
			CASE WHEN ProductID IN(11,39) THEN ChargeType ELSE 1 END, -- include GD tip charge type
			ChargeID
	FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyID, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
	
	INSERT INTO #Products(ProductID,ProductName)
	SELECT DISTINCT Productid,ProductName
	FROM bodb_licensee.dbo.Product3rd WITH (NOLOCK)
	
	INSERT INTO #Products(ProductID,ProductName) VALUES (0,'Sportsbook')
	
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
				LEFT JOIN bodb_licensee.dbo.LA_f_ExcludedBettypeListSel('13,25','') eb ON b.Bettype = eb.BettypeID
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID = 3
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR b.CurrencyID = @Currency)
				AND (b.CurrencyID <> @CurrencyTest)
				AND eb.BettypeID IS NULL
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
	
	/* Microgaming Live Casino Product Id = 14, Microgaming RNG Casino Product Id = 17 */
	IF (SELECT COUNT(*) FROM #ChargeInfo WHERE ProductID IN (14, 17)) > 0
	BEGIN
		DELETE #Data
		
		CREATE TABLE #GameTypes (ProductId INT, BettypeRef INT, BettypeId INT)
		CREATE TABLE #MicrogamingChargeInfo(LicenseeID INT, ProductID INT,BetTypeId INT ,Rate MONEY, Fromdate DATE, Todate DATE)

		INSERT INTO #GameTypes (ProductId, BettypeId, BettypeRef)
		SELECT CASE WHEN sp.Sporttype = 203 THEN 14
					WHEN sp.Sporttype = 205 THEN 17 ELSE 0 END AS ProductId, sp.Bettype, pr.BettypeRef
		FROM bodb_licensee.dbo.Sport_Bettype_Reference sp WITH (NOLOCK)
			LEFT JOIN bodb_licensee.dbo.LA_Product3rdSub pr WITH (NOLOCK) ON sp.BettypeRef = pr.BettypeRef
		GROUP BY sp.Sporttype, sp.Bettype, pr.BettypeRef
		
		INSERT INTO #MicrogamingChargeInfo(LicenseeID, ProductID, BetTypeId, Rate, Fromdate, Todate)
		SELECT LicenseeID, ci.ProductID, gt.BetTypeId, Rate, Fromdate, Todate 
		FROM #ChargeInfo ci
		INNER JOIN #GameTypes gt ON ci.ProductID = gt.ProductId AND ci.BetTypeId = gt.BettypeRef
		
		DROP TABLE #GameTypes
		
		CREATE TABLE #MicrogamingProducts (ProductId INT)
		
		IF EXISTS (SELECT * FROM #ChargeInfo WHERE ProductID = 14)
		BEGIN
			INSERT INTO #MicrogamingProducts VALUES(14)
		END
		
		IF EXISTS (SELECT * FROM #ChargeInfo WHERE ProductID = 17)
		BEGIN
			INSERT INTO #MicrogamingProducts VALUES(17)
		END
		
		INSERT INTO #Data(rptDate, ProductID, Currency, BetTypeId, Turnover, Winloss, AWinloss, AComm, Betcount)
		(
			SELECT b.rptDate,  b.ProductID, b.currencyID, ci.BetTypeId
				, SUM(b.turnover) Turnover
				, SUM(b.MemberWL)
				, 0
				, 0
				, SUM(b.betcount) BetCount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN (SELECT DISTINCT LicenseeID, ProductID, BetTypeId FROM #MicrogamingChargeInfo) ci ON b.SiteID = ci.LicenseeID AND ci.BetTypeId = b.Bettype AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID IN (SELECT ProductId FROM #MicrogamingProducts)
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR b.CurrencyID = @Currency)
				AND (b.CurrencyID <> @CurrencyTest)
			GROUP BY b.rptDate, b.ProductID, currencyID, ci.BetTypeId
		)
		
		INSERT INTO #Report (ReportDate, CurrencyID, ProductID, Turnover, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company, Betcount)
		(
			SELECT b.rptDate, b.currency, b.ProductID
				, SUM(b.turnover) Turnover
				, SUM(b.winloss) Winloss
				, -SUM(b.Winloss) AS LicenseeWL
				, 0 AS AmountDueToBA
				, 0 AS CommBA
				, -SUM(b.Winloss * ci.Rate) AS Company
				, SUM(betcount) BetCount
			FROM #Data b
				INNER JOIN (SELECT DISTINCT Fromdate, Todate, ProductID, BetTypeId, Rate FROM #MicrogamingChargeInfo WHERE ProductID IN (SELECT ProductId FROM #MicrogamingProducts)) ci 
					ON b.ProductID = ci.ProductID AND ci.BetTypeId = b.BetTypeId
			WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			GROUP BY b.rptDate, b.Currency, b.ProductID
		)
		
		DROP TABLE #MicrogamingChargeInfo
		DROP TABLE #MicrogamingProducts
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
		
		SELECT ci.PartyID, b.rptDate, b.ProductID, b.CurrencyId
			, SUM(b.turnover * 
				CASE WHEN b.bettype = 33 AND b.StatusId IN (114, 115) THEN 0.5 ELSE 1 END * 
				CASE WHEN @drawfilter IN (2, 3)	
						THEN CASE WHEN b.StatusId = 111 THEN 0 
						          WHEN b.StatusId IN (114, 115) AND b.Bettype != 33 THEN 0.5 
								  ELSE 1
							  END	
						ELSE 1
				END) Turnover
			, SUM(b.MemberWL) Winloss
			, SUM(CASE WHEN b.ProductID=31 THEN b.CommissionP ELSE 0 END) PComm
			, SUM(CASE WHEN b.ProductID=31 THEN b.CommissionA ELSE 0 END) AComm
			, SUM(b.betcount * CASE WHEN (@drawfilter = 2 AND b.StatusId = 111) OR b.Bettype IN (@PP_Contribution, @OddsSpread_BetType) THEN 0 ELSE 1 END) BetCount 
			, SUM(CASE WHEN b.Bettype IN (@PP_Contribution, @OddsSpread_BetType) THEN ISNULL(-b.GrossWL, 0) ELSE 0 END) AWinloss
		INTO #TmpData
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN (SELECT DISTINCT PartyID, LicenseeId, ProductID FROM #ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
			LEFT JOIN bodb_licensee.dbo.LA_f_ExcludedBettypeListSel('','999,4297') eb ON b.Bettype = eb.BettypeID
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.StatusId NOT IN (- 1, 101, 102, 103)
			AND (@Currency = 0 OR b.CurrencyID = @Currency)
			AND (b.CurrencyID <> @CurrencyTest)
			AND b.customercategory NOT IN (27,28)
			AND eb.BettypeID IS NULL
		GROUP BY ci.PartyID, b.rptDate, b.ProductID, b.CurrencyID

		INSERT INTO #Report (ReportDate, CurrencyID, ProductID, Turnover, Winlost, LicenseeWL, Company, Betcount, OddsSpreadCost)
		SELECT rptDate, b.CurrencyId, b.ProductID
			, SUM(b.turnover) Turnover
			, SUM(b.Winloss + CASE WHEN b.ProductID=31 THEN b.PComm ELSE 0 END) AS Winloss
			, SUM(-b.Winloss + CASE WHEN b.ProductID=31 THEN b.PComm ELSE 0 END) AS LicenseeWL
			, SUM((-b.Winloss - CASE WHEN b.ProductID = 32 THEN AWinloss ELSE 0 END) * ISNULL(cc.Rate,ci.Rate) - CASE WHEN b.ProductID=31 THEN (b.AComm + b.PComm) ELSE 0 END) AS Company
			, SUM(b.betcount) AS betcount
			, SUM(AWinloss) AS OddsSpreadCost
		FROM #TmpData b WITH (NOLOCK)
			INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, Rate, ChargeID, ChargeType FROM #ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) ci ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID				
			LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cc WITH (NOLOCK) ON cc.ChargeID=ci.ChargeId AND b.CurrencyId=cc.CurrencyID
		WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate AND ci.ChargeType = 1 -- Gross Win
		GROUP BY b.rptDate, b.CurrencyId, b.ProductID
		
		DROP TABLE #TmpData
	END

	INSERT INTO #Exchange(ExchangeDate, ExchangeId, Code, USD, EUR, MYR, GBP, CNY)
	SELECT DISTINCT ExchangeDate, ExchangeId, Code, USD, EUR, MYR, GBP, CNY
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
						ELSE 1 
					 END)
	END
	ELSE IF @IsConvert = 0
	BEGIN
		UPDATE #Exchange
		SET Base = 1
	END

	--Update Currency Name
	DECLARE @CurrencyTable AS TABLE (currency INT, CurrencyName VARCHAR(20), CurrencyCode VARCHAR(20))
	INSERT INTO @CurrencyTable(currency, CurrencyName, CurrencyCode)
	SELECT t.CurrencyID, e.currency, e.Code
	FROM (SELECT DISTINCT CurrencyID FROM #Report) t
	INNER JOIN dbo.Exchange e WITH (NOLOCK) ON t.CurrencyID = e.exchangeid
	
	UPDATE @CurrencyTable
	SET CurrencyCode = (CASE currency
					WHEN 51 THEN 'INH'
					WHEN 75 THEN 'PTU'
					WHEN 76 THEN 'PS'
					WHEN 77 THEN 'PTH'
					WHEN 92 THEN 'HID'
					ELSE CurrencyCode
				END)
	WHERE currency IN (51, 75, 76, 77, 92)	

	UPDATE t1
	SET CurrencyCode = t1.CurrencyCode + ' (' + CurrencyName + ')'
	FROM @CurrencyTable t1
	INNER JOIN (
	   SELECT CurrencyCode
		FROM @CurrencyTable
		GROUP BY CurrencyCode
		HAVING COUNT(1) > 1
	) t2 ON t1.CurrencyCode = t2.CurrencyCode

	SELECT p.ProductID, p.ProductName
		, CASE WHEN @ReportBy = 1 THEN CONVERT(VARCHAR(8), b.ReportDate, 112)
			 WHEN @ReportBy = 2 THEN CONVERT(VARCHAR(6), b.ReportDate, 112)
			 ELSE '0' END ReportDate
		, b.CurrencyID
		, CASE WHEN b.CurrencyID = 20 THEN e.Code			
			 ELSE ISNULL(t.CurrencyCode,e.Code) END AS CurrencyName
		, SUM(Betcount) AS TotalTransaction
		, CAST(SUM(Turnover * e.Base) AS MONEY) AS Turnover
		, CAST(SUM(Winlost * e.Base) AS MONEY) AS CustomerWinLoss
		, CAST(SUM(LicenseeWL * e.Base) AS MONEY) AS LicenseeWinLoss
		, CAST(SUM(AmtDueToBA * e.Base) AS MONEY) AS AmountDueToBA
		, CAST(SUM(CommBA * e.Base) AS MONEY) AS BACommission
		, CAST(SUM(Company * e.Base) AS MONEY) AS AmountCompany
		, CAST(SUM(OddsSpreadCost * e.Base) AS MONEY) AS OddsSpreadCost
		--MYR
		, CAST(SUM(Turnover * e.MYR) AS MONEY) AS TurnoverMYR
		, CAST(SUM(Winlost * e.MYR) AS MONEY) AS CustomerWinLossMYR
		, CAST(SUM(LicenseeWL * e.MYR) AS MONEY) AS LicenseeWinLossMYR
		, CAST(SUM(AmtDueToBA * e.MYR) AS MONEY) AS AmountDueToBAMYR
		, CAST(SUM(CommBA * e.MYR) AS MONEY) AS BACommissionMYR
		, CAST(SUM(Company * e.MYR) AS MONEY) AS AmountCompanyMYR
		, CAST(SUM(OddsSpreadCost * e.MYR) AS MONEY) AS OddsSpreadCostMYR
		--USD
		, CAST(SUM(Turnover * e.USD) AS MONEY) AS TurnoverUSD
		, CAST(SUM(Winlost * e.USD) AS MONEY) AS CustomerWinLossUSD
		, CAST(SUM(LicenseeWL * e.USD) AS MONEY) AS LicenseeWinLossUSD
		, CAST(SUM(AmtDueToBA * e.USD) AS MONEY) AS AmountDueToBAUSD
		, CAST(SUM(CommBA * e.USD) AS MONEY) AS BACommissionUSD
		, CAST(SUM(Company * e.USD) AS MONEY) AS AmountCompanyUSD
		, CAST(SUM(OddsSpreadCost * e.USD) AS MONEY) AS OddsSpreadCostUSD
		--EUR
		, CAST(SUM(Turnover * e.EUR) AS MONEY) AS TurnoverEUR
		, CAST(SUM(Winlost * e.EUR) AS MONEY) AS CustomerWinLossEUR
		, CAST(SUM(LicenseeWL * e.EUR) AS MONEY) AS LicenseeWinLossEUR
		, CAST(SUM(AmtDueToBA * e.EUR) AS MONEY) AS AmountDueToBAEUR
		, CAST(SUM(CommBA * e.EUR) AS MONEY) AS BACommissionEUR
		, CAST(SUM(Company * e.EUR) AS MONEY) AS AmountCompanyEUR
		, CAST(SUM(OddsSpreadCost * e.EUR) AS MONEY) AS OddsSpreadCostEUR
		--GBP
		, CAST(SUM(Turnover * e.GBP) AS MONEY) AS TurnoverGBP
		, CAST(SUM(Winlost * e.GBP) AS MONEY) AS CustomerWinLossGBP
		, CAST(SUM(LicenseeWL * e.GBP) AS MONEY) AS LicenseeWinLossGBP
		, CAST(SUM(AmtDueToBA * e.GBP) AS MONEY) AS AmountDueToBAGBP
		, CAST(SUM(CommBA * e.GBP) AS MONEY) AS BACommissionGBP
		, CAST(SUM(Company * e.GBP) AS MONEY) AS AmountCompanyGBP
		, CAST(SUM(OddsSpreadCost * e.GBP) AS MONEY) AS OddsSpreadCostGBP
		--CNY
		, CAST(SUM(Turnover * e.CNY) AS MONEY) AS TurnoverCNY
		, CAST(SUM(Winlost * e.CNY) AS MONEY) AS CustomerWinLossCNY
		, CAST(SUM(LicenseeWL * e.CNY) AS MONEY) AS LicenseeWinLossCNY
		, CAST(SUM(AmtDueToBA * e.CNY) AS MONEY) AS AmountDueToBACNY
		, CAST(SUM(CommBA * e.CNY) AS MONEY) AS BACommissionCNY
		, CAST(SUM(Company * e.CNY) AS MONEY) AS AmountCompanyCNY
		, CAST(SUM(OddsSpreadCost * e.CNY) AS MONEY) AS OddsSpreadCostCNY
	FROM #Report b
		INNER JOIN #Exchange e ON e.ExchangeDate = b.ReportDate AND e.ExchangeId = b.CurrencyID
		INNER JOIN #Products p ON b.ProductID = p.ProductID
		LEFT JOIN @CurrencyTable t ON b.CurrencyID = t.currency
	GROUP BY b.CurrencyID, p.Productid, p.ProductName,
			CASE WHEN @ReportBy = 1 THEN CONVERT(VARCHAR(8), b.ReportDate, 112)
				 WHEN @ReportBy = 2 THEN CONVERT(VARCHAR(6), b.ReportDate, 112)
				 ELSE '0' END, 
			CASE WHEN b.CurrencyID = 20 THEN e.Code
				 ELSE ISNULL(t.CurrencyCode, e.Code) END 
	ORDER BY ReportDate ASC

	DROP TABLE #Report
	DROP TABLE #ChargeInfo	
	DROP TABLE #Data
	DROP TABLE #Exchange
	DROP TABLE #Products
END
GO