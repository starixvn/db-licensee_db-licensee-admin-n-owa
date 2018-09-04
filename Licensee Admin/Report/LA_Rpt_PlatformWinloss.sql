/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
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

	Explanation:
	  + @PlatformType: 0: All
					   1: Asia (d,g)
					   2: China (a)
					   3: Euro (e) (and Euro 12bet (u))
					   4: New Asia (x)
					   5: New China (y)
					   6: New Euro (z)
					   7: WAP (m)
					   8: SMARTPHONE (s,l)
					   9: Tablet (r)

	  + @excludeTest: remove currency UUS
	  + @MoveBetsDay: The day we move tickets to bettrans14

*/

BEGIN
	SET NOCOUNT ON
	IF DATEDIFF(MONTH,@FromDate,@ToDate) > 1
		RETURN

	CREATE TABLE #WinLoss (
		LicenseeID		INT,
		Winlostdate		DATE,
		CurrencyId		INT,
		Turnover		DECIMAL(20,5),
		Winloss			DECIMAL(20,5),
		BetFrom			NVARCHAR(5)
	)

	DECLARE @MoveBetsDay SMALLDATETIME
	DECLARE @TempFromDate SMALLDATETIME
	DECLARE @TempToDate SMALLDATETIME
	DECLARE @MaxOldDate SMALLDATETIME
	DECLARE @FDate SMALLDATETIME
	DECLARE @TDate SMALLDATETIME

	CREATE TABLE #Cust (LicenseeID INT, custID INT, Currency INT, FromDate SMALLDATETIME, ToDate SMALLDATETIME)
	DECLARE @BalanceUpDay TABLE (BalanceUpDay DATETIME, MoveBetsDay DATETIME)

	INSERT INTO @BalanceUpDay
	EXEC dbo.Lrf_SelBalanceUpDay

	SELECT @MoveBetsDay = (SELECT MoveBetsDay FROM @BalanceUpDay)

	--  Charge Info
	DECLARE @ChargeInfo AS TABLE (PartyId INT, LicenseeId INT, Fromdate DATETIME, Todate DATETIME)

	INSERT INTO @ChargeInfo(PartyId, LicenseeId, Fromdate, Todate)
	(
		SELECT PartyID, LicenseeID, Fromdate, Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'SB', 'OA', 1)
	)

	SELECT @FDate=@FromDate,@TDate=@ToDate

	INSERT INTO #Cust (LicenseeID, custID,currency, FromDate, ToDate)
	SELECT li.licenseeID, custID,currency, li.Fromdate, li.Todate
	FROM  @ChargeInfo li
		CROSS APPLY bodb_Licensee.dbo.f_SelLicenseeCust(li.licenseeID) lc

	-- Get exchange rate info
	CREATE TABLE #Exchange (ExchangeDate DATETIME, ExchangeID INT, CurrencyCode VARCHAR(10), Rate FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrency)

	-- Get data.
	IF @TDate>@MoveBetsDay
	BEGIN
		IF @FDate <= @MoveBetsDay
			SET @TempFromDate =  DATEADD(DAY,1,@MoveBetsDay)
		ELSE
			SET @TempFromDate = @FDate

		INSERT INTO #WinLoss (LicenseeID, Winlostdate, CurrencyId, Turnover, Winloss, BetFrom)
		SELECT
			c.LicenseeID,
			b.winlostdate,
			c.currency,
			SUM(CASE WHEN b.bettype IN (33,43) AND b.liveawayscore=0 THEN b.stake/2 ELSE b.stake END * e.Rate),
			-SUM(CASE WHEN (b.bettype NOT BETWEEN 31 AND 33) THEN (b.winlost - b.actual_stake) * e.Rate ELSE 0 END),
			b.betfrom
			FROM dbo.bettrans b WITH (NOLOCK)
			INNER JOIN #Cust c ON c.CustID=b.recommend AND b.currency = c.currency AND b.winlostdate BETWEEN c.FromDate AND c.ToDate
			INNER JOIN #Exchange e ON b.Currency = e.ExchangeID AND b.Winlostdate = e.ExchangeDate
			LEFT JOIN bodb_licensee.dbo.LicenseeBATransaction ba WITH(NOLOCK) ON b.transid = ba.transid
			WHERE
				b.statusID  IN (111, 112, 113)
				AND b.winlostdate BETWEEN @TempFromDate AND @TDate
				AND (b.bettype<31 OR (b.bettype BETWEEN 121 AND 999) OR (b.Bettype BETWEEN 1301 and 1399)) --new tennis's bettypes
				AND b.bettype NOT IN (901,902,903,904/*bettrade*/,911,912,913,914/*cashout*/)
				AND ba.TransID IS NULL
				AND b.betfrom IN ('d','a','e','u','m','s','l','g', 'x','y','z','r')
			GROUP BY b.winlostdate, c.currency, c.LicenseeID,b.betfrom
	END

	IF @FDate <= @MoveBetsDay
	BEGIN
		IF @TDate >= @MoveBetsDay
			SET @TempToDate = @MoveBetsDay
		ELSE
			SET  @TempToDate = @TDate

		INSERT INTO #WinLoss (LicenseeID, Winlostdate, CurrencyId, Turnover, Winloss, BetFrom)
		SELECT
			ag.LicenseeID,
			b.winlostdate,
			ag.currency,
			SUM(b.turnover * e.Rate),
			-SUM( CASE WHEN (b.sporttype <> 151) THEN b.winlost * e.Rate ELSE 0 END),
			b.betfrom
		FROM bodb_licenseereport.dbo.rptLicWinloss2 b WITH ( NOLOCK )
			INNER JOIN #Cust ag ON b.CustId = ag.CustId AND b.Currency = ag.Currency AND b.winlostdate BETWEEN ag.FromDate AND ag.ToDate
			INNER JOIN #Exchange e ON b.Currency = e.ExchangeID AND b.Winlostdate = e.ExchangeDate
		WHERE
			b.Winlostdate BETWEEN @FDate AND @TempToDate
			AND b.roleid = 2
			AND b.statusID  NOT IN (-1, 101, 102, 103)
			AND b.bettype NOT IN (901,902,903,904/*bettrade*/,911,912,913,914/*cashout*/)
			AND ISNULL(b.isBA,0) = 0
			AND b.sporttype = 0
			AND b.betfrom IN ('d','a','e','u','m','s','l','g', 'x','y','z','r')
		GROUP BY
			b.winlostdate,
			b.currency,
			ag.LicenseeID,
			ag.Currency,
			b.betfrom
	END

	SELECT
		p.PartyName,
		w.LicenseeID,
		w.Winlostdate,
		SUM(CASE WHEN w.BetFrom IN ('g','d') THEN w.Turnover ELSE 0 END) TurnoverAsia,
		SUM(CASE WHEN w.BetFrom IN ('a') THEN w.Turnover ELSE 0 END) TurnoverChina,
		SUM(CASE WHEN w.BetFrom IN ('e','u') THEN w.Turnover ELSE 0 END) TurnoverEuro,
		SUM(CASE WHEN w.BetFrom IN ('x') THEN w.Turnover ELSE 0 END) TurnoverNewAsia,
		SUM(CASE WHEN w.BetFrom IN ('y') THEN w.Turnover ELSE 0 END) TurnoverNewChina,
		SUM(CASE WHEN w.BetFrom IN ('z') THEN w.Turnover ELSE 0 END) TurnoverNewEuro,
		SUM(CASE WHEN w.BetFrom IN ('m') THEN w.Turnover ELSE 0 END) TurnoverWAP,
		SUM(CASE WHEN w.BetFrom IN ('s','l') THEN w.Turnover ELSE 0 END) TurnoverSmart,
		SUM(CASE WHEN w.BetFrom IN ('r') THEN w.Turnover ELSE 0 END) TurnoverTablet,
		SUM(CASE WHEN w.BetFrom IN ('g','d') THEN w.Turnover ELSE 0 END) WinlossAsia,
		SUM(CASE WHEN w.BetFrom IN ('a') THEN w.Turnover ELSE 0 END) WinlossChina,
		SUM(CASE WHEN w.BetFrom IN ('e','u') THEN w.Turnover ELSE 0 END) WinlossEuro,
		SUM(CASE WHEN w.BetFrom IN ('x') THEN w.Turnover ELSE 0 END) WinlossNewAsia,
		SUM(CASE WHEN w.BetFrom IN ('y') THEN w.Turnover ELSE 0 END) WinlossNewChina,
		SUM(CASE WHEN w.BetFrom IN ('z') THEN w.Turnover ELSE 0 END) WinlossNewEuro,
		SUM(CASE WHEN w.BetFrom IN ('m') THEN w.Turnover ELSE 0 END) WinlossWAP,
		SUM(CASE WHEN w.BetFrom IN ('s','l') THEN w.Turnover ELSE 0 END) WinlossSmart,
		SUM(CASE WHEN w.BetFrom IN ('r') THEN w.Turnover ELSE 0 END) WinlossTablet
	FROM #WinLoss w
		INNER JOIN @ChargeInfo l ON w.LicenseeID = l.LicenseeId
		INNER JOIN bodb_licensee..OAS_Party p ON l.PartyId = p.PartyID
	GROUP BY w.LicenseeID, w.Winlostdate,p.PartyName
	ORDER BY w.LicenseeID, w.Winlostdate

	DROP TABLE #Exchange
	DROP TABLE #WinLoss
	DROP TABLE #Cust
END

GO
GRANT EXECUTE ON [dbo].[LA_Rpt_PlatformWinloss] TO [bodbLicenseeNet] AS [dbo]
GRANT EXECUTE ON [dbo].[LA_Rpt_PlatformWinloss] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_PlatformWinloss] TO [vnteam] AS [dbo]
GO