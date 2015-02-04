USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[OAS_Report_VirtualSportWinloss]    Script Date: 17/11/2014 11:22:30 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****** Object:  Stored Procedure dbo.OAS_Report_VirtualSportWinloss_NewStruct    Script Date: 4/14/2014 13:15:15  ******/
ALTER PROCEDURE [dbo].[OAS_Report_VirtualSportWinloss] 
	  @PartyID		INT
	, @Currency		INT				= 0
	, @drawfilter	SMALLINT		= 0
	, @FromDate		SMALLDATETIME
	, @ToDate		SMALLDATETIME
	, @SportList	VARCHAR(1000)

AS
/*  
 * Created by : 20131219@Francis 
 * Task  : Get Winloss report for Virtual Sports (compatible with the new structure)
 * DB   : DB052.bodb02
 * Revisions :  
	- 20140331@Florent: Aplly new report template
	- 20140416@Florent: Change condition of time range 
	- 20140410@Francis: Alter @drawfilter param's value to 0,1,2
 	- 20141103@Florent: Fix formula for OW revenue, use new structure (#25393)
	- 20141117@Florent: remove comm
	- 20150202@Florent: base currency GBP
 * Param's Explanation:    
	- @Currency: 0 : All
				-1: Base on EUR
				-2: Base on GBP
 *  
 */
