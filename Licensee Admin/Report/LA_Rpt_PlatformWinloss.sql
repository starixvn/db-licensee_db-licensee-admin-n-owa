/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[LA_Rpt_PlatformWinloss]
	 @PartyIds		VARCHAR(4000),
	 @FromDate		SMALLDATETIME,
	 @ToDate		SMALLDATETIME,
	 @BaseCurrency  VARCHAR(20)
AS
/*  Created: 20160512@Bravo
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

	Explanation:
	  + @PlatformType:
					   1: Asia (d,g)
					   2: New Asia (x)
					   3: China (a,z)
					   4: Euro (e,u)
					   6: WAP (m)
					   7: SMARTPHONE (l)
					   8: Tablet (r)
					   9: Mobile app for China (o)
					  10: Mobile lite version (c)
					  11: Others(t)

	  + @excludeTest: remove currency UUS
	  + @MoveBetsDay: The day we move tickets to bettrans14

*/

BEGIN
	SET NOCOUNT ON
	IF DATEDIFF(MONTH,@FromDate,@ToDate) > 1
		RETURN

	-- supported betfrom
	--
	DECLARE @betfrom TABLE(betfrom CHAR(1))
	INSERT INTO @betfrom SELECT val FROM dbo.strSplit('d,a,e,u,m,l,g,x,z,r,o,c,t',',')

	CREATE TABLE #WinLoss (
		LicenseeID		INT,
		Winlostdate		DATE,
		CurrencyId		INT,
		BetCount		INT,
		Turnover		DECIMAL(20,5),
		Winloss			DECIMAL(20,5),
		BetFrom			VARCHAR(1)
	)

	DECLARE @MoveBetsDay SMALLDATETIME
	DECLARE @TempFromDate SMALLDATETIME
	DECLARE @TempToDate SMALLDATETIME
	DECLARE @MaxOldDate SMALLDATETIME
	DECLARE @FDate SMALLDATETIME
	DECLARE @TDate SMALLDATETIME

	-- balance update
	--
	DECLARE @BalanceUpDay TABLE (BalanceUpDay DATETIME, MoveBetsDay DATETIME)
	INSERT INTO @BalanceUpDay
	EXEC dbo.Lrf_SelBalanceUpDay

	SELECT @MoveBetsDay = (SELECT MoveBetsDay FROM @BalanceUpDay)

	--  Charge Info
	--
	DECLARE @ChargeInfo AS TABLE (PartyId INT, LicenseeId INT, Fromdate DATETIME, Todate DATETIME)
	INSERT INTO @ChargeInfo(PartyId, LicenseeId, Fromdate, Todate)
	(
		SELECT PartyID, LicenseeID, Fromdate, Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'SB', 'OA', 1)
	)

	SELECT @FDate = @FromDate, @TDate = @ToDate

	-- cust info
	--
	CREATE TABLE #Cust (LicenseeID INT, custID INT, Currency INT)
	INSERT INTO #Cust (LicenseeID, custID, currency)
	(
		SELECT DISTINCT li.licenseeID, custID,currency
		FROM @ChargeInfo li CROSS APPLY bodb_Licensee.dbo.f_SelLicenseeCust(li.licenseeID) lc
		WHERE li.LicenseeId IS NOT NULL
	)
	CREATE CLUSTERED INDEX ix_Cust_cl ON #Cust(CustId, Currency)

	-- Get exchange rate info
	CREATE TABLE #Exchange (ExchangeDate DATETIME, ExchangeID INT, CurrencyCode VARCHAR(10), Rate FLOAT)
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	(
		SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
		FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrency)
	)

	-- Get data: bettrans
	--
	IF @TDate>@MoveBetsDay
	BEGIN
		IF @FDate <= @MoveBetsDay
			SET @TempFromDate =  DATEADD(DAY,1,@MoveBetsDay)
		ELSE
			SET @TempFromDate = @FDate

		SELECT b.transid, b.winlostdate, b.bettype,b.liveawayscore,b.stake,b.betfrom,b.statusID, b.winlost, b.actual_stake,b.recommend,b.currency
		INTO #tmpBettrans
		FROM dbo.bettrans b WITH (NOLOCK)
		INNER JOIN (SELECT DISTINCT CustId FROM #Cust) c ON c.CustID = b.recommend 
		INNER JOIN bodb_licensee.dbo.LA_f_BettypeProductMapping(0,'SB') bt ON b.bettype = bt.Bettype
		WHERE b.winlostdate BETWEEN @TempFromDate AND @TDate

		INSERT INTO #WinLoss (LicenseeID, Winlostdate, CurrencyId, BetCount, Turnover, Winloss, BetFrom)
		SELECT
			c.LicenseeID,
			b.winlostdate,
			c.currency,
			COUNT(*) AS BetCount,
			SUM(CASE WHEN b.bettype IN (33,43) AND b.liveawayscore=0 THEN b.stake/2 ELSE b.stake END),
			SUM(CASE WHEN (b.bettype NOT BETWEEN 31 AND 33) THEN -(b.winlost - b.actual_stake) ELSE 0 END),
			b.betfrom
			FROM #tmpBettrans b
			INNER JOIN #Cust c ON c.CustID = b.recommend
			LEFT JOIN bodb_licensee.dbo.LicenseeBATransaction ba WITH(NOLOCK) ON b.transid = ba.transid
			WHERE b.statusID IN (111, 112, 113)
				AND ba.TransID IS NULL
				AND b.betfrom IN (SELECT bf.betfrom FROM @betfrom bf)
				AND b.currency <> 20
				AND b.currency = c.currency
			GROUP BY b.winlostdate, c.currency, c.LicenseeID, b.betfrom

		DROP TABLE #tmpBettrans
	END

	-- get data: rptLicWinloss2
	--
	IF @FDate <= @MoveBetsDay
	BEGIN
		IF @TDate >= @MoveBetsDay
			SET @TempToDate = @MoveBetsDay
		ELSE
			SET  @TempToDate = @TDate

		INSERT INTO #WinLoss (LicenseeID, Winlostdate, CurrencyId, BetCount, Turnover, Winloss, BetFrom)
		SELECT
			ag.LicenseeID,
			b.winlostdate,
			ag.currency,
			SUM(b.BetCount) AS BetCount,
			SUM(b.turnover),
			SUM( CASE WHEN (b.sporttype <> 151) THEN -b.winlost ELSE 0 END),
			b.betfrom
		FROM bodb_licenseereport.dbo.rptLicWinloss2 b WITH ( NOLOCK )
			INNER JOIN #Cust ag ON b.CustId = ag.CustId AND b.Currency = ag.Currency
		WHERE
			b.Winlostdate BETWEEN @FDate AND @TempToDate
			AND b.roleid = 2
			AND b.statusID  NOT IN (-1, 101, 102, 103)
			AND b.bettype NOT IN (901,902,903,904/*bettrade*/,911,912,913,914/*cashout*/)
			AND ISNULL(b.isBA,0) = 0
			AND b.sporttype = 0
			AND b.betfrom IN (SELECT bf.betfrom FROM @betfrom bf)
			AND b.currency <> 20
		GROUP BY
			b.winlostdate,
			ag.LicenseeID,
			ag.Currency,
			b.betfrom
	END

	SELECT
		p.PartyName,
		w.WinlostDate,
		w.BetFrom,
		SUM(w.BetCount) AS TotalTrans,
		SUM(w.Turnover * e.Rate) AS Turnover,
		SUM(w.Winloss * e.Rate) AS Winloss
	FROM #WinLoss w
		INNER JOIN #Exchange e ON e.ExchangeDate = w.Winlostdate and w.CurrencyId = e.ExchangeID
		INNER JOIN @ChargeInfo l ON w.LicenseeID = l.LicenseeId AND w.Winlostdate BETWEEN l.Fromdate AND l.Todate
		INNER JOIN bodb_licensee.dbo.OAS_Party p ON l.PartyId = p.PartyID
	GROUP BY w.Winlostdate, p.PartyName, w.BetFrom

	DROP TABLE #Exchange
	DROP TABLE #WinLoss
	DROP TABLE #Cust
END
GO