ALTER  PROCEDURE [dbo].[OA_Rpt_LicWinloss_Summary2]  
 @Licensee	VARCHAR(1000),
 @Currency		INT = 0,
 @FromDate		SMALLDATETIME,  
 @ToDate		SMALLDATETIME,   
 @showSB		BIT=1,  
 @ShowRB		BIT=0,  
 @ShowNG		BIT=0, 
 @ShowBA		BIT=0,
 @ShowLC		BIT=0,
 @ShowVS		BIT=0,
 @SportID		INT=0,
 @BettypeID		INT=0,
 @ReportType	TINYINT=1,  
 @MoveBetsDay SMALLDATETIME,
 @drawfilter SMALLINT = 1  ,
 @excludeTest BIT = 0
AS  
/*  Created:  Jim
	Date: 2012-12-12
    Original:OA_Rpt_LicWinloss_Summary
	Task : LicenseeAdmin - Add sports+bet types filter to Licensee Winloss reports 
    DB: DB052.bodb02  
   
    Revisions:  
	20121231@Henry: Enhance Performance
	Param's Explanation:  
	  + @Licensee : a string of list LicenseeID,separate by ','
	  + @Currency :  0- All Currencies
	  + @ReportType: 1-Daily; 2-Monthly;  
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS
	  + @showSB: Show SportsBook bets
	  + @ShowRB: Show RB bets
	  + @ShowNG: Show Number game bets
	  + @ShowBA: Show Bet Aggregator bets (combined with Sportsbook or Number Game)
	  + @ShowLC: Show Live casino
	  + @ShowVS: Show Virtual Sports
	  +@SportID :
			0  : selected all sporttype 
	  +@BettypeID : 
			0: selected all bettype
	  + @MoveBetsDay: The day we move tickets to bettrans14
*/  
BEGIN  
SET NOCOUNT ON  

SET @ReportType=2 -- only allow monthly  


----DECLARE  	

CREATE TABLE #WinLoss (  
	LicenseeID 		INT,	
	ReportType		VARCHAR(6),     
	
	TurnOver		MONEY,   	
	Winlost			MONEY,  
	LicenseeWL		MONEY, 
	WinlossRB		MONEY,
	AmtDueToBA	MONEY,   
	AmtDueToRB	MONEY,
	CommBA			MONEY,   
	CommRB		MONEY,   
	Company		MONEY,
	Playercomm	MONEY,
	Betcount		BIGINT,
	
	TurnOverMYR		MONEY,   	
	WinlostMYR			MONEY,  
	LicenseeWLMYR		MONEY, 
	WinlossRBMYR		MONEY,
	AmtDueToBAMYR	MONEY,   
	AmtDueToRBMYR	MONEY,
	CommBAMYR			MONEY,   
	CommRBMYR		MONEY,   
	CompanyMYR		MONEY,
	PlayercommMYR	MONEY,
	
	TurnOverUSD		MONEY,   	
	WinlostUSD			MONEY,  
	LicenseeWLUSD		MONEY, 
	WinlossRBUSD		MONEY,
	AmtDueToBAUSD	MONEY,   
	AmtDueToRBUSD	MONEY,
	CommBAUSD			MONEY,   
	CommRBUSD		MONEY,   
	CompanyUSD		MONEY,
	PlayercommUSD	MONEY,
	
	TurnOverEUR		MONEY,   	
	WinlostEUR			MONEY,  
	LicenseeWLEUR		MONEY, 
	WinlossRBEUR		MONEY,
	AmtDueToBAEUR	MONEY,   
	AmtDueToRBEUR	MONEY,
	CommBAEUR			MONEY,   
	CommRBEUR		MONEY,   
	CompanyEUR		MONEY,
	PlayercommEUR	MONEY
)

