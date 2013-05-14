ALTER  PROCEDURE [dbo].[OA_Rpt_LicWinloss_Summary]  
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
 @ReportType	TINYINT=1,  
 @MoveBetsDay SMALLDATETIME,
 @IsOld BIT = 0,
 @drawfilter SMALLINT = 1  ,
 @excludeTest BIT = 0
AS  
/*  Created:  Jim
	Date: 2012-05-14
    Original:OA_Rpt_LicWinloss
	Task : Enhance Licensee Win Loss Report
    DB: DB052.bodb02  
   
    Revisions:  
	- 20120528@Henry: Enhance performance
	- 20120803@Henry: fix the commission formula
	- 20120815@Henry: add live casino
	- 20120905@Henry: add Virtual Sports
	- 20121128@Henry: use new table LicenseeBATransaction_active to get bettrans BA tickets
	Param's Explanation:  
	  + @Licensee : a string of list LicenseeID,separate by ','
	  + @Currency :  0- All Currencies
	  + @ReportType: 1-Daily; 2-Monthly;  
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @IsOld: 0 - query in table rptLicWinloss, 1 - query in table rptLicWinloss_old. 
	  + @excludeTest: remove currency UUS
	  + @showSB: Show SportsBook bets
	  + @ShowRB: Show RB bets
	  + @ShowNG: Show Number game bets
	  + @ShowBA: Show Bet Aggregator bets (combined with Sportsbook or Number Game)
	  + @ShowLC: Show Live casino
	  + @ShowVS: Show Virtual Sports
	  + @MoveBetsDay: The day we move tickets to bettrans14
*/  
BEGIN  
SET NOCOUNT ON  

CREATE TABLE #SAgWinLoss (  
	LicenseeID 		INT,	
	winlostdate		DATETIME,     
	Currency		INT,
	TurnOver		MONEY,   	
	Winlost			MONEY,  
	LicenseeWL		MONEY, 
	WinlossRB		MONEY,
	AmtDueToBA	MONEY,   
	AmtDueToRB	MONEY,
	CommBA			MONEY,   
	CommRB		MONEY,   
	Company		MONEY,
	Betcount		BIGINT,
	Playercomm	MONEY
)  

----DECLARE  	
DECLARE  @TempAg TABLE( custID INT  PRIMARY KEY,LicenseeID INT,currency int)  
DECLARE @VNDCurrencyName VARCHAR(20)
DECLARE @site TABLE (site VARCHAR(50))
DECLARE  @bettype TABLE(bettype INT PRIMARY KEY  )
DECLARE  @sporttype TABLE(sporttype INT PRIMARY KEY)

SELECT @VNDCurrencyName = currency FROM exchange (NOLOCK) WHERE ExchangeId = 51


DECLARE @Super TABLE(custid int , currency int, licenseeid int)
INSERT INTO @Super(custid,currency,licenseeid)  
SELECT 
	CustID,currency,l.licenseeid 
FROM Dep_CustSuper s WITH (NOLOCK)  
	INNER JOIN bodb_Licensee.dbo.Licensees l (NOLOCK) ON l.licenseename = s.site
WHERE  
	l.LicenseeID IN (SELECT VAL FROM strSplit(@Licensee,','))
	AND (@Currency=0 OR (@Currency<>0 AND Currency=@Currency))
	AND (@excludeTest=0 OR (@excludeTest=1 AND Currency<>20))

INSERT INTO @TempAg (custID,LicenseeID,currency)   
SELECT 
	lc.custID,lc.LicenseeID  ,lc.currency 
FROM 
	bodb_Licensee.dbo.LicenseeCust lc (NOLOCK)   
	INNER JOIN bodb_Licensee.dbo.Licensees l (NOLOCK) ON lc.LicenseeID=l.LicenseeID   
WHERE 
	lc.LicenseeID IN (SELECT VAL FROM strSplit(@Licensee,','))  
	AND (@Currency=0 OR (@Currency<>0 AND Currency=@Currency))  
	AND (@excludeTest=0 OR (@excludeTest=1 AND Currency<>20)) 

