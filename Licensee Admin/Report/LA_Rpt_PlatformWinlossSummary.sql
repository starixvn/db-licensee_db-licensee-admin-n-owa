/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[LA_Rpt_PlatformWinlossSummary]
	@PartyIds		VARCHAR(MAX), 
	@Platforms		VARCHAR(MAX),
	@FromDate		SMALLDATETIME,
	@ToDate			SMALLDATETIME,
	@BaseCurrency	VARCHAR(20) = 'EUR'
AS

/*
	Created: 20160725@Bravo
	Task: Platform Win Loss (Summary) #redmind: https://nexdev.net/issues/60707
	DB: DBEXT.bodb02

	Revisions:
		- 20160725@Bravo: create SP
		- 20170123@Bruce: Update SP to support new layout: https://nexdev.net/projects/owa/wiki/LA_Platform_WinLoss_Summary
		- 20170207@Bruce: exclude trial data and terminated [RedmindID: #60707]
		- 20171219@Bruce: increase length for variables [#88197]\
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20180904@bruce: Support more platform type in Platform WL reports [#96191]
		- 20181031@bruce: Cover betfrom 'o' in the report [#103999]
		- 20181206@bruce: [#105723]
			+ Implement E-sport 2 [#105723]
			+ Cover betfrom 'c' in the report
		- 20190516@Parsons: Show Bet count in Platform Win Loss (Summary) Report [#113568]
		- 20190827@Bruce: Add new betfrom 't' [#118998]
		- 20191010@Percy: Replace LicenseeBATransaction to LicenseeBATransaction_active [RedmineID: #103656]
		- 20191223@Bruce: Adding betform v and 0 [#118998]
		- 20200326@Parsons: Handle new betfrom v,1,2,3 into their own category [#130645]
		- 20200706@Parsons: Add new betfrom eGame Mobile and eGamer Desktop [#136414]
		- 20200807@Parsons: Filter data by platform : Platform WL (summary, detail) [#138249]
		- 20201204@Happy: Changing OddsSpread for Licensee [#142345]
		- 20210517@Percy: Using core function to group betfrom [RedmineID: #150899]

	Explanation:
		@Platforms: DetailPlatform from LA_f_BetFrom_Sel() function
*/

