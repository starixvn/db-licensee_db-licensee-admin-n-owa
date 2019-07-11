/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[OAS_Report_BAWinloss] 
	@PartyID		INT
	,@FromDate		DATETIME
	,@ToDate		DATETIME
	,@Currency		INT		  = 0
	,@ExchangeID	VARCHAR(5)= 'EUR'
	,@ReportBy		TINYINT	  = 1
	,@DrawFilter	TINYINT	  = 0
AS

/*
	Created by : 20131223@Francis
	Task: Get Winloss report for Sportbook (compatible with the new structure)
	DB: DBEXT.bodb02
	Original: [OAS_Report_BAWinloss]

	Revisions:
	   - 20140410@Francis: Fix showing data out of time-range bug
	   - 20141103@Florent: Fix formula for OW revenue, use new structure (#25393)
	   - 20141120@Winnie: change from LicenseeCust to f_SelLicenseeCust 
	   - 20150202@Florent: base currency GBP
	   - 20150824@Florent: remove bettrade ticket
	   - 20160808@Bravo: #57972 - LA/ OWA - Change Commercial Terms for BetTrade
	   - 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
	   - 20170405@Harper: #73310 - Remove Cashout Bettype

	Params explanation:
		- @ReportBy: 0 - Daily, 1 - Monthly
		- @Currency: 0 : All
					-1: Base on EUR
					-2: Base on GBP


		- @DrawFilter: 
			+ 0  Normal 
			+ 1  No draw (only win and loss tickets are calculated) 
			+ 2  No draw for Turnover only (the draw tickets will be calculated in the Total Trans, Turnover of these tickets will not be calculated)
*/

