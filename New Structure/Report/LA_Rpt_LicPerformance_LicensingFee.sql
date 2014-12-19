USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LicPerformance_LicensingFee]    Script Date: 01/12/2014 14:40:20 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicPerformance_LicensingFee]
      @PartyIDs	VARCHAR(1000)	 = ''
	,@Currency	INT			 = 0
	,@FromDate	SMALLDATETIME
	,@ToDate		SMALLDATETIME
	,@ProductCode	VARCHAR(500)
	,@IsConvert	BIT			 = 0
	,@BaseCurrency INT			 = 0
	,@drawfilter	SMALLINT		 = 1
	,@excludeTest	BIT			 = 0

AS  
/*  Created by: 20140930@Florent
    Task : LicenseeAdmin - Get Licensee Perfomance TurnOver Report for each Licensee in one month
    Base on [OA_Rpt_LicPerformance_LicensingFee]
    DB: DB052.bodb02  
   
    Revisions:  		
	Param's Explanation:  
	  + @PartyIDs : a string of list LicenseeID, separated by ','
	  + @Currency : 0-All Currencies
	  + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS
	  + @ProductCode : string,
		
	  + @IsConvert: =1 : convert figure to 
					=0 : no convert 
					(datatype:bit)
	  +@BaseCurrency -6 : convert to EUR
					 -2: convert to MYR
					 -3: convert to USD
		
*/  

/*
exec  OA_Rpt_LicPerformance_LicensingFee
	@Licensee='1,3,4,5,6,7,8,9,10,11,12,13,14,15,16',
	@Currency = 0,
	@FromDate ='2010-01-12',
	@ToDate ='2014-02-28',
	@ProductCode ='SB',
	@IsConvert =1,
	@BaseCurrency =-6,
	@drawfilter  = 1 ,
	@ExcludeTest = 0
*/
BEGIN  
	SET NOCOUNT ON  

	CREATE TABLE #Bettype (Bettype INT,ProductID INT)
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
     CREATE TABLE #Data (
		   rptDate	   SMALLDATETIME
		  ,currencyID	   INT 
		  ,winloss	   MONEY 
		  ,siteID		   INT)

     INSERT INTO #Bettype
     SELECT Bettype,ProductID FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0,@ProductCode)

     INSERT INTO #tmpParty
     SELECT PartyID,LicenseeID,isDeposit,AffectedDate,ProductID,DI_Rate,Fromdate,Todate
     FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs,@FromDate,@ToDate,@ProductCode,'OA',@ExcludeTest)
	
	CREATE TABLE #rptLicFee (
		   Licensee VARCHAR(20)
		   ,rptDate VARCHAR(50)
		   ,Fee MONEY)

	CREATE TABLE #Temp (
		   PartyId	   INT
		   ,rptDate	   DATETIME
		   ,CurrencyID	   INT
		   ,Winloss	   MONEY)
	
	CREATE TABLE #Exchange (
		ExchangeDate   DATE
		,ExchangeId    INT
		,Rate		FLOAT		
	)	
	CREATE TABLE #MY(sDate DATETIME)

	DECLARE @cols AS NVARCHAR(MAX),
			@query  AS NVARCHAR(MAX),			
			@sdate  AS DATETIME 
	SELECT @cols=NULL,
		   @query=NULL,		   
		   @sdate=@FromDate
    
    	WHILE ((MONTH(@sdate) <= MONTH(@ToDate) AND YEAR(@sdate) = YEAR(@ToDate)) OR (YEAR(@sdate) < YEAR(@ToDate)))
	BEGIN 
		INSERT INTO #MY(sDate)
		SELECT @sdate
		SET @sdate = DATEADD(m, 1, @sdate)
	END	

	IF  @ProductCode IN ('SB', 'NG', 'LC', 'VS', 'CS')
	BEGIN
		INSERT INTO #Data (rptDate, currencyID, winloss, siteID)
		SELECT rptDate, currencyID, SUM(winloss), siteID
		FROM bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK) 
			INNER JOIN #tmpParty tp ON tp.LicenseeID = b.SiteID
			INNER JOIN #bettype be ON b.bettype = be.bettype
		WHERE b.rptDate BETWEEN tp.FromDate AND tp.Todate
			 AND b.status NOT IN (-1, 103)
			 AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))  
			 AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20)) 
	     GROUP BY rptDate, currencyID, siteID, b.bettype, status

		INSERT INTO #Temp  (PartyId, rptDate, CurrencyID, Winloss)
		SELECT 
			tp.PartyID,
			b.rptDate,  
			b.currencyID,
			-SUM(b.winloss	* ISNULL(tp.Rate,1)) Winloss
		FROM #Data b WITH (NOLOCK)
			INNER JOIN #tmpParty tp ON tp.LicenseeID = b.SiteID
		WHERE b.rptDate  BETWEEN tp.Fromdate AND tp.Todate			
		GROUP BY tp.PartyID, b.rptDate, b .currencyID
		ORDER BY tp.PartyID, b.rptDate

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
	--					SELECT DISTINCT currencyID 
	--					FROM #Temp
	--					)
	IF (@isconvert = 0)
		BEGIN
			UPDATE #Exchange
			SET Rate = 1
		END
	
	INSERT INTO #rptLicFee(Licensee,rptDate,Fee)
	SELECT 
		p.PartyName,
		dbo.fnFormatDate(t.rptdate) rptDate,
		SUM(t.Winloss*ee.Rate) Fee
	FROM #Temp t
		INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON t.PartyId = p.PartyID
		INNER JOIN #Exchange  ee ON t.rptDate = ee.exchangedate AND t.CurrencyID = ee.ExchangeId
	GROUP BY p.PartyName, dbo.fnFormatDate(t.rptdate)
	ORDER BY  p.PartyName, dbo.fnFormatDate(t.rptdate)
	
	UPDATE #rptLicFee
	SET Fee = 0
	WHERE Fee < 0	
	--------------------------------- view result  -------------------------------------------
	SELECT @cols = STUFF((SELECT ',' + QUOTENAME(seq )
                    FROM 
                    (
                      SELECT dbo.fnFormatDate(sdate) seq
                     FROM #MY
                    )d
					FOR XML PATH(''), TYPE
					).value('.', 'NVARCHAR(MAX)') 
				,1,1,'')
	SET @query = 'SELECT Licensee AS PartyName,' + @cols + ' 
            FROM
            (
              SELECT s.Licensee, s.Fee,seq
              FROM
              (
                select Licensee,Fee
                  , rptdate seq
                FROM #rptLicFee
              ) s              
            ) x
            PIVOT 
            (
                MAX(Fee)
                FOR seq IN (' + CONVERT(VARCHAR(1000), @cols) + ')
            ) p '
			--print (@query)
	EXECUTE sp_executesql @query;
				
	DROP TABLE #rptLicFee
	DROP TABLE #Exchange
	DROP TABLE #Temp
	DROP TABLE #tmpParty
	DROP TABLE #MY
	DROP TABLE #bettype
	DROP TABLE #Data
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicPerformance_LicensingFee] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicPerformance_LicensingFee] TO bodbAdminNet 