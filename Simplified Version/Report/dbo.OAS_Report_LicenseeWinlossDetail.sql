 ALTER PROCEDURE [dbo].[OAS_Report_LicenseeWinlossDetail]  
	@LicenseeID	INT,
	@Currency		INT = 0,
	@CustID		INT = 0, --AgentID			
	@FromDate		SMALLDATETIME,  
	@ToDate		SMALLDATETIME,   
	@MoveBetsDay SMALLDATETIME,
	@IsOld BIT = 0,
	@drawfilter SMALLINT = 1,
	@excludeTest BIT = 0

AS  
/*   Created:  Henry
	Date: 2012-09-26
    Original:[Acc_Rpt_LicWinlossDetail2]
	Task : Sportbook winloss report
    DB: DB052.bodb02 
   
    Revisions:  
		
	Param's Explanation:  
	  + @CustID: SuperID  
	  + @BaseCurrency (input currencyID): 2-MYR ; 3-USD; 6-EUR
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @IsOld: 0 - query IN table rptLicWinloss, 1 - query IN table rptLicWinloss_old. 
	  + @excludeTest: remove currency UUS
	  + @MoveBetsDay: The day we move tickets to bettrans14 (new server DBDWCSS @Movebetsday = @BalanceUpDay)
	  
  
*/  
BEGIN  
SET NOCOUNT ON  

DECLARE @SAgWinLoss AS TABLE (  
	winlostdate		DATETIME,  
	CustID			INT,   
	username		NVARCHAR(50),
	Currency		INT,  
	TurnOver		MONEY,   	
	Winlost			MONEY,  
	LicenseeWL		MONEY,
	Company		MONEY,
	Betcount	BIGINT,
	Playercomm	MONEY
)  


DECLARE @tempAg	TABLE( custID INT PRIMARY KEY)  
DECLARE @VNDCurrencyName VARCHAR(20)
SELECT @VNDCurrencyName = currency FROM exchange (nolock) WHERE ExchangeId = 51

DECLARE @site VARCHAR(50)
SELECT @site=LicenseeName FROM bodb_licensee.dbo.Licensees (NOLOCK) 
WHERE LicenseeID=@LicenseeID


DECLARE @bettype AS TABLE (bettype INT PRIMARY KEY)
DECLARE @sporttype TABLE(sporttype INT)

-- get Licensee Cust with filter by @CustID, @Currency,@excludeTest
INSERT INTO @tempAg (custID) 
SELECT custID FROM bodb_Licensee.dbo.LicenseeCust (nolock) 
WHERE (LicenseeID = @LicenseeID) 
AND (@CustID=0 OR (@CustID<>0 AND CustID = @CustID)) 
AND (@Currency=0 OR (@Currency<>0 AND Currency=@Currency ))
AND (@excludeTest=0 OR (@excludeTest=1 AND Currency<>20 ))

--Only sportbooks
INSERT  INTO @sporttype( sporttype)
    VALUES  (0)	
	
INSERT INTO @bettype(bettype)
SELECT typeid FROM bettype (NOLOCK)
WHERE (typeid<31 OR (typeid BETWEEN 121 AND 999))


DECLARE @TempFromDate DATETIME 
DECLARE @TempToDate DATETIME 
DECLARE @MaxOldDate DATETIME
  
IF @ToDate >= @MoveBetsDay
BEGIN
	IF @FromDate <= @MoveBetsDay 
		SET @TempFromDate =  @MoveBetsDay
	ELSE
		SET @TempFromDate = @FromDate

	INSERT INTO @SAgWinLoss
	SELECT   
		b.winlostdate,  
		b.custid,
		b.username,
		b.currency, 
		SUM(stake
			*
			CASE WHEN @drawfilter IN (2,3) THEN
				CASE WHEN b.statusID = 111 THEN 0
				WHEN (b.statusID = 112 OR b.statusID = 113) AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5
				ELSE 1 END
			ELSE 1 END
		) turnover,
		SUM(b.winlost - b.actual_stake) AS Winlost,  
		- SUM(b.winlost - b.actual_stake) AS LicenseeWL,
		- SUM(b.awinlost + b.winlost - b.actual_stake + b.comm) Company  ,
		COUNT(b.transid)
		* CASE WHEN @drawfilter = 2 THEN
				CASE WHEN b.statusID = 111 THEN 0
				ELSE 1 END
			ELSE 1 END
		   BetCount,
		sum(playercomm) AS Playercomm   
	FROM 
		dbo.bettrans b WITH ( NOLOCK)  
		INNER JOIN @TempAg a ON b.recommend = a.custid
		INNER JOIN @bettype bt ON b.bettype = bt.bettype
	WHERE 
		b.winlostdate BETWEEN @TempFromDate AND @ToDate AND  
		b.statusID  IN (111, 112, 113)
		AND tpositiontaking <> 0 --exclude BA tickets
	GROUP BY   
		b.winlostdate,b.currency,b.custid,b.statusID,b.username

END  
 
