/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="1" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].LA_Rpt_KenoWinloss
	 @PartyIDs				VARCHAR(5500)
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME	
	, @Market				INT				= 0
	, @Bettype				INT				= 0
	, @Drawfilter			SMALLINT		= 1
	, @ExcludeTest			BIT				= 0
	, @IsConvert			BIT				= 1
	, @BaseCurrencyName		VARCHAR(10)		= 'GBP'
AS      
  
/*  
 * Created by : [20150303@Florent]  
 * Task  : Get Keno Winloss 
 * DB   : DB052.bodb02  
 
 * Revisions :  
	- 20150320@Florent: enhance SP, using function LA_f_ExchangeDailySel
	- 20150705@Florent: add GBP
	- 20170622@Scofield: get PayToSupplier [#78398]
	- 20171220@Parsons: increase length for variables [#88197]
	- 20180716@bruce: add new group TEST for credit [#98126]

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
		, PayToSupplier		MONEY
		, WinlostDate		DATE
		, CurrencyId		INT)
	CREATE TABLE #tmpParty (
		PartyId				INT
		, LicenseeId		INT
		, Rate				MONEY
		, Rate3rd			MONEY
		, FromDate			SMALLDATETIME
		, ToDate			SMALLDATETIME)
	CREATE TABLE #Bettype (
		Bettype				INT
		, ProductId			INT)

	CREATE TABLE #Party (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT)
	INSERT INTO #Party EXEC bodb_licensee.dbo.LA_PartyListSel

	INSERT INTO #tmpParty(PartyId, LicenseeId, Rate, Rate3rd, Fromdate, Todate)
	(
		SELECT c.PartyID, c.LicenseeID, c.DI_Rate, 
			CASE
				WHEN c.PartyId = 14 OR ISNULL(c.IsDeposit,0)=0 THEN 0.03
				ELSE 0.05
			END, c.Fromdate, c.Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'KN', 'OA', @ExcludeTest) c
		WHERE c.Fromdate <= c.Todate
	)

	INSERT INTO #Bettype (Bettype, ProductID)
	(
		SELECT Bettype, ProductID 
		FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(@Market, 'KN')
	)

	CREATE TABLE #Exchange( ExchangeDate DATE, ExchangeID INT, Rate FLOAT)
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate,  ExchangeID, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	IF @IsConvert = 0
	BEGIN
		UPDATE #Exchange
		SET Rate = 1
	END 

	--collect data
	INSERT INTO #Data (WinlostDate, Currency, PartyID, BettypeId, KNBettypeId, Turnover, MemberWinloss, Betcount)
	(
		SELECT  b.rptDate AS WinlostDate
				, b.CurrencyId, tp.PartyID, b.BetTypeId, b.KenoBetTypeId
				, SUM(CASE WHEN @drawfilter IN (2, 3) AND b.StatusId = 111 THEN 0 ELSE Turnover * ex.Rate END) AS Turnover
				, SUM(Winloss * ex.Rate)  AS MemberWinloss
				, SUM(BetCount * CASE WHEN @drawfilter = 2 AND b.StatusId = 111 THEN 0 ELSE 1 END) AS Betcount
		FROM bodb_LicenseeReport.dbo.rptKenoWinloss b WITH ( NOLOCK) 
			INNER JOIN #tmpParty tp ON tp.LicenseeID = b.SiteId AND b.RptDate BETWEEN tp.FromDate AND tp.ToDate
			INNER JOIN #Bettype bt ON b.BetTypeId = bt.Bettype			
			INNER JOIN #Exchange ex ON b.rptDate = ex.exchangedate and b.CurrencyId = ex.ExchangeId   	
		WHERE b.rptDate BETWEEN @Fromdate AND @Todate
			AND (@Bettype = 0 OR ( @Bettype <> 0 AND b.KenoBetTypeId = @Bettype)) 
			AND (@excludeTest = 0 OR (@excludeTest = 1 AND CurrencyID <> 20))			
			AND b.StatusID NOT IN (-1, 101, 102, 103)			
		GROUP BY b.rptDate, b.CurrencyId, b.BetTypeId, b.KenoBetTypeId, tp.PartyID	
	)
	
	INSERT INTO #Result (PartyID, TurnOver, BettypeId, KNBettypeId, MemberWinloss, LicWinloss, Betcount, AmtDueTo, PayToSupplier, WinlostDate, CurrencyId)
	SELECT	d.PartyID
			, CAST(ISNULL(SUM(d.TurnOver), 0) AS MONEY) AS TurnOver
			, d.BettypeId, d.KNBettypeId
			, CAST(ISNULL(SUM(d.MemberWinloss), 0) AS MONEY) AS MemberWinloss
			, CAST(- 1 * ISNULL(SUM(d.MemberWinloss), 0) AS MONEY) AS LicWinloss
			, ISNULL(SUM(d.Betcount), 0) AS BetCount
			, CAST(- 1 * ISNULL(SUM(d.MemberWinloss * ISNULL(tp.Rate, 0)), 0) AS MONEY) AS AmtDueTo
			, CAST(- 1 * ISNULL(SUM(d.MemberWinloss * ISNULL(tp.Rate3rd, 0)), 0) AS MONEY) AS PayToSupplier
			, DATEADD(MONTH, DATEDIFF(MONTH, 0,d.WinlostDate),0)
			, d.Currency
	FROM #Data d
		LEFT JOIN (SELECT DISTINCT PartyID, FromDate, ToDate, Rate, Rate3rd FROM #tmpParty) tp ON d.PartyID = tp.PartyID
	WHERE d.WinlostDate BETWEEN tp.FromDate AND tp.ToDate
	GROUP BY d.PartyID, DATEADD(MONTH, DATEDIFF(MONTH, 0,d.WinlostDate),0), d.Currency, d.BettypeId, d.KNBettypeId

	--return the result
	SELECT	
		CASE WHEN p.PartyName = 'IBC' THEN 'FDL'
			 WHEN p.PartyName = '18bb' THEN 'PIH'
			 ELSE p.PartyName 
		END AS PartyName
		, re.WinlostDate
		, re.BettypeId 
		, re.KNBettypeId AS KenoBettypeId
		, SUM(re.betcount) AS BetCount
		, CAST(SUM(re.turnover) AS MONEY)		AS Turnover
		, CAST(SUM(re.LicWinloss) AS MONEY)		AS Winloss
		, CAST(SUM(re.AmtDueTo) AS MONEY)		AS AmtDueTo	
		, CAST(SUM(re.PayToSupplier) AS MONEY)	AS PayToSupplier	
	FROM #Result re
		LEFT JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) on re.PartyID = p.PartyID    
	GROUP BY re.BettypeId, re.KNBettypeId, re.WinlostDate
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
	DROP TABLE #Exchange
	DROP TABLE #tmpParty
	DROP TABLE #Bettype
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_KenoWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_KenoWinloss] TO bodbAdminNet
GO