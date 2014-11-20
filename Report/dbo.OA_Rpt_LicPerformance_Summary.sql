USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[OA_Rpt_LicPerformance_Summary]    Script Date: 09/29/2014 06:17:31 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_Rpt_LicPerformance_Summary    Script Date: 3/6/2014 5:23:51 PM ******/

ALTER PROCEDURE [dbo].[OA_Rpt_LicPerformance_Summary]  
 @Licensee	VARCHAR(1000)='',
 @Currency		INT = 0,
 @FromDate		SMALLDATETIME,  
 @ToDate		SMALLDATETIME,   
 @ProductCode varchar(6),
 @ReportType	TINYINT=2,  
 @MoveBetsDay SMALLDATETIME,
 @drawfilter SMALLINT = 1  ,
 @excludeTest BIT = 0
AS  
/*  Created by: 20140224@Francis
	Original:OA_Rpt_LicWinloss_Summary2
	Task : LicenseeAdmin - Get Licensee Perfomance Summary Report 
    DB: DB052.bodb02  
   
    Revisions:  
    - 20140306@Francis: Fix incorrect Total Racing/BA Comm, showing Racing/BA Comm instead of AmtDueTo Racing/BA
	- 20140306@Francis: Negative value nolonger added to total Licensing Fee value
	Param's Explanation:  
	  + @Licensee : a string of list LicenseeID, separated by ','
	  + @Currency : 0-All Currencies
	  + @ReportType: 1-Daily; 2-Monthly
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS
	  + @showSB: Show SportsBook bets
	  + @ShowRB: Show RB bets
	  + @ShowNG: Show Number game bets
	  + @ShowBA: Show Bet Aggregator bets (combined with Sportsbook or Number Game)
	  + @ShowLC: Show Live casino
	  + @ShowVS: Show Virtual Sports
	  + @ShowCS: Show RNG Casino 
	  +@SportID: 0-selected all sporttype 
	  +@BettypeID : 0-selected all bettype
	  + @MoveBetsDay: The day we move tickets to bettrans14
*/  
BEGIN  
SET NOCOUNT ON  

SET @ReportType = 2 -- only allow monthly  

declare @showSB		BIT=0,  
        @ShowRB		BIT=0,  
		@ShowNG		BIT=0, 
		@ShowBA		BIT=0,
		@ShowLC		BIT=0,
		@ShowVS		BIT=0,
		@ShowCS		BIT=0,
		@SportID		INT=0,
		@BettypeID		INT=0
 
IF @ProductCode = 'SB'
	SET @showSB = 1
IF @ProductCode = 'RB'
	SET @showRB = 1
IF @ProductCode = 'NG'
	SET @showNG = 1
IF @ProductCode = 'BA'
	SET @showBA = 1
IF @ProductCode = 'LC'
	SET @showLC = 1
IF @ProductCode = 'VS'
	SET @showVS = 1
IF @ProductCode = 'CS'
	SET @showCS = 1


----DECLARE  	
--Licensee Fee Rate constant
DECLARE @RateSB float,
		@RateNG float,
		@RateNGHAIFA float,
		@12BetDate int,
		@RateNG12Bet float,
		@RateVS float,
		@RateLC float,
		@RateCS float,
		@HAIFAID int,
		@12BetID int
	
select @RateSB = 0.15, 
	   @RateNG = 0.15,
	   @RateNGHAIFA = 0.075,
	   @RateNG12Bet = 0.17,
	   @RateVS = 0.15,
	   @RateLC = 0.07,
	   @RateCS = 0.07,
	   @12BetDate = 201209

select @HAIFAID = LicenseeID
FROM bodb_licensee.dbo.Licensees with (NOLOCK)
where LicenseeName = 'HAIFA'

select @12BetID = LicenseeID
FROM bodb_licensee.dbo.Licensees with (NOLOCK)
where LicenseeName = '12Bet'