IF @ShowSB = 1  
BEGIN  
	INSERT  INTO @sporttype( sporttype)
    VALUES  (0)	
	
END  

IF @ShowRB = 1  
BEGIN  
	INSERT  INTO @sporttype( Sporttype)
    VALUES  (151)
END  

IF @ShowNG = 1
BEGIN
	INSERT INTO @sporttype(Sporttype)  
	VALUES(161)  
	
	INSERT INTO @bettype(bettype)
	SELECT typeid FROM bettype (NOLOCK)
	WHERE (typeid BETWEEN 81 AND 120)
END  

IF @ShowLC = 1
BEGIN
	INSERT  INTO @sporttype( Sporttype)
    VALUES  (162)
    
    INSERT INTO @bettype(bettype)
	SELECT typeid FROM bettype (NOLOCK)
	WHERE (typeid BETWEEN 1101 AND 1199)
END

IF @ShowVS = 1
BEGIN
	INSERT  INTO @sporttype( Sporttype)
    VALUES  (180)
    
    INSERT INTO @bettype(bettype)
	SELECT typeid FROM bettype (NOLOCK)
	WHERE (typeid BETWEEN 1201 AND 1299)
END

DECLARE @TempFromDate DATETIME 
DECLARE @TempToDate DATETIME 
DECLARE @MaxOldDate DATETIME
DECLARE @FDate SMALLDATETIME  
DECLARE @TDate SMALLDATETIME 
	
--to Deal With Parameter Sniffing
SELECT @FDate=@FromDate,@TDate=@ToDate 