BEGIN
	SET NOCOUNT ON

	IF DATEDIFF(MONTH, @FromDate, @ToDate) > 6 -- Only support 6 months
	BEGIN
		-- Return summary data
		SELECT
			CAST('' AS VARCHAR(500))AS [Platform],
			CAST(0 AS INT)			AS TotalTrans,
			CAST(0 AS MONEY)		AS Turnover,
			CAST(0 AS MONEY)		AS LicenseeWinLoss,
			CAST(0 AS FLOAT)		AS TurnoverPercent,
			CAST(0 AS FLOAT)		AS LicenseeWinLossPercent
		WHERE 1 = 0
		
		-- Return detail data
		SELECT
			CAST('' AS VARCHAR(500))AS [Platform],
			CAST(0 AS INT)			AS TotalTrans,
			CAST(0 AS MONEY)		AS Turnover,
			CAST(0 AS MONEY)		AS LicenseeWinLoss,
			CAST(0 AS FLOAT)		AS TurnoverPercent,
			CAST(0 AS FLOAT)		AS LicenseeWinLossPercent
		WHERE 1 = 0
		
		-- Return total
		SELECT
			CAST(0 AS INT)			AS TotalTrans,
			CAST(0 AS MONEY)		AS Turnover,
			CAST(0 AS MONEY)		AS LicenseeWinLoss
		WHERE 1 = 0

		RETURN
	END

	DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME
	DECLARE @MoveBetsDay SMALLDATETIME

	DECLARE @MBBU TABLE (BalanceUpDay SMALLDATETIME, MoveBetsDay SMALLDATETIME)
	INSERT INTO @MBBU (BalanceUpDay, MoveBetsDay)
	EXEC dbo.Age_SelBalanceUpDay

	SELECT @MoveBetsDay = MoveBetsDay FROM @MBBU

	-- Get Licensee Customer
	CREATE TABLE #Customer (srecommend INT, recommend INT, FromDate SMALLDATETIME, ToDate SMALLDATETIME)
	INSERT INTO #Customer (srecommend, recommend, FromDate, ToDate)
	SELECT c.srecommend, lc.CustId, ci.FromDate, ci.ToDate
	FROM (
		SELECT DISTINCT LicenseeId, FromDate, ToDate
		FROM bodb_Licensee.dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'SB', 'OA', 1)
	) ci
		INNER JOIN bodb_Licensee.dbo.LicenseeCust lc WITH (NOLOCK) ON ci.LicenseeId = lc.LicenseeId
		INNER JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON lc.CustId = c.CustId
	WHERE lc.Currency <> 20

	-- Get BetFrom data
	CREATE TABLE #Data (rptDate DATETIME, Currency INT, BetFrom NVARCHAR(1), BetCount INT, Turnover FLOAT, Winloss FLOAT)

	-- bettrans
	IF @ToDate > @MoveBetsDay
	BEGIN
		CREATE TABLE #bettype (bettype SMALLINT)
		INSERT INTO #bettype (bettype)
		SELECT DISTINCT bettype FROM dbo.SportBettypeMatrix WITH (NOLOCK) WHERE ProductId = 1 AND bettype <> 999

		SELECT @FDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
				,@TDate = @ToDate

		INSERT INTO #Data (rptDate, Currency, BetFrom, BetCount, Turnover, Winloss)
		SELECT b.winlostdate, b.currency, b.betfrom, COUNT(1) AS BetCount, SUM(b.stake), SUM(b.winlost - b.actual_stake)
		FROM dbo.bettrans b WITH (NOLOCK)
			INNER JOIN #Customer c ON b.recommend = c.recommend AND b.winlostdate BETWEEN c.FromDate AND c.ToDate
			INNER JOIN #bettype bt ON b.bettype = bt.bettype
			LEFT JOIN bodb_Licensee.dbo.LicenseeBATransaction_active ba WITH (NOLOCK) ON b.transid = ba.transid
		WHERE b.winlostdate BETWEEN @FDate AND @TDate
			AND b.statusId IN (111, 112, 113)
			AND ba.transid IS NULL
		GROUP BY b.winlostdate, b.currency, b.betfrom

		DROP TABLE #bettype
	END

	-- rptWinLoss2
	IF @FromDate <= @MoveBetsDay
	BEGIN
		SELECT @FDate = @FromDate
				,@TDate = CASE WHEN @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END

		INSERT INTO #Data (rptDate, Currency, BetFrom, BetCount, Turnover, Winloss)
		SELECT r.winlostdate, r.Currency, r.betfrom, SUM(r.BetCount), SUM(r.Turnover), SUM(r.Winlost)
		FROM bodb_LicenseeReport.dbo.rptLicWinloss2 r WITH (NOLOCK)
			INNER JOIN #Customer c ON r.srecommend = c.srecommend AND r.CustId = c.recommend AND r.winlostdate BETWEEN c.FromDate AND c.ToDate
		WHERE r.winlostdate BETWEEN @FDate AND @TDate
			AND r.sporttype = 0 AND r.bettype = 0 -- SB
			AND r.isBA = 0
			AND r.statusId IN (111, 112, 113, 114, 115)
		GROUP BY r.winlostdate, r.Currency, r.betfrom
	END

	-- Result
		-- betfrom does not define in LA_f_BetFrom_Sel --> add to group 'Others'
	DECLARE @Others_OrderDetail INT, @Others_OrderSummary INT, @Others_Platform VARCHAR(100) = 'Others'
	SELECT  @Others_OrderDetail = OrderDetail, @Others_OrderSummary = OrderSummary FROM dbo.LA_f_BetFrom_Sel() WHERE DetailPlatform = @Others_Platform AND SummaryPlatform = @Others_Platform

	CREATE TABLE #Result (OrderDetail INT, OrderSummary INT, DetailPlatform VARCHAR(500), SummaryPlatform VARCHAR(100), BetCount INT, Turnover FLOAT, LicenseeWinloss FLOAT)
	INSERT INTO #Result (OrderDetail, OrderSummary, DetailPlatform, SummaryPlatform, BetCount, Turnover, LicenseeWinloss)
	SELECT ISNULL(bf.OrderDetail, @Others_OrderDetail), ISNULL(bf.OrderSummary, @Others_OrderSummary), ISNULL(bf.DetailPlatform , @Others_Platform), ISNULL(bf.SummaryPlatform, @Others_Platform), SUM(BetCount), SUM(Turnover * e.BaseCurrencyRate), -SUM(Winloss * e.BaseCurrencyRate)
	FROM #Data d
		INNER JOIN dbo.LA_f_ExchangeDailySel (@FromDate, @ToDate, @BaseCurrency) e ON d.rptDate = e.ExchangeDate AND d.Currency = e.ExchangeId
		LEFT JOIN dbo.LA_f_BetFrom_Sel() bf ON d.BetFrom = bf.BetFrom
	GROUP BY ISNULL(bf.OrderDetail, @Others_OrderDetail), ISNULL(bf.OrderSummary, @Others_OrderSummary), ISNULL(bf.DetailPlatform , @Others_Platform), ISNULL(bf.SummaryPlatform, @Others_Platform)

	INSERT INTO #Result (OrderDetail, OrderSummary, DetailPlatform, SummaryPlatform, BetCount, Turnover, LicenseeWinloss)
	SELECT DISTINCT bf.OrderDetail, bf.OrderSummary, bf.DetailPlatform, bf.SummaryPlatform, 0, 0, 0
	FROM dbo.LA_f_BetFrom_Sel() bf
		LEFT JOIN #Result r ON bf.DetailPlatform = r.DetailPlatform
	WHERE r.DetailPlatform IS NULL
	
	DELETE #Result WHERE ',' + @Platforms + ',' NOT LIKE '%,' + DetailPlatform + ',%'

	DECLARE @TurnoverTotal FLOAT, @LicenseeWinlossTotal FLOAT
	SELECT  @TurnoverTotal = SUM(Turnover), @LicenseeWinlossTotal = SUM(LicenseeWinloss) FROM #Result
	SELECT  @TurnoverTotal = NULLIF(@TurnoverTotal, 0), @LicenseeWinlossTotal = NULLIF(@LicenseeWinlossTotal, 0)

	-- Return summary data
	SELECT SummaryPlatform AS [Platform]
		,SUM(BetCount) AS TotalTrans
		,CAST(SUM(Turnover) AS MONEY) AS Turnover
		,CAST(SUM(LicenseeWinloss) AS MONEY) AS LicenseeWinloss
		,CAST(ISNULL(SUM(Turnover) / @TurnoverTotal, 0) AS MONEY) AS TurnoverPercent
		,CAST(ISNULL(SUM(LicenseeWinloss) / @LicenseeWinlossTotal, 0) AS MONEY) AS LicenseeWinlossPercent
	FROM #Result
	GROUP BY OrderSummary, SummaryPlatform
	ORDER BY OrderSummary

	-- Return detail data
	SELECT DetailPlatform AS [Platform]
		,BetCount AS TotalTrans
		,CAST(Turnover AS MONEY) AS Turnover
		,CAST(LicenseeWinloss AS MONEY) AS LicenseeWinloss
		,CAST(ISNULL(Turnover / @TurnoverTotal, 0) AS MONEY) AS TurnoverPercent
		,CAST(ISNULL(LicenseeWinloss / @LicenseeWinlossTotal, 0) AS MONEY) AS LicenseeWinlossPercent
	FROM #Result
	ORDER BY OrderDetail

	-- Return total
	SELECT
		SUM(BetCount) AS TotalTrans
		,CAST(SUM(Turnover) AS MONEY) AS Turnover
		,CAST(SUM(LicenseeWinloss) AS MONEY) AS LicenseeWinloss
	FROM #Result
	
	DROP TABLE #Customer
	DROP TABLE #Data
	DROP TABLE #Result
END
GO