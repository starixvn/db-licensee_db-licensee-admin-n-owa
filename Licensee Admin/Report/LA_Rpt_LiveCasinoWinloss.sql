USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LiveCasinoWinloss_xtest]    Script Date: 01/12/2014 14:35:39 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[LA_Rpt_LiveCasinoWinloss]
	 @Partyids				VARCHAR(5500)
	, @GameType				INT				= 0
	, @Currency				INT				= 0
	, @drawfilter			SMALLINT		= 0
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME
	, @excludeTest			BIT				= 0
	, @IsConvert			BIT				= 1
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'
AS      
  
/*  
 * Created by : 201410919@Florent 
 * Task  : Get Live Casino Winloss 
 * DB   : DB052.bodb02  
 * Base on : OA_Rpt_LiveCasinoWinloss
 * Revisions :  
    - 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
	- 20150703@Florent: add GBP
	- 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
 * Param's Explanation:    
 
 *  
 */  
    
BEGIN
	SET NOCOUNT ON

	CREATE TABLE #Data (winlostdate  DATETIME, Currency  INT,  PartyID int, TurnOver MONEY, MemberWinloss MONEY, Betcount INT)
	
	--Output table 
	CREATE TABLE #Result (PartyID int, TurnOver MONEY, MemberWinloss MONEY, Betcount INT, GrossWinloss MONEY, OneworksRevenue MONEY, Currency INT, winlostdate datetime)
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
    FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs,@FromDate,@ToDate,'LC','OA',@ExcludeTest)

	
	--For Deposit Licensees
	BEGIN
		INSERT INTO #Data (winlostdate, Currency,  PartyID, TurnOver, MemberWinloss, Betcount)
		SELECT  b.rptDate, b.currencyID, tp.PartyID,
		 SUM(Turnover * 
				CASE   
					WHEN @drawfilter IN (2,3) THEN  
					CASE   
						WHEN b.status = 111 THEN 0  
						WHEN (b.status = 114 OR b.status = 115) THEN 0.5  
					ELSE 1   
					END  
				ELSE 1   
				END  			
		 ) AS TurnOver
		, SUM(b.Winloss) AS MemberWinloss, 
		SUM(BetCount * CASE   
						WHEN @drawfilter = 2 THEN  
							CASE   
							WHEN b.status = 111 THEN 0  
							ELSE 1   
							END  
						ELSE 1   
						END  ) AS BetCount
		FROM bodb_licenseereport.dbo.rpt_Betting b (NOLOCK) 
			INNER JOIN #tmpParty tp ON b.SiteID = tp.LicenseeID 			
		WHERE b.rptDate BETWEEN tp.FromDate AND tp.ToDate
			AND b.status NOT IN (-1, 101, 102, 103)
			AND (@excludeTest = 0 OR (@excludeTest = 1 AND CurrencyID<>20))
			AND ((bettype BETWEEN 1101 AND 1199 AND @GameType = 0) OR (bettype = @GameType))			
			AND (@Currency = 0 OR  b.CurrencyID = @Currency)
			AND b.customercategory NOT IN (27,28) 
		GROUP BY b.rptDate, b.CurrencyID, tp.PartyID
	END	

	CREATE NONCLUSTERED INDEX IDX_Currency ON #Data(Currency,winlostdate)
		
	--get specified exchange value in time range		
	SELECT DISTINCT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate 
	INTO #Exchange	
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName) 
	WHERE exchangeid IN (SELECT DISTINCT Currency FROM #Data)
	
	IF @IsConvert = 0
	BEGIN
		UPDATE #Exchange
		SET Rate = 1
	END
	
	BEGIN --time when Star Express has been terminated	
		INSERT INTO #Result(PartyID, TurnOver, MemberWinloss, GrossWinloss, 
							Betcount, OneworksRevenue, Currency,winlostdate)
		SELECT	
			d.PartyID,
			CAST(isnull(SUM(d.TurnOver ),0) AS MONEY) AS TurnOver,			
			CAST(isnull(SUM(d.MemberWinloss ),0) AS MONEY) AS MemberWinloss,			
			CAST( -1 * isnull(SUM(d.MemberWinloss ),0)AS money) AS GrossWinloss,			
			ISNULL(SUM(d.betcount), 0) AS BetCount,						
			CAST( isnull(SUM(-1 * d.MemberWinloss  * isnull(tp.Rate, 0)),0)  AS money) AS OneworksRevenue,
			Currency,winlostdate
		FROM #Data d			
			LEFT JOIN (SELECT DISTINCT PartyID,Rate,Fromdate,Todate FROM #tmpParty) tp ON d.PartyID = tp.PartyID
	     WHERE d.winlostdate BETWEEN tp.Fromdate AND tp.Todate
		GROUP BY
			d.PartyID, Currency,winlostdate
	END

	--return the result for deposit Lics
	SELECT 
		CONVERT(VARCHAR(6),winlostdate,112)   AS Winlostdate,
		CASE	WHEN p.PartyName = 'IBC' THEN 'FDL'
		     WHEN p.PartyName = '18bb' THEN 'PIH'
		     ELSE p.PartyName 
		END AS PartyName,				
		SUM(re.betcount) AS BetCount,
		--EUR
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
		INNER JOIN #Exchange e ON re.Currency = e.ExchangeId AND re.winlostdate = e.ExchangeDate
		LEFT JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK ) ON re.PartyID = p.PartyID		
	GROUP BY
		p.PartyName,CONVERT(VARCHAR(6),winlostdate,112),CASE	WHEN p.PartyName = 'IBC' THEN 'FDL'
		     WHEN p.PartyName = '18bb' THEN 'PIH'
		     ELSE p.PartyName 
		END 
     ORDER BY CONVERT(VARCHAR(6),winlostdate,112) ASC

	
	DROP TABLE	#Data
	DROP TABLE	#Result
	DROP TABLE	#Exchange	
	DROP TABLE	#tmpParty
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LiveCasinoWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LiveCasinoWinloss] TO bodbAdminNet 