USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LicPerformance_LicensingMargin]    Script Date: 01/12/2014 14:41:09 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicPerformance_LicensingMargin] 
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
    DB: DB052.bodb02  
    Base on: [OA_Rpt_LicPerformance_LicensingMargin]
   
    Revisions:  
    
	Param's Explanation:  
	  + @PartyIDs : a string of list PartyID, separated by ','
	  + @Currency : 0-All Currencies
	  + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS
	  + @ProductCode : string,
	 
*/  

/*
exec  OA_Rpt_LicPerformance_LicensingMargin
		@Licensee=N'58,1,4,2,14,6,85,74,101,98,78,90,84,22,109,67,23,76,108,30,111,25,72,107,94,19,86,110,89,79,80,93,17,83,77,12,91,82,7,3,9,8,15,10,97,81,21,70'
		,@Currency=0
		,@fromdate='2013-09-01 00:00:00'
		,@todate='2014-05-26 00:00:00'
		,@ProductCode=N'SB'
		,@drawfilter=1
		,@excludeTest=1
EXEC LA_Rpt_LicPerformance_LicensingMargin @FromDate = '2013-09-01 00:00:00'
	,@Currency = 0
	,@ToDate = '2014-05-01 00:00:00'
	,@excludeTest = 1
	,@PartyIDs = '14,15,16,17,19,20,21,22,23,24,26,27,33,39,40,42,43,44,45,46,47,48,49,52,53,54,55,56,29,31,34,35,36,37,38,41,58,59,60,61,62,63,64,65,66,67,68,69,70,71,72,73,74,75,76,77,78,79,80,81,25,30'
	,@drawfilter = 1
	,@ProductCode = 'SB'


*/
BEGIN  
	SET NOCOUNT ON  
	
	CREATE TABLE #rptLicMargin (  
		Licensee 		VARCHAR(20),
		rptDate		VARCHAR(50),	
		Margin		MONEY
	)

	CREATE TABLE #Temp (  
		PartyID 		INT,	
		rptDate 		DATETIME,
		CurrencyID 	INT, 
		Winloss		MONEY,
		TurnOver		MONEY
	)
	CREATE TABLE #Data (
		   rptDate	   SMALLDATETIME
		  ,currencyID	   INT 
		  ,winloss	   MONEY 
		  ,Turnover	   MONEY
		  ,siteID		   INT)

	CREATE TABLE #Bettype (Bettype INT,ProductID INT)
     CREATE TABLE #tmpParty (
		  PartyID		 INT
		  ,LicenseeID   INT
		  ,isDeposit    INT
		  ,AffectedDate SMALLDATETIME
		  ,ProductID    INT 	
		  ,Fromdate	 SMALLDATETIME
		  ,Todate		 SMALLDATETIME	  		  
		  )

     INSERT INTO #Bettype
     SELECT Bettype,ProductID FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, @ProductCode)

     INSERT INTO #tmpParty
     SELECT DISTINCT PartyID,LicenseeID,isDeposit,AffectedDate,ProductID,Fromdate,Todate
     FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA')
	IF (
	    EXISTS (
		  SELECT TOP 1 1
		  FROM #tmpParty
		  WHERE AffectedDate > Fromdate
		  )
	    AND @excludeTest = 1
	    )
	BEGIN
		UPDATE #tmpParty
		SET Fromdate = AffectedDate
		WHERE AffectedDate > Fromdate
	END

	CREATE TABLE #MY(sDate DATETIME)
	
	DECLARE @cols	    AS NVARCHAR(MAX),
			@query   AS NVARCHAR(MAX),
			@sdate   AS DATETIME 
	SELECT   @cols	 = NULL,
		    @query = NULL,
		    @sdate = @FromDate	

	WHILE ((MONTH(@sdate) <= MONTH(@ToDate) AND YEAR(@sdate) = YEAR(@ToDate)) OR (YEAR(@sdate) < YEAR(@ToDate)))
	BEGIN 
		INSERT INTO #MY(sDate)
		SELECT @sdate
		SET @sdate=DATEADD(m, 1, @sdate)
	END

	IF @ProductCode = 'BA'
	BEGIN 
		INSERT INTO #Temp (PartyID ,rptDate,CurrencyID,winloss,TurnOver)
		SELECT 
			tp.PartyID,
			b.rptDate,  
			b.currencyID,
			SUM(b.winloss) winloss,
			 SUM(b.turnover
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
					     WHEN b.status IN (114, 115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				)TurnOver
		FROM 
			bodb_Licensee.dbo.rpt_Betting_BA b WITH ( NOLOCK ) 
			INNER JOIN #tmpParty tp ON tp.LicenseeID = b.SiteID
		WHERE  
			b.rptDate BETWEEN tp.Fromdate AND tp.Todate
			AND b.status NOT IN (-1, 103)
			AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))  
			AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20)) 
		GROUP BY tp.PartyID, b.rptDate, b.currencyID
		ORDER BY tp.PartyID, b.rptDate
	END	
	IF  @ProductCode != 'BA'
	BEGIN
		INSERT INTO #Data (rptDate, currencyID, Turnover, winloss, siteID)
		SELECT rptDate, currencyID 
			 ,SUM(b.turnover
				*
				CASE WHEN @drawfilter IN (2, 3) THEN
					   CASE WHEN b.status = 111  THEN 0	
						  WHEN b.status IN (114, 115) THEN 0.5
						  ELSE 1 END 
					   ELSE 1 END
				) TurnOver, SUM(winloss), siteID
		FROM bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK) 
			INNER JOIN #tmpParty tp ON tp.LicenseeID = b.SiteID
			INNER JOIN #bettype be ON b.bettype = be.bettype
		WHERE b.rptDate BETWEEN @FromDate AND @Todate
			 AND b.status NOT IN (-1, 103)
			 AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))  
			 AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20)) 
	     GROUP BY rptDate, currencyID, siteID, b.bettype, status


		INSERT INTO #Temp (PartyID ,rptDate,CurrencyID,winloss,TurnOver)
		SELECT 
			tp.PartyID
		    ,b.rptDate
		    ,b.currencyID
		    ,SUM(b.winloss) winloss
		    ,SUM(b.turnover) TurnOver
		FROM #Data b WITH ( NOLOCK) 
			INNER JOIN #tmpParty tp ON tp.LicenseeID = b.SiteID			
		WHERE  b.rptDate BETWEEN tp.Fromdate AND tp.Todate
		GROUP BY tp.PartyID, b.rptDate, b.currencyID
		ORDER BY tp.PartyID, b.rptDate

	END	
	
	SELECT * INTO #TempExchange 
	FROM Lrf_f_GetExchangeDaily(@FromDate, @ToDate)
	--WHERE exchangeid IN (SELECT DISTINCT CurrencyID FROM #Temp)

	UPDATE  t
	SET Winloss = t.Winloss * e.EUR
	   ,TurnOver = t.TurnOver * e.EUR
	FROM #Temp t
		INNER JOIN #TempExchange e ON t.rptDate = e.ExchangeDate AND t.CurrencyID = e.ExchangeId
	INSERT INTO #rptLicMargin(Licensee, rptDate, Margin)
	SELECT 
		p.PartyName,
		dbo.fnFormatDate(t.rptdate) rptDate,
		CASE WHEN ISNULL(SUM(TurnOver),0) = 0 THEN 0  
			ELSE 
				-SUM(Winloss) / SUM(Turnover) 
			END Margin
	FROM #Temp t
		INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON t.PartyID = p.PartyID		
	GROUP BY 
		p.PartyName, dbo.fnFormatDate(t.rptDate)
	ORDER BY  p.PartyName, dbo.fnFormatDate(t.rptDate)

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
	SET @query='SELECT Licensee AS PartyName,' + @cols + ' 
            FROM
            (
              SELECT s.Licensee,s.margin,s.seq
              FROM
              (
                SELECT Licensee,margin
                  , rptdate seq
                FROM #rptLicMargin
              ) s
              
            ) x
            PIVOT
            (
                MAX(margin)
                FOR seq IN (' + convert(varchar(1000),@cols) + ')
            ) p '
			--print (@query)
	EXECUTE sp_executesql @query;
				
	DROP TABLE #rptLicMargin
	DROP TABLE #Temp
	DROP TABLE #MY
	DROP TABLE #TempExchange
	DROP TABLE #bettype
	DROP TABLE #tmpParty
	DROP TABLE #Data
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicPerformance_LicensingMargin] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicPerformance_LicensingMargin] TO bodbAdminNet 