BEGIN
	SET NOCOUNT ON

	DECLARE @tmpLicenseeReseller AS TABLE (FromPartyID INT, ToPartyID INT, FromDate DATETIME, ToDate DATETIME, OldRefID INT)
	DECLARE @sporttype TABLE (sporttype INT)
	CREATE TABLE #Exchange1(ExchangeDate DATE, ExchangeId INT, Code VARCHAR(10), EUR FLOAT, USD FLOAT, MYR FLOAT, GBP FLOAT)
	CREATE TABLE #Exchange(ExchangeDate DATE, ExchangeId INT, Code VARCHAR(10), EUR FLOAT, USD FLOAT, MYR FLOAT, GBP FLOAT)

	CREATE TABLE #Data (WinlostDate DATETIME,Currency INT, FromPartyID INT, ToPartyID INT, TurnOver MONEY, MemberWinloss MONEY , Betcount INT)

	--Output table 
	CREATE TABLE #Result (ResellerID INT, LicenseeID INT, TurnOver MONEY, MemberWinloss MONEY, GrossWinloss MONEY, Betcount INT, OneworksIncome MONEY, AmtDueToInspired MONEY, WinlostDate DATETIME, Currency INT)

	DECLARE @tmpTable AS TABLE (PartyID INT)

	INSERT INTO @tmpTable (PartyID)
	SELECT PartyID
	FROM bodb_licensee.dbo.OAS_Party(NOLOCK)
	WHERE PartyName IN ('Starlit', 'BA(FDL)')

	IF (RTRIM(LTRIM(ISNULL(@SportList, '')))) = ''
	BEGIN
		INSERT INTO @sporttype
		VALUES (180) --Virtual Soccer
	END
	ELSE
	BEGIN
		INSERT INTO @sporttype (sporttype)
		-- strSpit is a user-defined function
		SELECT RTRIM(LTRIM(VAL))
		FROM strSplit(@SportList, ',')
	END

	--hard code get licensee depend boping
	DECLARE  @isDeposit INT = 0, @isBoping INT = 0
		
	--Get normal licensee list	
	IF NOT EXISTS (SELECT TOP 1 1 FROM bodb_licensee.dbo.OAS_Party WITH (NOLOCK) WHERE PartyName = 'Boping' AND PartyID = @Partyid)
	BEGIN
		INSERT INTO @tmpLicenseeReseller (FromPartyID, ToPartyID, FromDate, ToDate, OldRefID)
		SELECT DISTINCT ci.FromParty, ci.ToParty
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
			,p.OldRefID
		FROM bodb_licensee.dbo.OAS_ChargeInfo ci(NOLOCK)
			INNER JOIN bodb_Licensee.dbo.OAS_Party p(NOLOCK) ON ci.FromParty = p.PartyID
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 4 --OWS
		WHERE (
				@FromDate BETWEEN ci.FromDate AND ci.ToDate
				OR @ToDate BETWEEN ci.FromDate AND ci.ToDate
				)
			AND ci.ChargeType = 1
			AND ci.ProductID = 5			
			AND ci.FromParty = @PartyID
	END
	ELSE -- get boping's licensees
	BEGIN
		INSERT INTO @tmpLicenseeReseller (FromPartyID, ToPartyID, FromDate, ToDate, OldRefID)
		SELECT DISTINCT ci.FromParty, ci.ToParty
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
			,p.OldRefID
		FROM bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK)
			INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK) ON ci.FromParty = p.PartyID
			INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 4 --OWS
		WHERE (
				@FromDate BETWEEN ci.FromDate AND ci.ToDate
				OR @ToDate BETWEEN ci.FromDate AND ci.ToDate
				)
			AND ci.ChargeType = 1
			AND ci.ProductID = 5			
			AND ci.ToParty = @PartyID
		SET @isBoping = 1
	END

	--For Deposit Licensees
	IF EXISTS (SELECT 1
				FROM @tmpLicenseeReseller tlr
				INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd1(NOLOCK) ON tlr.FromPartyID = pd1.PartyID
				WHERE pd1.IsDeposit = 1
					AND tlr.ToPartyID NOT IN (SELECT PartyID FROM @tmpTable))
	BEGIN
		INSERT INTO #Data (WinlostDate, Currency, FromPartyID, ToPartyID, TurnOver, MemberWinloss, Betcount)
		SELECT b.rptDate, b.currencyID, lr.FromPartyID, lr.ToPartyID
			,SUM(Turnover * CASE 
					WHEN @drawfilter IN (1, 2)
						THEN CASE 
								WHEN b.STATUS = 111 THEN 0
								WHEN (b.STATUS = 114 OR b.STATUS = 115) THEN 0.5
								ELSE 1
								END
					ELSE 1
					END)		 AS TurnOver
			,SUM(b.Winloss)	 AS MemberWinloss
			,SUM(BetCount * CASE 
					WHEN @drawfilter = 1
						THEN CASE 
								WHEN b.STATUS = 111 THEN 0
								ELSE 1
								END
					ELSE 1
					END) AS BetCount
		FROM bodb_Licensee.dbo.rpt_Betting b(NOLOCK)
			INNER JOIN @tmpLicenseeReseller lr ON b.SiteID = lr.OldRefID			
			INNER JOIN bodb02.dbo.league l(NOLOCK) ON l.leagueid = b.LeagueID
		WHERE b.rptDate BETWEEN lr.FromDate AND lr.ToDate
			AND b.STATUS NOT IN (- 1, 103)
			AND CurrencyID <> 20
			AND bettype BETWEEN 1201 AND 1299
			AND l.Sporttype IN (SELECT sporttype FROM @sporttype)
			--Exclude Licensees from Starlit, BA(FDL)
			AND lr.ToPartyID NOT IN (SELECT PartyID FROM @tmpTable)
			AND (@Currency <= 0 OR b.CurrencyID = @Currency)
		GROUP BY b.rptDate, b.CurrencyID, lr.ToPartyID, lr.FromPartyID

		SET @isDeposit = 1
	END

	--For Credit Licensees
	IF EXISTS (SELECT 1
				FROM @tmpLicenseeReseller tlr
					INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd1(NOLOCK) ON tlr.FromPartyID = pd1.PartyID
				WHERE pd1.IsDeposit = 0)
	BEGIN
		INSERT INTO #Data (WinlostDate, Currency, FromPartyID, ToPartyID, TurnOver, MemberWinloss, Betcount)
		SELECT b.rptDate, b.currencyID, lr.FromPartyID, lr.ToPartyID
			,SUM(Turnover * CASE 
					WHEN @drawfilter IN (1, 2)
						THEN CASE 
								WHEN b.STATUS = 111 THEN 0
								WHEN (b.STATUS = 114 OR b.STATUS = 115) THEN 0.5
								ELSE 1
								END
					ELSE 1
					END)		 AS TurnOver
			,SUM(b.Winloss)	 AS MemberWinloss
			,SUM(BetCount * CASE 
					WHEN @drawfilter = 1
						THEN CASE 
								WHEN b.STATUS = 111 THEN 0
								ELSE 1
								END
					ELSE 1
					END) AS BetCount
		FROM @tmpLicenseeReseller lr			
			INNER JOIN bodb_Licensee.dbo.labels lb(NOLOCK) ON lr.OldRefID = lb.LicenseeID
			INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK) ON b.siteID = lb.LabelID
		INNER JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
		WHERE b.rptDate BETWEEN lr.FromDate AND lr.ToDate
			AND b.STATUS NOT IN (- 1, 103)
			AND CurrencyID <> 20
			AND bettype BETWEEN 1201 AND 1299
			AND b.customercategory NOT IN (27, 28)
			AND l.Sporttype IN (SELECT sporttype FROM @sporttype)
			AND (@Currency <= 0 OR b.CurrencyID = @Currency)
		GROUP BY b.rptDate, b.CurrencyID, lr.ToPartyID, lr.FromPartyID
	END

	CREATE NONCLUSTERED INDEX IDX_Currency ON #Data (Currency, winlostdate)

	--get specified exchange value in time range	
	DECLARE @ExDate SMALLDATETIME, @Rate FLOAT

	SELECT @ExDate = CONVERT(VARCHAR(10), CASE 
				WHEN DATEDIFF(month, @ToDate, GETDATE()) <= 0
					THEN GETDATE()
				ELSE DATEADD(day, - 1, DATEADD(month, 1, '01 ' + SUBSTRING(CONVERT(VARCHAR(11), @ToDate, 106), 4, 8)))
				END, 120)

	INSERT INTO #Exchange1(ExchangeDate, ExchangeId, Code, EUR, USD, MYR, GBP)
	SELECT ExchangeDate, ExchangeId, Code, EUR, USD, MYR, GBP	
	FROM Lrf_f_GetExchangeDaily(@ExDate, @ExDate) -- get exchange rate in last day of month
	WHERE ExchangeId IN (SELECT DISTINCT Currency FROM #Data)
		OR ExchangeId = 6
	INSERT INTO #Exchange(ExchangeDate, ExchangeId, Code, EUR, USD, MYR, GBP)
	SELECT ExchangeDate, ExchangeId, Code, EUR, USD, MYR, GBP	
	FROM Lrf_f_GetExchangeDaily(@FromDate, @ToDate)
	WHERE ExchangeId IN (SELECT DISTINCT Currency FROM #Data)

	SELECT @Rate = GBP
	FROM #Exchange1
	WHERE ExchangeId = 6 --EUR

	--For Normal Licensees
	INSERT INTO #Result (ResellerID, LicenseeID, TurnOver, MemberWinloss, GrossWinloss, Betcount, OneworksIncome, AmtDueToInspired, WinlostDate, Currency)
	SELECT d.ToPartyID
		,d.FromPartyID
		,CAST(ISNULL(SUM(d.TurnOver), 0) AS MONEY) AS TurnOver
		,CAST(ISNULL(SUM(d.MemberWinloss), 0) AS MONEY) AS MemberWinloss
		,CAST(- 1 * isnull(SUM(d.MemberWinloss), 0) AS MONEY) AS GrossWinloss		
		,ISNULL(SUM(d.betcount), 0) AS BetCount
		,CAST(CASE 
				WHEN INS.Rate IS NOT NULL
					THEN --normal Licensee
						- 1 * isnull(SUM(d.MemberWinloss * ISNULL(OW.Rate, 0) ), 0)  --isnull(SUM(-1 * d.MemberWinloss ),0) < 0 THEN 0 
				ELSE - 1 * isnull(SUM(d.MemberWinloss * ISNULL(DI.Rate, 0) ), 0)  --direct licensee
				END AS MONEY) AS OneworksIncome
		,CAST(CASE 
				WHEN INS.Rate IS NOT NULL
					THEN ISNULL(SUM(- 1 * d.MemberWinloss * ISNULL(INS.Rate, 0)), 0) -- normal licensee
						--isnull(SUM(-1 * d.MemberWinloss ),0) < 0 THEN 0 
				ELSE ISNULL(SUM(- 1 * d.MemberWinloss * ISNULL(OW.Rate, 0)), 0)
				END AS MONEY) AS AmtDueToInspired
		,d.WinlostDate
		,Currency
	FROM #Data d
		LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo DI ON d.ToPartyID = DI.ToParty
			AND d.FromPartyID = DI.FromParty
			AND DI.ProductID = 5
			AND d.winlostdate BETWEEN DI.FromDate AND DI.ToDate
			AND DI.ChargeType = 1
		 INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON cs.ChargeID = DI.ChargeID AND cs.SystemID = 4
		LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo OW ON DI.ParentChargeID = OW.ChargeID
		LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo INS ON OW.ParentChargeID = INS.ChargeID
	GROUP BY d.ToPartyID, d.FromPartyID, d.WinlostDate, Currency, INS.Rate

	--return the result for deposit licensee
	 --normal Licensee and not Boping
	IF (@isDeposit = 1 AND @isBoping = 0)
		SELECT CONVERT(VARCHAR(6), winlostdate, 112) AS Winlostdate
			, re.Currency
			, CASE 
			 	WHEN re.Currency = 20
			 		THEN 'UUS'
			 	WHEN re.Currency = 51
			 		THEN 'INH'
			 	ELSE e.Code
			 	END AS CurrencyName
			, ISNULL(e1.EUR, 0) EUR
			, ISNULL(e1.GBP, 0) GBP
			, SUM(re.betcount) AS BetCount
			, SUM(re.turnover) AS Turnover
			, SUM(re.MemberWinloss) AS MemberWinloss
			, SUM(re.GrossWinloss) AS LicenseeWinloss
			, SUM(re.OneworksIncome - re.AmtDueToInspired) AS OneworksRevenue
			
			--EUR
			, SUM(re.turnover * e.EUR) AS TurnoverEUR
			, SUM(re.MemberWinloss * e.EUR) AS MemberWinlossEUR
			, SUM(re.GrossWinloss * e.EUR) AS LicenseeWinlossEUR
			, SUM(re.OneworksIncome * e.EUR - re.AmtDueToInspired * e.EUR) AS OneworksRevenueEUR
			
			--USD
			, SUM(re.turnover * e.USD) AS TurnoverUSD
			, SUM(re.MemberWinloss * e.USD) AS MemberWinlossUSD
			, SUM(re.GrossWinloss * e.USD) AS LicenseeWinlossUSD
			, SUM(re.OneworksIncome * e.USD - re.AmtDueToInspired * e.USD) AS OneworksRevenueUSD
			--GBP
			, SUM(re.turnover * e.GBP) AS TurnoverGBP
			, SUM(re.MemberWinloss * e.GBP) AS MemberWinlossGBP
			, SUM(re.GrossWinloss * e.GBP) AS LicenseeWinlossGBP
			, SUM(re.OneworksIncome * e.GBP - re.AmtDueToInspired * e.GBP) AS OneworksRevenueGBP
		FROM #Result re
			INNER JOIN #Exchange e ON re.currency = e.ExchangeId AND re.winlostdate = e.ExchangeDate
			LEFT JOIN #Exchange1 e1 ON re.currency = e1.ExchangeId
		GROUP BY re.Currency, ISNULL(e1.EUR, 0), ISNULL(e1.GBP, 0), e.code, CONVERT(VARCHAR(6), winlostdate, 112)

	--for credit
	--credit Licensee or Boping
	IF (@isDeposit = 0 OR @isBoping = 1) 
		SELECT CONVERT(VARCHAR(6), winlostdate, 112) AS Winlostdate
			,'EUR' CurrencyName
			/*,CASE WHEN @Currency = -2 THEN @Rate
						ELSE 1
					END EUR	
			*/
			, 1 EUR
			, @Rate GBP
			,ISNULL(SUM(re.betcount), 0) AS BetCount
			
			--base on EUR
			,SUM(re.turnover * e.EUR) AS Turnover
			,SUM(re.MemberWinloss * e.EUR) AS MemberWinloss
			,SUM(re.GrossWinloss * e.EUR) AS LicenseeWinloss
			,SUM(re.OneworksIncome * e.EUR - re.AmtDueToInspired * e.EUR) AS OneworksRevenue
			
			--EUR
			,SUM(re.turnover * e.EUR) AS TurnoverEUR
			,SUM(re.MemberWinloss * e.EUR) AS MemberWinlossEUR
			,SUM(re.GrossWinloss * e.EUR) AS LicenseeWinlossEUR
			,SUM(re.OneworksIncome * e.EUR - re.AmtDueToInspired * e.EUR) AS OneworksRevenueEUR
			
			--USD
			,SUM(re.turnover * e.USD) AS TurnoverUSD
			,SUM(re.MemberWinloss * e.USD) AS MemberWinlossUSD
			,SUM(re.GrossWinloss * e.USD) AS LicenseeWinlossUSD
			,SUM(re.OneworksIncome * e.USD - re.AmtDueToInspired * e.USD) AS OneworksRevenueUSD

			--GBP
			,SUM(re.turnover * e.GBP) AS TurnoverGBP
			,SUM(re.MemberWinloss * e.GBP) AS MemberWinlossGBP
			,SUM(re.GrossWinloss * e.GBP) AS LicenseeWinlossGBP
			,SUM(re.OneworksIncome * e.GBP - re.AmtDueToInspired * e.GBP) AS OneworksRevenueGBP
		FROM #Result re
			INNER JOIN #Exchange e ON re.Currency = e.ExchangeId AND re.WinlostDate = e.ExchangeDate
		GROUP BY CONVERT(VARCHAR(6), winlostdate, 112)

	DROP TABLE #Data
	DROP TABLE #Result
	DROP TABLE #Exchange
	DROP TABLE #Exchange1
END

GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Report_VirtualSportWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[OAS_Report_VirtualSportWinloss] TO bodbAdminNet 