CREATE TABLE #Result (  
	LicenseeID int,
	ReportType		VARCHAR(8),     
	
	TurnOver MONEY,   	
	CustomerWinlost	MONEY,  
	CommBA MONEY,   
	CommRB MONEY,
	Betcount BIGINT,
	LicensingFee MONEY,
	
	TurnOverMYR	MONEY,   	
	CustomerWinlostMYR MONEY,  
	CommBAMYR MONEY,   
	CommRBMYR MONEY,
	LicensingFeeMYR MONEY,
	
	TurnOverUSD	MONEY,   	
	CustomerWinlostUSD MONEY,  
	CommBAUSD MONEY,   
	CommRBUSD MONEY,
	LicensingFeeUSD MONEY,
	
	TurnOverEUR	MONEY,   	
	CustomerWinlostEUR MONEY,  
	CommBAEUR MONEY,   
	CommRBEUR MONEY,
	LicensingFeeEUR MONEY
)

CREATE TABLE #WinLoss (  
	LicenseeID 		INT,	
	ReportType		VARCHAR(6),     
	
	TurnOver		MONEY,   	
	Winlost			MONEY,  
	CommBA			MONEY,   
	CommRB		MONEY,   
	Betcount		BIGINT,
	
	TurnOverMYR		MONEY,   	
	WinlostMYR			MONEY,  
	CommBAMYR			MONEY,   
	CommRBMYR		MONEY,   
	
	TurnOverUSD		MONEY,   	
	WinlostUSD			MONEY,  
	CommBAUSD			MONEY,   
	CommRBUSD		MONEY,   
	
	TurnOverEUR		MONEY,   	
	WinlostEUR			MONEY,  
	CommBAEUR			MONEY,   
	CommRBEUR		MONEY
)

CREATE TABLE #Temp (  
	LicenseeID 		INT,	
	ReportType		INT,    
	Currency	INT, 
	
	TurnOver		MONEY,   	
	Winlost			MONEY,  
	CommBA			MONEY,   
	CommRB		MONEY,   
	Betcount		BIGINT
)

DECLARE  @tmpLicensee TABLE(LicenseeID INT)  
INSERT INTO @tmpLicensee (LicenseeID)   
SELECT l.LicenseeID
FROM bodb_Licensee.dbo.Licensees l (NOLOCK)
WHERE 
	l.LicenseeID IN (SELECT VAL FROM strSplit(@Licensee,','))  

DECLARE @Cutdate SMALLDATETIME
DECLARE @TempFromDate SMALLDATETIME 
DECLARE @TempToDate SMALLDATETIME 
DECLARE @_FromDate SMALLDATETIME , @_ToDate SMALLDATETIME

SELECT @_FromDate=@FromDate, @_ToDate=@ToDate
SET @Cutdate='2012-06-01'
	
CREATE TABLE #Exchange1 (ExchangeDate INT, ExchangeId INT, USD FLOAT, EUR FLOAT,MYR FLOAT, PRIMARY KEY(ExchangeDate,ExchangeId))	
CREATE TABLE #Exchange2 (ExchangeDate SMALLDATETIME, ExchangeId INT, USD FLOAT, EUR FLOAT,MYR FLOAT, PRIMARY KEY(ExchangeDate,ExchangeId))
	
