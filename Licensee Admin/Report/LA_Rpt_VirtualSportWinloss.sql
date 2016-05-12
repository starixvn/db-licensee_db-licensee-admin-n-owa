USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[LA_Rpt_VirtualSportWinloss]      	
	@PartyIDs				VARCHAR(5500) 
	, @FromDate				SMALLDATETIME    
	, @ToDate				SMALLDATETIME    
	, @SportType			INT				= 0
	, @BetType				INT				= 0
	, @drawfilter			SMALLINT		= 1
	, @excludeTest			BIT				= 0
	, @IsConvert			BIT				= 1
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'	
AS      
  
/*  
 * Created by : [20140911@Florent]  
 * Task  : Get Virtual Sports Winloss 
 * DB   : DB052.bodb02  
 * Base on : [OA_Rpt_VirtualSportWinloss]
 * Revisions :  
	   - 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
	   - 20150326@Florent: fix filter drawfilter
	   - 20150703@Florent: add GBP
	   - 20160115@Victor: Show data of credit licensees regardless Charge Rate = 0 [Redmine: #50829]
 * Param's Explanation:    
 *  - @FromDate   : From date   
 *  - @ToDate   : To date  
 *  - @Sporttype   : Sporttype 
 *  - @BetList:  Bettype offered for Virtual sports (0:All Bettype)
 *  - @drawfilter:  'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
 *  - @excludeTest:  0 Get all currency in date range from - to
				 1 get only real currency from licensee_launch_date/from_date to to_date
 */  
    
BEGIN      

SET NOCOUNT ON
CREATE TABLE #Data (winlostdate  DATETIME, Currency  INT,PartyID int,Sporttype int,bettype INT,turnover MONEY,
 MemberWinloss MONEY, Betcount INT)
CREATE TABLE #Result (PartyID int, TurnOver MONEY,SportType INT, BetType INT, MemberWinloss MONEY, GrossWinloss MONEY,
 Betcount INT, OneworksIncome MONEY, winlostdate  DATETIME, Currency INT)

CREATE TABLE #tmpParty (
	   PartyID	    INT
	   ,LicenseeID   INT
	   ,isDeposit    INT
	   ,AffectedDate SMALLDATETIME
	   ,ProductID    INT 
	   ,Rate	    Money
	   ,Fromdate	    SMALLDATETIME
	   ,Todate	    SMALLDATETIME
	   )

DECLARE @PartyIDs_NoCredit	VARCHAR(5500)
DECLARE @PartyIDs_Credit	VARCHAR(5500)

SELECT	@PartyIDs_NoCredit = COALESCE(@PartyIDs_NoCredit + ', ', '') + CONVERT(VARCHAR(10), val)
FROM	Lrf_f_StringSplit(@PartyIDs,',') s
	INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON p.PartyID = s.val AND p.PartyType = 1
	INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID AND pd.IsDeposit = 1

SELECT	@PartyIDs_Credit = COALESCE(@PartyIDs_Credit + ', ', '') + CONVERT(VARCHAR(10), val)
FROM	Lrf_f_StringSplit(@PartyIDs,',') s
	INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON p.PartyID = s.val AND p.PartyType = 1
	INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID AND pd.IsDeposit = 0
	
INSERT INTO #tmpParty
SELECT PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, DI_Rate, Fromdate, Todate
FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs_NoCredit,@FromDate,@ToDate,'VS','OA',@ExcludeTest)

INSERT INTO #tmpParty
SELECT PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, DI_Rate, Fromdate, Todate
FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs_Credit,@FromDate,@ToDate,'VS','OA',0)
 
-- normal Licensee
IF EXISTS(SELECT 1 FROM #tmpParty tp WHERE tp.IsDeposit = 1)
BEGIN
	INSERT INTO #Data
	SELECT  b.rptDate, b.currencyID, tp.PartyID, l.sporttype
		   , b.bettype
		   , SUM(Turnover * 
							CASE   
								WHEN @drawfilter IN (2,3) THEN  
								CASE   
									WHEN b.status = 111 THEN 0  
									WHEN (b.status = 114 OR b.status = 115) THEN 0.5  
								ELSE 1   
								END  
							ELSE 1   
							END) AS Turnover
		   , SUM(Winloss) AS MemberWinloss
		   , SUM(BetCount * 
							CASE   
								WHEN @drawfilter = 2 THEN  
									CASE   
										WHEN b.status = 111 THEN 0  
										ELSE 1   
									END  
								ELSE 1   
							END ) AS betcount
	FROM bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) 
		INNER JOIN #tmpParty tp ON tp.LicenseeID = b.siteID
		LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID				
	WHERE
		tp.IsDeposit = 1 AND
		b.rptDate BETWEEN tp.Fromdate AND tp.Todate
		AND b.status NOT IN (-1, 103)
		AND (@excludeTest = 0 OR (@excludeTest = 1 AND CurrencyID <> 20))
		AND bettype BETWEEN 1201 AND 1299
		AND (@Sporttype = 0 OR ( @Sporttype<>0 AND l.Sporttype = @Sporttype)) 
		AND (@bettype = 0 OR (b.bettype = @bettype AND @bettype <> 0))
		AND b.customercategory NOT IN (27,28) 
	GROUP BY b.rptDate,b.currencyID,tp.PartyID,l.sporttype, b.bettype