IF @FromDate < @MoveBetsDay 
BEGIN
	IF @ToDate >= @MoveBetsDay
			SET @TempToDate =  dateadd(day,-1,@MoveBetsDay)
		ELSE
			SET  @TempToDate = @ToDate

	INSERT INTO @SAgWinLoss  
	SELECT 
		b.winlostdate,  
		b.custid,
		b.username,
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
		- SUM(CASE WHEN b.sporttype=0 THEN b.winlost ELSE 0 END) AS LicenseeWL ,
		- SUM(CASE WHEN b.sporttype = 0 THEN (b.awinlost + b.winlost + b.comm) ELSE 0 END)  as Company   ,
		SUM(b.betcount)
		* CASE WHEN @drawfilter = 2 THEN
				CASE WHEN b.statusID = 111 THEN 0
				ELSE 1 END
			ELSE 1 END,
		sum(playercomm) AS Playercomm	
	FROM bodb_Licensee.dbo.rptLicWinloss2 b WITH ( NOLOCK )  
		INNER JOIN @TempAg ag ON ag.custid = b.recommend
		INNER JOIN @sporttype t ON b.sporttype = t.sporttype
	WHERE  
		b.Winlostdate BETWEEN @FromDate AND @TempToDate  
		AND b.roleid = 1
		AND b.statusID <> 101 --exclude REJECT bets
		AND ISNULL(b.isBA,0) = 0
	GROUP BY  b.winlostdate,b.currency,b.custid,b.statusID,b.username
			
 END 
 IF @IsOld = 1 
 BEGIN
	SELECT @MaxOldDate = MAX(winlostdate) FROM bodb_Licensee.dbo.rptLicWinloss_old (nolock)
	IF @ToDate >= @MaxOldDate
			SET @TempToDate = @MaxOldDate
		ELSE
			SET  @TempToDate = @ToDate
 
	INSERT INTO @SAgWinLoss  
	SELECT 
		b.winlostdate,  
		b.custid,
		b.currency,
		b.username,
		SUM(b.turnover
		*
			CASE WHEN @drawfilter IN (2,3) THEN
				CASE WHEN b.statusID = 111  THEN 0
				WHEN b.statusID IN (114,115) THEN 0.5
				ELSE 1 END
			ELSE 1 END
		),     
		SUM(b.winlost),  
		- SUM(CASE WHEN b.sporttype=0 THEN b.winlost ELSE 0 END) AS LicenseeWL ,
		- SUM(CASE WHEN b.sporttype = 0 THEN (b.awinlost + b.winlost + b.comm) ELSE 0 END)  as Company   ,
		SUM(b.betcount)
		* CASE WHEN @drawfilter = 2 THEN
				CASE WHEN b.statusID = 111 THEN 0
				ELSE 1 END
			ELSE 1 END,
		sum(playercomm) AS Playercomm		
	FROM bodb_Licensee.dbo.rptLicWinloss_old b WITH ( NOLOCK )  
		INNER JOIN @TempAg ag ON ag.custid = b.recommend
		INNER JOIN @sporttype t ON b.sporttype = t.sporttype
	WHERE  
		b.Winlostdate BETWEEN @FromDate AND @TempToDate  
		AND b.roleid = 1   
		AND b.statusID <> 101 --exclude REJECT bets
		AND ISNULL(b.isBA,0) = 0
	GROUP BY  b.winlostdate,b.currency, b.custid,b.statusID,b.username
	
 END
  
 
SELECT * INTO #TempExchange 
FROM Lrf_f_GetExchangeDaily(@FromDate,@ToDate)
WHERE exchangeid IN (SELECT DISTINCT Currency FROM @SAgWinLoss)
 
  --exclude betcount=0 AND turnover = 0
 SELECT 
	w.username,  
	w.custid, 
	w.currency,
	CASE WHEN w.Currency = 51 THEN @VNDCurrencyName 
			ELSE e.Code END AS CurrencyName,
	SUM(TurnOver)	AS Turnover,   
	SUM(Winlost)		AS Winlost,  
	SUM(LicenseeWL) AS LicenseeWL,
	SUM(Company) AS Company,
	SUM(Betcount)	AS Betcount,
	SUM(Playercomm) AS Playercomm,
	--BaseRM  
	CAST(SUM(TurnOver*e.MYR) AS MONEY)	AS TurnoverMYR,   
	CAST(SUM(Winlost*e.MYR) AS MONEY)	AS WinlostMYR,  
	CAST(SUM(LicenseeWL*e.MYR) AS MONEY) AS LicenseeWLMYR,
	CAST(SUM(Company * e.MYR) AS MONEY) AS CompanyMYR,
	CAST(SUM(Playercomm * e.MYR) AS MONEY) AS PlayercommMYR,
	--BaseUSD  
	CAST(SUM(TurnOver*e.USD) AS MONEY)	AS TurnoverUSD,   
	CAST(SUM(Winlost*e.USD) AS MONEY)	AS WinlostUSD,  
	CAST(SUM(LicenseeWL*e.USD) AS MONEY) AS LicenseeWLUSD,
	CAST(SUM(Company * e.USD) AS MONEY) AS CompanyUSD,
	CAST(SUM(Playercomm * e.USD) AS MONEY) AS PlayercommUSD,
	--BaseEUR  
	CAST(SUM(TurnOver*e.EUR) AS MONEY)	AS TurnoverEUR,   
	CAST(SUM(Winlost*e.EUR) AS MONEY)	AS WinlostEUR,  
	CAST(SUM(LicenseeWL*e.EUR) AS MONEY) AS LicenseeWLEUR,
	CAST(SUM(Company * e.EUR) AS MONEY) AS CompanyEUR,
	CAST(SUM(Playercomm * e.EUR) AS MONEY) AS PlayercommEUR
 FROM	@SAgWinLoss w   
		INNER JOIN #TempExchange e
		ON w.winlostdate = e.ExchangeDate AND w.currency = e.ExchangeId
  GROUP BY w.currency,w.custid, w.username,
			CASE WHEN w.Currency = 51 THEN @VNDCurrencyName 
			ELSE e.Code END
  ORDER BY w.currency
  
DROP TABLE #TempExchange
 
END   

GO
GRANT EXECUTE ON [dbo].[OAS_Report_LicenseeWinlossDetail] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Report_LicenseeWinlossDetail] TO [vnteam]   