CREATE TABLE #Temp (  
	LicenseeID 		INT,	
	ReportType		INT,    
	Currency	INT, 
	
	TurnOver		MONEY,   	
	Winlost			MONEY,  
	LicenseeWL		MONEY, 
	WinlossRB		MONEY,
	AmtDueToBA	MONEY,   
	AmtDueToRB	MONEY,
	CommBA			MONEY,   
	CommRB		MONEY,   
	Company		MONEY,
	Playercomm	MONEY,
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
		lc.LicenseeID IN (SELECT VAL FROM strSplit(@Licensee,','))  )	
	
	IF @ShowBA=1 
	BEGIN
		INSERT INTO #Temp  (LicenseeID ,ReportType,Currency,TurnOver,Winlost,LicenseeWL,WinlossRB,AmtDueToBA,AmtDueToRB,CommBA,CommRB,Company,Playercomm,Betcount)
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
			0 as LicenseeWL,
			0 AS WinlossRB,
			- SUM(b.winloss+b.winlossA+	b.CommissionA)as AmountDueToBA,
			0 as AmountDueToRB,
			SUM(b.CommissionA) as CommBA,
			0 as CommRB,
			0 as Company,
			SUM(commissionP) AS Playercomm,
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
	IF (@showSB = 1 or @ShowRB = 1 or @ShowNG = 1 or @ShowLC = 1 or @ShowVS = 1)
	BEGIN
		INSERT INTO #Temp  (LicenseeID ,ReportType,Currency,TurnOver,Winlost,LicenseeWL,WinlossRB,AmtDueToBA,AmtDueToRB,CommBA,CommRB,Company,Playercomm,Betcount)
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
			-SUM(CASE WHEN (b.Bettype NOT BETWEEN 31 AND 33) THEN b.winloss ELSE 0 END) AS LicenseeWL,
			SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33  THEN b.winlossA ELSE 0 END) AS WinlossRB,
			0 as AmountDueToBA,
			-SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33 THEN (b.winloss+b.winlossA+	b.CommissionA) ELSE 0 END ) AS AmountDueToRB,
			0 as CommBA,
			SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33   THEN b.CommissionA ELSE 0 END ) AS CommRB,
			-SUM(CASE WHEN b.bettype  NOT BETWEEN 31 AND 33  THEN (b.winloss+b.winlossA+ b.CommissionA) ELSE 0 END ) AS Company,
			
			SUM(commissionP) AS Playercomm,
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
			AND ( (@showSB=1 AND (b.bettype <31 OR b.bettype BETWEEN 121 AND 999))
				OR(@showRB=1 AND b.bettype BETWEEN 31 AND 33)
				OR(@showNG=1 AND b.bettype BETWEEN 81 AND 120)
				OR(@showLC=1 AND b.bettype BETWEEN 1101 AND 1199)
				OR(@showVS=1 AND b.bettype BETWEEN 1201 AND 1299)
				)	
		GROUP BY b.siteID, CONVERT(VARCHAR(6),b.rptDate,112) , b.status,b.currencyID
	END	
	
	INSERT INTO #WinLoss
	SELECT
		LicenseeID ,ReportType,TurnOver,Winlost,LicenseeWL,WinlossRB,AmtDueToBA,AmtDueToRB,CommBA,CommRB,Company,Playercomm,Betcount,
		TurnOver * e.MYR TurnOverMYR,
		Winlost * e.MYR WinlostMYR,
		LicenseeWL * e.MYR LicenseeWLMYR,
		WinlossRB * e.MYR WinlossRBMYR,
		AmtDueToBA * e.MYR AmtDueToBAMYR,
		AmtDueToRB * e.MYR AmtDueToRBMYR,
		CommBA * e.MYR CommBAMYR,
		CommRB * e.MYR CommRBMYR,
		Company * e.MYR CompanyMYR,
		Playercomm * e.MYR PlayercommMYR,
		
		TurnOver * e.USD TurnOverUSD,
		Winlost * e.USD WinlostUSD,
		LicenseeWL * e.USD LicenseeWLUSD,
		WinlossRB * e.USD WinlossRBUSD,
		AmtDueToBA * e.USD AmtDueToBAUSD,
		AmtDueToRB * e.USD AmtDueToRBUSD,
		CommBA * e.USD CommBAUSD,
		CommRB * e.USD CommRBUSD,
		Company * e.USD CompanyUSD,
		Playercomm * e.USD PlayercommUSD,
		
		TurnOver * e.EUR TurnOverEUR,
		Winlost * e.EUR WinlostEUR,
		LicenseeWL * e.EUR LicenseeWLEUR,
		WinlossRB * e.EUR WinlossRBEUR,
		AmtDueToBA * e.EUR AmtDueToBAEUR,
		AmtDueToRB * e.EUR AmtDueToRBEUR,
		CommBA * e.EUR CommBAEUR,
		CommRB * e.EUR CommRBEUR,
		Company * e.EUR CompanyEUR,
		Playercomm * e.EUR PlayercommEUR
		
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
		INSERT INTO #WinLoss  
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
			0 as LicenseeWL,
			0 AS WinlossRB,
			- SUM(b.winloss+b.winlossA+	b.CommissionA)as AmountDueToBA,
			0 as AmountDueToRB,
			SUM(b.CommissionA) as CommBA,
			0 as CommRB,
			0 as Company,
			SUM(commissionP) AS Playercomm,
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
			0 as LicenseeWLMYR,
			0 AS WinlossRBMYR,
			- SUM((b.winloss+b.winlossA+	b.CommissionA)*e.MYR ) as AmountDueToBAMYR,
			0 as AmountDueToRBMYR,
			SUM(b.CommissionA * e.MYR) as CommBAMYR,
			0 as CommRBMYR,
			0 as CompanyMYR,
			SUM(commissionP * e.MYR) AS PlayercommMYR,		
					
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
			0 as LicenseeWLUSD,
			0 AS WinlossRBUSD,
			- SUM((b.winloss+b.winlossA+	b.CommissionA)*e.USD ) as AmountDueToBAUSD,
			0 as AmountDueToRBUSD,
			SUM(b.CommissionA * e.USD) as CommBAUSD,
			0 as CommRBUSD,
			0 as CompanyUSD,
			SUM(commissionP * e.USD) AS PlayercommUSD,		
			
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
			0 as LicenseeWLEUR,
			0 AS WinlossRBEUR,
			- SUM((b.winloss+b.winlossA+	b.CommissionA)*e.EUR ) as AmountDueToBAEUR,
			0 as AmountDueToRBEUR,
			SUM(b.CommissionA * e.EUR) as CommBAEUR,
			0 as CommRBEUR,
			0 as CompanyEUR,
			SUM(commissionP * e.EUR) AS PlayercommEUR
					
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
	IF (@showSB = 1 or @ShowRB = 1 or @ShowNG = 1 or @ShowLC = 1 or @ShowVS = 1)
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
			-SUM(CASE WHEN (b.Bettype NOT BETWEEN 31 AND 33) THEN b.winloss ELSE 0 END) AS LicenseeWL,
			SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33  THEN b.winlossA ELSE 0 END) AS WinlossRB,
			0 as AmountDueToBA,
			-SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33 THEN (b.winloss+b.winlossA+	b.CommissionA) ELSE 0 END ) AS AmountDueToRB,
			0 as CommBA,
			SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33   THEN b.CommissionA ELSE 0 END ) AS CommRB,
			-SUM(CASE WHEN b.bettype  NOT BETWEEN 31 AND 33  THEN (b.winloss+b.winlossA+ b.CommissionA) ELSE 0 END ) AS Company,
			
			SUM(commissionP) AS Playercomm,
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
			-SUM(CASE WHEN (b.Bettype NOT BETWEEN 31 AND 33) THEN b.winloss ELSE 0 END * e.MYR) AS LicenseeWLMYR,
			SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33  THEN b.winlossA ELSE 0 END * e.MYR) AS WinlossRBMYR,
			0 as AmountDueToBAMYR,
			-SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33 THEN (b.winloss+b.winlossA+	b.CommissionA) ELSE 0 END * e.MYR) AS AmountDueToRBMYR,
			0 as CommBAMYR,
			SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33   THEN b.CommissionA ELSE 0 END * e.MYR) AS CommRBMYR,
			-SUM(CASE WHEN b.bettype  NOT BETWEEN 31 AND 33  THEN (b.winloss+b.winlossA+ b.CommissionA) ELSE 0 END * e.MYR) AS CompanyMYR,
			
			SUM(commissionP * e.MYR) AS PlayercommMYR,	  
			
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
			-SUM(CASE WHEN (b.Bettype NOT BETWEEN 31 AND 33) THEN b.winloss ELSE 0 END * e.USD) AS LicenseeWLUSD,
			SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33  THEN b.winlossA ELSE 0 END * e.USD) AS WinlossRBUSD,
			0 as AmountDueToBAUSD,
			-SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33 THEN (b.winloss+b.winlossA+	b.CommissionA) ELSE 0 END * e.USD) AS AmountDueToRBUSD,
			0 as CommBAUSD,
			SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33   THEN b.CommissionA ELSE 0 END * e.USD) AS CommRBUSD,
			-SUM(CASE WHEN b.bettype  NOT BETWEEN 31 AND 33  THEN (b.winloss+b.winlossA+ b.CommissionA) ELSE 0 END * e.USD) AS CompanyUSD,
			
			SUM(commissionP * e.USD) AS PlayercommUSD,	  
			
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
			-SUM(CASE WHEN (b.Bettype NOT BETWEEN 31 AND 33) THEN b.winloss ELSE 0 END * e.EUR) AS LicenseeWLEUR,
			SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33  THEN b.winlossA ELSE 0 END * e.EUR) AS WinlossRBEUR,
			0 as AmountDueToBAEUR,
			-SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33 THEN (b.winloss+b.winlossA+	b.CommissionA) ELSE 0 END * e.EUR) AS AmountDueToRBEUR,
			0 as CommBAEUR,
			SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33   THEN b.CommissionA ELSE 0 END * e.EUR) AS CommRBEUR,
			-SUM(CASE WHEN b.bettype  NOT BETWEEN 31 AND 33  THEN (b.winloss+b.winlossA+ b.CommissionA) ELSE 0 END * e.EUR) AS CompanyEUR,
			
			SUM(commissionP * e.EUR) AS PlayercommEUR  
				  
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
				)	
		GROUP BY b.siteID, CONVERT(VARCHAR(6),b.rptDate,112) , b.status
	END	
		