--BEGIN GET DATA INTO #SAgWinLoss  
IF @TDate > @MoveBetsDay
BEGIN
	IF @FDate <= @MoveBetsDay 
		SET @TempFromDate =  DATEADD(DAY,1,@MoveBetsDay)
	ELSE
		SET @TempFromDate = @FDate
	
	
	IF @ShowBA=1 
	BEGIN
		INSERT INTO #SAgWinLoss  
		SELECT   
			s.LicenseeID,
			b.winlostdate,  
			s.currency,
			SUM( stake
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (b.statusID = 112 OR b.statusID = 113)  AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			) turnover, 
			SUM(b.winlost - b.actual_stake) AS Winlost,  
			0 as LicenseeWL,
			0 as WinlossRB,
			- SUM (b.winlost - b.actual_stake + awinlost + comm  ) as AmountDueToBA,
			0 as AmountDueToRB,
			SUM (comm) as CommBA,
			0 as CommRB,
			0 as Company,
			COUNT(b.transid)
			* CASE WHEN @drawfilter = 2  AND b.statusID=111 THEN 0 
					ELSE 1 END BetCount	,
			sum(playercomm) AS Playercomm		
		FROM 
			dbo.bettrans b WITH ( NOLOCK,INDEX=IX_srecommend)    
			INNER JOIN @TempAg a ON b.recommend = a.custid
			INNER JOIN @Super s ON b.srecommend = s.custid
			INNER JOIN bodb_Licensee.dbo.LicenseeBATransaction_active BA WITH (NOLOCK) ON s.custid=BA.srecommend and b.transid = BA.transid 	 
		WHERE 
			b.winlostdate BETWEEN @TempFromDate AND @TDate AND  
			b.statusID  IN (111, 112, 113) 
		GROUP BY   
			b.winlostdate,s.LicenseeID, s.currency, b.statusID
	END
	
	IF @ShowSB=1
	BEGIN
		INSERT INTO #SAgWinLoss
		SELECT   
			s.LicenseeID,
			b.winlostdate,  
			s.currency,
			SUM(stake
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (@ShowSB=1)AND(b.statusID = 112 OR b.statusID = 113)  AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			) turnover, 
			SUM(b.winlost - b.actual_stake) AS Winlost,  
			- SUM(b.winlost - b.actual_stake) AS LicenseeWL,
			0 AS WinlossRB,
			0 as AmountDueToBA,
			0 as AmountDueToRB,
			0 as CommBA,
			0 as CommRB,
			- SUM(b.awinlost + b.winlost - b.actual_stake + b.comm) Company  ,
			COUNT(b.transid)
			* CASE WHEN @drawfilter = 2  AND b.statusID=111 THEN 0
					ELSE 1 END BetCount	,
			sum(playercomm) AS Playercomm		
		FROM 
			Bettrans b WITH ( NOLOCK,INDEX=IX_srecommend)
			INNER JOIN @Super s ON b.srecommend = s.custid
			INNER JOIN @TempAg a ON b.recommend = a.custid
		WHERE 
			(b.bettype<31 OR (b.bettype BETWEEN 121 AND 999)) AND
			b.tpositiontaking <> 0 AND
			b.winlostdate BETWEEN @TempFromDate AND @TDate AND  
			b.statusID  IN (111, 112, 113)
			
		GROUP BY   
			 b.winlostdate, s.LicenseeID,s.currency , b.statusID
	END
	
	IF @ShowNG=1 OR @ShowLC=1 OR @ShowVS = 1
	BEGIN
		INSERT INTO #SAgWinLoss
		SELECT   
			s.LicenseeID,
			b.winlostdate,  
			s.currency,
			SUM(stake
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					WHEN (@ShowSB=1)AND(b.statusID = 112 OR b.statusID = 113)  AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			) turnover, 
			SUM(b.winlost - b.actual_stake) AS Winlost,  
			- SUM(b.winlost - b.actual_stake) AS LicenseeWL,
			0 AS WinlossRB,
			0 as AmountDueToBA,
			0 as AmountDueToRB,
			0 as CommBA,
			0 as CommRB,
			- SUM(b.awinlost + b.winlost - b.actual_stake + b.comm) Company  ,
			COUNT(b.transid)
			* CASE WHEN @drawfilter = 2  AND b.statusID=111 THEN 0
					ELSE 1 END BetCount	,
			sum(playercomm) AS Playercomm		
		FROM 
			Bettrans b WITH ( NOLOCK,INDEX=IX_srecommend)
			INNER JOIN @Super s ON b.srecommend = s.custid
			INNER JOIN @TempAg a ON b.recommend = a.custid
			INNER JOIN @bettype bt ON b.bettype = bt.bettype
		WHERE 
			b.winlostdate BETWEEN @TempFromDate AND @TDate AND  
			b.statusID  IN (111, 112, 113)
		GROUP BY   
			 b.winlostdate, s.LicenseeID,s.currency , b.statusID
			
	END
	
	IF @ShowRB = 1
	BEGIN
		INSERT INTO #SAgWinLoss
		SELECT   
			s.LicenseeID,
			b.winlostdate,  
			s.currency,
			SUM(CASE WHEN b.bettype in (33, 43) AND liveawayscore = 0 THEN stake/2 ELSE stake END 
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111 THEN 0
					ELSE 1 END
				ELSE 1 END
			) turnover, 
			SUM(b.winlost - b.actual_stake) AS Winlost,  
			0 AS LicenseeWL,
			SUM (b.awinlost) AS WinlossRB,
			0 as AmountDueToBA,
			- SUM ((b.winlost - b.actual_stake + awinlost + comm)) as AmountDueToRB,
			0 as CommBA,
			SUM ( comm) as CommRB,
			0 as Company, 
			COUNT(b.transid)
			* CASE WHEN @drawfilter = 2 AND b.statusID=111 THEN 0
				   ELSE 1 END BetCount	,
			sum(playercomm) AS Playercomm	   
		FROM 
			Bettrans b WITH ( NOLOCK,INDEX=IX_srecommend)
			INNER JOIN @TempAg a ON b.recommend = a.custid
			INNER JOIN @Super s ON b.srecommend = s.custid
		WHERE 
			b.winlostdate BETWEEN @TempFromDate AND @TDate AND  
			bettype BETWEEN 31 AND 33 AND
			b.statusID IN (111, 112, 113)
		GROUP BY   
			b.winlostdate, s.LicenseeID,s.currency, b.statusID
	END

