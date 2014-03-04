USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER  PROCEDURE [dbo].[OA_Rpt_LicPerformance_TurnOver]  
	@Licensee VARCHAR(1000)='',
	@Currency INT = 0,
	@FromDate SMALLDATETIME,
	@ToDate SMALLDATETIME,
	@ProductCode VARCHAR(500),
	@IsConvert BIT=0,
	@BaseCurrency INT=0,
	@MoveBetsDay SMALLDATETIME='',
	@drawfilter SMALLINT = 1 ,
	@excludeTest BIT = 0
AS  
/*  Created by: 20140225@Jim
	Task : LicenseeAdmin - Get Licensee Perfomance TurnOver Report for each Licensee in one month
    DB: DB052.bodb02  
   
    Revisions:  
    
	Param's Explanation:  
	  + @Licensee : a string of list LicenseeID, separated by ','
	  + @Currency : 0-All Currencies
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS
	  +@ProductCode : string,
		
	  + @MoveBetsDay: The day we move tickets to bettrans14
	  + @IsConvert: =1 : convert figure to 
					=0 : no convert 
					(datatype:bit)
	  +@BaseCurrency -6 : convert to EUR
					 -2: convert to MYR
					 -3: convert to USD
		
*/  

/*
exec  OA_Rpt_LicPerformance_TurnOver
	@Licensee='1,3,4,5,6,7,8,9,10,11,12,13,14,15,16',
	@Currency = 0,
	@FromDate ='2010-01-12',
	@ToDate ='2014-02-28',
	@ProductCode ='SB',
	@IsConvert =1,
	@BaseCurrency =-6,
	@drawfilter  = 1 ,
	@excludeTest = 0
*/
BEGIN  
	SET NOCOUNT ON  

	CREATE TABLE #rptTurnOver (  
		Licensee 		VARCHAR(20),
		rptDate			VARCHAR(50),	
		TurnOver		MONEY	
		
	)

	CREATE TABLE #Temp (  
		LicenseeID 		INT,	
		rptDate 		DATETIME,
		CurrencyID 		INT, 
		TurnOver		MONEY
	)
	CREATE  TABLE #tmpLicensee(
			LicenseeID INT
	)  
	
	CREATE TABLE #Exchange (
		ExchangeDate DATE,
		ExchangeId INT,
		Rate FLOAT,
		PRIMARY KEY(ExchangeDate,ExchangeId)
	)	
	CREATE TABLE #MY(
		sDate DATETIME
		)

	DECLARE @cols AS NVARCHAR(MAX),
			@query  AS NVARCHAR(MAX),
			@sdate  AS DATETIME 	
				
	SELECT @cols=NULL,@query=NULL,@sdate=@FromDate

	INSERT INTO #tmpLicensee (LicenseeID)   
	SELECT l.LicenseeID
	FROM bodb_Licensee.dbo.Licensees l (NOLOCK)
	WHERE l.LicenseeID IN (SELECT VAL FROM strSplit(@Licensee,','))  
	
	WHILE (@sdate<=@ToDate )	
	BEGIN 
		INSERT INTO #MY(sDate)
		SELECT @sdate
		SET @sdate=DATEADD(m,1,@sdate)
	END
		
	IF @ProductCode='BA'
	BEGIN
		INSERT INTO #Temp  (LicenseeID ,rptDate,CurrencyID,TurnOver)
		SELECT 
			b.siteID,
			rptDate,  
			b.currencyID,
			SUM(b.turnover
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
						 WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				) TurnOver
		FROM 
			bodb_Licensee.dbo.rpt_Betting_BA b WITH ( NOLOCK ) 
			INNER JOIN #tmpLicensee ag ON ag.LicenseeID=b.SiteID
		WHERE  
			b.rptDate  BETWEEN @FromDate AND @ToDate 
			AND b.status NOT IN (-1,103)
			AND (@Currency=0 OR (@Currency<>0 AND b.CurrencyID=@Currency))  
			AND (@excludeTest=0 OR (@excludeTest=1 AND b.CurrencyID<>20)) 
		GROUP BY b.siteID,rptDate , status, currencyID
		ORDER BY b.siteID,
		b.rptDate

	END
		
		--exclude BA tickets
	IF  @ProductCode IN ('SB','RB','NG','LC','VS','CS')
	BEGIN
		INSERT INTO #Temp  (LicenseeID ,rptDate,CurrencyID,TurnOver)
		SELECT 
			b.siteID,
			b.rptDate,  
			b.currencyID,
			SUM(b.turnover
				*
				CASE WHEN b.bettype=33 AND b.status IN (114,115) THEN 0.5 ELSE 1 END
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
						 WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				) TurnOver
		FROM 
			bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK ) 
			INNER JOIN #tmpLicensee ag ON ag.LicenseeID=b.SiteID
			LEFT JOIN dbo.League l (NOLOCK) ON b.leagueid=l.leagueid
		WHERE  
			b.rptDate  BETWEEN @FromDate AND @ToDate 
			AND b.status NOT IN (-1,103)
			AND ( (@ProductCode='SB' AND (b.bettype <31 OR b.bettype BETWEEN 121 AND 999))
				OR(@ProductCode='RB' AND b.bettype BETWEEN 31 AND 33)
				OR(@ProductCode='NG' AND b.bettype BETWEEN 81 AND 120)
				OR(@ProductCode='LC' AND b.bettype BETWEEN 1101 AND 1199)
				OR(@ProductCode='VS' AND b.bettype BETWEEN 1201 AND 1299)
				OR(@ProductCode='CS' AND b.bettype =71)
				)	
			AND (@Currency=0 OR (@Currency<>0 AND b.CurrencyID=@Currency))  
			AND (@excludeTest=0 OR (@excludeTest=1 AND b.CurrencyID<>20)) 
		GROUP BY b.siteID, b.rptDate,b.currencyID
		ORDER BY 
			b.rptDate ASC

	END	

	INSERT INTO #Exchange (ExchangeDate,ExchangeId , Rate )
	SELECT exchangedate
			,exchangeid
			,CASE @BaseCurrency WHEN -2 THEN MYR
								WHEN -3 THEN USD
								WHEN -6 THEN EUR
								ELSE 1 END AS Rate
	FROM Lrf_f_GetExchangeDaily (@fromdate,@todate)
	WHERE exchangeid IN (
						SELECT DISTINCT currencyID 
						FROM #Temp
						)
							
	IF (@isconvert=0)
		BEGIN
			UPDATE #Exchange
			SET Rate=1
		END
	
	INSERT INTO #rptTurnOver(Licensee,rptDate,TurnOver)
	--create table rptTurnOver (Licensee VARCHAR(20),rptDate VARCHAR(20),TurnOVer MONEY)
	SELECT 
		l.LicenseeName,
		dbo.fnFormatDate(t.rptdate) rptDate,
		SUM(ISNULL(t.TurnOver,0)*ee.Rate) TurnOver
		
	FROM #Temp t
		INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON t.LicenseeId=l.LicenseeId
		INNER JOIN #Exchange  ee ON t.rptDate=ee.exchangedate AND t.CurrencyID=ee.ExchangeId
	GROUP BY 
		l.LicenseeName,
		dbo.fnFormatDate(t.rptdate)
	
	
	UPDATE 	#rptTurnOver
	SET TurnOver=0
	WHERE (ISNULL(TurnOver,0)=0 OR TurnOver<0)
	--------------------------------- view result  -------------------------------------------
	SELECT @cols= STUFF((SELECT ',' + QUOTENAME(seq )
                    FROM 
                    (
                      select dbo.fnFormatDate(sdate) seq
                      from #MY
                    )d
					FOR XML PATH(''), TYPE
					).value('.', 'NVARCHAR(MAX)') 
				,1,1,'')
	SET @query='select Licensee,' + @cols + ' 
            from
            (
              select s.Licensee, s.TurnOver,seq
              from
              (
                select Licensee,isnull(TurnOver,0) TurnOver
                  , rptdate seq
                from #rptTurnOver
              ) s
              
            ) x
            pivot 
            (
                max(TurnOver)
                for seq in (' + CONVERT(VARCHAR(1000),@cols) + ')
            ) p '
			--print (@query)
	EXECUTE sp_executesql @query;
				
	DROP TABLE #rptTurnOver
	DROP TABLE #Exchange
	DROP TABLE #Temp
	DROP TABLE #tmpLicensee
	DROP TABLE #MY

END

GO
GRANT EXECUTE ON [dbo].[OA_Rpt_LicPerformance_TurnOver] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_Rpt_LicPerformance_TurnOver] TO [vnteam]
