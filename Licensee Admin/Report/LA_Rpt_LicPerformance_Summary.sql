USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LicPerformance_Summary]    Script Date: 01/12/2014 14:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_Rpt_LicPerformance_Summary    Script Date: 3/6/2014 5:23:51 PM ******/
ALTER PROCEDURE [dbo].[LA_Rpt_LicPerformance_Summary] 
	 @PartyIDs			VARCHAR(4000)	= ''
	, @Currency			INT				= 0
	, @FromDate			SMALLDATETIME
	, @ToDate			SMALLDATETIME
	, @ProductCode		VARCHAR(10)
	, @ReportType		TINYINT			= 2	
	, @drawfilter		SMALLINT		= 1
	, @excludeTest		BIT				= 0
	, @MoveBetsDay		SMALLDATETIME	= ''
	, @IsConvert		BIT				= 0
	, @BaseCurrencyName	VARCHAR(10)		= 'GBP'
WITH RECOMPILE
AS  
/*	Created by: 20140929@Florent
	Original: OA_Rpt_LicPerformance_Summary
	Task : LicenseeAdmin - Get Licensee Perfomance Summary Report 
     DB: DB052.bodb02  
   
    Revisions:  
	   - 20141223@Florent: remove un-use code and enhance
	   - 20150703@Florent: add GBP
	   - 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]	
	Param's Explanation:  
	  + @PartyIDs : a string of list PartyID, separated by ','
	  + @Currency : 0-All Currencies
	  + @ReportType: 1-Daily; 2-Monthly
	  + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS
	  + @BettypeID : 0-selected all bettype	  
*/  
BEGIN  
	SET NOCOUNT ON  

	SET @ReportType = 2 -- only allow monthly  
	DECLARE @Bettype TABLE(Bettype INT, ProductID INT)
	INSERT INTO @Bettype
	SELECT Bettype, ProductID 
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, @ProductCode)

	DECLARE @tmpParty TABLE(ChargeId INT, PartyID INT, LicenseeID INT, IsDeposit INT, ProductID INT
						, Rate MONEY, AffectedDate SMALLDATETIME, Fromdate SMALLDATETIME, Todate SMALLDATETIME)
	INSERT INTO @tmpParty(ChargeId, PartyID, LicenseeID, IsDeposit, ProductID, Rate, AffectedDate, FromDate, ToDate)
	SELECT DISTINCT ChargeId, PartyID, LicenseeID, IsDeposit, ProductID, DI_Rate, AffectedDate, Fromdate, Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', @ExcludeTest)

	CREATE TABLE #Result (PartyID INT, ReportType VARCHAR(8), TurnOver MONEY, CustomerWinlost MONEY, CommBA MONEY ,CommRB MONEY, Betcount BIGINT
		, LicensingFee MONEY)

	CREATE TABLE #Temp (PartyID INT	,Rptdate DATETIME, Currency INT, TurnOver MONEY, Winlost MONEY, CommBA MONEY, CommRB MONEY, Betcount BIGINT)

	CREATE TABLE #Exchange (ExchangeDate SMALLDATETIME, ExchangeId INT, Rate FLOAT)	
	INSERT INTO #Exchange(ExchangeDate, ExchangeId, Rate)
	SELECT DISTINCT ExchangeDate, ExchangeId, BaseCurrencyRate 
	FROM dbo.LA_f_ExchangeDailySel(@Fromdate, @ToDate, @BaseCurrencyName)	
	
	IF (@isconvert = 0)
	BEGIN
		UPDATE #Exchange
		SET Rate = 1
	END	

	IF CHARINDEX('BA',@ProductCode) <> 0
	BEGIN
		INSERT INTO #Temp (PartyID, Rptdate, Currency, TurnOver, Winlost, CommBA, CommRB, Betcount)
		(
			SELECT PartyID, b.rptDate , b.currencyID
			, SUM(b.turnover *
				CASE WHEN @drawfilter IN (2,3) THEN
						CASE WHEN b.status = 111  THEN 0	
							WHEN b.status IN (114, 115) THEN 0.5
							ELSE 1 END 
						ELSE 1 END
				) TurnOver
			, SUM(b.winloss) Winloss
			--, 0 AS LicenseeFee
			, SUM(b.CommissionA) AS CommBA				
			, 0 AS CommRB
			, SUM(betcount * 
					CASE WHEN @drawfilter = 2 AND b.status = 111 THEN 0
						ELSE 1 END) AS BetCount
			FROM bodb_LicenseeReport.dbo.rpt_Betting_BA b WITH (NOLOCK) 			
			INNER JOIN(
					SELECT DISTINCT PartyID, LicenseeID
					FROM @tmpParty
			)tp ON b.SiteID = tp.LicenseeID		
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate 
			AND b.Bettype IN (SELECT Bettype FROM @Bettype)
			AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))  
			AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20)) 
			AND b.status NOT IN (-1, 101, 102, 103)
			GROUP BY PartyID, b.rptDate, currencyID
		)
	END

	--exclude BA tickets
	IF CHARINDEX('BA',@ProductCode) = 0
	BEGIN
		INSERT INTO #Temp (PartyID, Rptdate, Currency, TurnOver, Winlost, CommBA, CommRB, Betcount)
		(
			SELECT PartyID, b.rptDate, b.currencyID 
			, SUM(b.turnover
				* CASE WHEN b.bettype = 33 AND b.Status IN (114, 115) THEN 0.5 ELSE 1 END
				* CASE WHEN @drawfilter IN (2, 3) THEN
						CASE WHEN b.Status = 111  THEN 0	
							WHEN b.Status IN (114, 115) AND b.Bettype != 33 THEN 0.5
							ELSE 1 END 
						ELSE 1 END
				) TurnOver
			, SUM(b.winloss) AS Winlost
			--, 0 AS LicenseeFee	 
			, 0 AS CommBA
			, SUM(CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.CommissionA ELSE 0 END ) AS CommRB
			, SUM(b.betcount * 
					CASE WHEN @drawfilter = 2 AND b.Status = 111 THEN 0
					ELSE 1 END) AS BetCount			
			FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH ( NOLOCK ) 
			INNER JOIN(
					SELECT DISTINCT PartyID, LicenseeID--, Bettype
					FROM @tmpParty
			)tp ON b.SiteID = tp.LicenseeID-- AND b.Bettype = tp.Bettype	
			WHERE  b.rptDate BETWEEN @Fromdate AND @ToDate
			AND b.Bettype IN (SELECT Bettype FROM @Bettype)
			AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
			AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20)) 
			AND b.status NOT IN (-1, 101, 102, 103)
			AND b.customercategory NOT IN (27, 28)			
			GROUP BY PartyID, b.rptDate, b.currencyID
		) 
	END		

	INSERT INTO #Result	
	SELECT b.PartyID
		, CONVERT(VARCHAR(6),b.rptDate,112)
		, SUM(TurnOver * e.Rate) AS Turnover
		, SUM(Winlost * e.Rate) AS CustomerWinlost
		, SUM(CommBA * e.Rate) AS CommBA
		, SUM(CommRB * e.Rate) AS CommRB
		, SUM(Betcount) AS Betcount
		, - SUM(b.Winlost * ISNULL(p.Rate,0) * e.Rate) AS LicenseeFee		
	FROM #Temp b
	INNER JOIN #Exchange e  ON e.ExchangeDate = b.Rptdate AND e.ExchangeId = b.Currency	   
	INNER JOIN  (
		SELECT DISTINCT PartyID, FromDate, ToDate, Rate
		FROM @tmpParty
	) p ON b.PartyID = p.PartyID AND b.rptDate BETWEEN p.Fromdate AND p.Todate
	GROUP BY CONVERT(VARCHAR(6), b.rptDate, 112), b.PartyID	

	UPDATE #Result
	SET LicensingFee = 0
	WHERE LicensingFee < 0

	-------------------------final select -------------------------------
	SELECT CAST((ReportType + '01') AS DATE) AS [DateTime]
		, SUM(TurnOver) AS TurnOver
		, SUM(CustomerWinlost) AS CustomerWinlost
		, SUM(CommBA) AS AmtDueToBA
		, SUM(CommRB) AS AmtDueToRB
		, SUM(Betcount) AS BetCount
		, CASE WHEN SUM(LicensingFee) < 0 THEN 0 ELSE SUM(LicensingFee) END AS LicensingFee			
	FROM #Result
	GROUP BY ReportType
	ORDER BY ReportType ASC

	DROP TABLE #Result
	DROP TABLE #Exchange
	DROP TABLE #Temp	
END

GO
GRANT EXECUTE ON [dbo].[LA_Rpt_LicPerformance_Summary] TO [bodbLicenseeNet] 
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicPerformance_Summary] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicPerformance_Summary] TO bodbAdminNet 
