USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER  PROCEDURE [dbo].[OA_Rpt_LicPerformance_LicensingMargin]  
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
/*  Created by: 20140522@Jim
	Task : LicenseeAdmin - Get Licensee Perfomance TurnOver Report for each Licensee in one month
    DB: DB052.bodb02  
   
    Revisions:  
    
	Param's Explanation:  
	  + @Licensee : a string of list LicenseeID, separated by ','
	  + @Currency : 0-All Currencies
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS
	  + @ProductCode : string,
	  + @MoveBetsDay: The day we move tickets to bettrans14
	 
*/  

/*
exec  OA_Rpt_LicPerformance_LicensingMargin
		@Licensee='1,3,4,5,6,7,8,9,10,11,12,13,14,15,16',
		@Currency = 0,
		@FromDate ='2013-04-01',
		@ToDate ='2014-04-30',
		@ProductCode ='SB',
		@drawfilter  = 1 ,
		@excludeTest = 0
*/
BEGIN  
	SET NOCOUNT ON  

	CREATE TABLE #rptLicMargin (  
		Licensee 		VARCHAR(20),
		rptDate			VARCHAR(50),	
		Margin			MONEY	
		
	)

	CREATE TABLE #Temp (  
		LicenseeID 		INT,	
		rptDate 		DATETIME,
		CurrencyID 		INT, 
		Winloss		  	MONEY,
		TurnOver		MONEY
	)
	CREATE  TABLE #tmpLicensee(
			LicenseeID INT
	)  
		
	CREATE TABLE #MY(
		sDate DATETIME
		)
	DECLARE @cols AS NVARCHAR(MAX),
			@query  AS NVARCHAR(MAX),
			@sdate  AS DATETIME 
	SELECT  @cols=NULL,
		    @query=NULL,
		    @sdate=@FromDate
	
	INSERT INTO #tmpLicensee (LicenseeID)   
	SELECT l.LicenseeID
	FROM bodb_Licensee.dbo.Licensees l (NOLOCK)
	WHERE l.LicenseeID IN (SELECT VAL FROM strSplit(@Licensee,','))  
	
	WHILE (month(@sdate)<=month(@ToDate) OR year(@sdate)<year(@ToDate))	
	BEGIN 
		INSERT INTO #MY(sDate)
		SELECT @sdate
		SET @sdate=DATEADD(m,1,@sdate)
	END
	IF @ProductCode='BA'
	BEGIN 
		INSERT INTO #Temp  (LicenseeID ,rptDate,CurrencyID,winloss,TurnOver)
		SELECT 
			b.siteID,
			b.rptDate,  
			b.currencyID,
			SUM(b.winloss) winloss,
			 SUM(b.turnover
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
					     WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				)TurnOver
		FROM 
			bodb_Licensee.dbo.rpt_Betting_BA b WITH ( NOLOCK ) 
			INNER JOIN #tmpLicensee ag ON ag.LicenseeID=b.SiteID
		WHERE  
			b.rptDate  BETWEEN @FromDate AND @ToDate 
			AND b.status NOT IN (-1,103)
			AND (@Currency=0 OR (@Currency<>0 AND b.CurrencyID=@Currency))  
			AND (@excludeTest=0 OR (@excludeTest=1 AND b.CurrencyID<>20)) 
		GROUP BY b.siteID, b.rptDate,b.currencyID
		ORDER BY b.siteID,
			     b.rptDate
	END	
	IF  @ProductCode IN ('SB','NG','LC','VS','CS','RB')
	BEGIN
		INSERT INTO #Temp  (LicenseeID ,rptDate,CurrencyID,winloss,TurnOver)
		SELECT 
			b.siteID,
			b.rptDate,  
			b.currencyID,
			SUM(b.winloss) winloss,
			 SUM(b.turnover
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
					     WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				)TurnOver
		FROM 
			bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK ) 
			INNER JOIN #tmpLicensee ag ON ag.LicenseeID=b.SiteID
		WHERE  
			b.rptDate  BETWEEN @FromDate AND @ToDate 
			AND b.status NOT IN (-1,103)
			AND ( (@ProductCode='SB' AND (b.bettype <31 OR b.bettype BETWEEN 121 AND 999))
				OR(@ProductCode='NG' AND b.bettype BETWEEN 81 AND 120)
				OR(@ProductCode='LC' AND b.bettype BETWEEN 1101 AND 1199)
				OR(@ProductCode='VS' AND b.bettype BETWEEN 1201 AND 1299)
				OR(@ProductCode='CS' AND b.bettype =71)
				OR(@ProductCode='RB' AND b.bettype BETWEEN 31 AND 33)
				)	
			AND (@Currency=0 OR (@Currency<>0 AND b.CurrencyID=@Currency))  
			AND (@excludeTest=0 OR (@excludeTest=1 AND b.CurrencyID<>20)) 
		GROUP BY b.siteID, b.rptDate,b.currencyID
		ORDER BY b.siteID,
			     b.rptDate

	END	

	INSERT INTO #rptLicMargin(Licensee,rptDate,margin)
	SELECT 
		l.LicenseeName,
		dbo.fnFormatDate(t.rptdate) rptDate,
		CASE WHEN ISNULL(SUM(TurnOver),0)=0 THEN 0  
			ELSE 
				-SUM(Winloss)/SUM(Turnover) 
			END Margin
		/*				
		SUM( CASE WHEN ISNULL(TurnOver,0)=0 THEN 0 
				  ELSE 
						-t.Winloss/TurnOver
				   END
			) margin
			*/
	FROM #Temp t
		INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON t.LicenseeId=l.LicenseeId
	GROUP BY 
		l.LicenseeName,
		dbo.fnFormatDate(t.rptdate)
	ORDER BY  l.LicenseeName,
		dbo.fnFormatDate(t.rptdate)
	
	--------------------------------- view result  -------------------------------------------
	SELECT @cols= STUFF((SELECT ',' + QUOTENAME(seq)
                    FROM 
                    (
                      SELECT dbo.fnFormatDate(sdate) seq
                      FROM #MY
                    )d
					FOR XML PATH(''),TYPE
					).value('.', 'NVARCHAR(MAX)') 
				    ,1,1,'')
	SET @query='select Licensee,' + @cols + ' 
            from
            (
              select s.Licensee,s.margin,s.seq
              from
              (
                select Licensee,margin
                  , rptdate seq
                from #rptLicMargin
              ) s
              
            ) x
            pivot 
            (
                max(margin)
                for seq in (' + convert(varchar(1000),@cols) + ')
            ) p '
			--print (@query)
	EXECUTE sp_executesql @query;
				
	DROP TABLE #rptLicMargin
	DROP TABLE #Temp
	DROP TABLE #tmpLicensee
	DROP TABLE #MY
END

GO
GRANT EXECUTE ON [dbo].[OA_Rpt_LicPerformance_LicensingMargin] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_Rpt_LicPerformance_LicensingMargin] TO [vnteam]