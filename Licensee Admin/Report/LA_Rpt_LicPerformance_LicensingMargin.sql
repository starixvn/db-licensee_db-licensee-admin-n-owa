USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LicPerformance_LicensingMargin]    Script Date: 01/12/2014 14:41:09 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicPerformance_LicensingMargin] 
@PartyIDs				VARCHAR(1000)	= ''
	, @Currency				INT				= 0
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME
	, @ProductCode			VARCHAR(500)	
	, @drawfilter			SMALLINT		= 1
	, @excludeTest			BIT				= 0
	, @IsConvert			BIT				= 1
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'
WITH RECOMPILE
AS
 
/*  Created by: 20140930@Florent
	Task : LicenseeAdmin - Get Licensee Perfomance TurnOver Report for each Licensee in one month
    DB: DB052.bodb02  
    Base on: [OA_Rpt_LicPerformance_LicensingMargin]
   
    Revisions:  
	   - 20141226@Florent: enhance SP
	   - 20150705@Florent: add GBP
	   - 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
	Param's Explanation:  
	  + @PartyIDs : a string of list PartyID, separated by ','
	  + @Currency : 0-All Currencies
	  + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS
	  + @ProductCode : string,
	 
*/  
BEGIN  
	SET NOCOUNT ON  
	
	CREATE TABLE #rptLicMargin (Licensee VARCHAR(20), rptDate VARCHAR(50), Margin MONEY)
	CREATE TABLE #Temp (PartyID INT, rptDate DATETIME, CurrencyID INT, Winloss MONEY, TurnOver MONEY)
	DECLARE @Bettype TABLE (Bettype INT, ProductID INT)
     DECLARE @tmpParty TABLE (PartyID INT, LicenseeID INT, ProductID INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME)     

     INSERT INTO @Bettype( Bettype, ProductID)
     SELECT Bettype,ProductID 
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, @ProductCode)

     INSERT INTO @tmpParty( PartyID, LicenseeID,ProductID, Fromdate, Todate)
     SELECT DISTINCT PartyID, LicenseeID, ProductID, Fromdate, Todate
     FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', @ExcludeTest)

	DECLARE @MY TABLE (sDate DATETIME)

	CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeId INT, Rate FLOAT)
	
	DECLARE	 @cols	   AS NVARCHAR(MAX)
			, @query	   AS NVARCHAR(MAX)
			, @sdate	   AS DATETIME 
	SELECT   @cols	 = NULL
		    , @query = NULL
		    , @sdate = @FromDate	

	--WHILE ((MONTH(@sdate) <= MONTH(@ToDate) AND YEAR(@sdate) = YEAR(@ToDate)) OR (YEAR(@sdate) < YEAR(@ToDate)))
	WHILE (@sdate <= @ToDate)
	BEGIN 
		INSERT INTO @MY(sDate)
		SELECT @sdate
		SET @sdate = DATEADD(M, 1, @sdate)
	END

	INSERT INTO #Exchange (ExchangeDate, ExchangeId, Rate)
	SELECT ExchangeDate, ExchangeId, BaseCurrencyRate			
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	IF @IsConvert = 0
	BEGIN
		UPDATE #Exchange
		SET Rate = 1
	END

	IF @ProductCode = 'BA'
	BEGIN
	   INSERT INTO #Temp (PartyID, rptDate, CurrencyID, TurnOver, Winloss)
	   SELECT 
		  tp.PartyID, b.rptDate, b.currencyID		  
		  , SUM(b.turnover *
			 CASE WHEN @drawfilter IN (2, 3)	  THEN
				    CASE WHEN b.Status = 111	  THEN 0	
					    WHEN b.Status IN (114, 115) THEN 0.5
					    ELSE 1 END 
				    ELSE 1 END
			 ) AS TurnOver
		  , SUM(b.winloss) AS Winloss
	   FROM bodb_LicenseeReport.dbo.rpt_Betting_BA b WITH ( NOLOCK ) 
		  INNER JOIN (SELECT DISTINCT PartyID, LicenseeID FROM @tmpParty) tp ON tp.LicenseeID = b.SiteID
	   WHERE b.rptDate BETWEEN @Fromdate AND @Todate
		  AND b.Status NOT IN (-1, 101, 102, 103)
		  AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))  
		  AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20)) 
	   GROUP BY tp.PartyID, b.rptDate, b.currencyID			
	END	

	IF  @ProductCode != 'BA'
	BEGIN
	   INSERT INTO #Temp (PartyID, rptDate, CurrencyID, TurnOver, Winloss)
	   SELECT tp.PartyID, rptDate, currencyID
		  , SUM(b.turnover 
			 * CASE WHEN b.bettype = 33 AND b.Status IN (114, 115) THEN 0.5 ELSE 1 END
			 * CASE WHEN @drawfilter IN (2, 3) THEN
					   CASE WHEN b.Status = 111  THEN 0	
						   WHEN b.Status IN (114, 115) AND b.Bettype != 33 THEN 0.5
						   ELSE 1 END 
					   ELSE 1 END
				) AS TurnOver
		  , SUM(winloss) AS Winloss
	   FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH (NOLOCK) 			
		  INNER JOIN (SELECT DISTINCT PartyID, LicenseeID FROM @tmpParty) tp ON tp.LicenseeID = b.SiteID
		  --INNER JOIN @bettype be ON b.bettype = be.bettype
	   WHERE b.rptDate BETWEEN @FromDate AND @Todate
		  AND b.Bettype IN (SELECT Bettype FROM @Bettype)		  
		  AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))  
		  AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20)) 
		  AND b.status NOT IN (-1, 101, 102, 103)
		  AND b.customercategory NOT IN (27, 28)
	   GROUP BY tp.PartyID, rptDate, currencyID
	END		

	INSERT INTO #rptLicMargin(Licensee, rptDate, Margin)
	   SELECT 
		  --p.PartyName		  
		  CASE p.PartyName
			 WHEN '18bb' THEN 'PIH'
			 WHEN 'IBC'  THEN 'FDL'
			 ELSE p.PartyName
		    END AS PartyName
		  , DATENAME(YEAR, d.rptDate)  + '-' + DATENAME(MONTH, d.rptDate) AS rptDate
		  , CASE WHEN ISNULL(SUM(TurnOver * e.Rate), 0) = 0 THEN 0  
			 ELSE 
				- SUM(Winloss * e.Rate) / SUM(Turnover * e.Rate) 
			 END AS Margin
	   FROM #Temp d
		  INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON d.PartyID = p.PartyID		
		  INNER JOIN #Exchange e ON d.rptDate = e.ExchangeDate AND d.CurrencyID = e.ExchangeId
		  INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate FROM @tmpParty) tp ON tp.PartyID = d.PartyID
	   WHERE  d.rptDate BETWEEN tp.Fromdate AND tp.Todate	   
	   GROUP BY p.PartyName, DATENAME(YEAR, d.rptDate)  + '-' + DATENAME(MONTH, d.rptDate)

	--------------------------------- view result  -------------------------------------------
	SELECT @cols = COALESCE(@cols + ',' + QUOTENAME(DATENAME(YEAR, sdate)  + '-' + DATENAME(MONTH, sdate))
									, QUOTENAME(DATENAME(YEAR, sdate)  + '-' + DATENAME(MONTH, sdate)))
	FROM @MY
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
	EXECUTE sp_executesql @query;
				
	DROP TABLE #rptLicMargin
	DROP TABLE #Temp	
	DROP TABLE #Exchange	
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicPerformance_LicensingMargin] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicPerformance_LicensingMargin] TO bodbAdminNet 