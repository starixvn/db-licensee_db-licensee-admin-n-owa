/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE [bodb02]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicPerformance_LicensingMargin]
	@PartyIDs				VARCHAR(4000)	= ''
	, @Currency				INT				= 0
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME
	, @ProductCode			VARCHAR(500)	
	, @drawfilter			SMALLINT		= 1
	, @IsConvert			BIT				= 1
	, @BaseCurrencyName		VARCHAR(10)		= 'EUR'
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
	   - 20171205@Bruce: fix partyid length [#87723]
	   - 20171212@Bruce: Add Average Margin [#87843]
	   - 20180718@Bruce: Change default currency to EUR [#94108]
	   - 20180815@Scofield: Remove "Exclude Test Data" checkbox [#98623]
	   
	Param's Explanation:  
	  + @PartyIDs : a string of list PartyID, separated by ','
	  + @Currency : 0-All Currencies
	  + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @ProductCode : string,
	 
*/  
BEGIN  
	SET NOCOUNT ON  
	
	CREATE TABLE #rptLicMargin (PartyName NVARCHAR(200), ReportDate SMALLDATETIME, Margin MONEY)
	CREATE TABLE #Temp (PartyID INT, rptDate DATETIME, CurrencyID INT, Winloss MONEY, TurnOver MONEY)
	DECLARE @Bettype TABLE (Bettype INT, ProductID INT)
	DECLARE @tmpParty TABLE (PartyID INT, LicenseeID INT, ProductID INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME)

	INSERT INTO @Bettype( Bettype, ProductID)
	SELECT Bettype,ProductID
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, @ProductCode)

	INSERT INTO @tmpParty( PartyID, LicenseeID,ProductID, Fromdate, Todate)
	SELECT DISTINCT PartyID, LicenseeID, ProductID, Fromdate, Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', 1)

	CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeId INT, Rate FLOAT)
	INSERT INTO #Exchange (ExchangeDate, ExchangeId, Rate)
	SELECT ExchangeDate, ExchangeId, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	IF @IsConvert = 0
	BEGIN
		UPDATE #Exchange SET Rate = 1
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
		  AND (b.CurrencyID <> 20)
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
	   WHERE b.rptDate BETWEEN @FromDate AND @Todate
		  AND b.Bettype IN (SELECT Bettype FROM @Bettype)
		  AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
		  AND (b.CurrencyID <> 20)
		  AND b.status NOT IN (-1, 101, 102, 103)
		  AND b.customercategory NOT IN (27, 28)
	   GROUP BY tp.PartyID, rptDate, currencyID
	END

	;WITH d(PartyID, rptDate, TurnOver, Winloss) AS
	(
		SELECT d.PartyID, DATEADD(MONTH, DATEDIFF(MONTH, 0, d.rptDate), 0)
			, SUM(d.TurnOver * e.Rate)
			, SUM(d.Winloss * e.Rate)
		FROM #Temp d
			INNER JOIN #Exchange e ON d.rptDate = e.ExchangeDate AND d.CurrencyID = e.ExchangeId
			INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate FROM @tmpParty) tp ON tp.PartyID = d.PartyID
		WHERE  d.rptDate BETWEEN tp.Fromdate AND tp.Todate
		GROUP BY d.PartyID, DATEADD(MONTH, DATEDIFF(MONTH, 0, d.rptDate), 0)
	)
	INSERT INTO #rptLicMargin(ReportDate,PartyName,Margin)
	(
		SELECT d.rptDate
			, CASE p.PartyName WHEN '18bb' THEN 'PIH' WHEN 'IBC'  THEN 'FDL' ELSE p.PartyName END AS PartyName
			, CASE WHEN d.TurnOver = 0 THEN 0 ELSE -d.Winloss/d.TurnOver END AS Margin
		FROM d INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON d.PartyID = p.PartyID
		UNION ALL
		SELECT d.rptDate,'Average Margin'
			, CASE WHEN SUM(d.TurnOver) = 0 THEN 0 ELSE SUM(-d.Winloss)/SUM(d.TurnOver) END AS Margin
		FROM d
		GROUP BY d.rptDate
	)

	-- insert missing month
	DECLARE @Date SMALLDATETIME = DATEADD(MONTH, DATEDIFF(MONTH, 0, @FromDate), 0)
	DECLARE @MonthList TABLE(DateValue SMALLDATETIME)

	WHILE(@Date <= @ToDate)
	BEGIN
		INSERT INTO @MonthList(DateValue) VALUES(@Date)
		SET @Date = DATEADD(MONTH,1,@Date)
	END

	INSERT INTO #rptLicMargin(PartyName, ReportDate, Margin)
	(
		SELECT y.PartyName,m.DateValue,0
		FROM @MonthList m
			INNER JOIN (SELECT DISTINCT x.PartyName FROM #rptLicMargin x) y ON 1=1
			LEFT JOIN #rptLicMargin r ON r.PartyName = y.PartyName AND r.ReportDate = m.DateValue
		WHERE r.ReportDate IS NULL
	)	

	SELECT PartyName, ReportDate, Margin
	FROM #rptLicMargin

	DROP TABLE #rptLicMargin
	DROP TABLE #Temp
	DROP TABLE #Exchange
END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicPerformance_LicensingMargin] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_Rpt_LicPerformance_LicensingMargin] TO bodbAdminNet
GO
