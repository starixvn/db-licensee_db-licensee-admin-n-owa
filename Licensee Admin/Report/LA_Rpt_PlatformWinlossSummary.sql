/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_PlatformWinlossSummary]
	@PartyIDs		VARCHAR(4000),
	@FromDate		SMALLDATETIME,
	@ToDate			SMALLDATETIME,
	@BaseCurrency	VARCHAR(20) = 'EUR'
AS
/*	Created: Bravo
	Date: 2016-07-25
	Task: Platform Win Loss (Summary) #redmind: https://nexdev.net/issues/60707
	DB: DB052.bodb02

	Revisions:
		- 20160725@Bravo: create SP
		- 20170123@Bruce: Update SP to support new layout: https://nexdev.net/projects/owa/wiki/LA_Platform_WinLoss_Summary
		- 20170207@Bruce: exclude trial data and terminated [RedmindID: #60707]
		- 20171219@Bruce: increase length for variables [#88197]\
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20180904@bruce: Support more platform type in Platform WL reports [#96191]
		- 20181031@bruce: Cover betfrom 'o' in the report [#103999]
		- 20181206@bruce: Implement E-sport 2 [#105723]
		- 20181220@bruce: Cover betfrom 'c' in the report [#106089]

	Explanation:
		- Desktop: contain the followings:
			Asia:		betfrom = d,g
			China:		betfrom = a
			Euro:		betfrom = e,u
			New Asia:	betfrom = x
			New China:	betfrom = y
			New Euro:	betfrom = z
		- Mobile: contain the followings:
			WAP:	betfrom = m
			Smart:	betfrom = s,l
			Tablet: betfrom = r
			App for China: o
			Lite version: c
		- Other: betfrom is different from the aboves
			=> use *
*/
BEGIN
	SET NOCOUNT ON

	-- Only support 6 months
	IF DATEDIFF(MONTH,@FromDate,@ToDate) > 6
	BEGIN
		SELECT TOP 0
			CAST('' AS NVARCHAR(1))	AS BetFrom,
			CAST(0 AS MONEY)		AS Turnover,
			CAST(0 AS MONEY)		AS LicenseeWinLoss
	RETURN
	END

	-- supported betfrom
	--
	DECLARE @betfrom TABLE(betfrom CHAR(1))
	INSERT INTO @betfrom SELECT val FROM dbo.strSplit('d,a,e,u,m,s,l,g,x,y,z,r,o,c',',')

	-- #1: get licensee/customer and currency info
	--
	-- Licensee customer info
	CREATE TABLE #LicenseeCustInfo(LicenseeId INT, CustId INT, CurrencyId INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME)
	DECLARE @LicenseeInfo AS TABLE (PartyId INT, LicenseeId INT, IsSelectCust BIT, Fromdate SMALLDATETIME, Todate SMALLDATETIME)

	-- notes: only support SB
	INSERT INTO @LicenseeInfo(PartyId, LicenseeId, Fromdate, Todate)
	SELECT DISTINCT PartyID, LicenseeID, Fromdate, Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'SB', 'OA', 1)

	-- get cust list
	DECLARE @KeenOceanID INT = (SELECT LicenseeID FROM bodb_licensee.dbo.Licensees WITH (NOLOCK) WHERE LicenseeName LIKE 'KeenOcean')
	DECLARE @RMB INT = (SELECT ExchangeID FROM bodb02.dbo.Exchange WITH (NOLOCK) WHERE currency = 'RMB')
	DECLARE @YUN INT = (SELECT ExchangeID FROM bodb02.dbo.Exchange WITH (NOLOCK) WHERE currency = 'YUN')

	;WITH Cust AS (
		SELECT c.LicenseeID, c.CustID, c.Currency, l.Fromdate, l.Todate
		FROM bodb_Licensee.dbo.LicenseeCust c WITH (NOLOCK)
			INNER JOIN @LicenseeInfo l ON l.LicenseeId = c.LicenseeID
		WHERE Currency <> 20
		UNION ALL
		SELECT c.LicenseeID, c.CustID, @RMB Currency, l.Fromdate, l.Todate
		FROM bodb_Licensee.dbo.LicenseeCust c WITH (NOLOCK)
			INNER JOIN @LicenseeInfo l ON l.LicenseeId = c.LicenseeID
		WHERE l.LicenseeID = @KeenOceanID AND Currency = @YUN
	)
	INSERT INTO #LicenseeCustInfo (LicenseeId, CustId, CurrencyId, Fromdate, Todate)
	SELECT DISTINCT LicenseeId, CustId, Currency, Fromdate, Todate
	FROM Cust

	CREATE CLUSTERED INDEX ix_LicenseeCustInfo_cl ON #LicenseeCustInfo(CustId, CurrencyId)

	-- #2: get move bet info
	--
	DECLARE @BalanceUpDay TABLE (BalanceUpDay DATETIME, MoveBetsDay DATETIME)
	INSERT INTO @BalanceUpDay EXEC dbo.Lrf_SelBalanceUpDay

	DECLARE @MoveBetsDay DATETIME = (SELECT TOP 1 MoveBetsDay FROM @BalanceUpDay)

	-- #3: if data from moveBetsDay: get data from bettrans
	-- else get data from rptWinLoss2
	CREATE TABLE #Data (ReportDate DATETIME, CurrencyId INT, BetFrom NVARCHAR(1), Turnover DECIMAL(20,5), LicenseeWinLoss DECIMAL(20,5))

	 -- get data from bettrans
	IF @ToDate > @MoveBetsDay
	BEGIN
		DECLARE @TempFromDate SMALLDATETIME = CASE WHEN @FromDate <= @MoveBetsDay THEN DATEADD(DAY,1,@MoveBetsDay) ELSE @FromDate END

		SELECT b.transid,b.winlostdate,b.recommend,b.stake,b.betfrom,b.statusID, b.winlost, b.actual_stake,b.currency
		INTO #tmpBettrans
		FROM dbo.bettrans b WITH (NOLOCK)
		INNER JOIN (SELECT DISTINCT CustId FROM #LicenseeCustInfo) l ON l.CustId=b.recommend
		INNER JOIN bodb_licensee.dbo.LA_f_BettypeProductMapping(0,'SB') bt ON bt.Bettype = b.bettype
		WHERE b.winlostdate BETWEEN @FromDate AND @ToDate

		INSERT INTO #Data(ReportDate, CurrencyId, BetFrom, Turnover, LicenseeWinLoss)
		(
			SELECT
				b.winlostdate,
				l.CurrencyId,
				ISNULL(bf.betfrom,'*'),
				SUM(b.stake),
				SUM(-(b.winlost - b.actual_stake))
			FROM #tmpBettrans b
				INNER JOIN #LicenseeCustInfo l ON l.CustId=b.recommend
				LEFT JOIN bodb_licensee.dbo.LicenseeBATransaction ba WITH(NOLOCK) ON b.transid = ba.transid
				LEFT JOIN @betfrom bf ON bf.betfrom=ISNULL(b.betfrom,'')
			WHERE b.statusID IN (111, 112, 113)
				AND ba.TransID IS NULL
				AND b.currency=l.CurrencyId
				AND b.winlostdate BETWEEN l.Fromdate AND l.Todate
			GROUP BY b.winlostdate, l.CurrencyId,ISNULL(bf.betfrom,'*')
		)

		DROP TABLE #tmpBettrans
	END

	-- get data from rptWinLoss2
	IF @FromDate <= @MoveBetsDay
	BEGIN
		DECLARE @TempToDate SMALLDATETIME = CASE WHEN @ToDate >= @MoveBetsDay THEN @MoveBetsDay ELSE @ToDate END
		INSERT INTO #Data(ReportDate, CurrencyId, BetFrom, Turnover, LicenseeWinLoss)
		(
			SELECT
				b.winlostdate,
				l.CurrencyId,
				ISNULL(bf.betfrom,'*'),
				SUM(b.turnover),
				SUM(-b.winlost)
			FROM bodb_licenseereport.dbo.rptLicWinloss2 b WITH ( NOLOCK )
			INNER JOIN #LicenseeCustInfo l ON b.CustId = l.CustId AND b.Currency = l.CurrencyId AND b.winlostdate BETWEEN l.Fromdate AND l.Todate
			LEFT JOIN @betfrom bf ON bf.betfrom=ISNULL(b.betfrom,'')
			WHERE b.Winlostdate BETWEEN @FromDate AND @TempToDate
				AND b.sporttype = 0 -- jobsum SB as 0
				AND b.roleid = 2 -- Sum on agent for better performance
				AND b.statusID NOT IN (-1, 101, 102, 103)
				AND b.bettype = 0 -- jobsum SB as 0
				AND ISNULL(b.isBA,0) = 0
			GROUP BY b.winlostdate, l.CurrencyId,ISNULL(bf.betfrom,'*')
		)
	END

	-- #4: sum & exchange
	-- Get exchange rate info
	CREATE TABLE #Exchange (
		ExchangeDate	DATETIME,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrency)

	;WITH Result AS (
		SELECT d.BetFrom
			, SUM(d.Turnover * e.Rate) Turnover
			, SUM(d.LicenseeWinLoss * e.Rate) LicenseeWinLoss
		FROM #Data d
		INNER JOIN #Exchange e ON d.CurrencyId = e.ExchangeID AND d.ReportDate = e.ExchangeDate
		GROUP BY d.BetFrom
	)
	SELECT BetFrom
		, CAST(Turnover AS MONEY) Turnover
		, CAST(LicenseeWinLoss AS MONEY) LicenseeWinLoss
	FROM Result

	DROP TABLE #Exchange
	DROP TABLE #LicenseeCustInfo
	DROP TABLE #Data
END
GO