/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap,wsv_lap" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Rpt_GroupLicensingFeeWinLoss]
	@PartyIds				VARCHAR(MAX)	= ''
	,@ProductCodes			VARCHAR(MAX)	= ''	
	,@FromDate				DATETIME
	,@ToDate				DATETIME	
AS
/*  Created: Scofield.Huynh
	Date: 2018-12-04
	DB: DB052.bodb_licensee

	Revisions:
		- 20181204@Scofield: create	
		- 20190425@Parsons: Integrate-PP-Promotion-Prize [#109014] 
		- 20191216@Parsons: PP tournament [#123958]
		- 20191125@Mason: Setup billing terms by Currency [#120005]
		- 20200228@Parsons: Support-HID-currency [#128856]
		- 20200409@Parsons: Integrate SA Gaming [#129276] 
		- 20200820@Parsons: Implement PP JP Changes In Reports Phase 2 [#139055]
		- 20201023@Parsons: Arcadia Gaming Add Bonus [#143597]  
		- 20201113@Parsons: Changing OddsSpread for licensee [#142345]
		- 20201209@Happy: Saba.club - Offer Freebet tickets [#141423]
		- 20210111@Happy: Saba.club - Integrate Slot Game [#147977]
		- 20210712@Danny: Vgaming - Free bets and Jackpot prize integration [#156185]
		- 20210812@Percy: Integrate Bitcoin - apply core function GroupProduct [RedmineID: #159691]
		- 20211026@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
		- 20211212@Percy: Set OddsSpread = 0 if negative value [RedmineID: #165849]
		- 20201003@Danny: Support USDT as base currency [RedmineID: #180313]
		- 20220227@Danny: Incorporate USDTJP currency [RedmineID: #183461]
		- 20230713@Danny: Incorporate USDT2 currency [RedmineID: #191165]
		- 20230823@Danny: Incorporate US$KH currency [RedmineID: #192544]
		- 20230919@Danny: Support Jollysport licensees [RedmineID: #193214]
		- 20240924@Danny: exclude BTS currency [RedmineID: #210422]
		- 20240923@Sally: Support Odds Boost Voucher [#209884]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE = @FromDate, @TDate DATE = @ToDate

	-- Get Product List
	BEGIN
		DECLARE @ProductList TABLE (GroupProductId INT, GroupProductName VARCHAR(50), ProductId INT, ProductCode VARCHAR(20), FromDate DATE, ToDate DATE)
		INSERT INTO @ProductList (GroupProductId, GroupProductName, ProductId, ProductCode, FromDate, ToDate)
		SELECT GroupProductId, GroupProductName, ProductId, ProductCode, FromDate, ToDate
		FROM dbo.LA_f_GroupProduct(@ProductCodes, @FromDate, @ToDate)

		SET @ProductCodes = NULL
		SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM @ProductList
	END

	-- Get Party List / Charge Info
	BEGIN
		DECLARE @PartyList TABLE (PartyId INT, PartyName VARCHAR(50), BaseCurrencyId INT, BaseCurrencyName VARCHAR(5))
		DECLARE @ChargeInfo TABLE (ChargeId INT, PartyId INT, LicenseeId INT, ProductId INT, FromDate DATE, ToDate DATE, Rate FLOAT)

		INSERT INTO @ChargeInfo (ChargeId, PartyId, LicenseeId, ProductId, FromDate, ToDate, Rate)
		SELECT ChargeId, PartyId, LicenseeId, ProductId, FromDate, ToDate, CASE WHEN ISNULL(isDeposit, 0) = 1 THEN DI_Rate ELSE 0 END
		FROM LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) c
		WHERE ChargeType <> 12 -- Exclude Tips

		INSERT INTO @PartyList (PartyId)
		SELECT DISTINCT PartyId FROM @ChargeInfo

		UPDATE pl
		SET pl.BaseCurrencyId = ISNULL(bc.BaseCurrencyId, 6), pl.BaseCurrencyName = ISNULL(CASE WHEN e.Code = 'UST' THEN 'USDT' ELSE e.Code END , 'EUR')
			,pl.PartyName = CASE p.PartyName
								WHEN '18bb' THEN 'PIH'
								WHEN 'IBC'	THEN 'FDL'
								ELSE p.PartyName END
		FROM @PartyList pl
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON pl.PartyId = p.PartyId
			LEFT JOIN dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK) ON p.PartyId = bc.PartyId AND bc.FromDate <= @TDate AND bc.ToDate >= @FDate
			LEFT JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON bc.BaseCurrencyId = e.ExchangeId
	END

	-- Get Exchange Rate
	BEGIN
		DECLARE @BaseCurrencyId INT, @BaseCurrencyName VARCHAR(5)
		DECLARE @BaseCurrency TABLE (BaseCurrencyId INT, BaseCurrencyName VARCHAR(5))
		DECLARE @ExchangeRate TABLE (ExchangeDate DATE, ExchangeId INT, BaseCurrencyId INT, Rate FLOAT)

		INSERT INTO @BaseCurrency (BaseCurrencyId, BaseCurrencyName)
		SELECT DISTINCT BaseCurrencyId, BaseCurrencyName FROM @PartyList

		WHILE EXISTS (SELECT 1 FROM @BaseCurrency)
		BEGIN
			SELECT TOP 1 @BaseCurrencyId = BaseCurrencyId, @BaseCurrencyName = BaseCurrencyName FROM @BaseCurrency

			INSERT INTO @ExchangeRate (ExchangeDate, ExchangeId, BaseCurrencyId, Rate)
			SELECT ExchangeDate, ExchangeId, @BaseCurrencyId, BaseCurrencyRate
			FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

			DELETE @BaseCurrency WHERE BaseCurrencyId = @BaseCurrencyId
		END
	END

	-- Get data
	BEGIN
		CREATE TABLE #tmpData (rptDate DATE, SiteId INT, ProductId INT, CurrencyId INT, BetType INT, Winloss MONEY, AWinloss MONEY, AComm MONEY, ValidBetAmount MONEY)
		CREATE TABLE #tmpResult (PartyId INT, PartyName VARCHAR(50), ProductId INT, ProductName VARCHAR(50), CurrencyId INT, Company MONEY, OddsSpread MONEY, BasedOddsSpread MONEY)

		INSERT INTO #tmpData (rptDate, SiteId, ProductId, CurrencyId, BetType, Winloss, AWinloss, AComm, ValidBetAmount)
		SELECT rptDate, SiteId, ProductId, CurrencyId, BetType, SUM(MemberWL), SUM(GrossWL), SUM(CommissionA), SUM(ValidBetAmount) AS ValidBetAmount
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct WITH (NOLOCK)
		WHERE rptDate BETWEEN @FromDate AND @ToDate
			AND CustomerCategory NOT IN (27, 28)
			AND StatusId IN (111, 112, 113, 114, 115)
			AND ProductId <> 25 -- CO
			AND Bettype <> 1706 -- GD Tips
			AND	ISNULL(TicketType, 0) <> 2 -- Free Bet
			AND CurrencyId NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
		GROUP BY rptDate, SiteId, ProductId, CurrencyId, BetType

		-- CO
		DECLARE @_FDate SMALLDATETIME = @FromDate, @T_Date SMALLDATETIME = @ToDate
		INSERT INTO #tmpData (rptDate, SiteId, ProductId, CurrencyId, BetType, Winloss, AWinloss, AComm)
		SELECT WinlostDate, SiteId, 25 ProductId, Currency, -1, BuyBackAmt, 0 AWinloss, BuyBackAmt + BABuyBackAmt - TicketPayout
		FROM bodb_LicenseeReport.dbo.rptLicCashoutSummary WITH (NOLOCK)
		WHERE WinlostDate BETWEEN @_FDate AND @T_Date
			AND RoleId = 1
			AND Currency NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
			AND ProductId = 25
			
		INSERT INTO #tmpResult (PartyId, PartyName, ProductId, ProductName, CurrencyId, Company, OddsSpread, BasedOddsSpread)
		SELECT pl.PartyId, pl.PartyName, p.GroupProductId, p.GroupProductName, e.ExchangeId
			,SUM(CASE
					WHEN gb.TypeId = 7 THEN 0 -- OddsSpread Adjustment
					WHEN gb.TypeId = 2 THEN t.AWinloss -- Contribution
					ELSE (-t.Winloss 
							+ CASE WHEN gb.TypeId = 11 AND t.ProductId = 0 THEN t.ValidBetAmount ELSE 0 END -- OddsBoostBonus
						 )* ISNULL(cr.Rate, c.Rate)
						- CASE WHEN c.ProductId IN (3, 25) THEN t.AComm ELSE 0 END
				END
			) AS Company
			,SUM(CASE WHEN gb.TypeId = 7 THEN -t.AWinloss ELSE 0 END) AS OddsSpread
			,SUM(CASE WHEN gb.TypeId = 7 THEN -t.AWinloss * e.Rate ELSE 0 END) AS BasedOddsSpread
		FROM #tmpData t
			LEFT JOIN dbo.LA_f_GroupBettype() gb ON t.BetType = gb.Bettype
			INNER JOIN @ProductList p ON t.ProductId = p.ProductId AND t.rptDate BETWEEN p.FromDate AND p.ToDate
			INNER JOIN @ChargeInfo c ON t.SiteId = c.LicenseeId AND p.GroupProductId = c.ProductId AND t.rptDate BETWEEN c.FromDate AND c.ToDate
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON c.ChargeId = cr.ChargeId AND t.CurrencyId = cr.CurrencyId
			INNER JOIN @PartyList pl ON c.PartyId = pl.PartyId
			INNER JOIN @ExchangeRate e ON t.rptDate = e.ExchangeDate AND t.CurrencyId = e.ExchangeId AND pl.BaseCurrencyId = e.BaseCurrencyId
		WHERE gb.Bettype IS NULL OR gb.TypeId IN (2, 7, 11) -- 11: Odds Boost Adjustment
		GROUP BY pl.PartyId, pl.PartyName, p.GroupProductId, p.GroupProductName, e.ExchangeId

		-- Set OddsSpread = 0 if negative value
		;WITH CTE_OddsSpread AS (
			SELECT PartyId, ProductId
			FROM #tmpResult
			WHERE OddsSpread <> 0
			GROUP BY PartyId, ProductId
			HAVING SUM(BasedOddsSpread) <= 0
		)
		UPDATE t
		SET t.OddsSpread = 0, t.BasedOddsSpread = 0
		FROM #tmpResult t
			INNER JOIN CTE_OddsSpread c ON t.PartyId = c.PartyId AND t.ProductId = c.ProductId

		UPDATE #tmpResult SET Company = Company + OddsSpread WHERE OddsSpread <> 0

	END
	
	-- Return data
	DECLARE @Exchange TABLE (CurrencyId INT, CurrencyName VARCHAR(20), CurrencyCode VARCHAR(65), OriginalCurrencyCode VARCHAR(20))
	INSERT INTO @Exchange (CurrencyId, CurrencyName, OriginalCurrencyCode, CurrencyCode)
	SELECT ExchangeId, Currency, CASE WHEN Code = 'UST' THEN 'USDT' ELSE Code END
		,CASE ExchangeId
			WHEN 51 THEN 'INH'
			WHEN 75 THEN 'PTU'
			WHEN 76 THEN 'PS'
			WHEN 77 THEN 'PTH'
			WHEN 92 THEN 'HID' 
			WHEN 142 THEN 'USDT' 
			WHEN 96 THEN 'USD (USDT)'
			WHEN 206 THEN 'USD (USDT2)'
			WHEN 202 THEN 'USD (USDTJP)'
			WHEN 208 THEN 'USD (US$KH)'
			WHEN 209 THEN 'MP'
			ELSE Code END
	FROM bodb02.dbo.Exchange WITH (NOLOCK)
	WHERE ExchangeId IN (SELECT CurrencyId FROM #tmpResult)

	UPDATE e
	SET e.CurrencyCode = e.CurrencyCode + ' (' + e.CurrencyName + ')'
	FROM @Exchange e
		INNER JOIN (SELECT CurrencyCode FROM @Exchange GROUP BY CurrencyCode HAVING COUNT(1) > 1) t ON e.CurrencyCode = t.CurrencyCode
		

	-- Add data for products with no ticket
	;WITH CTE_Currency AS (SELECT DISTINCT CurrencyId FROM #tmpResult)
	,CTE_Product AS (SELECT DISTINCT c.PartyId, c.ProductId, p.GroupProductName AS ProductName FROM @ChargeInfo c INNER JOIN @ProductList p ON c.ProductId = p.GroupProductId)
	,CTE_Data AS (SELECT c.CurrencyId, p.ProductId, p.ProductName, pl.PartyId, pl.PartyName FROM CTE_Currency c CROSS JOIN CTE_Product p INNER JOIN @PartyList pl ON p.PartyId = pl.PartyId)
	INSERT INTO #tmpResult (PartyId, PartyName, ProductId, ProductName, CurrencyId, Company)
	SELECT d.PartyId, d.PartyName, d.ProductId, d.ProductName, d.CurrencyId, 0 AS Company FROM CTE_Data d
		LEFT JOIN #tmpResult r ON d.PartyId = r.PartyId AND d.ProductId = r.ProductId AND d.CurrencyId = r.CurrencyId
	WHERE r.PartyId IS NULL
	
	SELECT t.PartyName, e.CurrencyCode AS CurrencyName, t.ProductName, t.ProductId, t.Company * CASE WHEN e.OriginalCurrencyCode IN ('VND', 'IDR') THEN 1000 ELSE 1 END AS AmountToCompany
	FROM #tmpResult t
		INNER JOIN @Exchange e ON t.CurrencyId = e.CurrencyId
	ORDER BY t.PartyName, e.CurrencyCode, t.ProductName

	DROP TABLE #tmpData
	DROP TABLE #tmpResult
END
GO