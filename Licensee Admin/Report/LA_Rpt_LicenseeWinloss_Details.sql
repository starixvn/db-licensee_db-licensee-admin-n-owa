/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet,bodbLicenseeNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
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
	, @BaseCurrencyName		VARCHAR(10)		= 'GBP'

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

	CREATE TABLE #Report (ReportDate DATE, CurrencyID INT, ProductID INT, Turnover MONEY, Winlost MONEY, LicenseeWL MONEY, WinlossRB MONEY, 
						AmtDueToBA MONEY, AmtDueToRB MONEY, CommBA MONEY, CommRB MONEY, Company MONEY, Betcount BIGINT)							
	CREATE TABLE #Exchange (ExchangeId INT, ExchangeDate DATE, Code VARCHAR(20), USD FLOAT, EUR FLOAT, MYR FLOAT, GBP FLOAT, CNY FLOAT, Base FLOAT)
	CREATE TABLE #Data (rptDate DATE, PartyID INT, ProductID INT, Currency INT,BetTypeId INT, Turnover MONEY, Winloss MONEY, AWinloss MONEY, AComm MONEY, PComm MONEY, Betcount BIGINT)
	CREATE TABLE #Products(ProductID INT, ProductName VARCHAR(50))
	CREATE TABLE #ChargeInfo (PartyID INT, LicenseeID INT, ProductID INT, BetTypeID INT, Rate MONEY, Fromdate DATE , Todate DATE)
	
	DECLARE @VNDCurrencyName VARCHAR(20)

	SELECT @VNDCurrencyName = currency
	FROM dbo.Exchange (NOLOCK)
	WHERE ExchangeId = 51

	INSERT INTO #ChargeInfo (PartyID, LicenseeID, ProductID, BetTypeID, Rate, Fromdate, Todate)
	SELECT DISTINCT PartyID, LicenseeID, ProductID, Bettype, 
			CASE WHEN ISNULL(isDeposit, 0) = 1 THEN DI_Rate ELSE 0 END,
			Fromdate, Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyID, @FromDate, @ToDate, @ProductCodes, 'OA', 1)
	
	INSERT INTO #Products(ProductID,ProductName)
	SELECT DISTINCT Productid,ProductName
	FROM bodb_licensee.dbo.Product3rd
	
	INSERT INTO #Products(ProductID,ProductName) VALUES (0,'Sportsbook')
	
	/* BA Product Id = 3 */
	IF (SELECT COUNT(*) FROM #ChargeInfo WHERE ProductID = 3) > 0
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
				INNER JOIN #ChargeInfo ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID = 3
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
				AND (b.CurrencyID <> 20)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
			GROUP BY ci.PartyID, b.rptDate, b.ProductID, currencyID
		)
		
		INSERT INTO #Report (ReportDate, CurrencyID, ProductID, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount)
		(
			SELECT b.rptDate, b.currency, b.ProductID
				, SUM(b.turnover) Turnover
				, SUM(b.winloss) Winloss
				, 0 AS LicenseeWL
				, 0 AS WinlossRB
				, -SUM((b.winloss * ci.Rate ) + b.AComm) AS AmountDueToBA
				, 0 AS AmountDueToRB
				, SUM(b.AComm) AS CommBA
				, 0 AS CommRB
				, 0 AS Company
				, SUM(betcount) BetCount
			FROM #Data b
				INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, Rate FROM #ChargeInfo WHERE ProductID = 3) ci ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID				
			WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			GROUP BY b.rptDate, b.Currency, b.ProductID
		)
	END
	
	/* Microgaming Live Casino Product Id = 14, Microgaming RNG Casino Product Id = 17 */
	IF (SELECT COUNT(*) FROM #ChargeInfo WHERE ProductID IN (14, 17)) > 0
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
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
				AND (b.CurrencyID <> 20)
			GROUP BY ci.PartyID, b.rptDate, b.ProductID, currencyID, ci.BetTypeId
		)
		
		INSERT INTO #Report (ReportDate, CurrencyID, ProductID, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount)
		(
			SELECT b.rptDate, b.currency, b.ProductID
				, SUM(b.turnover) Turnover
				, SUM(b.winloss) Winloss
				, -SUM(b.Winloss) AS LicenseeWL
				, 0 AS WinlossRB
				, 0 AS AmountDueToBA
				, 0 AS AmountDueToRB
				, 0 AS CommBA
				, 0 AS CommRB
				, -SUM(b.Winloss * ci.Rate) AS Company
				, SUM(betcount) BetCount
			FROM #Data b
				INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, BetTypeId, Rate FROM #MicrogamingChargeInfo WHERE ProductID IN (SELECT ProductId FROM #MicrogamingProducts)) ci 
				ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID AND ci.BetTypeId = b.BetTypeId			
			WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			GROUP BY b.rptDate, b.Currency, b.ProductID
		)
		
		DROP TABLE #MicrogamingChargeInfo
		DROP TABLE #MicrogamingProducts
	END
	
	/* Racing Product Id = 1 */
	IF (SELECT COUNT(*) FROM #ChargeInfo WHERE ProductID = 1) > 0
	BEGIN
		DELETE #Data
		
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, Turnover, Winloss, AWinloss, AComm, Betcount)
		(
			SELECT b.rptDate, ci.PartyID, b.ProductID, b.currencyID
				, SUM(b.turnover * 
					CASE WHEN b.bettype = 33 AND b.StatusId IN (114, 115) THEN 0.5 ELSE 1 END * 
					CASE WHEN @drawfilter IN (2, 3)	
							THEN CASE WHEN b.StatusId = 111 THEN 0 WHEN b.StatusId IN (114, 115) AND b.Bettype != 33
								THEN 0.5 ELSE 1
							END	ELSE 1
					END) TurnOver
				, SUM(b.MemberWL)
				, SUM(b.GrossWL)
				, SUM(b.CommissionA)
				, SUM(b.betcount * CASE WHEN @drawfilter = 2 AND b.StatusId = 111 THEN 0 ELSE 1 END) BetCount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #ChargeInfo ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID = 1
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
				AND (b.CurrencyID <> 20)
			GROUP BY ci.PartyID, b.rptDate, b.ProductID, currencyID
		)
		
		INSERT INTO #Report (ReportDate, CurrencyID, ProductID, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount)
		(
			SELECT b.rptDate, b.currency, b.ProductID
				, SUM(b.turnover) Turnover
				, SUM(b.Winloss) Winloss
				, 0 AS LicenseeWL
				, SUM(b.AWinloss) AS WinlossRB
				, 0 AS AmountDueToBA
				, -SUM(b.Winloss + b.AWinloss + b.AComm) AS AmountDueToRB
				, 0 AS CommBA
				, SUM(b.AComm) AS CommRB
				, 0 AS Company
				, SUM(b.betcount) AS betcount
			FROM #Data b
				INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, Rate FROM #ChargeInfo WHERE ProductID = 1) ci 
				ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID		
			WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			GROUP BY b.rptDate, b.Currency, b.ProductID
		)
	END
	
	IF (SELECT COUNT(*) FROM #ChargeInfo WHERE ProductID = 15) > 0
	BEGIN
		-- Region: Local variables
		DECLARE @CBProductId INT = 15
		DECLARE @CommChargeType INT = 6
		DECLARE @CashInShareChargeType INT = 7

		-- Region: Commision and Cash in share Rates
		DECLARE @CBShare AS TABLE(PartyId INT, LicenseeId INT, Rate MONEY, TypeId SMALLINT, FromDate DATETIME, ToDate DATETIME)

		INSERT INTO @CBShare(PartyId, LicenseeId, Rate, TypeId, FromDate, ToDate)
		SELECT PartyID,LicenseeID,DI_Rate,ChargeType,Fromdate,Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyID,@FromDate,@ToDate,'CB','OA',1)		
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
				(b.CurrencyID <> 20) AND
				(@Currency = 0 OR (@Currency <> 0 AND CurrencyId = @Currency)) AND
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
		
		INSERT INTO #Report (ReportDate, CurrencyID, ProductID, Company, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Betcount)
		SELECT td.rptDate, td.CurrencyId, @CBProductId,
			Turnover - WinningPrize - Cashout - CommisionShare - CashInShare,
			0, 0, 0, 0, 0, 0, 0, 0, 0
		FROM #TempData td	
		
		DROP TABLE #TempData
	END
	
	IF (SELECT COUNT(*) FROM #ChargeInfo WHERE ProductID = 25) > 0
	BEGIN
		DECLARE @COProductId INT = 25

		INSERT INTO #Report (ReportDate, CurrencyID, ProductID, Company, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Betcount)
		(
			SELECT
				d.Winlostdate,
				d.Currency,		
				@COProductId,
				SUM(TicketsPayout - BuyBackAmountSB - BuyBackAmountBA - CashoutCommission) AS Company,
				0, 0, 0, 0, 0, 0, 0, 0, 0
			FROM (
					SELECT b.Winlostdate, b.Currency,
							SUM(b.BuyBackAmt) AS BuyBackAmountSB,
							SUM(b.BABuyBackAmt) AS BuyBackAmountBA,
							SUM(b.TicketPayout) AS TicketsPayout,					
							SUM(b.BuyBackAmt * ci.Rate) AS CashoutCommission	
					FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)
						INNER JOIN #ChargeInfo ci ON b.SiteId = ci.LicenseeID AND b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate AND b.ProductID = ci.ProductId					
					WHERE b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate									
						AND (b.Currency <> 20)
						AND(@Currency = 0 OR (@Currency <> 0 AND b.Currency = @Currency))
						AND b.ProductID = @COProductId
						AND b.RoleID = 1 -- Member
					GROUP BY b.Winlostdate, b.Currency			
			) d
			GROUP BY d.Winlostdate, d.Currency
		)
	END
	
	IF (SELECT COUNT(*) FROM #ChargeInfo WHERE ProductID = 13) > 0
	BEGIN
		DECLARE @BTProductId INT = 13
		DECLARE @Bettype AS TABLE(Bettype INT, ProductId INT)
		
		INSERT INTO @Bettype (Bettype, ProductId)		
		SELECT Bettype, ProductID
		FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, 'BT,SB,BA')		

		INSERT INTO #Report (ReportDate, CurrencyID, ProductId, Company, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Betcount)
		(
			SELECT
				d.RptDate,
				d.CurrencyID,
				@BTProductId,
				SUM ((d.BTWinLoss + d.BettradeComm + d.Actual_stake - d.BuyBackAmountTotal)) AS Company,
				0, 0, 0, 0, 0, 0, 0, 0, 0
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
					AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
					AND (b.CurrencyID <> 20)
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
					AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
					AND (b.CurrencyID <> 20)
					AND b.Status NOT IN (-1, 101, 102, 103)
					AND b.CustomerCategory = 1002 -- for BT BA
				GROUP BY b.RptDate, b.CurrencyId

			) d
			GROUP BY d.RptDate, d.CurrencyID
		)
	END
	
	DECLARE @ExcludedProductIds TABLE(ProductId INT)
	INSERT INTO @ExcludedProductIds(ProductId) VALUES (1), (3), (14), (17), (15), (25), (13)
	
	IF (SELECT COUNT(*) FROM #ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) > 0
	BEGIN
		DELETE #Data
		
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, Turnover, Winloss, AWinloss, PComm, AComm, Betcount)
		(
			SELECT  b.rptDate, ci.PartyID, b.ProductID, b.currencyID
				, SUM(b.turnover * 
					CASE WHEN b.bettype = 33 AND b.StatusId IN (114, 115) THEN 0.5 ELSE 1 END * 
					CASE WHEN @drawfilter IN (2, 3)	
							THEN CASE WHEN b.StatusId = 111 THEN 0 WHEN b.StatusId IN (114, 115) AND b.Bettype != 33
								THEN 0.5 ELSE 1
							END	ELSE 1
					END) Turnover
				, SUM(b.MemberWL)
				, 0
				, SUM(CASE WHEN b.ProductID=31 THEN b.CommissionP ELSE 0 END)
				, SUM(CASE WHEN b.ProductID=31 THEN b.CommissionA ELSE 0 END)
				, SUM(b.betcount * CASE WHEN @drawfilter = 2 AND b.StatusId = 111 THEN 0 ELSE 1 END) BetCount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN (SELECT DISTINCT PartyId, LicenseeId, ProductID FROM #ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27,28)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
			GROUP BY b.rptDate, ci.PartyID, b.ProductID, b.CurrencyID
		)
		
		INSERT INTO #Report (ReportDate, CurrencyID, ProductID, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount)
		SELECT rptDate, b.Currency, b.ProductID
			, SUM(b.turnover) Turnover
			, SUM(b.Winloss + CASE WHEN b.ProductID=31 THEN b.PComm ELSE 0 END) AS Winloss
			, - SUM(b.Winloss + CASE WHEN b.ProductID=31 THEN b.PComm ELSE 0 END) AS LicenseeWL
			, 0 AS WinlossRB
			, 0 AS AmountDueToBA
			, 0 AS AmountDueToRB
			, 0 AS CommBA
			, 0 AS CommRB
			, SUM(-b.Winloss * ci.Rate - CASE WHEN b.ProductID=31 THEN (b.AComm + b.PComm) ELSE 0 END) AS Company
			, SUM(b.betcount) AS betcount
		FROM #Data b WITH (NOLOCK)
			INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, Rate FROM #ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) ci ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID				
		WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
		GROUP BY b.rptDate, b.Currency, b.ProductID
	END

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
	INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON t.CurrencyID = e.exchangeid
	
	UPDATE @CurrencyTable
	SET CurrencyCode = (CASE currency
					WHEN 51 THEN 'INH'
					WHEN 75 THEN 'PTU'
					WHEN 76 THEN 'PS'
					WHEN 77 THEN 'PTH' 
					ELSE CurrencyCode
				END)
	WHERE currency IN (51, 75, 76, 77)	

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
		, CAST(SUM(WinlossRB * e.Base) AS MONEY) AS RacingWinLoss
		, CAST(SUM(AmtDueToBA * e.Base) AS MONEY) AS AmountDueToBA
		, CAST(SUM(AmtDueToRB * e.Base) AS MONEY) AS AmountDueToRacing
		, CAST(SUM(CommBA * e.Base) AS MONEY) AS BACommission
		, CAST(SUM(CommRB * e.Base) AS MONEY) AS RacingCommission
		, CAST(SUM(Company * e.Base) AS MONEY) AS AmountCompany
		--MYR
		, CAST(SUM(Turnover * e.MYR) AS MONEY) AS TurnoverMYR
		, CAST(SUM(Winlost * e.MYR) AS MONEY) AS CustomerWinLossMYR
		, CAST(SUM(LicenseeWL * e.MYR) AS MONEY) AS LicenseeWinLossMYR
		, CAST(SUM(WinlossRB * e.MYR) AS MONEY) AS RacingWinLossMYR
		, CAST(SUM(AmtDueToBA * e.MYR) AS MONEY) AS AmountDueToBAMYR
		, CAST(SUM(AmtDueToRB * e.MYR) AS MONEY) AS AmountDueToRacingMYR
		, CAST(SUM(CommBA * e.MYR) AS MONEY) AS BACommissionMYR
		, CAST(SUM(CommRB * e.MYR) AS MONEY) AS RacingCommissionMYR
		, CAST(SUM(Company * e.MYR) AS MONEY) AS AmountCompanyMYR
		--USD
		, CAST(SUM(Turnover * e.USD) AS MONEY) AS TurnoverUSD
		, CAST(SUM(Winlost * e.USD) AS MONEY) AS CustomerWinLossUSD
		, CAST(SUM(LicenseeWL * e.USD) AS MONEY) AS LicenseeWinLossUSD
		, CAST(SUM(WinlossRB * e.USD) AS MONEY) AS RacingWinLossUSD
		, CAST(SUM(AmtDueToBA * e.USD) AS MONEY) AS AmountDueToBAUSD
		, CAST(SUM(AmtDueToRB * e.USD) AS MONEY) AS AmountDueToRacingUSD
		, CAST(SUM(CommBA * e.USD) AS MONEY) AS BACommissionUSD
		, CAST(SUM(CommRB * e.USD) AS MONEY) AS RacingCommissionUSD
		, CAST(SUM(Company * e.USD) AS MONEY) AS AmountCompanyUSD
		--EUR
		, CAST(SUM(Turnover * e.EUR) AS MONEY) AS TurnoverEUR
		, CAST(SUM(Winlost * e.EUR) AS MONEY) AS CustomerWinLossEUR
		, CAST(SUM(LicenseeWL * e.EUR) AS MONEY) AS LicenseeWinLossEUR
		, CAST(SUM(WinlossRB * e.EUR) AS MONEY) AS RacingWinLossEUR
		, CAST(SUM(AmtDueToBA * e.EUR) AS MONEY) AS AmountDueToBAEUR
		, CAST(SUM(AmtDueToRB * e.EUR) AS MONEY) AS AmountDueToRacingEUR
		, CAST(SUM(CommBA * e.EUR) AS MONEY) AS BACommissionEUR
		, CAST(SUM(CommRB * e.EUR) AS MONEY) AS RacingCommissionEUR
		, CAST(SUM(Company * e.EUR) AS MONEY) AS AmountCompanyEUR
		--GBP
		, CAST(SUM(Turnover * e.GBP) AS MONEY) AS TurnoverGBP
		, CAST(SUM(Winlost * e.GBP) AS MONEY) AS CustomerWinLossGBP
		, CAST(SUM(LicenseeWL * e.GBP) AS MONEY) AS LicenseeWinLossGBP
		, CAST(SUM(WinlossRB * e.GBP) AS MONEY) AS RacingWinLossGBP
		, CAST(SUM(AmtDueToBA * e.GBP) AS MONEY) AS AmountDueToBAGBP
		, CAST(SUM(AmtDueToRB * e.GBP) AS MONEY) AS AmountDueToRacingGBP
		, CAST(SUM(CommBA * e.GBP) AS MONEY) AS BACommissionGBP
		, CAST(SUM(CommRB * e.GBP) AS MONEY) AS RacingCommissionGBP
		, CAST(SUM(Company * e.GBP) AS MONEY) AS AmountCompanyGBP
		--CNY
		, CAST(SUM(Turnover * e.CNY) AS MONEY) AS TurnoverCNY
		, CAST(SUM(Winlost * e.CNY) AS MONEY) AS CustomerWinLossCNY
		, CAST(SUM(LicenseeWL * e.CNY) AS MONEY) AS LicenseeWinLossCNY
		, CAST(SUM(WinlossRB * e.CNY) AS MONEY) AS RacingWinLossCNY
		, CAST(SUM(AmtDueToBA * e.CNY) AS MONEY) AS AmountDueToBACNY
		, CAST(SUM(AmtDueToRB * e.CNY) AS MONEY) AS AmountDueToRacingCNY
		, CAST(SUM(CommBA * e.CNY) AS MONEY) AS BACommissionCNY
		, CAST(SUM(CommRB * e.CNY) AS MONEY) AS RacingCommissionCNY
		, CAST(SUM(Company * e.CNY) AS MONEY) AS AmountCompanyCNY
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