END  

IF @FDate <= @MoveBetsDay 
BEGIN
	IF @TDate >= @MoveBetsDay
			SET @TempToDate = @MoveBetsDay
		ELSE
			SET  @TempToDate = @TDate
	
	IF @ShowBA=1 
	BEGIN
		INSERT INTO #SAgWinLoss  
		SELECT 
			ag.LicenseeID,
			b.winlostdate,  
			b.currency,
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			),     
			SUM(b.winlost),  
			0 as LicenseeWL,
			0 AS WinlossRB,
			- SUM (b.winlost+b.awinlost+b.comm) as AmountDueToBA,
			0 as AmountDueToRB,
			SUM (comm) as CommBA,
			0 as CommRB,
			0 as Company,
			SUM(b.betcount)
			* CASE WHEN @drawfilter = 2 AND b.statusID=111 THEN 0
					ELSE 1 END BetCount,
			sum(playercomm) AS Playercomm		
		FROM 
			bodb_Licensee.dbo.rptLicWinloss2 b WITH ( NOLOCK ) 
			INNER JOIN @TempAg ag ON ag.custid = b.recommend AND b.roleID=2
		WHERE  
			b.Winlostdate BETWEEN @FDate AND @TempToDate  
			AND b.statusID <> 101 --exclude REJECT bets
			AND ISNULL(b.isBA,0) = 1
		GROUP BY b.winlostdate,ag.LicenseeID,b.currency, b.statusID
	END
	
	--exclude BA tickets
	IF (@showSB = 1 or @ShowRB = 1 or @ShowNG = 1 or @ShowLC = 1 or @ShowVS = 1)
	BEGIN
		INSERT INTO #SAgWinLoss  
		SELECT 
			ag.LicenseeID,
			b.winlostdate,  
			b.currency,
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			),     
			SUM(b.winlost),  
			- SUM(CASE WHEN (b.sporttype IN (0,161,162,180))  THEN b.winlost ELSE 0 END) AS LicenseeWL ,
			SUM(CASE WHEN b.sporttype = 151 THEN b.awinlost ELSE 0 END) AS WinlossRB,
			0 as AmountDueToBA,
			- SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost+b.comm) ELSE 0 END) as AmountDueToRB,
			0 as CommBA,
			SUM ( CASE WHEN b.sporttype = 151 THEN (comm) ELSE 0 END) as CommRB,
			- SUM(CASE WHEN b.sporttype <> 151 THEN (b.winlost+b.awinlost+b.comm) ELSE 0 END)  as Company   ,
			SUM(b.betcount)
			* CASE WHEN @drawfilter = 2 AND b.statusID=111 THEN 0
				  ELSE 1 END BetCount,
			sum(playercomm) AS Playercomm	  
		FROM 
			bodb_Licensee.dbo.rptLicWinloss2 b WITH ( NOLOCK)  
			INNER JOIN @sporttype t ON b.sporttype = t.sporttype
			INNER JOIN @TempAg ag ON ag.custid = b.recommend AND b.roleID=2
		WHERE  
			b.Winlostdate BETWEEN @FDate AND @TempToDate  
			AND b.statusID <> 101 --exclude REJECT bets
			AND ISNULL(b.isBA,0) = 0
		GROUP BY b.winlostdate,ag.LicenseeID, b.currency, b.statusID
	END
	