IF @_ToDate >= @Cutdate --new data after 1/6/2012
BEGIN
	IF @_FromDate < @Cutdate 
		SET @TempFromDate =  @Cutdate
	ELSE
		SET @TempFromDate = @_FromDate	
	
	INSERT INTO #Exchange1(ExchangeDate,ExchangeId,USD,EUR,MYR)
	SELECT DISTINCT CONVERT(VARCHAR(6),ExchangeDate,112) ,ExchangeId,USD,EUR,MYR 
	FROM Lrf_f_GetExchangeDaily(@TempFromDate,@_ToDate)
	WHERE exchangeid IN (SELECT DISTINCT Currency FROM bodb_Licensee.dbo.LicenseeCust lc WITH (NOLOCK) WHERE 
		lc.LicenseeID IN (SELECT VAL FROM strSplit(@Licensee,',')))	
	
	--Case selected product is BA
	IF @ShowBA=1 
	BEGIN
		INSERT INTO #Temp  (LicenseeID ,ReportType,Currency,TurnOver,Winlost,CommBA,CommRB,Betcount)
		SELECT 
			b.siteID,
			CONVERT(VARCHAR(6),b.rptDate,112) ReportType,  
			b.currencyID,
			SUM(b.turnover
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
					     WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				) TurnOver,
			SUM(b.winloss) Winloss,
			SUM(b.CommissionA) as CommBA,
			0 as CommRB,
			SUM(betcount)
			* CASE WHEN @drawfilter = 2 AND b.status=111 THEN 0
					ELSE 1 END BetCount
		FROM 
			bodb_Licensee.dbo.rpt_Betting_BA b WITH ( NOLOCK ) 
			INNER JOIN @tmpLicensee ag ON ag.LicenseeID=b.SiteID
			LEFT JOIN dbo.League l (NOLOCK) ON b.leagueid=l.leagueid
		WHERE  
			b.rptDate  BETWEEN @TempFromDate AND @_ToDate 
			AND b.status NOT IN (-1,103)
			AND (@sportID=0 
				OR ( @sportID<>0  AND  l.sporttype=@sportID )
				)
			AND (@bettypeID=0 OR (@bettypeID<>0 AND b.bettype=@bettypeID))
			AND (@Currency=0 OR (@Currency<>0 AND b.CurrencyID=@Currency))  
			AND (@excludeTest=0 OR (@excludeTest=1 AND b.CurrencyID<>20)) 
		GROUP BY b.siteID,CONVERT(VARCHAR(6),b.rptDate,112) , status, currencyID
	END
	

	
	--exclude BA tickets
	IF (@showSB = 1 or @ShowRB = 1 or @ShowNG = 1 or @ShowLC = 1 or @ShowVS = 1 or @ShowCS=1)
	BEGIN
		INSERT INTO #Temp  (LicenseeID ,ReportType,Currency,TurnOver,Winlost,CommBA,CommRB,Betcount)
		SELECT 
			b.siteID,
			CONVERT(VARCHAR(6),b.rptDate,112)  ReportType,  
			b.currencyID,
			SUM(b.turnover
				*
				CASE WHEN b.bettype=33 AND b.status IN (114,115) THEN 0.5 ELSE 1 END
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
					     WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				) TurnOver,
			SUM(b.winloss) Winloss,	
			0 as CommBA,
			SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33   THEN b.CommissionA ELSE 0 END ) AS CommRB,
			SUM(b.betcount)
			* CASE WHEN @drawfilter = 2 AND b.status=111 THEN 0
				  ELSE 1 END BetCount
			
		FROM 
			bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK ) 
			INNER JOIN @tmpLicensee ag ON ag.LicenseeID=b.SiteID
			LEFT JOIN dbo.League l (NOLOCK) ON b.leagueid=l.leagueid
		WHERE  
			b.rptDate  BETWEEN @TempFromDate AND @_ToDate
			AND b.status NOT IN (-1,103)
			AND (@sportID=0 
				OR ( @sportID<>0  AND b.bettype NOT BETWEEN 31 AND 120 AND l.sporttype=@sportID )
				)
			AND (@bettypeID=0 OR (@bettypeID<>0 AND b.bettype=@bettypeID))
			AND (@Currency=0 OR (@Currency<>0 AND b.CurrencyID=@Currency))  
			AND (@excludeTest=0 OR (@excludeTest=1 AND b.CurrencyID<>20)) 
			AND ((@showSB=1 AND (b.bettype <31 OR b.bettype BETWEEN 121 AND 999))
				OR(@showRB=1 AND b.bettype BETWEEN 31 AND 33)
				OR(@showNG=1 AND b.bettype BETWEEN 81 AND 120)
				OR(@showLC=1 AND b.bettype BETWEEN 1101 AND 1199)
				OR(@showCS=1 AND b.bettype =71 ) -- RNG Casino
				OR(@showVS=1 AND b.bettype BETWEEN 1201 AND 1299)
				)	
		GROUP BY b.siteID, CONVERT(VARCHAR(6),b.rptDate,112) , b.status,b.currencyID
	END	
	
	INSERT INTO #WinLoss (LicenseeID,ReportType,TurnOver,Winlost,CommBA,CommRB,Betcount,
						  TurnOverMYR,WinlostMYR,CommBAMYR,CommRBMYR,
						  TurnOverUSD,WinlostUSD,CommBAUSD,CommRBUSD,
						  TurnOverEUR,WinlostEUR,CommBAEUR,CommRBEUR)
	SELECT
		LicenseeID ,ReportType,TurnOver,Winlost,CommBA,CommRB,Betcount,
		TurnOver * e.MYR TurnOverMYR,
		Winlost * e.MYR WinlostMYR,
		CommBA * e.MYR CommBAMYR,
		CommRB * e.MYR CommRBMYR,
		
		TurnOver * e.USD TurnOverUSD,
		Winlost * e.USD WinlostUSD,
		CommBA * e.USD CommBAUSD,
		CommRB * e.USD CommRBUSD,
		
		TurnOver * e.EUR TurnOverEUR,
		Winlost * e.EUR WinlostEUR,
		CommBA * e.EUR CommBAEUR,
		CommRB * e.EUR CommRBEUR
		
	FROM 	#Temp b
		LEFT JOIN #Exchange1 e  ON e.ExchangeDate = ReportType AND e.exchangeid = b.currency
	
