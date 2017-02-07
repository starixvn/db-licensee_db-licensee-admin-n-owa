USE bodb02
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_PlatformWinloss]
	 @PartyIds		VARCHAR(500),
	 @FromDate		SMALLDATETIME,
	 @ToDate		SMALLDATETIME,
	 @BaseCurrency  VARCHAR(20)
AS
/*  Created: 20160512@Bravo
    Task : Platform WinLoss Report 
    DB: DBEXT/bodb02    

    Revisions:  
		- 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
		- 20170207@Bruce:	exclude ticket 904, refund tickets
							exclude trial data and terminated

	Explanation:  
	  + @PlatformType: 0: All  
					   1: Asia (d)  
					   2: China (a)
					   3: Euro (e) (and Euro 12bet (u))
					   4: WAP (m)    
					   5: SMARTPHONE (s,l)  
	  
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
		TurnoverAsia	MONEY, 
		WinlossAsia		MONEY,
		TurnoverChina	MONEY, 
		WinlossChina	MONEY,
		TurnoverEuro	MONEY, 
		WinlossEuro		MONEY,
		TurnoverWap		MONEY, 
		WinlossWap		MONEY,
		TurnoverSmart	MONEY, 
		WinlossSmart	MONEY
	)
		
	DECLARE @MoveBetsDay DATETIME 
	DECLARE @TempFromDate DATETIME 
	DECLARE @TempToDate DATETIME 
	DECLARE @MaxOldDate DATETIME
	DECLARE @FDate DATETIME
	DECLARE @TDate DATETIME

	CREATE TABLE #sporttype (sporttype INT, ProductPrefix VARCHAR(10))
	CREATE TABLE #bettype	(bettype INT PRIMARY KEY, ProductPrefix VARCHAR(10))
	CREATE TABLE #tempAg	(LicenseeID INT, custID INT, Currency INT)
	DECLARE @tempDate TABLE (BalanceUpDay DATETIME, MoveBetsDay DATETIME)

	INSERT INTO @tempDate
	EXEC Lrf_SelBalanceUpDay 
	
	SELECT @MoveBetsDay = (SELECT MoveBetsDay FROM @tempDate)

	--  Charge Info
	DECLARE @LicenseeInfo AS TABLE (
		PartyId		INT,
		LicenseeId	INT,
		IsSelectCust BIT,
		Fromdate DATETIME,
		Todate DATETIME
	)

	INSERT INTO @LicenseeInfo(PartyId, LicenseeId, Fromdate, Todate)
	(
		SELECT	PartyID, LicenseeID, Fromdate, Todate
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'SB', 'OA', 1)
	)

	SELECT @FDate=@FromDate,@TDate=@ToDate 
	
	WHILE EXISTS (SELECT * FROM @LicenseeInfo WHERE IsSelectCust IS NULL)
	BEGIN
		DECLARE @licenseeID INT = (SELECT TOP 1 LicenseeId FROM @LicenseeInfo WHERE IsSelectCust IS NULL)

		INSERT INTO #tempAg (LicenseeID, custID,currency) 
		SELECT @licenseeID, custID,currency 
		FROM  bodb_Licensee.dbo.f_SelLicenseeCust(@licenseeID) lc

		UPDATE @LicenseeInfo SET IsSelectCust = 1 WHERE LicenseeId = @licenseeID
	END		
	
	INSERT  INTO #sporttype(sporttype, ProductPrefix) VALUES  (0, 'SB')	

	-- Get exchange rate info
	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)
	
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

		INSERT INTO #WinLoss (LicenseeID, Winlostdate, CurrencyId, TurnoverAsia, TurnoverChina, TurnoverEuro, TurnoverWap, TurnoverSmart, WinlossAsia, WinlossChina, WinlossEuro, WinlossWap, WinlossSmart)
		SELECT
			tma.LicenseeID,
			b.winlostdate, 
			tma.currency,				
			SUM(
				CASE
					WHEN b.betfrom = 'd' THEN CASE WHEN b.bettype in (33,43) AND b.liveawayscore=0 THEN b.stake/2 ELSE b.stake END
					ELSE 0 
				END
			) TurnoverAsia,
			SUM(
				CASE
					WHEN b.betfrom = 'a' THEN CASE WHEN b.bettype in (33,43) AND b.liveawayscore=0 THEN b.stake/2 ELSE b.stake END
					ELSE 0 
				END
			) TurnoverChina,
			SUM(
				CASE
					WHEN b.betfrom IN ('e', 'u') THEN CASE WHEN b.bettype in (33,43) AND b.liveawayscore=0 THEN b.stake/2 ELSE b.stake END
					ELSE 0 
				END
			) TurnoverEuro,
			SUM(
				CASE
					WHEN b.betfrom = 'm' THEN CASE WHEN b.bettype in (33,43) AND b.liveawayscore=0 THEN b.stake/2 ELSE b.stake END
					ELSE 0 
				END
			) TurnoverWap,
			SUM(
				CASE
					WHEN b.betfrom IN ('s','l') THEN CASE WHEN b.bettype in (33,43) AND b.liveawayscore=0 THEN b.stake/2 ELSE b.stake END
					ELSE 0 
				END
			) TurnoverSmart,
				
			-SUM(
				CASE
					WHEN b.betfrom = 'd' THEN CASE WHEN (b.bettype NOT BETWEEN 31 AND 33)  THEN (b.winlost - b.actual_stake) ELSE 0 END
					ELSE 0 
				END
			) WinlossAsia,
			-SUM(
				CASE
					WHEN b.betfrom = 'a' THEN CASE WHEN (b.bettype NOT BETWEEN 31 AND 33)  THEN (b.winlost - b.actual_stake) ELSE 0 END
					ELSE 0 
				END
			) WinlossChina,
			-SUM(
				CASE
					WHEN b.betfrom IN ('e', 'u') THEN CASE WHEN (b.bettype NOT BETWEEN 31 AND 33)  THEN (b.winlost - b.actual_stake) ELSE 0 END
					ELSE 0 
				END
			) WinlossEuro,
			-SUM(
				CASE
					WHEN b.betfrom = 'm' THEN CASE WHEN (b.bettype NOT BETWEEN 31 AND 33)  THEN (b.winlost - b.actual_stake) ELSE 0 END
					ELSE 0 
				END
			) WinlossWap,
			-SUM(
				CASE
					WHEN b.betfrom IN ('s','l') THEN CASE WHEN (b.bettype NOT BETWEEN 31 AND 33)  THEN (b.winlost - b.actual_stake) ELSE 0 END
					ELSE 0 
				END
			) WinlossSmart				
			FROM dbo.bettrans b WITH (NOLOCK)
				INNER JOIN #tempAg tma ON tma.CustID=b.recommend  AND b.currency = tma.currency
				INNER JOIN @LicenseeInfo li ON li.LicenseeId = tma.LicenseeId AND b.winlostdate BETWEEN li.Fromdate AND li.Todate
				LEFT JOIN bodb_licensee.dbo.LicenseeBATransaction ba WITH(NOLOCK) ON b.transid = ba.transid AND ba.transdate BETWEEN @TempFromDate AND @TDate
			WHERE
				b.statusID  IN (111, 112, 113)
				AND b.winlostdate BETWEEN @TempFromDate AND @TDate
				AND (b.bettype<31 OR (b.bettype BETWEEN 121 AND 999)
								  OR (b.Bettype BETWEEN 1301 and 1399) --new tennis's bettypes
				) 
				AND b.bettype NOT IN (901,902,903,904/*bettrade*/,911,912,913,914/*cashout*/)
				AND ba.TransID IS NULL -- not BA
			GROUP BY  b.winlostdate, tma.currency, tma.LicenseeID
	END				

	IF @FDate <= @MoveBetsDay 
	BEGIN
		IF @TDate >= @MoveBetsDay
			SET @TempToDate = @MoveBetsDay
		ELSE
			SET  @TempToDate = @TDate		

		INSERT INTO #WinLoss (LicenseeID, Winlostdate, CurrencyId, TurnoverAsia, TurnoverChina, TurnoverEuro, TurnoverWap, TurnoverSmart, WinlossAsia, WinlossChina, WinlossEuro, WinlossWap, WinlossSmart)
		SELECT
			ag.LicenseeID,
			b.winlostdate, 
			ag.currency,				
			SUM(
				CASE
					WHEN b.betfrom = 'd' THEN b.turnover
					ELSE 0 
				END
			) TurnoverAsia,
			SUM(
				CASE
					WHEN b.betfrom = 'a' THEN b.turnover
					ELSE 0 
				END
			) TurnoverChina,
			SUM(
				CASE
					WHEN b.betfrom IN ('e', 'u') THEN b.turnover
					ELSE 0 
				END
			) TurnoverEuro,
			SUM(
				CASE
					WHEN b.betfrom = 'm' THEN b.turnover
					ELSE 0 
				END
			) TurnoverWap,
			SUM(
				CASE
					WHEN b.betfrom IN ('s','l') THEN b.turnover
					ELSE 0 
				END
			) TurnoverSmart,
				
			-SUM(
				CASE
					WHEN b.betfrom = 'd' THEN CASE WHEN (b.sporttype <> 151)  THEN b.winlost ELSE 0 END
					ELSE 0 
				END
			) WinlossAsia,
			-SUM(
				CASE
					WHEN b.betfrom = 'a' THEN CASE WHEN (b.sporttype <> 151)  THEN b.winlost ELSE 0 END
					ELSE 0 
				END
			) WinlossChina,
			-SUM(
				CASE
					WHEN b.betfrom IN ('e', 'u') THEN CASE WHEN (b.sporttype <> 151)  THEN b.winlost ELSE 0 END
					ELSE 0 
				END
			) WinlossEuro,
			-SUM(
				CASE
					WHEN b.betfrom = 'm' THEN CASE WHEN (b.sporttype <> 151)  THEN b.winlost ELSE 0 END
					ELSE 0 
				END
			) WinlossWap,
			-SUM(
				CASE
					WHEN b.betfrom IN ('s','l') THEN CASE WHEN (b.sporttype <> 151)  THEN b.winlost ELSE 0 END
					ELSE 0 
				END
			) WinlossSmart	
		FROM bodb_licenseereport.dbo.rptLicWinloss2 b WITH ( NOLOCK )
			INNER JOIN #tempAg ag ON b.recommend = ag.CustId AND b.Currency = ag.Currency
			INNER JOIN @LicenseeInfo li ON li.LicenseeId = ag.LicenseeId AND b.winlostdate BETWEEN li.Fromdate AND li.Todate
			INNER JOIN #sporttype t ON b.sporttype = t.sporttype
		WHERE 		
			b.Winlostdate BETWEEN @FDate AND @TempToDate  
			AND b.roleid = 1   
			AND b.statusID  NOT IN (-1, 101, 102, 103)
			AND b.bettype NOT IN (901,902,903,904/*bettrade*/,911,912,913,914/*cashout*/)
			AND ISNULL(b.isBA,0) = 0	
		GROUP BY	
			b.winlostdate,
			b.currency,
			ag.LicenseeID,
			ag.Currency
	END
	
	SELECT 
		p.PartyName,
		w.LicenseeID,
		w.Winlostdate,
		SUM(w.TurnoverAsia * e.Rate) TurnoverAsia,
		SUM(w.TurnoverChina * e.Rate) TurnoverChina,
		SUM(w.TurnoverEuro * e.Rate) TurnoverEuro,
		SUM(w.TurnoverWap * e.Rate) TurnoverWap,
		SUM(w.TurnoverSmart * e.Rate) TurnoverSmart,
		SUM(w.WinlossAsia * e.Rate) WinlossAsia,
		SUM(w.WinlossChina * e.Rate) WinlossChina,
		SUM(w.WinlossEuro * e.Rate) WinlossEuro,
		SUM(w.WinlossWap * e.Rate) WinlossWap,
		SUM(w.WinlossSmart * e.Rate) WinlossSmart
	FROM #WinLoss w
		INNER JOIN #Exchange e ON w.CurrencyId = e.ExchangeID AND w.Winlostdate = e.ExchangeDate
		INNER JOIN @LicenseeInfo l ON w.LicenseeID = l.LicenseeId
		INNER JOIN bodb_licensee..OAS_Party p ON l.PartyId = p.PartyID
	GROUP BY w.LicenseeID, w.Winlostdate,p.PartyName
	ORDER BY w.LicenseeID, w.Winlostdate

	DROP TABLE #sporttype
	DROP TABLE #bettype
	DROP TABLE #Exchange
	DROP TABLE #WinLoss
	DROP TABLE #tempAg
END

GO
GRANT EXECUTE ON [dbo].[LA_Rpt_PlatformWinloss] TO [bodbLicenseeNet] AS [dbo]
GRANT EXECUTE ON [dbo].[LA_Rpt_PlatformWinloss] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_PlatformWinloss] TO [vnteam] AS [dbo]