END	
	


SELECT   
	w.LicenseeID,
	l.LicenseeName,
	w.ReportType,  
	SUM(TurnOver)	AS Turnover,   
	SUM(Winlost)		AS Winlost,  
	SUM(LicenseeWL) AS LicenseeWL,
	SUM(WinlossRB)	AS WinlossRB,
	SUM(CommBA) AS CommBA,
	SUM(CommRB) AS CommRB,
	SUM(AmtDuetoBA) AS AmtDuetoBA,
	SUM(AmtDuetoRB) AS AmtDuetoRB,
	SUM(Company) AS Company,
	SUM(Betcount)	AS Betcount,
	SUM(Playercomm) AS Playercomm,

	--BaseRM  
	SUM(TurnOverMYR)	AS TurnoverMYR,   
	SUM(WinlostMYR)		AS WinlostMYR,  
	SUM(LicenseeWLMYR) AS LicenseeWLMYR,
	SUM(WinlossRBMYR)	AS WinlossRBMYR,
	SUM(CommBAMYR) AS CommBAMYR,
	SUM(CommRBMYR) AS CommRBMYR,
	SUM(AmtDuetoBAMYR) AS AmtDuetoBAMYR,
	SUM(AmtDuetoRBMYR) AS AmtDuetoRBMYR,
	SUM(CompanyMYR) AS CompanyMYR,
	SUM(PlayercommMYR) AS PlayercommMYR,

	--BaseUSD  
	SUM(TurnOverUSD)	AS TurnoverUSD,   
	SUM(WinlostUSD)		AS WinlostUSD,  
	SUM(LicenseeWLUSD) AS LicenseeWLUSD,
	SUM(WinlossRBUSD)	AS WinlossRBUSD,
	SUM(CommBAUSD) AS CommBAUSD,
	SUM(CommRBUSD) AS CommRBUSD,
	SUM(AmtDuetoBAUSD) AS AmtDuetoBAUSD,
	SUM(AmtDuetoRBUSD) AS AmtDuetoRBUSD,
	SUM(CompanyUSD) AS CompanyUSD,
	SUM(PlayercommUSD) AS PlayercommUSD,

	--BaseEUR  
	SUM(TurnOverEUR)	AS TurnoverEUR,   
	SUM(WinlostEUR)		AS WinlostEUR,  
	SUM(LicenseeWLEUR) AS LicenseeWLEUR,
	SUM(WinlossRBEUR)	AS WinlossRBEUR,
	SUM(CommBAEUR) AS CommBAEUR,
	SUM(CommRBEUR) AS CommRBEUR,
	SUM(AmtDuetoBAEUR) AS AmtDuetoBAEUR,
	SUM(AmtDuetoRBEUR) AS AmtDuetoRBEUR,
	SUM(CompanyEUR) AS CompanyEUR,
	SUM(PlayercommEUR) AS PlayercommEUR
FROM	
	#WinLoss w
	INNER JOIN bodb_Licensee.dbo.Licensees l (NOLOCK) ON l.LicenseeID = w.LicenseeID
GROUP BY   
	w.LicenseeID,
	l.LicenseeName,
	w.ReportType
ORDER BY l.LicenseeName,ReportType

DROP TABLE #WinLoss
DROP TABLE #Exchange1
DROP TABLE #Exchange2
DROP TABLE #Temp

END   
GO
GRANT EXECUTE ON [dbo].[OA_Rpt_LicWinloss_Summary2] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_Rpt_LicWinloss_Summary2]TO [vnteam]  

