/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicPerformance_LicensingFee]
	   @PartyIDs			VARCHAR(4000)	= ''
	   , @Currency			INT				= 0
	   , @FromDate			SMALLDATETIME
	   , @ToDate			SMALLDATETIME
	   , @ProductCode		VARCHAR(500)
	   , @IsConvert			BIT				= 0
	   , @BaseCurrencyName	VARCHAR(10)		= 'GBP'
	   , @drawfilter		SMALLINT		= 1
	   , @excludeTest		BIT				= 0
WITH RECOMPILE
AS  
/*  Created by: 20140930@Florent
    Task : LicenseeAdmin - Get Licensee Perfomance TurnOver Report for each Licensee in one month
    Base on [OA_Rpt_LicPerformance_LicensingFee]
    DB: DB052.bodb02  
   
    Revisions:  		
	   - 20141226@Florent: enhance SP
	   - 20150703@Florent: add GBP
	   - 20160506@Bravo: Add VB data.
	   - 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
	   - 20171205@Bruce: fix partyid length [#87723]
	   - 20180716@bruce: add new group TEST for credit [#98126]
	   
	Param's Explanation:  
	  + @PartyIDs : a string of list LicenseeID, separated by ','
	  + @Currency : 0-All Currencies
	  + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS
	  + @ProductCode : string,
		
	  + @IsConvert: =1 : convert figure to 
					=0 : no convert 
					(datatype:bit)
		
*/  
BEGIN  
	SET NOCOUNT ON  

	CREATE TABLE #Bettype (Bettype INT, ProductID INT)
     CREATE TABLE #tmpParty (PartyID INT, LicenseeID INT, ProductID INT, Rate MONEY, Fromdate SMALLDATETIME, Todate SMALLDATETIME)

     INSERT INTO #Bettype( Bettype, ProductID)
     SELECT Bettype,ProductID 
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0,@ProductCode)

     INSERT INTO #tmpParty( PartyID, LicenseeID, ProductID, Rate, Fromdate, Todate)
     SELECT PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
     FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', @ExcludeTest)
	
	CREATE TABLE #rptLicFee (Licensee VARCHAR(20), rptDate VARCHAR(50), Fee MONEY)

	CREATE TABLE #Temp (PartyId INT, rptDate DATETIME, CurrencyID INT, Winloss MONEY)
	
	CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeId INT, Rate FLOAT)	

	CREATE TABLE #MY(sDate DATETIME)

	DECLARE @cols	    AS NVARCHAR(MAX),
			@query   AS NVARCHAR(MAX),			
			@sdate   AS DATETIME 
	SELECT @cols = NULL,
		  @query = NULL,		   
		  @sdate = @FromDate
    
    	WHILE ((MONTH(@sdate) <= MONTH(@ToDate) AND YEAR(@sdate) = YEAR(@ToDate)) OR (YEAR(@sdate) < YEAR(@ToDate)))
	BEGIN 
		INSERT INTO #MY(sDate)
		SELECT @sdate
		SET @sdate = DATEADD(m, 1, @sdate)
	END	

	IF @ProductCode IN ('SB', 'NG', 'LC', 'VS', 'CS', 'VB')
	BEGIN		
		INSERT INTO #Temp (PartyId, rptDate, CurrencyID, Winloss)
		SELECT tp.PartyID, d.rptDate, d.CurrencyID, - SUM(d.Winloss * ISNULL(tp.Rate,0))
		FROM (
		    SELECT rptDate, currencyID, tp.PartyID, SUM(winloss) AS Winloss
		    FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK) 
			    INNER JOIN (SELECT DISTINCT PartyID, LicenseeID FROM #tmpParty) tp ON tp.LicenseeID = b.SiteID
			    INNER JOIN #bettype be ON b.bettype = be.bettype 
		    WHERE b.rptDate BETWEEN @FromDate AND @Todate
				AND b.status NOT IN (-1, 101, 102, 103)
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))  
				AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20)) 
				AND b.customercategory NOT IN (27, 28)
		    GROUP BY rptDate, currencyID, tp.PartyID
		    ) d 
			 INNER JOIN (SELECT DISTINCT PartyID, Rate, Fromdate, Todate FROM #tmpParty) tp ON tp.PartyID = d.PartyID 
		WHERE d.rptDate  BETWEEN tp.Fromdate AND tp.Todate			
		GROUP BY tp.PartyID, d.rptDate, d.currencyID		
	END	

	INSERT INTO #Exchange (ExchangeDate, ExchangeId, Rate)
	SELECT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate
	FROM dbo.LA_f_ExchangeDailySel(@fromdate, @todate, @BaseCurrencyName)

	IF (@isconvert = 0)
		BEGIN
			UPDATE #Exchange
			SET Rate = 1
		END
	
	INSERT INTO #rptLicFee(Licensee, rptDate, Fee)
	SELECT 
		CASE p.PartyName
			 WHEN '18bb' THEN 'PIH'
			 WHEN 'IBC'  THEN 'FDL'
			 ELSE p.PartyName
		    END AS PartyName
		, DATENAME(YEAR, t.rptDate)  + '-' + DATENAME(MONTH, t.rptDate) AS rptDate
		, SUM(t.Winloss * ee.Rate) Fee
	FROM #Temp t
		INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON t.PartyId = p.PartyID
		INNER JOIN #Exchange ee ON t.rptDate = ee.exchangedate AND t.CurrencyID = ee.ExchangeId
	GROUP BY p.PartyName, DATENAME(YEAR, t.rptDate)  + '-' + DATENAME(MONTH, t.rptDate)
	
	
	UPDATE #rptLicFee
	SET Fee = 0
	WHERE Fee < 0	
	--------------------------------- view result  -------------------------------------------
	--SELECT @cols = STUFF((SELECT ',' + QUOTENAME(seq )
 --                   FROM 
 --                   (
 --                     SELECT dbo.fnFormatDate(sdate) seq
 --                    FROM #MY
 --                   )d
	--				FOR XML PATH(''), TYPE
	--				).value('.', 'NVARCHAR(MAX)') 
	--			, 1, 1, '')
	SELECT @cols = COALESCE(@cols + ',' + QUOTENAME(DATENAME(YEAR, sdate)  + '-' + DATENAME(MONTH, sdate))
									, QUOTENAME(DATENAME(YEAR, sdate)  + '-' + DATENAME(MONTH, sdate)))
	FROM #MY
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
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicPerformance_LicensingFee] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicPerformance_LicensingFee] TO bodbAdminNet 
GO