END 
IF @IsOld = 1 
BEGIN
	SELECT @MaxOldDate = MAX(winlostdate) FROM bodb_Licensee.dbo.rptLicWinloss_old (NOLOCK)
	IF @TDate >= @MaxOldDate
			SET @TempToDate = @MaxOldDate
		ELSE
			SET  @TempToDate = @TDate

	IF @ShowBA=1 
	BEGIN
		INSERT INTO #SAgWinLoss  
		SELECT
			ag.LicenseeID,
			b.winlostdate,  
			b.currency,
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			),     
			SUM(b.winlost),  
			0 as LicenseeWL,
			0 AS WinlossRB,
			- SUM (b.winlost+b.awinlost+b.comm) as AmountDueToBA,
			0 as AmountDueToRB,
			SUM (comm) as CommBA,
			0 as CommRB,
			0 as Company,
			SUM(b.betcount)
			* CASE WHEN @drawfilter = 2 AND b.statusID=111 THEN 0 
					ELSE 1 END BetCount,
			sum(playercomm) AS Playercomm		
		FROM 
			bodb_Licensee.dbo.rptLicWinloss_old b WITH ( NOLOCK ) 
			INNER JOIN @TempAg ag ON ag.custid = b.recommend AND b.roleID=2
		WHERE  
			b.Winlostdate BETWEEN @FDate AND @TempToDate  
			AND b.statusID <> 101 --exclude REJECT bets
			AND ISNULL(b.isBA,0) = 1
		GROUP BY b.winlostdate,ag.LicenseeID, b.currency, b.statusID
	END
	--exclude BA tickets
	IF (@showSB = 1 or @ShowRB = 1 or @ShowNG = 1 or @ShowLC = 1 or @ShowVS=1)
	BEGIN
		INSERT INTO #SAgWinLoss  
		SELECT 
			ag.LicenseeID,
			b.winlostdate,  
			b.currency,
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.statusID = 111  THEN 0
					WHEN b.statusID IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			),     
			SUM(b.winlost),  
			- SUM(CASE WHEN (b.sporttype IN (0,161,162,180))  THEN b.winlost ELSE 0 END) AS LicenseeWL ,
			SUM(CASE WHEN b.sporttype = 151 THEN b.awinlost ELSE 0 END) AS WinlossRB,
			0 as AmountDueToBA,
			- SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost+b.comm) ELSE 0 END) as AmountDueToRB,
			0 as CommBA,
			SUM ( CASE WHEN b.sporttype = 151 THEN (comm) ELSE 0 END) as CommRB,
			- SUM(CASE WHEN b.sporttype <> 151 THEN (b.awinlost + b.winlost + b.comm) ELSE 0 END)  as Company   ,
			SUM(b.betcount)
			* CASE WHEN @drawfilter = 2  AND b.statusID=111 THEN 0
				   ELSE 1 END BetCount,
			sum(playercomm) AS Playercomm	   
		FROM 
			bodb_Licensee.dbo.rptLicWinloss_old b WITH ( NOLOCK )  
			INNER JOIN @TempAg ag ON ag.custid = b.recommend AND b.roleID=2 
			INNER JOIN @sporttype t ON b.sporttype = t.sporttype
		WHERE  
			b.Winlostdate BETWEEN @FDate AND @TempToDate  
			AND b.statusID <> 101 --exclude REJECT bets
			AND ISNULL(b.isBA,0) = 0
		GROUP BY b.winlostdate,ag.LicenseeID, b.currency,b.statusID
	END
	
END

CREATE NONCLUSTERED INDEX IDX_Index_SA ON #SAgWinLoss(Currency)