END

IF @_FromDate < @Cutdate --Old data before 1/6/2012
BEGIN
	IF @_ToDate >= @Cutdate
			SET @TempToDate = DATEADD(DAY,-1,@Cutdate)
		ELSE
			SET  @TempToDate = @_ToDate

	INSERT INTO #Exchange2(ExchangeDate,ExchangeId,USD,EUR,MYR)
	SELECT ExchangeDate,ExchangeId,USD,EUR,MYR 
	FROM Lrf_f_GetExchangeDaily(@_FromDate,@TempToDate)
	WHERE exchangeid IN (SELECT DISTINCT Currency FROM bodb_Licensee.dbo.LicenseeCust lc WITH (NOLOCK) WHERE 
		lc.LicenseeID IN (SELECT VAL FROM strSplit(@Licensee,','))  )	
		
	IF @ShowBA=1 
	BEGIN
		INSERT INTO #WinLoss (LicenseeID,ReportType,TurnOver,Winlost,CommBA,CommRB,Betcount,
						      TurnOverMYR,WinlostMYR,CommBAMYR,CommRBMYR,
						      TurnOverUSD,WinlostUSD,CommBAUSD,CommRBUSD,
						      TurnOverEUR,WinlostEUR,CommBAEUR,CommRBEUR)
		SELECT 
			b.siteID,
			CONVERT(VARCHAR(6),b.rptDate,112) ReportType,  
			SUM(b.turnover
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
					     WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				) TurnOver,
			SUM(b.winloss) Winloss,
			SUM(b.CommissionA) as CommBA,
			0 as CommRB,
			SUM(betcount)
			* CASE WHEN @drawfilter = 2 AND b.status=111 THEN 0
					ELSE 1 END BetCount,
			
			--MYR
			SUM(b.turnover
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
					     WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				* e.MYR
				) TurnOverMYR,
			SUM(b.winloss * e.MYR) WinlossMYR,
			SUM(b.CommissionA * e.MYR) as CommBAMYR,
			0 as CommRBMYR,
								
			--USD
			SUM(b.turnover
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
					     WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				* e.USD
				) TurnOverUSD,
			SUM(b.winloss * e.USD) WinlossUSD,
			SUM(b.CommissionA * e.USD) as CommBAUSD,
			0 as CommRBUSD,
						
			--EUR
			SUM(b.turnover
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
					     WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				* e.EUR
				) TurnOverEUR,
			SUM(b.winloss * e.EUR) WinlossEUR,
			SUM(b.CommissionA * e.EUR) as CommBAEUR,
			0 as CommRBEUR						
		FROM 
			bodb_Licensee.dbo.rpt_Betting_BA b WITH ( NOLOCK ) 
			INNER JOIN @tmpLicensee ag ON ag.LicenseeID=b.SiteID
			LEFT JOIN dbo.League l (NOLOCK) ON b.leagueid=l.leagueid
			LEFT JOIN #Exchange2 e  ON e.ExchangeDate = b.rptDate AND e.exchangeid = b.currencyID
		WHERE  
			b.rptDate  BETWEEN @_FromDate AND @TempToDate 
			AND b.status NOT IN (-1,103)
			AND (@sportID=0 
				OR ( @sportID<>0  AND  l.sporttype=@sportID )
				)
			AND (@bettypeID=0 OR (@bettypeID<>0 AND b.bettype=@bettypeID))
			AND (@Currency=0 OR (@Currency<>0 AND b.CurrencyID=@Currency))  
			AND (@excludeTest=0 OR (@excludeTest=1 AND b.CurrencyID<>20)) 
		GROUP BY b.siteID,CONVERT(VARCHAR(6),b.rptDate,112) , status
	END
	
	--exclude BA tickets
	IF (@showSB = 1 or @ShowRB = 1 or @ShowNG = 1 or @ShowLC = 1 or @ShowVS = 1 OR @ShowCS=1)
	BEGIN
		INSERT INTO #WinLoss  
		SELECT 
			b.siteID,
			CONVERT(VARCHAR(6),b.rptDate,112)  ReportType,  
			
			SUM(b.turnover
				*
				CASE WHEN b.bettype=33 AND b.status IN (114,115) THEN 0.5 ELSE 1 END
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
					     WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				) TurnOver,
			SUM(b.winloss) Winloss,	
			0 as CommBA,
			SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33   THEN b.CommissionA ELSE 0 END ) AS CommRB,
			SUM(b.betcount)
			* CASE WHEN @drawfilter = 2 AND b.status=111 THEN 0
				  ELSE 1 END BetCount,
			
			--MYR
			SUM(b.turnover
				*
				CASE WHEN b.bettype=33 AND b.status IN (114,115) THEN 0.5 ELSE 1 END
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
					     WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				* e.MYR	
				) TurnOverMYR,
			SUM(b.winloss * e.MYR) WinlossMYR,	
			0 as CommBAMYR,
			SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33   THEN b.CommissionA ELSE 0 END * e.MYR) AS CommRBMYR,
			
			--USD
			SUM(b.turnover
				*
				CASE WHEN b.bettype=33 AND b.status IN (114,115) THEN 0.5 ELSE 1 END
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
					     WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				* e.USD	
				) TurnOverUSD,
			SUM(b.winloss * e.USD) WinlossUSD,	
			0 as CommBAUSD,
			SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33   THEN b.CommissionA ELSE 0 END * e.USD) AS CommRBUSD,
						
			--EUR
			SUM(b.turnover
				*
				CASE WHEN b.bettype=33 AND b.status IN (114,115) THEN 0.5 ELSE 1 END
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
					     WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				* e.EUR	
				) TurnOverEUR,
			SUM(b.winloss * e.EUR) WinlossEUR,	
			0 as CommBAEUR,
			SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33   THEN b.CommissionA ELSE 0 END * e.EUR) AS CommRBEUR				  
		FROM 
			bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK ) 
			INNER JOIN @tmpLicensee ag ON ag.LicenseeID=b.SiteID
			LEFT JOIN dbo.League l (NOLOCK) ON b.leagueid=l.leagueid
			LEFT JOIN #Exchange2 e  ON e.ExchangeDate = b.rptDate AND e.exchangeid = b.currencyID
		WHERE  
			b.rptDate  BETWEEN @_FromDate AND @TempToDate  
			AND b.status NOT IN (-1,103)
			AND (@sportID=0 
				OR ( @sportID<>0  AND b.bettype NOT BETWEEN 31 AND 120 AND l.sporttype=@sportID )
				)
			AND (@bettypeID=0 OR (@bettypeID<>0 AND b.bettype=@bettypeID))
			AND (@Currency=0 OR (@Currency<>0 AND b.CurrencyID=@Currency))  
			AND (@excludeTest=0 OR (@excludeTest=1 AND b.CurrencyID<>20)) 
			AND ( (@showSB=1 AND (b.bettype <31 OR b.bettype BETWEEN 121 AND 999))
				OR(@showRB=1 AND b.bettype BETWEEN 31 AND 33)
				OR(@showNG=1 AND b.bettype BETWEEN 81 AND 120)
				OR(@showLC=1 AND b.bettype BETWEEN 1101 AND 1199)
				OR(@showVS=1 AND b.bettype BETWEEN 1201 AND 1299)
				OR(@showCS=1 AND b.bettype =71)
				)	
		GROUP BY b.siteID, CONVERT(VARCHAR(6),b.rptDate,112) , b.status
	END	
		
