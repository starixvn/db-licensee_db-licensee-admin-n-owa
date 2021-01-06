/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
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
	   - 20180510@Bruce: Integrate Pragmatic [#94108]
	   - 20180815@Scofield: Remove "Exclude Test Data" checkbox [#98623]
	   - 20190325@Parsons: Integrate-PP-Promotion-Prize [#109014]
	   - 20191205@Parsons: PP tournament [#123958]
	   - 20191226@Parsons: Setup billing terms by Currency  [#120005]
	   - 20200311@Mason: Spadegaming integration  [#123959]
	   - 20200317@Parsons: Integrate Virtual Games [#125222]
	   - 20200323@Parsons: Intergrate Indo 4D [#130910]
	   - 20200411@Parsons: Integrate Table Games [#131166]
	   - 20200423@Parsons: Integrate Saba.club [#132730]
	   - 20200507@Parsons: Integrate Sexy Gaming for deposit licensees [#132665]
	   - 20200624@Parsons: Keep Negative Licensing Fee for 2 special licensees 9wickets, 9Wsports [#136334]
	   - 20200820@Parsons: Implement PP JP Changes In Reports Phase 2 [#139055]
	   - 20200909@Parsons: Implement PG Soft [RedmineID: #138983]
	   - 20200930@Parsons: Implement Joker Games [RedmineID: #141421]
	   - 20201113@Parsons: Changing OddsSpread for licensee [#142345]
	   - 20201211@Happy: Saba.club - Offer Freebet tickets [#141423]
	   - 20201223@Happy: Implement WM [#141357]
	   - 20201223@Parsons: Integrate Leap Gaming Virtual Sports [#145339]  
	   - 20201230@Parsons: Integrate Gold Diamond Gaming [#145340]
	   - 20201231@Parsons: Integrate Big Gaming [#145342]
	   - 20210106@Happy: Integrate MaxGame [#147375]


	Param's Explanation:  
	  + @PartyIDs : a string of list LicenseeID, separated by ','
	  + @Currency : 0-All Currencies
	  + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @ProductCode : string,
		
	  + @IsConvert: =1 : convert figure to 
					=0 : no convert 
					(datatype:bit)
		
*/  
BEGIN  
	SET NOCOUNT ON  

	CREATE TABLE #Bettype (Bettype INT, ProductID INT)
    CREATE TABLE #tmpParty (PartyID INT, LicenseeID INT, ProductID INT, Rate MONEY, Fromdate SMALLDATETIME, Todate SMALLDATETIME, ChargeID INT)

    INSERT INTO #Bettype( Bettype, ProductID)
    SELECT Bettype,ProductID 
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0,@ProductCode)

    INSERT INTO #tmpParty(PartyID, LicenseeID, ProductID, Rate, Fromdate, Todate, ChargeID)
    SELECT PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate, ChargeID
    FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', 1)
	
	CREATE TABLE #rptLicFee (PartyId INT, Licensee VARCHAR(20), rptDate VARCHAR(50), LicensingFee MONEY)

	CREATE TABLE #Temp (PartyId INT, rptDate DATETIME, CurrencyID INT,LicensingFee MONEY)
	
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

	IF @ProductCode IN ('NG', 'LC', 'VS', 'CS', 'VB', 'SG', 'VRG', 'I4D', 'TG', 'SBC', 'SXG', 'PGS', 'JK', 'WM', 'VS3', 'GDG', 'BGG', 'MXG')
	BEGIN		
		INSERT INTO #Temp (PartyId, rptDate, CurrencyID, LicensingFee)
		SELECT tp.PartyID, d.rptDate, d.CurrencyID, - SUM(d.Winloss * ISNULL(cc.Rate, tp.Rate))
		FROM (
		    SELECT rptDate, currencyID, tp.PartyID, SUM(winloss) AS Winloss
		    FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK) 
			    INNER JOIN (SELECT DISTINCT PartyID, LicenseeID FROM #tmpParty) tp ON tp.LicenseeID = b.SiteID
			    INNER JOIN #bettype be ON b.bettype = be.bettype 
		    WHERE b.rptDate BETWEEN @FromDate AND @Todate
				AND b.status NOT IN (-1, 101, 102, 103)
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))  
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND	ISNULL(b.TicketType, 0) <> 2 -- Free_Bets_TicketType
		    GROUP BY rptDate, currencyID, tp.PartyID
		    ) d 
			 INNER JOIN (SELECT DISTINCT PartyID, Rate, Fromdate, Todate, ChargeID FROM #tmpParty) tp ON tp.PartyID = d.PartyID
			 LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cc WITH (NOLOCK) ON d.CurrencyID = cc.CurrencyID AND tp.ChargeID = cc.ChargeID 
		WHERE d.rptDate  BETWEEN tp.Fromdate AND tp.Todate			
		GROUP BY tp.PartyID, d.rptDate, d.currencyID		
	END	

	IF @ProductCode = 'SB'
	BEGIN		
		DECLARE @SB_Product INT = 0, 
				@SB_AdjustedOdds SMALLINT = 999
		;WITH cte_TempData AS 
		(
			SELECT  ci.PartyID, b.rptDate, b.currencyID
			, SUM(CASE WHEN b.Bettype = @SB_AdjustedOdds THEN 0 ELSE ISNULL(-b.MemberWL, 0) END * ISNULL(cr.Rate, ci.Rate)) AS LicencingFeeAdjustedOdds
			, SUM(CASE WHEN b.Bettype = @SB_AdjustedOdds THEN ISNULL(-b.GrossWL, 0) ELSE 0 END) AS OddsSpreadCost
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #tmpParty ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID AND b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND b.CurrencyId = cr.CurrencyID
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.ProductID = @SB_Product
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27,28)
			GROUP BY ci.PartyID, b.rptDate, b.currencyID
		)
		INSERT INTO #Temp (PartyId, rptDate, CurrencyID, LicensingFee)
		SELECT PartyID, rptDate, CurrencyId, LicencingFeeAdjustedOdds + OddsSpreadCost
		FROM cte_TempData
	END

	IF @ProductCode = 'PP'
	BEGIN		
		DECLARE @PP_Contribution SMALLINT = 4297,
				@PP_JackpotPrize SMALLINT = 4298,
				@PPTournament SMALLINT = 4299,
				@PromotionPrize SMALLINT = 4300
		;WITH cte_PPWinLossData AS(
			SELECT tp.PartyID, b.rptDate, b.CurrencyID
				, SUM(ISNULL(-b.MemberWL, 0)) LicenseeWL
				, SUM(CASE WHEN b.Bettype = @PP_Contribution THEN ISNULL(-b.GrossWL, 0) ELSE 0 END) Contribution
				FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
					INNER JOIN (SELECT DISTINCT PartyID, LicenseeID FROM #tmpParty) tp ON tp.LicenseeID = b.SiteID
				WHERE b.ProductID = 32
					AND b.rptDate BETWEEN @FromDate AND @ToDate
					AND (b.CurrencyID <> 20)
					AND (@Currency = 0 OR b.CurrencyID = @Currency)  
					AND b.[StatusId] NOT IN (-1, 101, 102, 103)
					AND b.Bettype NOT IN (@PPTournament, @PromotionPrize,@PP_JackpotPrize)
				GROUP BY tp.PartyID, b.rptDate, b.CurrencyID
		)
		INSERT INTO #Temp (PartyId, rptDate, CurrencyID, LicensingFee)
		(
			SELECT tp.PartyID, b.rptDate, b.CurrencyId, SUM((LicenseeWL - Contribution) * ISNULL(cc.Rate, tp.Rate))			
			FROM cte_PPWinLossData b
				INNER JOIN (SELECT DISTINCT PartyID, Rate, Fromdate, Todate, ChargeID FROM #tmpParty) tp ON tp.PartyID = b.PartyID
				LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cc WITH (NOLOCK) ON b.CurrencyID = cc.CurrencyID AND tp.ChargeID = cc.ChargeID 
			WHERE b.rptDate BETWEEN tp.Fromdate AND tp.Todate
			GROUP BY tp.PartyID, b.rptDate, b.CurrencyId
		)

	END	
	INSERT INTO #Exchange (ExchangeDate, ExchangeId, Rate)
	SELECT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate
	FROM dbo.LA_f_ExchangeDailySel(@fromdate, @todate, @BaseCurrencyName)

	IF (@isconvert = 0)
		BEGIN
			UPDATE #Exchange
			SET Rate = 1
		END
	
	INSERT INTO #rptLicFee(PartyId, Licensee, rptDate, LicensingFee)
	SELECT p.PartyId, 
		CASE p.PartyName
			 WHEN '18bb' THEN 'PIH'
			 WHEN 'IBC'  THEN 'FDL'
			 ELSE p.PartyName
		    END AS PartyName
		, DATENAME(YEAR, t.rptDate)  + '-' + DATENAME(MONTH, t.rptDate) AS rptDate
		, SUM(t.LicensingFee * ee.Rate) LicensingFee
	FROM #Temp t
		INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON t.PartyId = p.PartyID
		INNER JOIN #Exchange ee ON t.rptDate = ee.exchangedate AND t.CurrencyID = ee.ExchangeId
	GROUP BY p.PartyId, p.PartyName, DATENAME(YEAR, t.rptDate)  + '-' + DATENAME(MONTH, t.rptDate)

	UPDATE #rptLicFee
	SET LicensingFee = 0
	WHERE LicensingFee < 0 AND PartyId NOT IN (316, 459) --9wickets-316, 9Wsports-459
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
                select Licensee,LicensingFee AS Fee
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