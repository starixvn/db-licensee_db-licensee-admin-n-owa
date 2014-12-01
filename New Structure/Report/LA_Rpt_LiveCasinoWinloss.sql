USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LiveCasinoWinloss_xtest]    Script Date: 01/12/2014 14:35:39 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[LA_Rpt_LiveCasinoWinloss]
	 @Partyids	VARCHAR(5500)
	,@GameType	INT			 = 0
	,@Currency	INT			 = 0
	,@drawfilter	SMALLINT		 = 0
	,@FromDate	SMALLDATETIME
	,@ToDate		SMALLDATETIME
	,@excludeTest	BIT			 = 0

	
AS      
  
/*  
 * Created by : 201410919@Florent 
 * Task  : Get Live Casino Winloss 
 * DB   : DB052.bodb02  
 * Base on : OA_Rpt_LiveCasinoWinloss
 * Revisions :  
    - 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
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
    SELECT PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, OW_Rate, Fromdate, Todate
    FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs,@FromDate,@ToDate,'LC','OA')
	  -- filter with exclude test data before launch date
	IF (EXISTS (
			SELECT TOP 1 1
			FROM #tmpParty
			WHERE AffectedDate > Fromdate
			) AND @excludeTest =1 )
	BEGIN
		UPDATE #tmpParty
		SET Fromdate = AffectedDate
		WHERE AffectedDate > Fromdate
	END
	
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
		FROM bodb_Licensee.dbo.rpt_Betting b (NOLOCK) 
			INNER JOIN #tmpParty tp ON b.SiteID = tp.LicenseeID 			
		WHERE b.rptDate BETWEEN tp.FromDate AND tp.ToDate
			AND b.status NOT IN (-1,103)
			AND (@excludeTest = 0 OR (@excludeTest = 1 AND CurrencyID<>20))
			AND ((bettype BETWEEN 1101 AND 1199 AND @GameType = 0) OR (bettype = @GameType))			
			AND (@Currency = 0 OR  b.CurrencyID = @Currency)
			AND b.customercategory NOT IN (27,28) 
		GROUP BY b.rptDate, b.CurrencyID, tp.PartyID
	END	

	--For Credit Licensees
	/*
	IF EXISTS(SELECT 1 FROM #tmpParty tlr
							INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd1 (NOLOCK)
							ON tlr.PartyID = pd1.PartyID
							WHERE pd1.IsDeposit = 0)
	BEGIN
		INSERT INTO #Data (winlostdate, Currency,  PartyID, TurnOver, MemberWinloss, Betcount)
		SELECT  b.rptDate, b.currencyID, tp.PartyID, 
		SUM(Turnover* CASE   
					WHEN @drawfilter IN (1, 2) THEN  
					CASE   
						WHEN b.status = 111 THEN 0  
						WHEN (b.status = 114 OR b.status = 115) THEN 0.5  
					ELSE 1   
					END  
				ELSE 1   
				END) AS TurnOver
		, SUM(b.Winloss) AS MemberWinloss, 
		SUM(BetCount* CASE   
								WHEN @drawfilter = 1 THEN  
									CASE   
									WHEN b.status = 111 THEN 0  
									ELSE 1   
									END  
								ELSE 1   
								END) AS BetCount
		 FROM  bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) 
			  INNER JOIN bodb_Licensee.dbo.labels lb (NOLOCK) ON b.SiteID = lb.LabelID 
			  INNER JOIN #tmpParty tp ON lb.LicenseeID = tp.LicenseeID
			  INNER JOIN bodb_Licensee.dbo.OAS_PartyDetail pd (NOLOCK) ON tp.PartyID = pd.PartyID 
	   /* FROM #tmpParty tp 
			INNER JOIN bodb_Licensee.dbo.OAS_PartyDetail pd (NOLOCK) ON tp.PartyID = pd.PartyID 
			INNER JOIN bodb_Licensee.dbo.labels lb (NOLOCK) ON tp.LicenseeID = lb.LicenseeID 
			INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID = lb.LabelID
	   */
		WHERE pd.IsDeposit = 0 
	 		AND b.rptDate BETWEEN tp.FromDate AND tp.ToDate
			AND b.status NOT IN (-1,103)
			AND (@excludeTest = 0 OR (@excludeTest = 1 AND CurrencyID<>20))
			AND ((bettype BETWEEN 1101 AND 1199 AND @GameType=0) OR (bettype=@GameType))
			AND b.customercategory NOT IN (27,28)		
			AND (@Currency=0 OR  b.CurrencyID =@Currency)
		GROUP BY b.rptDate, b.CurrencyID, tp.PartyID		
	END
	*/

	CREATE NONCLUSTERED INDEX IDX_Currency ON #Data(Currency,winlostdate)
		
	--get specified exchange value in time range		
	SELECT *
	INTO #Exchange	
	FROM Lrf_f_GetExchangeDaily(@FromDate,@ToDate) -- get exchange rate in last day of month
	WHERE exchangeid IN (SELECT DISTINCT Currency FROM #Data)
			
	--check whether Star Express is terminated in the time range
	DECLARE @PartyTerminated BIT
	SET @PartyTerminated = 0
	IF EXISTS (SELECT TOP 1 1 FROM bodb_licensee.dbo.LicenseeEventLog (NOLOCK) 
						  WHERE SystemID = 4 AND ActionID = 3 AND ObjectID = 5 
							AND (@FromDate >= FromDate AND (ToDate IS NULL OR @ToDate <= ToDate)))
	SET @PartyTerminated = 1
		
	--For Normal Licensees
	IF @PartyTerminated = 0 --time when Star Express has not been terminated
	BEGIN
		INSERT INTO #Result( PartyID, TurnOver, MemberWinloss, GrossWinloss, Betcount, OneworksRevenue, Currency,winlostdate)
		SELECT	
			d.PartyID,
			CAST(isnull(SUM(d.TurnOver),0) AS MONEY) AS TurnOver,			
			CAST(isnull(SUM(d.MemberWinloss),0) AS MONEY) AS MemberWinloss,			
			CAST(-1 * isnull(SUM(d.MemberWinloss ),0) AS money) AS GrossWinloss,			
			ISNULL(SUM(d.betcount), 0) AS BetCount,
			CAST(isnull(SUM(-1 * d.MemberWinloss  * isnull(tp.Rate,0)),0)  AS MONEY) AS OneworksRevenue	
			,Currency,winlostdate
		FROM #Data d
			LEFT JOIN #tmpParty tp ON d.PartyID = tp.PartyID
		GROUP BY
			d.PartyID, Currency,winlostdate
	END
	ELSE
	BEGIN --time when Star Express has been terminated	
		INSERT INTO #Result(PartyID, TurnOver, MemberWinloss, GrossWinloss, 
							Betcount, OneworksRevenue, Currency,winlostdate)
		SELECT	
			d.PartyID,
			CAST(isnull(SUM(d.TurnOver ),0) AS MONEY) AS TurnOver,			
			CAST(isnull(SUM(d.MemberWinloss ),0) AS MONEY) AS MemberWinloss,			
			CAST( -1 * isnull(SUM(d.MemberWinloss ),0)AS money) AS GrossWinloss,			
			ISNULL(SUM(d.betcount), 0) AS BetCount,						
			CAST( isnull(SUM(-1 * d.MemberWinloss  * isnull(tp.Rate,0)),0)  AS money) AS OneworksRevenue,
			Currency,winlostdate
		FROM #Data d			
			LEFT JOIN #tmpParty tp ON d.PartyID = tp.PartyID
		GROUP BY
			d.PartyID, Currency,winlostdate
	END
	
	--return the result for deposit Lics
	SELECT 
		CONVERT(VARCHAR(6),winlostdate,112)   AS Winlostdate,
		CASE	WHEN p.PartyName='IBC' THEN 'FDL'
		     WHEN p.PartyName='18bb' THEN 'PIH'
		     ELSE p.PartyName 
		END AS PartyName,				
		SUM(re.betcount) AS BetCount,
		--EUR
		SUM(re.turnover * e.EUR) AS Turnover,
		SUM(re.MemberWinloss * e.EUR) AS MemberWinloss,
		SUM(re.GrossWinloss * e.EUR) AS LicenseeWinloss,		
		SUM(re.OneworksRevenue * e.EUR) AS OneworksRevenue
	FROM #Result re
		INNER JOIN #Exchange e ON re.currency = e.ExchangeId AND re.winlostdate=e.ExchangeDate
		LEFT JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK ) ON re.PartyID = p.PartyID		
	GROUP BY
		p.PartyName,CONVERT(VARCHAR(6),winlostdate,112),CASE	WHEN p.PartyName='IBC' THEN 'FDL'
		     WHEN p.PartyName='18bb' THEN 'PIH'
		     ELSE p.PartyName 
		END 
     ORDER BY CONVERT(VARCHAR(6),winlostdate,112) ASC

	
	DROP TABLE	#Data
	DROP TABLE	#Result
	DROP TABLE	#Exchange	
END    
    
    

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LiveCasinoWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LiveCasinoWinloss] TO bodbAdminNet 