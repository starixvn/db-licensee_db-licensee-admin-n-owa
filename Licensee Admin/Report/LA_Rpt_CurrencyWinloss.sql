USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_CurrencyWinloss]    Script Date: 01/12/2014 14:33:23 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_Rpt_CurrencyWinloss]
	@PartyIDs				VARCHAR(5500)	= ''
	, @Currency				INT				= 0
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME
	, @ProductCodes			VARCHAR(1000)
	, @SportType			INT				= 0
	, @Bettype				INT				= 0
	, @ReportBy				TINYINT			= 0 
	, @drawfilter			SMALLINT		= 1
	, @excludeTest			BIT				= 0
	, @IsConvert			BIT				= 0
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'
AS
/*  Created: Florent.Nguyen
	Date: 2014-09-03
	Task : Licensee Currency Winlost Report
	Base on: OA_Rpt_SummaryCurrencyWinloss
	DB: DB052.bodb02

	Revisions:
	   - 20141021@Florent: show credit's licensee
	   - 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
	   - 20150703@Florent: add GBP
	   - 20160504@Bruce: Remove dynamic sql
	   - 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]

	Param's Explanation:
	  + @ReportType: 1-Live; 2-Non-Live; 0: All;
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS
	  + @MoveBetsDay: The day we move tickets to bettrans14
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @ProductList TABLE (ProductCode VARCHAR(20))

	INSERT INTO @ProductList
	SELECT Val FROM dbo.strSplit(@ProductCodes, ',')

	CREATE TABLE #tmpWinLoss(
		Winlostdate		DATETIME,
		PartyID			INT,
		ProductID		INT,
		Currency		INT,
		TurnOver		MONEY,
		Winlost			MONEY,
		LicenseeWL		MONEY,
		WinlossRB		MONEY,
		AmtDueToBA		MONEY,
		AmtDueToRB		MONEY,
		CommBA			MONEY,
		CommRB			MONEY,
		Company			MONEY,
		Betcount		BIGINT,
		Playercomm		MONEY
	)

	CREATE INDEX IX_tmpWinloss ON #tmpWinLoss(PartyID, winlostdate, Currency)

	CREATE TABLE #Data (
		rptDate			DATETIME
		,SiteID			INT
		,PartyID		INT
		,ProductID		INT
		,Bettype		INT
		,[Status]		SMALLINT
		,CurrencyID		INT
		,TurnOver		MONEY
		,Winloss		MONEY
		,WinlossA		MONEY
		,CommissionA	MONEY
		,CommissionP	MONEY
		,Betcount		BIGINT
	)

	CREATE TABLE #tmpParty (
		PartyID			INT
		,LicenseeID		INT
		,isDeposit		INT
		,AffectedDate	SMALLDATETIME
		,ProductID		INT
		,Rate			MONEY
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
	)

	INSERT INTO #tmpParty (PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, Rate, Fromdate, Todate)
	(
		SELECT PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, DI_Rate, Fromdate, Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', @excludeTest)
	)

	CREATE TABLE #Bettype (Bettype INT, ProductID INT)

	INSERT INTO #Bettype(Bettype, ProductID)
	SELECT Bettype, ProductID
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(@Bettype, @ProductCodes)

	IF EXISTS (SELECT 1 FROM @ProductList WHERE ProductCode='BA')
	BEGIN
		--BA rpt_Betting_BA
		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, ProductID, Currency, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company,Betcount, Playercomm)
		(
			SELECT	b.rptDate,
					tp.PartyID,
					tp.ProductID,
					b.currencyID,
					SUM(b.Turnover) * (CASE	WHEN @drawfilter IN (2, 3) AND b.[Status] = 111			THEN 0
											WHEN @drawfilter IN (2, 3) AND b.[Status] IN (114,115)	THEN 0.5
											ELSE 1 END),
					SUM(b.WinLoss),
					0 as LicenseeWL,
					0 AS WinlossRB,
					- SUM((b.WinLoss * tp.Rate ) + b.CommissionA) AS AmountDueToBA,
					0 as AmountDueToRB,
					SUM (CommissionA),
					0 as CommRB,
					0 as Company,
					SUM(b.BetCount) * (CASE	WHEN @drawfilter = 2 AND b.[Status] = 111 THEN 0 ELSE 1 END),
					SUM(b.CommissionP)
			FROM bodb_licenseereport.dbo.rpt_Betting_BA b WITH (NOLOCK)
				INNER JOIN #tmpParty tp ON b.SiteID = tp.LicenseeID AND tp.ProductID = 3
				INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype AND tp.ProductID = bt.ProductID
				LEFT JOIN League l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
			WHERE	(b.rptDate BETWEEN tp.Fromdate AND tp.ToDate) AND
					 b.[Status] NOT IN (-1,103) AND
					(@Currency = 0 OR @Currency = b.CurrencyID) AND
					(@excludeTest = 0 OR b.CurrencyID<>20) AND
					(@SportType = 0 OR (b.bettype NOT IN (9,29) AND l.Sporttype = @SportType)) AND
					((@ReportBy = 0) OR
					 (@ReportBy = 1 AND b.IsLive=1 AND b.bettype NOT IN (9,29,10)) OR
					 (@ReportBy = 2 AND b.IsLive=0))
			GROUP BY b.rptDate, tp.ProductID, tp.PartyID, b.currencyID, b.[Status]
		)
	END

	IF EXISTS (SELECT TOP 1 1 FROM @ProductList WHERE ProductCode <> 'BA')
	BEGIN
		--exclude BA rpt_Betting
		SELECT DISTINCT p.PartyID, p.LicenseeID, p.ProductID, bt.Bettype
		INTO #PartyBettypeMapping
		FROM #tmpParty p
		INNER JOIN #Bettype bt ON p.ProductID = bt.ProductID
		WHERE p.ProductID <> 3

		INSERT INTO #Data(rptDate, SiteID, PartyID, ProductID, Bettype, [Status], CurrencyID, TurnOver, Winloss, WinlossA, CommissionA, CommissionP, Betcount)
		(
			SELECT	b.rptDate
					,b.SiteID
					,t.PartyID
					,t.ProductID
					,b.Bettype
					,b.[Status]
					,b.CurrencyID
					,SUM(b.turnover)
					,SUM(b.winloss)
					,SUM(b.winlossA)
					,SUM(b.CommissionA)
					,SUM(b.commissionP)
					,SUM(b.BetCount)
			FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
			INNER JOIN #PartyBettypeMapping t ON b.Bettype = t.Bettype AND b.SiteID = t.LicenseeID
			LEFT JOIN dbo.League l WITH(NOLOCK) ON b.leagueid = l.leagueid
			WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate) AND
					 b.[Status] NOT IN (- 1, 103) AND
					(@Currency = 0 OR @Currency = b.CurrencyID) AND
					(@excludeTest = 0 OR b.CurrencyID<>20) AND
					(@SportType = 0 OR (b.bettype NOT IN (9,29) AND (b.bettype NOT BETWEEN 31 AND 120) AND l.Sporttype = @Sporttype)) AND
					((@ReportBy = 0) OR
					 (@ReportBy = 1 AND b.IsLive=1 AND b.bettype NOT IN (9,29,10,31,32,33)) OR
					 (@ReportBy = 2 AND b.IsLive=0)) AND
					b.CustomerCategory NOT IN (27,28)
			GROUP BY b.rptDate
					,b.SiteID
					,t.PartyID
					,t.ProductID
					,b.Bettype
					,b.[Status]
					,b.CurrencyID
		)

		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, ProductID, Currency, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount, Playercomm)
		(
			SELECT	b.rptDate,
					tp.PartyID,
					tp.ProductID,
					b.CurrencyID,
					SUM(b.Turnover * 
						(CASE WHEN b.Bettype=33 AND b.[Status] IN (114,115) THEN 0.5 ELSE 1 END) *
						(CASE WHEN @drawfilter IN (2, 3) AND b.[Status] = 111  THEN 0
							  WHEN @drawfilter IN (2, 3) AND b.[Status] IN (114,115) AND b.bettype <> 33 THEN 0.5
							  ELSE 1 END)),
					SUM(b.winloss),
					-SUM(CASE WHEN b.bettype NOT IN (31,32, 33) THEN b.winloss ELSE 0 END) AS LicenseeWL,
					SUM(CASE WHEN b.bettype IN (31,32, 33) THEN b.WinlossA ELSE 0 END) AS WinlossRB,
					0 as AmountDueToBA,
					- SUM (CASE WHEN b.bettype IN (31,32, 33) THEN (b.winloss + b.winlossA + b.CommissionA) ELSE 0 END) AS AmountDueToRB,
					0 as CommBA,
					SUM ( CASE WHEN b.bettype IN (31,32, 33) THEN CommissionA ELSE 0 END) as CommRB,
					-SUM(CASE WHEN b.bettype NOT IN (31,32, 33) THEN (b.winloss * tp.Rate) ELSE 0 END) AS Company,
					SUM(b.Betcount) * (CASE WHEN @drawfilter = 2 AND b.[Status] = 111 THEN 0 ELSE 1 END),
					SUM(b.CommissionP)
			FROM #Data b WITH (NOLOCK)
			INNER JOIN #tmpParty tp ON b.SiteID = tp.LicenseeID AND tp.ProductID <> 3 AND b.ProductID = tp.ProductID
			WHERE b.rptDate BETWEEN tp.FromDate AND tp.Todate
			GROUP BY  b.rptDate, tp.ProductID, tp.PartyID, b.currencyID, b.[Status]
		)
	END

	-- Exchange rate
	SELECT DISTINCT ExchangeDate, ExchangeId, Code, BaseCurrencyRate AS Rate
	INTO #DailyExchange
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	IF @IsConvert = 0
	BEGIN
		UPDATE #DailyExchange
		SET Rate = 1
	END

	SELECT	w.PartyID,
			CASE WHEN p.PartyName ='18bb' THEN 'PIH'
				 WHEN p.PartyName ='IBC' THEN 'FDL'
				 ELSE p.PartyName
			END AS PartyName,
			SUM(TurnOver * e.Rate) AS Turnover,
			SUM(Winlost * e.Rate) AS Winlost,
			SUM(LicenseeWL * e.Rate) AS LicenseeWL,
			SUM(WinlossRB * e.Rate) AS WinlossRB,
			SUM(CommBA * e.Rate) AS CommBA,
			SUM(CommRB * e.Rate) AS CommRB,
			SUM(AmtDuetoBA * e.Rate) AS AmtDuetoBA,
			SUM(AmtDuetoRB * e.Rate) AS AmtDuetoRB,
			SUM(Company * e.Rate) AS Company,
			SUM(Betcount) AS Betcount,
			SUM(Playercomm * e.Rate) AS Playercomm
	FROM #tmpWinLoss w
	INNER JOIN #DailyExchange e ON w.Winlostdate = e.ExchangeDate AND w.currency = e.ExchangeId
	LEFT JOIN bodb_licensee.dbo.OAS_Party p ON w.PartyID = p.PartyID
	GROUP BY w.PartyID,p.PartyName
	ORDER BY w.PartyID,p.PartyName

	DECLARE @Exchange AS TABLE (Currency INT, CurrencyName VARCHAR(20), CurrencyCode VARCHAR(20))

	INSERT INTO @Exchange(Currency, CurrencyName, CurrencyCode)
	SELECT e.exchangeid, e.currency, e.Code
	FROM bodb02.dbo.Exchange e WITH (NOLOCK)
	WHERE e.exchangeid IN (SELECT DISTINCT Currency FROM #tmpWinLoss)

	UPDATE e
	SET CurrencyCode = e.CurrencyCode + '(' + CurrencyName + ')'
	FROM @Exchange e
	WHERE e.CurrencyCode IN (SELECT CurrencyCode FROM @Exchange GROUP BY CurrencyCode HAVING COUNT(1) > 1)

	SELECT	CASE WHEN w.Currency = 51 THEN 'INH'
				WHEN w.Currency = 20 THEN e.Code
				ELSE t.CurrencyCode END AS currencyName,
			w.currency,
			SUM(TurnOver * e.Rate) AS Turnover,
			SUM(Winlost * e.Rate) AS Winlost,
			SUM(LicenseeWL * e.Rate) AS LicenseeWL,
			SUM(WinlossRB * e.Rate) AS WinlossRB,
			SUM(CommBA * e.Rate) AS CommBA,
			SUM(CommRB * e.Rate) AS CommRB,
			SUM(AmtDuetoBA * e.Rate) AS AmtDuetoBA,
			SUM(AmtDuetoRB * e.Rate) AS AmtDuetoRB,
			SUM(Company * e.Rate) AS Company,
			SUM(Betcount) AS Betcount,
			SUM(Playercomm * e.Rate) AS Playercomm
	FROM #tmpWinLoss w	
	INNER JOIN #DailyExchange e ON w.Winlostdate = e.ExchangeDate AND w.Currency = e.ExchangeId
	LEFT JOIN @Exchange t ON w.Currency = t.Currency
	GROUP BY CASE WHEN w.Currency = 51 THEN 'INH' WHEN w.Currency = 20 THEN e.Code ELSE t.CurrencyCode END, w.currency
	ORDER BY CASE WHEN w.Currency = 51 THEN 'INH' WHEN w.Currency = 20 THEN e.Code ELSE t.CurrencyCode END

	DROP TABLE #tmpWinLoss
	DROP TABLE #Bettype
	DROP TABLE #tmpParty
	DROP TABLE #Data
	DROP TABLE #PartyBettypeMapping
	DROP TABLE #DailyExchange
END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_CurrencyWinloss] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_Rpt_CurrencyWinloss] TO bodbAdminNet
