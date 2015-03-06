USE [bodb02]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[LA_Rpt_KenoWinloss] 
	 @PartyIDs		VARCHAR(5500)
	, @FromDate		SMALLDATETIME
	, @ToDate		SMALLDATETIME	
	, @Market		INT				= 0
	, @Bettype		INT				= 0
	, @drawfilter	SMALLINT		= 1
	, @excludeTest	BIT				= 0
AS      
  
/*  
 * Created by : [20150303@Florent]  
 * Task  : Get Keno Winloss 
 * DB   : DB052.bodb02  
 
 * Revisions :  

 * Param's Explanation:    
 *  - @FromDate		: From date   
 *  - @ToDate		: To date   
 *	- @Market		: Market, Country or bettype in DB. Example: 1501	Australia
																 1502	Bejing
 *	- @Bettype		: is Keno Bettype. Example : 1 - 'Big/Small'
												 2 - 'Odd/Even'
												 3 - 'Up/Down'
 *  - @drawfilter:  'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
 *  - @excludeTest:  0 Get all currency in date range from - to
				 1 get only real currency from licensee_launch_date/from_date to to_date
 */  
    
BEGIN      

	SET NOCOUNT ON

	CREATE TABLE #Data (
		WinlostDate			DATE
		, Currency			INT
		, PartyID			INT
		, BettypeId			INT
		, KNBettypeId		INT
		, Turnover			MONEY
		, MemberWinloss		MONEY
		, Betcount			INT)
	CREATE TABLE #Result (
		PartyID				INT
		, TurnOver			MONEY
		, BettypeId			INT
		, KNBettypeId		INT
		, MemberWinloss		MONEY
		, LicWinloss		MONEY
		, Betcount			INT
		, AmtDueTo			MONEY
		, WinlostDate		VARCHAR(6)
		, CurrencyId		INT)
	CREATE TABLE #tmpParty (
		PartyId				INT
		, LicenseeId		INT
		, Rate				MONEY
		, FromDate			SMALLDATETIME
		, ToDate			SMALLDATETIME)
	CREATE TABLE #Bettype (
		Bettype				INT
		, ProductId			INT)

	INSERT INTO #tmpParty(PartyId, LicenseeId, Rate, Fromdate, Todate)
	(
		SELECT PartyID, LicenseeID, DI_Rate, Fromdate, Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'KN', 'OA', @ExcludeTest)
	)

	INSERT INTO #Bettype (Bettype, ProductID)
	(
		SELECT Bettype, ProductID 
		FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(@Market, 'KN')
	)

	--collect data
	BEGIN
		INSERT INTO #Data (WinlostDate, Currency, PartyID, BettypeId, KNBettypeId, Turnover, MemberWinloss, Betcount)
		(
			SELECT  b.rptDate AS WinlostDate
					, b.CurrencyId, tp.PartyID, b.BetTypeId, b.KenoBetTypeId
					, SUM(Turnover) AS Turnover
					, SUM(Winloss)  AS MemberWinloss
					, SUM(BetCount) AS Betcount
			FROM bodb_LicenseeReport.dbo.rptKenoWinloss b WITH ( NOLOCK) 
				INNER JOIN #tmpParty tp ON tp.LicenseeID = b.SiteId
				INNER JOIN #Bettype bt ON b.BetTypeId = bt.Bettype				
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate			
				AND (@Bettype = 0 OR ( @Bettype <> 0 AND b.KenoBetTypeId = @Bettype)) 
				AND (@excludeTest = 0 OR (@excludeTest = 1 AND CurrencyID <> 20))			
				AND b.StatusID NOT IN (-1, 103)			
			GROUP BY b.rptDate, b.CurrencyId, tp.PartyID, b.BetTypeId, b.KenoBetTypeId
		)
	END

	SELECT DISTINCT CONVERT(VARCHAR(6), ExchangeDate, 112) AS ExchangeDate
			, ExchangeId, USD, EUR, MYR 
	INTO #TempExchange 
	FROM Lrf_f_GetExchangeDaily(@FromDate, @ToDate)
	WHERE ExchangeId IN (SELECT DISTINCT Currency FROM #Data)

	INSERT INTO #Result (PartyID, TurnOver, BettypeId, KNBettypeId, MemberWinloss, LicWinloss, Betcount, AmtDueTo, WinlostDate, CurrencyId)
	SELECT	d.PartyID
			, CAST(ISNULL(SUM(d.TurnOver), 0) AS MONEY) AS TurnOver
			, d.BettypeId, d.KNBettypeId
			, CAST(ISNULL(SUM(d.MemberWinloss), 0) AS MONEY) AS MemberWinloss
			, CAST(- 1 * ISNULL(SUM(d.MemberWinloss), 0) AS MONEY) AS LicWinloss
			, ISNULL(SUM(d.Betcount), 0) AS BetCount
			, CAST(- 1 * ISNULL(SUM(d.MemberWinloss * ISNULL(tp.Rate, 0)), 0) AS MONEY) AS AmtDueTo
			, CONVERT(VARCHAR(6), d.WinlostDate, 112) AS WinlostDate
			, d.Currency
	FROM #Data d
		LEFT JOIN #tmpParty tp ON d.PartyID = tp.PartyID
	WHERE d.WinlostDate BETWEEN tp.FromDate AND tp.ToDate
	GROUP BY d.PartyID, CONVERT(VARCHAR(6), d.WinlostDate, 112), d.Currency, d.BettypeId, d.KNBettypeId

	--return the result
	SELECT	
		CASE WHEN p.PartyName = 'IBC' THEN 'FDL'
			 WHEN p.PartyName = '18bb' THEN 'PIH'
			 ELSE p.PartyName 
		END AS PartyName
		, re.WinlostDate
		, re.BettypeId 
		, re.KNBettypeId 
		, SUM(re.betcount) AS BetCount
		, CAST(SUM(re.turnover * ex.EUR) AS MONEY) AS Turnover
		, CAST(SUM(re.LicWinloss * ex.EUR) AS MONEY) AS Winlost
		, CAST(SUM(re.AmtDueTo * ex.EUR) AS MONEY) AS AmtDueTo	
	FROM #Result re
		INNER JOIN #TempExchange ex ON re.winlostdate = ex.exchangedate and re.CurrencyId = ex.ExchangeId    
		LEFT JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) on re.PartyID = p.PartyID    
	GROUP BY re.BettypeId, re.KNBettypeId, CONVERT(VARCHAR(6), re.winlostdate, 112)
			, CASE  WHEN p.PartyName = 'IBC' THEN 'FDL'
					WHEN p.PartyName = '18bb' THEN 'PIH'
					ELSE p.PartyName 
				END
	ORDER BY re.winlostdate ASC
			, CASE WHEN p.PartyName = 'IBC' THEN 'FDL'
				   WHEN p.PartyName = '18bb' THEN 'PIH'
				   ELSE p.PartyName 
				END
			, re.BettypeId, re.KNBettypeId
	DROP TABLE #Data
	DROP TABLE #Result
	DROP TABLE #TempExchange
	DROP TABLE #tmpParty
	DROP TABLE #Bettype
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_KenoWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_KenoWinloss] TO bodbAdminNet