END	

insert INTO #Result	
	SELECT   
		w.LicenseeID,
		w.ReportType,  
		SUM(TurnOver) AS Turnover,   
		SUM(Winlost) AS CustomerWinlost,  
		SUM(CommBA) AS CommBA,
		SUM(CommRB) AS CommRB,
		SUM(Betcount) AS Betcount,
		--Licensee Fee Hard-Code calculating
		CASE 
			WHEN @ShowSB = 1 THEN -SUM(Winlost) * @RateSB
			WHEN @ShowVS = 1 THEN -SUM(Winlost) * @RateVS
			WHEN @ShowLC = 1 THEN -SUM(Winlost) * @RateLC
			WHEN @ShowCS = 1 THEN -SUM(Winlost) * @RateCS
			WHEN @ShowNG = 1 THEN CASE WHEN w.LicenseeID = @HAIFAID THEN -SUM(Winlost) * @RateNGHAIFA
								       WHEN w.LicenseeID = @12BetID AND cast(w.ReportType AS int) < @12BetDate THEN -SUM(Winlost) * @RateNG12Bet
								       ELSE -SUM(Winlost) * @RateNG 
								       END
			ELSE 0
			END
		 AS LicensingFee,

	 --BaseRM  
		SUM(TurnOverMYR)	AS TurnoverMYR,   
		SUM(WinlostMYR)		AS CustomerWinlostMYR,  
		SUM(CommBAMYR) AS CommBAMYR,
		SUM(CommRBMYR) AS CommRBMYR,
		--Licensee Fee Hard-Code calculating
		CASE 
			WHEN @ShowSB = 1 THEN -SUM(WinlostMYR) * @RateSB
			WHEN @ShowVS = 1 THEN -SUM(WinlostMYR) * @RateVS
			WHEN @ShowLC = 1 THEN -SUM(WinlostMYR) * @RateLC
			WHEN @ShowCS = 1 THEN -SUM(WinlostMYR) * @RateCS
			WHEN @ShowNG = 1 THEN CASE WHEN w.LicenseeID = @HAIFAID THEN -SUM(WinlostMYR) * @RateNGHAIFA
								       WHEN w.LicenseeID = @12BetID AND cast(w.ReportType AS int) < @12BetDate THEN -SUM(WinlostMYR) * @RateNG12Bet
								       ELSE -SUM(WinlostMYR) * @RateNG 
								       END
			ELSE 0
			END
		 AS LicensingFeeMYR,

	--BaseUSD  
		SUM(TurnOverUSD)	AS TurnoverUSD,   
		SUM(WinlostUSD)		AS CustomerWinlostUSD,  
		SUM(CommBAUSD) AS CommBAUSD,
		SUM(CommRBUSD) AS CommRBUSD,
		--Licensee Fee Hard-Code calculating
		CASE 
			WHEN @ShowSB = 1 THEN -SUM(WinlostUSD) * @RateSB
			WHEN @ShowVS = 1 THEN -SUM(WinlostUSD) * @RateVS
			WHEN @ShowLC = 1 THEN -SUM(WinlostUSD) * @RateLC
			WHEN @ShowCS = 1 THEN -SUM(WinlostUSD) * @RateCS
			WHEN @ShowNG = 1 THEN CASE WHEN w.LicenseeID = @HAIFAID THEN -SUM(WinlostUSD) * @RateNGHAIFA
								       WHEN w.LicenseeID = @12BetID AND cast(w.ReportType AS int) < @12BetDate THEN -SUM(WinlostUSD) * @RateNG12Bet
								       ELSE -SUM(WinlostUSD) * @RateNG 
								       END
			ELSE 0
			END
		 AS LicensingFeeUSD,

	--BaseEUR  
		SUM(TurnOverEUR)	AS TurnoverEUR,   
		SUM(WinlostEUR)		AS CustomerWinlostEUR,  
		SUM(CommBAEUR) AS CommBAEUR,
		SUM(CommRBEUR) AS CommRBEUR,
		--Licensee Fee Hard-Code calculating
		CASE 
			WHEN @ShowSB = 1 THEN -SUM(WinlostEUR) * @RateSB
			WHEN @ShowVS = 1 THEN -SUM(WinlostEUR) * @RateVS
			WHEN @ShowLC = 1 THEN -SUM(WinlostEUR) * @RateLC
			WHEN @ShowCS = 1 THEN -SUM(WinlostEUR) * @RateCS
			WHEN @ShowNG = 1 THEN CASE WHEN w.LicenseeID = @HAIFAID THEN -SUM(WinlostEUR) * @RateNGHAIFA
								       WHEN w.LicenseeID = @12BetID AND cast(w.ReportType AS int) < @12BetDate THEN -SUM(WinlostEUR) * @RateNG12Bet
								       ELSE -SUM(WinlostEUR) * @RateNG 
								       END
			ELSE 0
			END
		 AS LicensingFeeEUR
	FROM	
		#WinLoss w
	GROUP BY w.ReportType, w.LicenseeID
	ORDER BY w.ReportType, w.LicenseeID

