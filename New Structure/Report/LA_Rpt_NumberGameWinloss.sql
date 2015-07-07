USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_NumberGameWinloss]    Script Date: 01/12/2014 14:36:23 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_Rpt_NumberGameWinloss] 
	 @PartyIDs				VARCHAR(5500)
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME
	, @Currency				INT				= 0
	, @drawfilter			SMALLINT		= 0
	, @excludeTest			BIT				= 0
	, @IsConvert			BIT				= 1
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'

AS      
  
/*  
 * Created by : [20140904@Florent.Nguyen]  
 * Task  : Get Number Game Winloss 
 * DB   : DB052.bodb02  
 * Revisions :  	
    - 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
	- 20150703@Florent: add GBP
 * Param's Explanation:
 *  
 */  

BEGIN
	SET NOCOUNT ON	
	
	CREATE TABLE #Data (winlostdate  DATETIME, Currency  INT,  PartyID int,  TurnOver MONEY, MemberWinloss MONEY, LicenseeWL MONEY, Betcount INT)		
		
	--get list PartyIDs
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

    INSERT INTO #tmpParty
    SELECT PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, DI_Rate, Fromdate, Todate
    FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'NG', 'OA', @ExcludeTest) 

	--Output table 
	CREATE TABLE #Result (PartyID int,Currency int, TurnOver MONEY, MemberWinloss MONEY, GrossWinloss MONEY, Betcount INT, OneworksRevenue MONEY, winlostdate datetime)
	
	BEGIN
		INSERT INTO #Data (winlostdate, Currency,  PartyID,  TurnOver, MemberWinloss, LicenseeWL, Betcount)
		SELECT  b.rptDate, b.currencyID, lr.PartyID,
		 SUM(Turnover * 
				CASE   
					WHEN @drawfilter IN (2, 3) THEN  
					CASE   
						WHEN b.status = 111 THEN 0  
						WHEN (b.status = 114 OR b.status = 115) THEN 0.5  
					ELSE 1   
					END  
				ELSE 1   
				END  			
		 ) AS TurnOver, 
		 SUM(b.Winloss) AS MemberWinloss, SUM(CASE WHEN lr.isDeposit = 1 THEN winlossA ELSE 0 END) AS LicenseeWL, 
		 SUM(BetCount * CASE   
						WHEN @drawfilter = 2 THEN  
							CASE   
							WHEN b.status = 111 THEN 0  
							ELSE 1   
							END  
						ELSE 1   
						END  ) AS BetCount
		FROM bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK) 
			INNER JOIN #tmpParty lr ON b.SiteID = lr.LicenseeID 			
		WHERE b.rptDate BETWEEN lr.FromDate AND lr.ToDate
			AND b.status NOT IN (-1,103)
			AND (@excludeTest = 0 OR (@excludeTest = 1 AND CurrencyID <> 20))
			AND bettype BETWEEN 81 AND 120			
			AND b.customercategory NOT IN (27,28)
		GROUP BY b.rptDate, b.CurrencyID, lr.PartyID
	END	

	CREATE NONCLUSTERED INDEX IDX_Currency ON #Data(Currency,winlostdate)
	
	SELECT DISTINCT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate 
	INTO #Exchange	
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName) 
	WHERE exchangeid IN (SELECT DISTINCT Currency FROM #Data)
	
	IF @IsConvert = 0
	BEGIN
		UPDATE #Exchange
		SET Rate = 1
	END

	BEGIN
		INSERT INTO #Result(PartyID, TurnOver, MemberWinloss, GrossWinloss,  
							Betcount,  OneworksRevenue, winlostdate,Currency)
		SELECT	
			d.PartyID,
			CAST(isnull(SUM(d.TurnOver ),0) AS MONEY) AS TurnOver,			
			CAST(isnull(SUM(d.MemberWinloss ),0) AS MONEY) AS MemberWinloss,			
			CAST(-1 * isnull(SUM(d.MemberWinloss ),0) AS money) AS GrossWinloss,			
			ISNULL(SUM(d.betcount), 0) AS BetCount,
			CAST(-1 * isnull(SUM(d.MemberWinloss  * isnull(tp.Rate,0)),0) AS MONEY) AS OneworksRevenue
			,winlostdate,d.Currency
		FROM #Data d						
			LEFT JOIN (SELECT DISTINCT PartyID,Rate,Fromdate,Todate FROM #tmpParty) tp ON d.PartyID = tp.PartyID
	     WHERE d.winlostdate BETWEEN tp.Fromdate AND tp.Todate
		GROUP BY
			 d.PartyID, d.Currency,winlostdate
	END
	
		
	SELECT	
		CASE	WHEN p.PartyName = 'IBC' THEN 'FDL'
		     WHEN p.PartyName = '18bb' THEN 'PIH'
		     ELSE p.PartyName 
		END AS PartyName,
		CONVERT(VARCHAR(6),winlostdate,112)   AS Winlostdate,
		SUM(re.betcount) AS BetCount,

		SUM(re.turnover * e.Rate) AS Turnover,
		SUM(re.MemberWinloss * e.Rate) AS MemberWinloss,
		CASE WHEN SUM(re.GrossWinloss * e.Rate) <= 0
			 THEN 0 
			 ELSE SUM(re.GrossWinloss * e.Rate)
		 END AS LicenseeWinloss,
		CASE WHEN SUM(re.OneworksRevenue * e.Rate) <= 0
			 THEN 0
			ELSE SUM(re.OneworksRevenue * e.Rate)
		END AS OneworksRevenue
	FROM #Result re
		INNER JOIN #Exchange e ON re.currency = e.ExchangeId AND re.winlostdate = e.ExchangeDate
		LEFT JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON re.PartyID = p.PartyID		
	GROUP BY
		CONVERT(VARCHAR(6),winlostdate,112),CASE WHEN p.PartyName = 'IBC' THEN 'FDL'
		     WHEN p.PartyName = '18bb' THEN 'PIH'
		     ELSE p.PartyName 
		END
     ORDER BY CONVERT(VARCHAR(6), winlostdate, 112) ASC
	
	DROP TABLE	#Data
	DROP TABLE	#Exchange
	DROP TABLE	#Result
	DROP TABLE	#tmpParty
END    

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_NumberGameWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_NumberGameWinloss] TO bodbAdminNet 
