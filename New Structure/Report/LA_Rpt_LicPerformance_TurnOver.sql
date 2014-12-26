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
WITH RECOMPILE
AS
 
/*  Created by: 20140930@Florent
    Task : LicenseeAdmin - Get Licensee Perfomance TurnOver Report for each Licensee in one month
    Original: OA_Rpt_LicPerformance_TurnOver
    DB: DB052.bodb02  
   
    Revisions: 
		- 20141026@Patrick: Optimize code
    
    Param's Explanation:  
	   + @partyIDs : a string of list PartyID, separated by ','
	   + @Currency : 0-All Currencies
	   + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	   + @excludeTest: remove currency UUS
	   + @ProductCode : string,
	   + @IsConvert: =1 : convert figure to 
					   =0 : no convert 
					   (datatype:bit)
	   + @BaseCurrency -6 : convert to EUR
					   -2: convert to MYR
					   -3: convert to USD
		
*/  
BEGIN  
    SET NOCOUNT ON  

    DECLARE @Bettype TABLE(Bettype INT, ProductID INT)
    INSERT INTO @Bettype
    SELECT Bettype, ProductID 
    FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, @ProductCode)

    DECLARE @tmpParty TABLE(ChargeId INT, PartyID INT, LicenseeID INT, IsDeposit INT, ProductID INT
	   , Rate MONEY, AffectedDate SMALLDATETIME, Fromdate SMALLDATETIME, Todate SMALLDATETIME)
    INSERT INTO @tmpParty(ChargeId, PartyID, LicenseeID, IsDeposit, ProductID, Rate, AffectedDate, FromDate, ToDate)
    SELECT DISTINCT ChargeId, PartyID, LicenseeID, IsDeposit, ProductID, DI_Rate, AffectedDate, Fromdate, Todate
    FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', @ExcludeTest)
    
    CREATE TABLE #rptTurnOver (PartyName VARCHAR(20), rptDate VARCHAR(50), TurnOver MONEY)
    CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeId INT, Rate FLOAT)
    DECLARE @MY TABLE(sDate DATETIME)

    DECLARE @cols AS NVARCHAR(MAX), @query AS NVARCHAR(MAX), @sdate AS DATETIME
    SELECT @cols = NULL,@query = NULL,@sdate = @FromDate
	
    WHILE (@sdate <= @ToDate)
    BEGIN 
	   INSERT INTO @MY(sDate)
	   SELECT @sdate
	   SET @sdate = DATEADD(M, 1, @sdate)
    END

    INSERT INTO #Exchange (ExchangeDate, ExchangeId, Rate )
    SELECT ExchangeDate
	   , ExchangeId
	   , CASE @BaseCurrency WHEN -2 THEN MYR
					   WHEN -3 THEN USD
					   WHEN -6 THEN EUR
					   ELSE 1 END AS Rate
    FROM dbo.Lrf_f_GetExchangeDaily (@fromdate, @todate)
							
    IF (@isconvert = 0)
    BEGIN
	   UPDATE #Exchange
	   SET Rate=1
    END
		
    CREATE TABLE #Tmp(PartyId INT, rptDate DATE, CurrencyId INT, TurnOver MONEY)

    --get data for BA tickets
    IF @ProductCode = 'BA'
    BEGIN
	   INSERT INTO #Tmp(PartyId, rptDate, CurrencyId, TurnOver)
	   (
		  SELECT tp.PartyID, rptDate, b.currencyID
			 , SUM(b.turnover
				* CASE WHEN @drawfilter IN (2,3) THEN
					   CASE WHEN b.Status = 111  THEN 0	
						  WHEN b.Status IN (114, 115) THEN 0.5
						  ELSE 1 END 
					   ELSE 1 END
				) TurnOver
		  FROM bodb_Licensee.dbo.rpt_Betting_BA b WITH ( NOLOCK ) 
			 INNER JOIN(
				    SELECT DISTINCT PartyID, LicenseeID
				    FROM @tmpParty
			 )tp ON b.SiteID = tp.LicenseeID
		  WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			 AND b.Bettype IN (SELECT Bettype FROM @Bettype)
			 AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))  
			 AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20)) 
			 AND b.status NOT IN (-1, 103)
		  GROUP BY tp.PartyID, rptDate, currencyID
		  ) 
    END

    --exclude BA tickets
    IF @ProductCode IN ('SB', 'RB', 'NG', 'LC', 'VS', 'CS')
    BEGIN		
	   INSERT INTO #Tmp(PartyId, rptDate, CurrencyId, TurnOver)
	   (
		  SELECT tp.PartyID
			 , b.rptDate
			 , b.currencyID
			 , SUM(b.turnover
				* CASE WHEN b.Bettype = 33 AND b.Status IN (114, 115) THEN 0.5 ELSE 1 END
				* CASE WHEN @drawfilter IN (2, 3) THEN
					   CASE WHEN b.Status = 111  THEN 0	
						   WHEN b.Status IN (114, 115) AND b.Bettype != 33 THEN 0.5
						   ELSE 1 END 
					   ELSE 1 END
				) TurnOver
		  FROM bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK) 
			 INNER JOIN (
				    SELECT DISTINCT PartyID, LicenseeID
				    FROM @tmpParty
			 ) tp ON b.SiteID = tp.LicenseeID
		  WHERE b.rptDate  BETWEEN @FromDate AND @ToDate 
			 AND b.Bettype IN (SELECT Bettype FROM @Bettype)
			 AND b.Status NOT IN (-1, 103)
			 AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))  
			 AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20)) 
			 AND b.customercategory NOT IN (27,28)
		  GROUP BY tp.PartyID, rptDate, currencyID
	   )
    END	
	
    INSERT INTO #rptTurnOver(PartyName, rptDate, TurnOver)
    SELECT p.PartyName	   
	   , DATENAME(YEAR, t.rptDate)  + '-' + DATENAME(MONTH, t.rptDate)
	   , SUM(ISNULL(t.TurnOver, 0) * ee.Rate)
    FROM #Tmp t 
	   INNER JOIN (
		  SELECT DISTINCT PartyID, FromDate, ToDate 
		  FROM @tmpParty) tp ON t.PartyID = tp.PartyID AND t.rptDate BETWEEN tp.FromDate AND tp.ToDate
	   INNER JOIN #Exchange ee ON t.rptDate = ee.ExchangeDate AND t.CurrencyID = ee.ExchangeId
	   INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON tp.PartyID = p.PartyID			 
    GROUP BY p.PartyName, DATENAME(YEAR, t.rptDate)  + '-' + DATENAME(MONTH, t.rptDate)

    DROP TABLE #Tmp	

    UPDATE #rptTurnOver
    SET TurnOver = 0
    WHERE (ISNULL(TurnOver, 0) = 0 OR TurnOver < 0)
    --------------------------------- view result  -------------------------------------------
    SELECT @cols = COALESCE(@cols + ',' + QUOTENAME(DATENAME(YEAR, sdate)  + '-' + DATENAME(MONTH, sdate))
								    , QUOTENAME(DATENAME(YEAR, sdate)  + '-' + DATENAME(MONTH, sdate)))
    FROM @MY
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
END


GO
GRANT EXECUTE ON [dbo].[LA_Rpt_LicPerformance_TurnOver] TO [bodbAdminNet]
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicPerformance_TurnOver] TO [vnteam]