SELECT * INTO #TempExchange 
FROM Lrf_f_GetExchangeDaily(@FDate,@TDate)
WHERE exchangeid IN (SELECT DISTINCT Currency FROM #SAgWinLoss)

SELECT   
	w.LicenseeID,
	l.LicenseeName,
	lr.ResellerID,	
	CASE WHEN @ReportType = 1 THEN CONVERT(VARCHAR(8),w.winlostdate,112)    
		WHEN @ReportType = 2 THEN CONVERT(VARCHAR(6),w.winlostdate,112)  
		ELSE '0' END ReportType,  
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
	CAST(SUM(TurnOver*e.MYR) AS MONEY)	AS TurnoverMYR,   
	CAST(SUM(Winlost*e.MYR) AS MONEY)	AS WinlostMYR,  
	CAST(SUM(LicenseeWL*e.MYR) AS MONEY) AS LicenseeWLMYR,
	CAST(SUM(WinlossRB*e.MYR) AS MONEY)	AS WinlossRBMYR,
	CAST(SUM(CommBA * e.MYR) AS MONEY) AS CommBAMYR,
	CAST(SUM(CommRB * e.MYR) AS MONEY) AS CommRBMYR,
	CAST(SUM(AmtDuetoBA*e.MYR) AS MONEY) AS AmtDuetoBAMYR,
	CAST(SUM(AmtDuetoRB*e.MYR) AS MONEY) AS AmtDuetoRBMYR,
	CAST(SUM(Company * e.MYR) AS MONEY) AS CompanyMYR,
	CAST(SUM(Playercomm * e.MYR) AS MONEY) AS PlayercommMYR,

	--BaseUSD  
	CAST(SUM(TurnOver*e.USD) AS MONEY)	AS TurnoverUSD,   
	CAST(SUM(Winlost*e.USD) AS MONEY)	AS WinlostUSD,  
	CAST(SUM(LicenseeWL*e.USD) AS MONEY) AS LicenseeWLUSD,
	CAST(SUM(WinlossRB*e.USD) AS MONEY)	AS WinlossRBUSD,
	CAST(SUM(CommBA * e.USD) AS MONEY) AS CommBAUSD,
	CAST(SUM(CommRB * e.USD) AS MONEY) AS CommRBUSD,
	CAST(SUM(AmtDuetoBA*e.USD) AS MONEY) AS AmtDuetoBAUSD,
	CAST(SUM(AmtDuetoRB*e.USD) AS MONEY) AS AmtDuetoRBUSD,
	CAST(SUM(Company * e.USD) AS MONEY) AS CompanyUSD,
	CAST(SUM(Playercomm * e.USD) AS MONEY) AS PlayercommUSD,

	--BaseEUR  
	CAST(SUM(TurnOver*e.EUR) AS MONEY)	AS TurnoverEUR,   
	CAST(SUM(Winlost*e.EUR) AS MONEY)	AS WinlostEUR,  
	CAST(SUM(LicenseeWL*e.EUR) AS MONEY) AS LicenseeWLEUR,
	CAST(SUM(WinlossRB*e.EUR) AS MONEY)	AS WinlossRBEUR,
	CAST(SUM(CommBA * e.EUR) AS MONEY) AS CommBAEUR,
	CAST(SUM(CommRB * e.EUR) AS MONEY) AS CommRBEUR,
	CAST(SUM(AmtDuetoBA*e.EUR) AS MONEY) AS AmtDuetoBAEUR,
	CAST(SUM(AmtDuetoRB*e.EUR) AS MONEY) AS AmtDuetoRBEUR,
	CAST(SUM(Company * e.EUR) AS MONEY) AS CompanyEUR,
	CAST(SUM(Playercomm * e.EUR) AS MONEY) AS PlayercommEUR
FROM	
	#SAgWinLoss w
	INNER JOIN #TempExchange e ON w.winlostdate = e.ExchangeDate AND w.currency = e.ExchangeId
	INNER JOIN  bodb_Licensee.dbo.LicenseeReseller lr (NOLOCK) ON w.LicenseeID=lr.LicenseeID AND lr.ResellerID<>3-- exclude Starlit
	INNER JOIN bodb_Licensee.dbo.Licensees l (NOLOCK) ON l.LicenseeID = w.LicenseeID
GROUP BY   
	w.LicenseeID,
	l.LicenseeName,
	lr.ResellerID,
	CASE WHEN @ReportType = 1 THEN CONVERT(VARCHAR(8),w.winlostdate,112)  
		  WHEN @ReportType = 2 THEN CONVERT(VARCHAR(6),w.winlostdate,112)  
		  ELSE '0' END   
ORDER BY l.LicenseeName,ReportType

DROP TABLE #SAgWinLoss
DROP TABLE #TempExchange

END   
GO
GRANT EXECUTE ON [dbo].[OA_Rpt_LicWinloss_Summary] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_Rpt_LicWinloss_Summary]TO [vnteam]  