END

--FDL + PIH...
IF EXISTS (SELECT 1 FROM #tmpParty tp WHERE tp.IsDeposit = 0)
BEGIN
	INSERT INTO #Data
	SELECT  b.rptDate, b.currencyID, lr.PartyID, l.sporttype, b.bettype
		, SUM(Turnover * 
						CASE   
							WHEN @drawfilter IN (2,3) THEN  
							CASE   
								WHEN b.status = 111 THEN 0  
								WHEN (b.status = 114 OR b.status = 115) THEN 0.5  
							ELSE 1   
							END  
						ELSE 1   
						END) AS Turnover
		, SUM(Winloss) AS MemberWinloss
		, SUM(BetCount * 
						CASE   
							WHEN @drawfilter = 2 THEN  
								CASE   
									WHEN b.status = 111 THEN 0  
									ELSE 1   
								END  
							ELSE 1   
						END ) AS betcount
	FROM #tmpParty lr		
		INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID = lr.LicenseeID
		LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID		
	WHERE
		lr.IsDeposit = 0 AND
		b.rptDate BETWEEN lr.Fromdate AND lr.Todate
		AND b.status NOT IN (-1,103)
		AND (@excludeTest = 0 OR (@excludeTest = 1 AND CurrencyID <> 20))
		AND bettype BETWEEN 1201 AND 1299
		AND b.customercategory NOT IN (27,28) 
		AND (@Sporttype = 0 OR ( @Sporttype<>0 AND l.Sporttype = @Sporttype)) 
		AND (@bettype = 0 OR (b.bettype = @bettype AND @bettype <> 0))
	GROUP BY b.rptDate,b.currencyID, lr.PartyID,l.sporttype, b.bettype	
END

CREATE NONCLUSTERED INDEX IDX_Currency ON #Data(Currency)

SELECT DISTINCT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate 
INTO #TempExchange	
FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName) 
WHERE exchangeid IN (SELECT DISTINCT Currency FROM #Data)
	
IF @IsConvert = 0
BEGIN
	UPDATE #TempExchange
	SET Rate = 1
END

INSERT INTO #Result (PartyID,TurnOver,SportType,BetType,MemberWinloss,GrossWinloss,Betcount,
OneworksIncome,winlostdate,Currency)
SELECT	
		d.PartyID,
		CAST(isnull(SUM(d.TurnOver ),0) AS MONEY) AS TurnOver,		
		d.Sporttype,d.bettype,
		CAST(isnull(SUM(d.MemberWinloss ),0) AS MONEY) AS MemberWinloss,		
		CAST(-1 * isnull(SUM(d.MemberWinloss ),0) AS money) AS GrossWinloss,
		ISNULL(SUM(d.betcount), 0) AS BetCount,
		CAST(-1 * isnull(SUM(d.MemberWinloss  * isnull(tp.Rate,0)),0) AS money) AS OneworksIncome
		,winlostdate,Currency
	FROM #Data d			
		LEFT JOIN (SELECT DISTINCT PartyID,Rate,Fromdate,Todate FROM #tmpParty) tp ON d.PartyID = tp.PartyID
     WHERE d.winlostdate BETWEEN tp.Fromdate AND tp.Todate
	GROUP BY
		d.PartyID, winlostdate,Currency,d.Sporttype,d.bettype

--return the result
SELECT	
	CASE WHEN p.PartyName = 'IBC' THEN 'FDL'
		     WHEN p.PartyName = '18bb' THEN 'PIH'
		     ELSE p.PartyName 
		END AS PartyName,
	CONVERT(Varchar(6), re.winlostdate, 112) AS winlostdate,	
	re.sporttype,
	re.bettype,
	ISNULL(SUM(re.betcount), 0) AS BetCount,
	CAST(isnull(SUM(re.turnover * ex.Rate),0) AS MONEY) AS Turnover,	
	CAST(isnull(SUM(re.GrossWinloss * ex.Rate),0) AS MONEY) AS GrossWinloss,	
	CAST(isnull(SUM(re.OneworksIncome * ex.Rate),0) AS MONEY) AS OneworksIncome	
FROM #Result re
    INNER JOIN #TempExchange ex ON re.winlostdate = ex.exchangedate and re.Currency = ex.ExchangeId    
    LEFT JOIN bodb_licensee.dbo.OAS_Party p on re.PartyID = p.PartyID    
GROUP BY
	re.sporttype,re.bettype,
	CONVERT(Varchar(6),re.winlostdate,112),
	CASE WHEN p.PartyName = 'IBC' THEN 'FDL'
		     WHEN p.PartyName = '18bb' THEN 'PIH'
		     ELSE p.PartyName 
		END
ORDER BY
     CONVERT(Varchar(6),re.winlostdate,112) ASC,
	CASE WHEN p.PartyName = 'IBC' THEN 'FDL'
		     WHEN p.PartyName = '18bb' THEN 'PIH'
		     ELSE p.PartyName 
		END,re.sporttype,re.bettype
	
DROP TABLE  #Data
DROP TABLE  #Result
DROP TABLE  #TempExchange
DROP TABLE  #tmpParty
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_VirtualSportWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_VirtualSportWinloss] TO bodbAdminNet 