/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicPerformance_TurnOver] 
	 @PartyIDs				VARCHAR(4000)	= ''
	,	@Currency			INT				= 0
	,	@FromDate			SMALLDATETIME
	,	@ToDate				SMALLDATETIME
	,	@ProductCode		VARCHAR(500)
	,	@IsConvert			BIT				= 0
	,	@BaseCurrencyName	VARCHAR(10)		= 'GBP'
	,	@drawfilter			SMALLINT		= 1
WITH RECOMPILE
AS
 
/*  Created by: 20140930@Florent
    Task : LicenseeAdmin - Get Licensee Perfomance TurnOver Report for each Licensee in one month
    DB: DBEXT.bodb02  
   
    Revisions: 
		- 20141026@Patrick: Optimize code
		- 20150703@Florent: add GBP
		- 20160506@Bravo: Add VB data.
		- 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
		- 20171205@Bruce: fix partyid length [#87723]
		- 20180118@Parsons: Data is incorrect when chosing cross month [#89351]
		- 20180716@bruce: add new group TEST for credit [#98126]		
		- 20180510@Bruce: Integrate Pragmatic [#94108]
		- 20180815@Scofield: Remove "Exclude Test Data" checkbox [#98623]
		- 20200311@Mason: Spadegaming integration [#123959]
	    - 20200317@Parsons: Integrate Virtual Games [#125222]
	    - 20200323@Parsons: Intergrate Indo 4D [#130910]
	    - 20200411@Parsons: Integrate Table Games [#131166]

    Param's Explanation:  
	   + @partyIDs : a string of list PartyID, separated by ','
	   + @Currency : 0-All Currencies
	   + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	   + @ProductCode : string,
	   + @IsConvert: =1 : convert figure to 
					   =0 : no convert 
					   (datatype:bit)
		
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
    FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', 1)
    
    CREATE TABLE #rptTurnOver (PartyName VARCHAR(20), rptDate VARCHAR(50), TurnOver MONEY)
    CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeId INT, Rate FLOAT)
    DECLARE @MY TABLE(sDate DATETIME)

    DECLARE @cols AS NVARCHAR(MAX), @query AS NVARCHAR(MAX), @sdate AS DATETIME
    SELECT @cols = NULL,@query = NULL,@sdate = DATEADD(MONTH,DATEDIFF(MONTH, 0, @FromDate),0)
	
    WHILE (@sdate <= @ToDate)
    BEGIN 
	   INSERT INTO @MY(sDate)
	   SELECT @sdate
	   SET @sdate = DATEADD(M, 1, @sdate)
    END

    INSERT INTO #Exchange (ExchangeDate, ExchangeId, Rate )
    SELECT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate	   
    FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
							
    IF (@isconvert = 0)
    BEGIN
	   UPDATE #Exchange
	   SET Rate = 1
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
		  FROM bodb_licenseereport.dbo.rpt_Betting_BA b WITH ( NOLOCK ) 
			 INNER JOIN(
				    SELECT DISTINCT PartyID, LicenseeID
				    FROM @tmpParty
			 )tp ON b.SiteID = tp.LicenseeID
		  WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			 AND b.Bettype IN (SELECT Bettype FROM @Bettype)
			 AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))  
			 AND (b.CurrencyID <> 20)
			 AND b.status NOT IN (-1, 101, 102, 103)
		  GROUP BY tp.PartyID, rptDate, currencyID
		  ) 
    END

    --exclude BA tickets
    IF @ProductCode IN ('SB', 'RB', 'NG', 'LC', 'VS', 'CS', 'VB', 'PP', 'SG', 'VRG', 'I4D', 'TG')
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
		  FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK) 
			 INNER JOIN (
				    SELECT DISTINCT PartyID, LicenseeID
				    FROM @tmpParty
			 ) tp ON b.SiteID = tp.LicenseeID
		  WHERE b.rptDate  BETWEEN @FromDate AND @ToDate 
			 AND b.Bettype IN (SELECT Bettype FROM @Bettype)
			 AND b.Status NOT IN (-1, 101, 102, 103)
			 AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))  
			 AND (b.CurrencyID <> 20)
			 AND b.customercategory NOT IN (27,28)
		  GROUP BY tp.PartyID, rptDate, currencyID
	   )
    END	
	
    INSERT INTO #rptTurnOver(PartyName, rptDate, TurnOver)
    SELECT --p.PartyName	   
		  CASE p.PartyName
			 WHEN '18bb' THEN 'PIH'
			 WHEN 'IBC'  THEN 'FDL'
		  ELSE p.PartyName
		  END AS PartyName
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