BEGIN
	SET NOCOUNT ON

	CREATE TABLE #BAWinLoss (
		WLDate DATETIME
		,Currency INT
		,TurnOver MONEY
		,TotalTrans INT
		,CustomerWL MONEY
		,BAComm MONEY
		,AmountBA MONEY
		)

	DECLARE @tempAg TABLE (
		custID	INT
		,currency INT
		,Rate	MONEY
		,FromDate DATETIME
		,ToDate	DATETIME
		)
	DECLARE @LicenseeName VARCHAR(50)

	SELECT @LicenseeName = PartyName
	FROM bodb_Licensee.dbo.OAS_Party(NOLOCK)
	WHERE PartyID = @PartyID

	INSERT INTO @tempAg (
		custID
		,currency
		,Rate
		,FromDate
		,ToDate
		)
	SELECT lc.custID
		,lc.currency
		,ci.Rate
		,CASE 
			WHEN @FromDate <= ci.FromDate
				THEN ci.FromDate
			ELSE @FromDate
			END
		,CASE 
			WHEN @ToDate >= ci.ToDate
				THEN ci.ToDate
			ELSE @ToDate
			END
	FROM bodb_Licensee.dbo.f_SelLicenseeCust(0) lc--(NOLOCK)
	INNER JOIN bodb_licensee.dbo.OAS_Party p(NOLOCK) ON lc.LicenseeID = p.OldRefID
		AND p.PartyType = 1
	INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci(NOLOCK) ON ci.FromParty = p.PartyID
	INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs(NOLOCK) ON ci.ChargeID = cs.ChargeID
		AND cs.SystemID = 4
	WHERE p.PartyID = @PartyID
		AND (
			@FromDate BETWEEN ci.FromDate AND ci.ToDate
			OR @ToDate BETWEEN ci.FromDate AND ci.ToDate
			)
		AND ci.ChargeType = 1
		AND ci.ProductID = 3
		AND (
			@Currency <= 0
			OR (
				@Currency > 0
				AND Currency = @Currency
				)
			)
		AND (Currency <> 20)

	DECLARE @Super AS TABLE (
		custid INT --PRIMARY KEY
		,currency INT
		)

	INSERT INTO @Super (
		custid
		,currency
		)
	SELECT DISTINCT CustID
		,currency
	FROM bodb_licensee.dbo.f_SelDepCustSuper(@licenseeName)--(NOLOCK)
	--WHERE site = @licenseeName

	DECLARE @moveBetsDay SMALLDATETIME

	SELECT @moveBetsDay = MAX(m.eventdate)
	FROM dbo.match14 m(NOLOCK)

	DECLARE @TempFromDate DATETIME
	DECLARE @TempToDate DATETIME
	DECLARE @MaxOldDate DATETIME
	DECLARE @FDate DATETIME
	DECLARE @TDate DATETIME

	IF (@FromDate <= (SELECT TOP 1 FromDate FROM @tempAg))
		SET @FromDate = (SELECT TOP 1 FromDate FROM @tempAg)

	IF (@ToDate >= (SELECT TOP 1 ToDate FROM @tempAg))
		SET @ToDate = (SELECT TOP 1 ToDate FROM @tempAg)

	SELECT @FDate = @fromDate
		,@TDate = @toDate

	IF @TDate > @moveBetsDay
	BEGIN
		IF @FDate <= @moveBetsDay
			SET @TempFromDate = DATEADD(DAY, 1, @moveBetsDay)
		ELSE
			SET @TempFromDate = @FDate

		INSERT INTO #BAWinLoss
		SELECT b.winlostdate
			,b.currency
			,SUM(b.stake * CASE 
					WHEN @DrawFilter IN (1, 2)
						THEN CASE 
								WHEN b.statusID = 111
									THEN 0
								WHEN (
										b.statusID IN (112, 113)
										AND ABS(b.modds) = 0.25
										AND b.bettype IN (1, 3, 7, 8, 17, 18)
										)
									THEN 0.5
								ELSE 1
								END
					ELSE 1
					END) AS TurnOver
			,COUNT(b.transid) AS TotalTrans
			,SUM(b.winlost - b.actual_stake + PlayerComm) AS CustomerWL
			,SUM(comm) AS BAComm
			--,- SUM(b.winlost - b.actual_stake + awinlost + comm) AS AmountBA
			,- SUM((b.winlost - b.actual_stake) * tma.Rate + comm) AS AmountBA
		FROM dbo.bettrans b WITH (NOLOCK,INDEX = IX_srecommend)
			INNER JOIN @Super s ON b.srecommend = s.custid AND b.currency=s.currency
			INNER JOIN @TempAg tma ON tma.CustID = b.recommend AND tma.currency=b.currency
			INNER JOIN bodb_Licensee.dbo.LicenseeBATransaction_active BA WITH (NOLOCK) ON s.custid = BA.srecommend AND b.transid = BA.transid
		WHERE b.winlostdate BETWEEN @TempFromDate AND @TDate
			AND b.statusID IN (111, 112, 113)
			AND (
				@DrawFilter <> 1
				OR b.statusID != 111
				) -- NoDraw filter
			AND b.bettype NOT IN( 901, 902, 903, 904, 911, 912, 913, 914)
		GROUP BY b.winlostdate
			,b.currency
	END

	IF @FDate <= @moveBetsDay
	BEGIN
		IF @TDate >= @moveBetsDay
			SET @TempToDate = @moveBetsDay
		ELSE
			SET @TempToDate = @TDate

		INSERT INTO #BAWinLoss
		SELECT b.winlostdate
			,b.currency
			,SUM(b.turnover * CASE 
					WHEN @DrawFilter IN (1, 2)
						THEN CASE 
								WHEN b.statusID = 111
									THEN 0
								WHEN b.statusID IN (114, 115)
									THEN 0.5
								ELSE 1
								END
					ELSE 1
					END) AS TurnOver
			,SUM(b.BetCount) AS TotalTrans
			,SUM(b.winlost + b.playerComm) AS CustomerWL
			,SUM(comm) AS BAComm
			--,- SUM(b.winlost + b.awinlost + b.comm) AS AmountBA
			,- SUM((b.winlost * ag.Rate) + b.comm) AS AmountBA
		FROM bodb_licenseereport.dbo.rptLicWinloss2 b(NOLOCK)
		INNER JOIN @TempAg ag ON ag.custid = b.recommend AND ag.currency=b.Currency
		WHERE b.Winlostdate BETWEEN @FDate AND @TempToDate
			AND b.roleid = 2
			AND b.statusID <> 101 --exclude REJECT bets
			AND ISNULL(b.isBA, 0) = 1
			AND b.statusID IN (111, 112, 113, 114, 115)
			AND (
				@DrawFilter <> 1
				OR b.statusID != 111
				) -- NoDraw filter
			AND b.bettype NOT IN( 901, 902, 903, 904, 911, 912, 913, 914)
		GROUP BY b.winlostdate
			,b.currency
	END

	CREATE NONCLUSTERED INDEX IDX_Index_BA ON #BAWinLoss (Currency)

	-- Remove data before AffectedDate
	DECLARE @AffectedDate DATETIME

	SELECT @AffectedDate = FromDate
	FROM bodb_licensee.dbo.OAS_ChargeInfo (NOLOCK)
	WHERE FromParty = @PartyID
		AND (
			@FromDate BETWEEN FromDate AND ToDate
			OR @ToDate BETWEEN FromDate AND ToDate
			)
		AND ProductID = 3
		AND ChargeType = 1

	DELETE
	FROM #BAWinLoss
	WHERE WLDate < @AffectedDate

	SELECT exchangedate
		,ExchangeId
		,Code
		,CASE @ExchangeID
			WHEN 'USD'
				THEN USD
			WHEN 'EUR'
				THEN EUR
			WHEN 'GBP'
				THEN GBP
			ELSE CNY
			END AS ExRate
	INTO #TempExchange
	FROM Lrf_f_GetExchangeDaily(@FromDate, @ToDate)
	WHERE exchangeid IN (
			SELECT DISTINCT Currency
			FROM #BAWinLoss
			)

	IF (@ReportBy = 0) -- Daily report
	BEGIN
		SELECT CONVERT(VARCHAR(10), wl.WLDate, 101) AS WLDate
			,wl.Currency
			,wl.TurnOver
			,wl.TotalTrans
			,wl.CustomerWL
			,wl.BAComm
			,wl.AmountBA
			,CASE 
				WHEN wl.Currency = 20
					THEN 'UUS'
				WHEN wl.Currency = 51
					THEN 'INH'
				ELSE e.Code
				END AS CurrencyName
			,wl.TurnOver * e.ExRate AS TurnOverEx
			,wl.CustomerWL * e.ExRate AS CustomerWLEx
			,wl.BAComm * e.ExRate AS BACommEx
			,wl.AmountBA * e.ExRate AS AmountBAEx
		FROM #BAWinLoss wl
		INNER JOIN #tempExchange e ON wl.WLDate = e.ExchangeDate
			AND wl.currency = e.ExchangeId
		ORDER BY CONVERT(VARCHAR(10), wl.WLDate, 101)
			,wl.Currency
	END
	ELSE -- Monthly report
	BEGIN
		SELECT SUBSTRING(CONVERT(VARCHAR(10), wl.WLDate, 103), 4, 7) AS WLDate
			,wl.Currency
			,SUM(wl.TurnOver) AS TurnOver
			,SUM(wl.TotalTrans) AS TotalTrans
			,SUM(wl.CustomerWL) AS CustomerWL
			,SUM(wl.BAComm) AS BAComm
			,SUM(wl.AmountBA) AS AmountBA
			,CASE 
				WHEN wl.Currency = 20
					THEN 'UUS'
				WHEN wl.Currency = 51
					THEN 'INH'
				ELSE e.Code
				END AS CurrencyName
			,SUM(wl.TurnOver * e.ExRate) AS TurnOverEx
			,SUM(wl.CustomerWL * e.ExRate) AS CustomerWLEx
			,SUM(wl.BAComm * e.ExRate) AS BACommEx
			,SUM(wl.AmountBA * e.ExRate) AS AmountBAEx
		FROM #BAWinLoss wl
		INNER JOIN #tempExchange e ON wl.WLDate = e.ExchangeDate
			AND wl.currency = e.ExchangeId
		GROUP BY SUBSTRING(CONVERT(VARCHAR(10), wl.WLDate, 103), 4, 7)
			,wl.Currency
			,CASE 
				WHEN wl.Currency = 20
					THEN 'UUS'
				WHEN wl.Currency = 51
					THEN 'INH'
				ELSE e.Code
				END
		ORDER BY SUBSTRING(CONVERT(VARCHAR(10), wl.WLDate, 103), 4, 7)
			,wl.Currency
	END

	DROP TABLE #BAWinLoss
	DROP TABLE #TempExchange
END
GO