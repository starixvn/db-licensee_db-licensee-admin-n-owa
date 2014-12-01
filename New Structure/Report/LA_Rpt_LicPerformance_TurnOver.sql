USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LicPerformance_TurnOver]    Script Date: 01/12/2014 14:39:52 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_Rpt_LicPerformance_TurnOver    Script Date: 3/4/2014 4:17:39 PM ******/
ALTER PROCEDURE [dbo].[LA_Rpt_LicPerformance_TurnOver] 
	 @PartyIDs	    VARCHAR(1000)	= ''
	,@Currency	    INT			= 0
	,@FromDate	    SMALLDATETIME
	,@ToDate		    SMALLDATETIME
	,@ProductCode	    VARCHAR(500)
	,@IsConvert	    BIT			= 0
	,@BaseCurrency	    INT			= 0
	,@drawfilter	    SMALLINT		= 1
	,@excludeTest	    BIT			= 0
AS
 
/*  Created by: 20140930@Florent
    Task : LicenseeAdmin - Get Licensee Perfomance TurnOver Report for each Licensee in one month
    Original: OA_Rpt_LicPerformance_TurnOver
    DB: DB052.bodb02  
   
    Revisions:  
    
    Param's Explanation:  
	   + @partyIDs : a string of list PartyID, separated by ','
	   + @Currency : 0-All Currencies
	   + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	   + @excludeTest: remove currency UUS
	   + @ProductCode : string,
		
	   + @MoveBetsDay: The day we move tickets to bettrans14
	   + @IsConvert: =1 : convert figure to 
					   =0 : no convert 
					   (datatype:bit)
	   + @BaseCurrency -6 : convert to EUR
					   -2: convert to MYR
					   -3: convert to USD
		
*/  

