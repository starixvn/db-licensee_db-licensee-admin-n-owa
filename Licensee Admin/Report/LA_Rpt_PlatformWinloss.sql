/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[LA_Rpt_PlatformWinloss]
	@PartyIds		VARCHAR(MAX), 
	@Platforms		VARCHAR(MAX),
	@FromDate		SMALLDATETIME,
	@ToDate			SMALLDATETIME,
	@BaseCurrency	VARCHAR(20) = 'EUR'
AS

/*
	Created: 20160512@Bravo
    Task : Platform WinLoss Report
    DB: DBEXT/bodb02

    Revisions:
		- 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
		- 20170207@Bruce:	exclude ticket 904, refund tickets [RedmindID:	#60707]
							exclude trial data and terminated
		- 20171219@Bruce: increase length for variables [#88197]
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
		- 20200318@Parsons: Handle new betfrom v,1,2,3 into their own category [#130645]
		- 20200706@Parsons: Add new betfrom eGame Mobile and eGamer Desktop [#136414]
		- 20200807@Parsons: Filter data by platform : Platform WL (summary, detail) [#138249]
		- 20201204@Happy: Changing OddsSpread for Licensee [#142345]
		- 20210517@Percy: Using core function to group betfrom [RedmineID: #150899]
		- 20211223@Percy: Using core function to group product under SB [RedmineID: #165971]
		- 20230407@Danny: Extend betfrom data length [#178060]
	
	Explanation:
		@Platforms: DetailPlatform from LA_f_BetFrom_Sel() function
*/

