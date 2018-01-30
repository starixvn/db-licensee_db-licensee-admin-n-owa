/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet,bodbLicenseeNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeWinloss] 
	  @PartyIDs				VARCHAR(4000)	= ''
	, @Currency				INT				= 0
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME
	, @ProductCodes			VARCHAR(1000)
	, @DrawFilter			SMALLINT		= 1
	, @excludeTest			BIT				= 0
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
	Param's Explanation:  
		+ @PartyIDs	: a string of list PartyID, separate by ','
		+ @Currency	:  0- All Currencies
		+ @DrawFilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
		+ @excludeTest: add/remove currency UUS
		+ @ProductCodes	: Products code :
				. SB _ SportBook
				. NG _ Number Game
				...
		+ @IsConvert: 0-No Convert, 1-Convert
		+ @BaseCurrencyName: GBP, CNY, USD, EUR, MYR
*/
BEGIN
	SET NOCOUNT ON
	CREATE TABLE #Report (PartyID INT, ReportDate DATE, CurrencyID INT, Turnover MONEY, Winlost MONEY, LicenseeWL MONEY, WinlossRB MONEY, 
						AmtDueToBA MONEY, AmtDueToRB MONEY, CommBA MONEY, CommRB MONEY, Company MONEY, Betcount BIGINT)
						
	CREATE TABLE #Exchange(ExchangeId INT, ExchangeDate DATE, Code VARCHAR(20), USD FLOAT, EUR FLOAT, MYR FLOAT, GBP FLOAT, CNY FLOAT, Base FLOAT)
	
	DECLARE @ChargeInfo TABLE(PartyID INT, LicenseeID INT, ProductID INT,BetTypeId INT ,Rate MONEY, Fromdate DATE, Todate DATE)
	
	CREATE TABLE #Data (rptDate DATE, PartyID INT, ProductID INT, Currency INT,BetTypeId INT, Turnover MONEY, Winloss MONEY, AWinloss MONEY, AComm MONEY, PComm MONEY, Betcount BIGINT)
	
	INSERT INTO @ChargeInfo(PartyID, LicenseeID, ProductID, BetTypeId, Rate, Fromdate, Todate)
	SELECT DISTINCT PartyID, LicenseeID, ProductID, Bettype, DI_Rate, Fromdate, Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', @excludeTest)
	
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
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
				AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
			GROUP BY ci.PartyID, b.rptDate, b.ProductID, currencyID
		)
		
		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount)
		(
			SELECT ci.PartyID, b.rptDate, b.currency
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
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
				AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
			GROUP BY ci.PartyID, b.rptDate, b.ProductID, currencyID, ci.BetTypeId
		)
			
		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount)
		(
			SELECT ci.PartyID, b.rptDate, b.currency
				, SUM(b.turnover) Turnover
				, SUM(b.Winloss) Winloss
				, -SUM(b.Winloss) AS LicenseeWL
				, 0 AS WinlossRB
				, 0 AS AmountDueToBA
				, 0 AS AmountDueToRB
				, 0 AS CommBA
				, 0 AS CommRB
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
	
	/* Racing Product Id = 1 */
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = 1) > 0
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
				INNER JOIN @ChargeInfo ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID = 1
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
				AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
			GROUP BY ci.PartyID, b.rptDate, b.ProductID, currencyID
		)
		
		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount)
		(
			SELECT ci.PartyID, b.rptDate, b.currency
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
				INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, BetTypeId, Rate FROM @ChargeInfo WHERE ProductID = 1) ci 
				ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID		
			WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			GROUP BY ci.PartyID, b.rptDate, b.Currency
		)
	END
	
	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = 15) > 0
	BEGIN
		-- Region: Local variables
		DECLARE @CBProductId INT = 15
		DECLARE @CommChargeType INT = 6
		DECLARE @CashInShareChargeType INT = 7		
		DECLARE @Cte_AffectDate TABLE (PartyID INT, AffectedDate DATE) 		

		-- Region: Commision and Cash in share Rates
		DECLARE @CBShare AS TABLE(PartyId INT, LicenseeId INT, Rate MONEY, TypeId SMALLINT, FromDate DATETIME, ToDate DATETIME)	

		INSERT INTO @CBShare(PartyId, LicenseeId, Rate, TypeId, FromDate, ToDate)
		SELECT	ci.FromParty,
				CASE WHEN ISNULL(pd.IsDeposit, 0) = 1 THEN p.OldRefID ELSE lb.LabelID END AS LicenseeId,
				ci.Rate,
				ci.ChargeType,
				CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
				CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH(NOLOCK) ON ci.FromParty = p.PartyID
			LEFT JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH(NOLOCK) ON pd.PartyID = p.PartyID
			LEFT JOIN bodb_licensee.dbo.Labels lb WITH (NOLOCK) ON p.OldRefID = lb.LicenseeID
		WHERE FromParty IN (SELECT VAL FROM strSplit(@PartyIDs, ',')) AND ProductID = @CBProductId AND ChargeType IN (@CommChargeType,@CashInShareChargeType) AND (
			@FromDate BETWEEN ci.FromDate AND ci.ToDate OR
			@ToDate BETWEEN ci.FromDate AND ci.ToDate OR
			ci.FromDate BETWEEN @FromDate AND @ToDate OR
			ci.ToDate BETWEEN @FromDate AND @ToDate
		)
		
		-- Test Data
		IF @excludeTest = 0
		BEGIN	
			DECLARE @TempCBShare AS TABLE (PartyId INT, LicenseeId INT, Rate MONEY, TypeId SMALLINT, FromDate DATETIME, ToDate DATETIME)	

			INSERT INTO @Cte_AffectDate (PartyID, AffectedDate)
			(
				SELECT FromParty AS PartyID, MIN(FromDate) AS AffectedDate		  			  
				FROM bodb_licensee..OAS_Party p WITH (NOLOCK)
					INNER JOIN bodb_licensee..OAS_ChargeInfo ci WITH (NOLOCK) ON p.PartyID = ci.FromParty
				WHERE ChargeType != 2
				  AND p.PartyID IN (SELECT VAL FROM strSplit(@PartyIDs, ','))		  
				  AND ci.ProductID = @CBProductId
				GROUP BY FromParty
			)
			
			INSERT INTO @TempCBShare(PartyId, LicenseeId, Rate, TypeId, FromDate, ToDate)
			SELECT DISTINCT 
				f1.Val PartyId,
				CASE 
					WHEN ISNULL(pd.IsDeposit, 0) = 1
						THEN p.OldRefID
					ELSE lb.LabelID END AS LicenseeID,				
				0 DI_Rate,
				@CommChargeType,
				@FromDate,
				CASE WHEN @ToDate >= DATEADD(D, - 1, cte.AffectedDate)
						THEN DATEADD(D, - 1, cte.AffectedDate)
					ELSE @ToDate END
			FROM strSplit(@PartyIDs, ',') f1
				INNER JOIN bodb_licensee..OAS_Party p WITH (NOLOCK) ON f1.Val = p.PartyID
				LEFT JOIN bodb_licensee..OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
				LEFT JOIN bodb_licensee..labels lb(NOLOCK) ON p.OldRefID = lb.LicenseeID
				LEFT JOIN @Cte_AffectDate cte ON p.PartyID = cte.PartyID
			WHERE @FromDate <= cte.AffectedDate

			INSERT INTO @TempCBShare(PartyId, LicenseeId, Rate, TypeId, FromDate, ToDate)
			SELECT PartyId, LicenseeId, Rate, @CashInShareChargeType, FromDate, ToDate
			FROM @TempCBShare

			INSERT @CBShare(PartyId, LicenseeId, Rate, TypeId, FromDate, ToDate)
			SELECT PartyId, LicenseeId, Rate, TypeId, FromDate, ToDate
			FROM @TempCBShare
		END				
		-- End Region: Commision and Cash in share Rates

		-- Region: Get Winloss Data
		CREATE TABLE #TempData (
			PartyId							INT,
			rptDate							DATETIME,
			CurrencyId						INT,
			Turnover						MONEY,
			WinningPrize					MONEY,
			CashOut							MONEY,
			CommisionShare					MONEY,
			CashInShare						MONEY,
			CashInAmount					MONEY
		)

		INSERT INTO #TempData (PartyId, rptDate, CurrencyId, Turnover, WinningPrize, CashOut, CashInAmount)
		SELECT	cb.PartyId,
				rptDate,
				CurrencyId,
				SUM(Turnover) Turnover,
				SUM(ISNULL(WinPrizeAmount,0)) WinningPrize,
				SUM(ISNULL(CashOutAmount,0)) CashOut,
				SUM(ISNULL(BuyBackAmount,0)) CashInAmount
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN @CBShare cb ON b.SiteID = cb.LicenseeId AND b.rptDate BETWEEN cb.FromDate AND cb.ToDate
		WHERE	ProductID = @CBProductId AND
				CustomerCategory NOT IN (27, 28) AND
				b.StatusId NOT IN (-1, 101, 102, 103) AND
				(@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20)) AND
				(@Currency = 0 OR (@Currency <> 0 AND CurrencyId = @Currency)) AND
				cb.TypeId = @CommChargeType -- to remove duplicate we use one of (6,7)
		GROUP BY cb.PartyId, rptdate, CurrencyId
		-- End Region: Get Winloss Data

		UPDATE #TempData
		SET CommisionShare = td.Turnover * cm.Rate,
			CashInShare = td.CashInAmount * ci.Rate
		FROM #TempData td
		INNER JOIN @CBShare AS cm ON cm.TypeId = @CommChargeType AND (td.rptDate BETWEEN cm.FromDate AND cm.ToDate) AND cm.PartyId = td.PartyId
		INNER JOIN @CBShare AS ci ON ci.TypeId = @CashInShareChargeType AND (td.rptDate BETWEEN ci.FromDate AND ci.ToDate) AND ci.PartyId = td.PartyId
		-- End Region: Calculate Commision, Cash In Share		

		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Company, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Betcount)
		SELECT td.PartyId, td.rptDate, td.CurrencyId, 
			Turnover - WinningPrize - Cashout - CommisionShare - CashInShare,
			0, 0, 0, 0, 0, 0, 0, 0, 0
		FROM #TempData td	
		
		DROP TABLE #TempData
	END

	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID = 25) > 0
	BEGIN		
		DECLARE @COProductId INT = 25

		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Company, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Betcount)
		(
			SELECT
				d.PartyId,
				d.Winlostdate,
				d.Currency,				
				SUM(TicketsPayout - BuyBackAmountSB - BuyBackAmountBA - CashoutCommission) AS Company,
				0, 0, 0, 0, 0, 0, 0, 0, 0
			FROM (
					SELECT ci.PartyId, b.Winlostdate, b.Currency,											
							SUM(b.BuyBackAmt) AS BuyBackAmountSB,
							SUM(b.BABuyBackAmt) AS BuyBackAmountBA,
							SUM(b.TicketPayout) AS TicketsPayout,					
							SUM(b.BuyBackAmt * ci.Rate) AS CashoutCommission	
					FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)
						INNER JOIN @ChargeInfo ci ON b.SiteId = ci.LicenseeID AND b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate AND b.ProductID = ci.ProductId					
					WHERE b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate									
						AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.Currency <> 20))
						AND(@Currency = 0 OR (@Currency <> 0 AND b.Currency = @Currency))
						AND b.ProductID = @COProductId
						AND b.RoleID = 1 -- Member
					GROUP BY ci.PartyId, b.Winlostdate, b.Currency			
			) d
			GROUP BY d.PartyId, d.Winlostdate, d.Currency
		)
	END
	
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

		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Company, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Betcount)
		(
			SELECT
				d.PartyId,
				d.RptDate,
				d.CurrencyID,
				SUM ((d.BTWinLoss + d.BettradeComm + d.Actual_stake - d.BuyBackAmountTotal)) AS Company,
				0, 0, 0, 0, 0, 0, 0, 0, 0
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
					AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
					AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
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
					AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
					AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
					AND b.Status NOT IN (-1, 101, 102, 103)
					AND b.CustomerCategory = 1002 -- for BT BA	
					AND bt.ProductId = 3				
				GROUP BY b.RptDate, b.CurrencyId, ci.PartyId
			) d
			GROUP BY d.RptDate, d.CurrencyID, d.PartyId
		)
	END

	DECLARE @ExcludedProductIds TABLE(ProductId INT)
	INSERT INTO @ExcludedProductIds(ProductId) VALUES (1), (3), (14), (17), (15), (25), (13)

	IF (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) > 0
	BEGIN
		DELETE #Data
		
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, Turnover, Winloss, AWinloss, PComm, AComm, Betcount)
		(
			SELECT  b.rptDate, ci.PartyID, b.ProductID, b.currencyID
				, SUM(b.turnover * 
					CASE WHEN @drawfilter IN (2, 3) 
						THEN CASE WHEN b.StatusId = 111 THEN 0
							WHEN b.StatusId IN (114, 115)	THEN 0.5 ELSE 1	END
						ELSE 1
					END) Turnover
				, SUM(b.MemberWL)
				, 0
				, SUM(CASE WHEN b.ProductID=31 THEN b.CommissionP ELSE 0 END)
				, SUM(CASE WHEN b.ProductID=31 THEN b.CommissionA ELSE 0 END)
				, SUM(b.betcount * CASE WHEN @drawfilter = 2 AND b.StatusId = 111 THEN 0 ELSE 1 END) BetCount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN (SELECT DISTINCT PartyId, LicenseeId, ProductID FROM @ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
				AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
				AND b.customercategory NOT IN (27,28)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
			GROUP BY b.rptDate, ci.PartyID, b.ProductID, b.CurrencyID
		)

		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount)
		SELECT ci.PartyID, rptDate, b.Currency
			, SUM(b.turnover) Turnover
			, SUM(b.Winloss + CASE WHEN b.ProductID=31 THEN b.PComm ELSE 0 END) AS Winloss
			, - SUM(b.Winloss + CASE WHEN b.ProductID=31 THEN b.PComm ELSE 0 END) AS LicenseeWL
			, 0 AS WinlossRB
			, 0 AS AmountDueToBA
			, 0 AS AmountDueToRB
			, 0 AS CommBA
			, 0 AS CommRB
			, SUM(-b.Winloss * ci.Rate + CASE WHEN b.ProductID=31 THEN b.AComm ELSE 0 END) AS Company
			, SUM(b.betcount) AS betcount
		FROM #Data b WITH (NOLOCK)
			INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, Rate FROM @ChargeInfo WHERE ProductID NOT IN (SELECT ProductId From @ExcludedProductIds)) ci ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID				
		WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
		GROUP BY ci.PartyID, b.rptDate, b.Currency
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
		INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK) ON p.PartyID = b.PartyID
	GROUP BY b.PartyID, p.PartyName ,CONVERT(VARCHAR(6), b.ReportDate, 112)
	ORDER BY ReportDate ASC, CASE p.PartyName WHEN '18bb' THEN 'PIH' WHEN 'IBC' THEN 'FDL' ELSE p.PartyName END
	
	DROP TABLE #Exchange
	DROP TABLE #Report
	DROP TABLE #Data
END
GO