/*
EXEC OA_Rpt_LicPerformance_TurnOver 
	 @Licensee = '1,3,4,5,6,7,8,9,10,11,12,13,14,15,16'
	,@Currency = 0
	,@FromDate = '2014-01-12'
	,@ToDate = '2014-10-28'
	,@ProductCode = 'SB'
	,@IsConvert = 1
	,@BaseCurrency = - 6
	,@drawfilter = 1
	,@excludeTest = 0
 
EXEC LA_Rpt_LicPerformance_TurnOver 
      @PartyIDs = '14,16,17,18,19,20,21,22,23,24,25,26,27'
	,@Currency = 0
	,@FromDate = '2014-01-12'
	,@ToDate = '2014-10-28'
	,@ProductCode = 'SB'
	,@IsConvert = 1
	,@BaseCurrency = - 6
	,@drawfilter = 1
	,@excludeTest = 0

*/
BEGIN  
	SET NOCOUNT ON  

	CREATE TABLE #Bettype (Bettype INT, ProductID INT)
     CREATE TABLE #tmpParty (
		  PartyID		   INT
		  ,LicenseeID	   INT
		  ,isDeposit	   INT		  
		  ,ProductID	   INT 		  		  
		  )

     INSERT INTO #Bettype
     SELECT Bettype, ProductID FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, @ProductCode)

     INSERT INTO #tmpParty
     SELECT DISTINCT PartyID,LicenseeID,isDeposit,ProductID
     FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA')


	CREATE TABLE #rptTurnOver (  
		PartyName 		VARCHAR(20),
		rptDate		VARCHAR(50),	
		TurnOver		MONEY)
	
	CREATE TABLE #Temp (  
		PartyID	 	INT,	
		rptDate 		DATETIME,
		CurrencyID 	INT, 
		TurnOver		MONEY)	
	
	CREATE TABLE #Exchange (
		   ExchangeDate   DATE
		   ,ExchangeId	   INT
		   ,Rate		   FLOAT
		   ,PRIMARY KEY (ExchangeDate,ExchangeId))

	CREATE TABLE #MY(sDate DATETIME)

	DECLARE  @cols AS NVARCHAR(MAX)
		   ,@query AS NVARCHAR(MAX)
		   ,@sdate AS DATETIME

				
	SELECT @cols = NULL,@query = NULL,@sdate = @FromDate
	
	WHILE (MONTH(@sdate) <= MONTH(@ToDate) OR YEAR(@sdate) < YEAR(@ToDate))	
	BEGIN 
		INSERT INTO #MY(sDate)
		SELECT @sdate
		SET @sdate = DATEADD(m, 1, @sdate)
	END
		
	IF @ProductCode = 'BA'
	BEGIN
		INSERT INTO #Temp  (PartyID , rptDate, CurrencyID, TurnOver)
		SELECT 
			tp.PartyID
			,rptDate
			,b.currencyID
			,SUM(b.turnover
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
						 WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				) TurnOver
		FROM 
			bodb_Licensee.dbo.rpt_Betting_BA b WITH ( NOLOCK ) 
			INNER JOIN #tmpParty tp ON tp.LicenseeID = b.SiteID
		WHERE  
			b.rptDate BETWEEN @FromDate AND @ToDate 
			AND b.status NOT IN (-1, 103)
			AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))  
			AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20)) 
		GROUP BY tp.PartyID, rptDate, status, currencyID
		ORDER BY tp.PartyID, b.rptDate

	END
		
		--exclude BA tickets
	IF  @ProductCode IN ('SB', 'RB', 'NG', 'LC', 'VS', 'CS')
	BEGIN
		INSERT INTO #Temp(PartyID, rptDate, CurrencyID, TurnOver)
		SELECT 
			tp.PartyID
			,b.rptDate
			,b.currencyID
			,SUM(b.turnover
				*
				CASE WHEN b.bettype = 33 AND b.status IN (114, 115) THEN 0.5 ELSE 1 END
				*
				CASE WHEN @drawfilter IN (2, 3) THEN
					CASE WHEN b.status = 111  THEN 0	
						 WHEN b.status IN (114, 115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				) TurnOver
		FROM 
			bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK) 
			INNER JOIN #tmpParty tp ON tp.LicenseeID = b.SiteID
			INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
			LEFT JOIN dbo.League l (NOLOCK) ON b.leagueid = l.leagueid
		WHERE  
			b.rptDate  BETWEEN @FromDate AND @ToDate 
			AND b.status NOT IN (-1,103)			
			AND (@Currency = 0 OR (@Currency<>0 AND b.CurrencyID = @Currency))  
			AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20)) 
		GROUP BY tp.PartyID, b.rptDate, b.currencyID
		ORDER BY tp.PartyID ASC

	END	

	INSERT INTO #Exchange (ExchangeDate, ExchangeId, Rate )
	SELECT ExchangeDate
		  ,ExchangeId
		  ,CASE @BaseCurrency WHEN -2 THEN MYR
						  WHEN -3 THEN USD
						  WHEN -6 THEN EUR
						  ELSE 1 END AS Rate
	FROM Lrf_f_GetExchangeDaily (@fromdate, @todate)
	--WHERE exchangeid IN (
	--				   SELECT DISTINCT currencyID 
	--				   FROM #Temp
	--				   )
							
	IF (@isconvert = 0)
		BEGIN
			UPDATE #Exchange
			SET Rate=1
		END

	INSERT INTO #rptTurnOver(PartyName,rptDate,TurnOver)
	--create table rptTurnOver (Licensee VARCHAR(20),rptDate VARCHAR(20),TurnOVer MONEY)
	SELECT 
		p.PartyName					   
	    ,dbo.fnFormatDate(t.rptDate)		   AS rptDate
	    ,SUM(ISNULL(t.TurnOver, 0) * ee.Rate)  AS TurnOver
	FROM #Temp t
		INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON t.PartyID = p.PartyID
		INNER JOIN #Exchange ee ON t.rptDate = ee.ExchangeDate AND t.CurrencyID = ee.ExchangeId
	GROUP BY 
		p.PartyName, dbo.fnFormatDate(t.rptDate)
	
	
	UPDATE #rptTurnOver
	SET TurnOver = 0
	WHERE (ISNULL(TurnOver, 0) = 0 OR TurnOver < 0)
	--------------------------------- view result  -------------------------------------------
	SELECT @cols = STUFF((SELECT ',' + QUOTENAME(seq )
                    FROM 
                    (
                      select dbo.fnFormatDate(sdate) seq
                      from #MY
                    )d
					FOR XML PATH(''), TYPE
					).value('.', 'NVARCHAR(MAX)') 
				,1,1,'')
	SET @query='SELECT PartyName AS PartyName,' + @cols + ' 
            FROM
            (
              SELECT s.PartyName, s.TurnOver, seq
              FROM
              (
                SELECT PartyName, isnull(TurnOver, 0) TurnOver
                  , rptDate seq
                FROM #rptTurnOver
              ) s
              
            ) x
            PIVOT 
            (
                MAX(TurnOver)
                FOR seq IN (' + CONVERT(VARCHAR(1000), @cols) + ')
            ) p '
			print (@query)
	EXECUTE sp_executesql @query;
				
	DROP TABLE #rptTurnOver
	DROP TABLE #Exchange
	DROP TABLE #Temp
	DROP TABLE #tmpParty
	DROP TABLE #Bettype
	DROP TABLE #MY
END

GO
GRANT EXECUTE ON [dbo].[LA_Rpt_LicPerformance_TurnOver] TO [bodbAdminNet]
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicPerformance_TurnOver] TO [vnteam]