update #Result
	SET LicensingFee = 0, LicensingFeeMYR = 0, LicensingFeeUSD = 0, LicensingFeeEUR = 0
	WHERE LicensingFee < 0

select CAST((ReportType + '01') AS date) AS [DateTime],
	SUM(TurnOver) AS TurnOver,   	
	SUM(CustomerWinlost) AS CustomerWinlost,  
	SUM(CommBA) AS AmtDueToBA,   
	SUM(CommRB) AS AmtDueToRB,
	SUM(Betcount)AS BetCount,
	CASE WHEN SUM(LicensingFee) < 0 THEN 0
		 ELSE SUM(LicensingFee)
		 END
		 AS LicensingFee,
	
	SUM(TurnOverMYR) AS TurnOverMYR,   	
	SUM(CustomerWinlostMYR) AS CustomerWinlostMYR,  
	SUM(CommBAMYR) AS AmtDueToBAMYR,   
	SUM(CommRBMYR) AS AmtDueToRBMYR,
	CASE WHEN SUM(LicensingFeeMYR) < 0 THEN 0
		 ELSE SUM(LicensingFeeMYR)
		 END
	AS LicensingFeeMYR,
	
	SUM(TurnOverUSD) AS TurnOverUSD,   	
	SUM(CustomerWinlostUSD) AS CustomerWinlostUSD,  
	SUM(CommBAUSD) AS AmtDueToBAUSD,   
	SUM(CommRBUSD) AS AmtDueToRBUSD,
	CASE WHEN SUM(LicensingFeeUSD) < 0 THEN 0
		 ELSE SUM(LicensingFeeUSD)
		 END
	AS LicensingFeeUSD,
	
	SUM(TurnOverEUR) AS TurnOverEUR,   	
	SUM(CustomerWinlostEUR) AS CustomerWinlostEUR,  
	SUM(CommBAEUR) AS AmtDueToBAEUR,   
	SUM(CommRBEUR) AS AmtDueToRBEUR,
	CASE WHEN SUM(LicensingFeeEUR) < 0 THEN 0
		 ELSE SUM(LicensingFeeEUR)
		 END
	AS LicensingFeeEUR
	   
from #Result
GROUP BY ReportType
ORDER BY ReportType ASC


DROP TABLE #Result
DROP TABLE #WinLoss
DROP TABLE #Exchange1
DROP TABLE #Exchange2
DROP TABLE #Temp

END