BEGIN
	SET NOCOUNT ON

	;WITH CTE_DetailPlatform AS (SELECT DISTINCT DetailPlatform FROM dbo.LA_f_BetFrom_Sel() WHERE ',' + @Platforms + ',' LIKE '%,' + DetailPlatform + ',%')
	SELECT @Platforms = (SELECT ',' + DetailPlatform FROM CTE_DetailPlatform FOR XML PATH(''))
	SELECT @Platforms = RIGHT(@Platforms, LEN(@Platforms)-1) -- remove first comma

	IF ISNULL(@Platforms, '') = ''
	BEGIN
		SELECT
			CAST('' AS DATETIME)		AS WinlostDate
			,CAST('' AS VARCHAR(50))	AS LicenseeName
		WHERE 1 = 0

		RETURN
	END
	
	DECLARE @OutputColumns VARCHAR(MAX)

	IF DATEDIFF(MONTH, @FromDate, @ToDate) > 6 -- Only support 6 months
	BEGIN
		SELECT  @OutputColumns = 'CAST(0 AS MONEY) AS [' + REPLACE(@Platforms, ',', '_Turnover], CAST(0 AS MONEY) AS [') + '_Turnover]'
		SELECT  @OutputColumns = @OutputColumns  + ', ' + REPLACE(@OutputColumns, '_Turnover', '_LicenseeWinLoss')
												 + ', ' + REPLACE(@OutputColumns, '_Turnover', '_TurnoverPercent')

		SELECT @OutputColumns = 'SELECT CAST('''' AS VARCHAR(50)) AS LicenseeName, CAST(NULL AS Date) AS [Date], ' + @OutputColumns + ' WHERE 1 = 0'
		
		EXEC (@OutputColumns)

		RETURN
	END

	DECLARE @FDate SMALLDATETIME, @TDate SMALLDATETIME
	DECLARE @MoveBetsDay SMALLDATETIME

	DECLARE @MBBU TABLE (BalanceUpDay SMALLDATETIME, MoveBetsDay SMALLDATETIME)
	INSERT INTO @MBBU (BalanceUpDay, MoveBetsDay)
	EXEC dbo.Age_SelBalanceUpDay

	SELECT @MoveBetsDay = MoveBetsDay FROM @MBBU

	-- Get Licensee Customer
	CREATE TABLE #Customer (LicenseeName VARCHAR(50), srecommend INT, recommend INT, FromDate SMALLDATETIME, ToDate SMALLDATETIME)
	INSERT INTO #Customer (LicenseeName, srecommend, recommend, FromDate, ToDate)
	SELECT l.LicenseeName, c.srecommend, lc.CustId, ci.FromDate, ci.ToDate
	FROM (
		SELECT DISTINCT LicenseeId, FromDate, ToDate
		FROM bodb_Licensee.dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'SB', 'OA', 1)
	) ci
		INNER JOIN bodb_Licensee.dbo.LicenseeCust lc WITH (NOLOCK) ON ci.LicenseeId = lc.LicenseeId
		INNER JOIN bodb_Licensee.dbo.Licensees l WITH (NOLOCK) ON lc.LicenseeId = l.LicenseeId
		INNER JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON lc.CustId = c.CustId
	WHERE lc.Currency <> 20

	-- Get BetFrom data
	CREATE TABLE #Data (rptDate DATETIME, LicenseeName VARCHAR(50), Currency INT, BetFrom NVARCHAR(4), Turnover FLOAT, Winloss FLOAT)

	-- bettrans
	IF @ToDate > @MoveBetsDay
	BEGIN
		SELECT @FDate = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY, 1, @MoveBetsDay) ELSE @FromDate END
				,@TDate = @ToDate

		DECLARE @ProductTab TABLE (ProductID INT)
		INSERT INTO @ProductTab (ProductID)
		SELECT	p.ProductID 
		FROM	bodb_Licensee.dbo.LA_f_GroupProduct('SB', @FDate, @TDate) m
		INNER JOIN bodb02.dbo.Products p WITH(NOLOCK)  ON m.ProductCode = p.ProductPrefix
		WHERE m.GroupProductId = 0

		CREATE TABLE #bettype (bettype SMALLINT)
		INSERT INTO #bettype (bettype)
		SELECT DISTINCT bettype FROM dbo.SportBettypeMatrix WITH (NOLOCK) 
		WHERE ProductId IN (SELECT x.ProductID FROM @ProductTab x) 
			AND bettype <> 999 -- exclude Odds Spread Adjustment

		INSERT INTO #Data (rptDate, LicenseeName, Currency, BetFrom, Turnover, Winloss)
		SELECT b.winlostdate, c.LicenseeName, b.currency, b.betfrom, SUM(b.stake), SUM(b.winlost - b.actual_stake)
		FROM dbo.bettrans b WITH (NOLOCK)
			INNER JOIN #Customer c ON b.recommend = c.recommend AND b.winlostdate BETWEEN c.FromDate AND c.ToDate
			INNER JOIN #bettype bt ON b.bettype = bt.bettype
			LEFT JOIN bodb_Licensee.dbo.LicenseeBATransaction_active ba WITH (NOLOCK) ON b.transid = ba.transid
		WHERE b.winlostdate BETWEEN @FDate AND @TDate
			AND b.statusId IN (111, 112, 113)
			AND ba.transid IS NULL
		GROUP BY b.winlostdate, c.LicenseeName, b.currency, b.betfrom

		DROP TABLE #bettype
	END

	-- rptWinLoss2
	IF @FromDate <= @MoveBetsDay
	BEGIN
		SELECT @FDate = @FromDate
				,@TDate = CASE WHEN @ToDate > @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END
		
		DECLARE @SportTypeTab TABLE (sporttype INT)
		INSERT INTO @SportTypeTab (sporttype)
		SELECT	DISTINCT CASE WHEN ma.ProductID = 1 THEN 0 ELSE  ma.SportType END
		FROM	bodb_Licensee.dbo.LA_f_GroupProduct('SB', @FDate, @TDate) m
		INNER JOIN bodb02.dbo.Products p WITH(NOLOCK)  ON m.ProductCode = p.ProductPrefix
		INNER JOIN dbo.SportBettypeMatrix ma WITH(NOLOCK)  ON p.ProductID = ma.ProductID
		WHERE m.GroupProductId = 0

		;WITH CTE_Data AS (
			SELECT r.winlostdate, r.srecommend, r.recommend, r.Currency, r.betfrom, SUM(r.Turnover) AS Turnover, SUM(r.Winlost) AS Winlost
			FROM bodb_LicenseeReport.dbo.rptLicWinloss2 r WITH (NOLOCK)
			WHERE r.winlostdate BETWEEN @FDate AND @TDate
				AND r.sporttype IN (SELECT x.sporttype FROM @SportTypeTab x) AND r.bettype NOT IN (901, 902, 903, 904, 911, 912, 913, 914, 999) -- exclude BT, CO, Odds Spread Adjustment
				AND r.isBA = 0
				AND r.statusId IN (111, 112, 113, 114, 115)
				AND r.roleid = 2
			GROUP BY r.winlostdate, r.srecommend, r.recommend, r.Currency, r.betfrom
		)
		INSERT INTO #Data (rptDate, LicenseeName, Currency, BetFrom, Turnover, Winloss)
		SELECT d.winlostdate, c.LicenseeName, d.Currency, d.betfrom, SUM(d.Turnover), SUM(d.Winlost)
		FROM CTE_Data d
			INNER JOIN #Customer c ON d.srecommend = c.srecommend AND d.recommend = c.recommend AND d.winlostdate BETWEEN c.FromDate AND c.ToDate
		GROUP BY d.winlostdate, c.LicenseeName, d.Currency, d.betfrom
	END

	-- Result
	CREATE TABLE #Result (LicenseeName VARCHAR(50), rptDate DATETIME, DetailPlatform VARCHAR(500), Turnover FLOAT, LicenseeWinloss FLOAT)
	CREATE CLUSTERED INDEX CIX_Result ON #Result (LicenseeName, rptDate)

	INSERT INTO #Result (LicenseeName, rptDate, DetailPlatform, Turnover, LicenseeWinloss)
	SELECT d.LicenseeName, d.rptDate, ISNULL(bf.DetailPlatform , 'Others'), SUM(Turnover * e.BaseCurrencyRate), -SUM(Winloss * e.BaseCurrencyRate)
	FROM #Data d
		INNER JOIN dbo.LA_f_ExchangeDailySel (@FromDate, @ToDate, @BaseCurrency) e ON d.rptDate = e.ExchangeDate AND d.Currency = e.ExchangeId
		LEFT JOIN dbo.LA_f_BetFrom_Sel() bf ON d.BetFrom = bf.BetFrom
	GROUP BY d.LicenseeName, d.rptDate, ISNULL(bf.DetailPlatform , 'Others')

	DELETE #Result WHERE ',' + @Platforms + ',' NOT LIKE '%,' + DetailPlatform + ',%'

	SELECT @OutputColumns = '[' + REPLACE(@Platforms, ',', '_Turnover], [') + '_Turnover]'
	SELECT @OutputColumns = @OutputColumns  + ', ' + REPLACE(@OutputColumns, '_Turnover', '_LicenseeWinLoss')
											+ ', ' + REPLACE(@OutputColumns, '_Turnover', '_TurnoverPercent')

	DECLARE @SQL VARCHAR(MAX)
	SET @SQL = '
	;WITH CTE_tempResult AS (
		SELECT
			r.LicenseeName
			,r.rptDate
			,r.DetailPlatform
			,r.Turnover
			,r.LicenseeWinloss
			,CAST(CASE WHEN t.Turnover = 0 THEN 0 ELSE r.Turnover / t.Turnover END AS FLOAT) AS TurnoverPercent
		FROM #Result r
			INNER JOIN (
				SELECT LicenseeName, rptDate, SUM(Turnover) AS Turnover, SUM(LicenseeWinloss) AS LicenseeWinloss
				FROM #Result
				GROUP BY LicenseeName, rptDate
			) t ON r.LicenseeName = t.LicenseeName AND r.rptDate = t.rptDate
	), CTE_Result AS (
		SELECT r.LicenseeName, r.rptDate, r.DetailPlatform + ''_'' + t.Figure AS Figure, CAST(ISNULL(t.Value, 0) AS FLOAT) AS Value
		FROM CTE_tempResult r
			CROSS APPLY (
				SELECT ''Turnover'' AS Figure, Turnover AS Value
				UNION ALL SELECT ''LicenseeWinloss'', LicenseeWinloss
				UNION ALL SELECT ''TurnoverPercent'', TurnoverPercent
			) t
	)
	SELECT rptDate AS WinlostDate, LicenseeName, ' + @OutputColumns + '
	FROM CTE_Result r
	PIVOT (
		MAX (Value)
		FOR Figure IN (' + @OutputColumns + ')
	) p'

	EXEC (@SQL)
	
	DROP TABLE #Customer
	DROP TABLE #Data
	DROP TABLE #Result
END
GO