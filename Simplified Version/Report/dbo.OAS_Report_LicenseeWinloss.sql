ALTER PROCEDURE [dbo].[OAS_Report_LicenseeWinloss]    
	@ID    INT,  
	@Type   TINYINT,  
	@Currency  INT    = 0,  
	@FromDate  SMALLDATETIME,    
	@ToDate   SMALLDATETIME,     
	@ReportType  TINYINT   = 1,    
	@MoveBetsDay SMALLDATETIME,  
	@IsOld   BIT    = 0,  
	@drawfilter  SMALLINT  = 1  ,  
	@excludeTest BIT    = 1 
AS    
  
/*  
 * Created by : [20111219@Kos]  
 * Task  : Get win loss report of operator or licensee  
 * DB   : DB052.bodb02 
 * Revisions : 
 * -	20120203@Jim:Edit in case: Operator is BA  
 * -    20120214@Jim: change to use  table ExchangeDaily by use function Lrf_f_GetExchangeDaily   
 * -	20120704@Henry: Map Licensee with System
 * -	20120803@Henry: fix the commission formula
 * -    20131028@Victor: Add ExchangeRate to result table
 * -    20131028@Victor: Use the end of month Exchange Rate for daily report
 * Param's Explanation:    
 *  - @ID   : Licensee ID or operator ID  
 *  - @Type   : 1 : licensee, 2 : operator  
 *  - @Currency  : Currency  
 *  - @FromDate  : From date  
 *  - @ToDate  : To date  
 *  - @ReportType : 1-Daily; 2-Monthly;  
 *  - @MoveBetsDay : The day we move tickets to bettrans14   (DBDWCSS @MoveBetsDay = @BalanceUpDay)
 *  - @IsOld  : 0 - query in table rptLicWinloss, 1 - query in table rptLicWinloss_old.   
 *  - @drawfilter : 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)  
 *  - @excludeTest : remove currency UUS  
 */  
  
BEGIN    
SET NOCOUNT ON    
  
CREATE TABLE #SAgWinLoss(    
	winlostdate  DATETIME,       
	Currency  INT,  
	sporttype  INT,    
	TurnOver  MONEY,      
	Winlost   MONEY,    
	LicenseeWL  MONEY, --Sportbook and NumberGame  
	Company   MONEY,  
	Betcount  BIGINT,
	Playercomm	MONEY  
)    
  
DECLARE @tmpAg   TABLE( custID INT PRIMARY KEY)    
DECLARE @VNDCurrencyName VARCHAR(20)  
  
SELECT @VNDCurrencyName = currency FROM exchange (NOLOCK) WHERE ExchangeId = 51  

IF @Type = 1  
	BEGIN  
		INSERT INTO @tmpAg (custID)   
		SELECT custID 
		FROM 
			bodb_Licensee.dbo.LicenseeCust lc WITH (NOLOCK)   
			INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON lc.LicenseeID = l.LicenseeID
			INNER JOIN bodb_Licensee.dbo.SystemLicensee sl (NOLOCK) ON l.LicenseeID=sl.LicenseeID 
			INNER JOIN bodb_Licensee.dbo.Systems s (NOLOCK) ON sl.SystemID=s.ID
		WHERE l.LicenseeID = @ID AND (@Currency = 0 OR Currency = @Currency)  
			AND sl.IsActive = 1 AND s.SystemName='OAS'
	END  
ELSE IF @Type = 2  
	BEGIN  
		INSERT INTO @tmpAg (custID)   
		SELECT DISTINCT lc.custID  
		FROM bodb_Licensee.dbo.LicenseeCust lc WITH (NOLOCK)   
			INNER JOIN bodb_Licensee.dbo.LicenseeReseller lr WITH (NOLOCK) ON lc.LicenseeID = lr.LicenseeID  
			INNER JOIN bodb_Licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = lr.ResellerID  
			INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON lc.LicenseeID = l.LicenseeID
			INNER JOIN bodb_Licensee.dbo.SystemLicensee sl (NOLOCK) ON l.LicenseeID=sl.LicenseeID 
			INNER JOIN bodb_Licensee.dbo.Systems s (NOLOCK) ON sl.SystemID=s.ID
		WHERE 
			r.ResellerID = @ID AND r.ResellerType = 2 AND (@Currency = 0 OR lc.Currency = @Currency)  
			AND sl.IsActive = 1 AND s.SystemName='OAS'
	END  
  
DECLARE @TempFromDate DATETIME   
DECLARE @TempToDate DATETIME   
DECLARE @MaxOldDate DATETIME  
DECLARE @FDate SMALLDATETIME  
DECLARE @TDate SMALLDATETIME 
	
--to Deal With Parameter Sniffing
SELECT @FDate=@FromDate,@TDate=@ToDate 
	
IF @TDate >= @MoveBetsDay  
BEGIN  
	IF @FDate <= @MoveBetsDay   
		SET @TempFromDate = @MoveBetsDay
	ELSE  
		SET @TempFromDate = @FDate  
  
	--SB   
	INSERT INTO #SAgWinLoss  
	SELECT     
		b.winlostdate,      
		b.currency,  
		0 AS sporttype,  
		SUM(stake *  
		CASE   
			WHEN @drawfilter IN (2, 3) THEN  
			CASE   
				WHEN b.statusID = 111 THEN 0  
				WHEN (b.statusID = 112 OR b.statusID = 113)   
				AND ABS(modds) = 0.25 AND b.bettype IN(1, 3, 7, 8, 17, 18) THEN 0.5  
			ELSE 1   
			END  
		ELSE 1   
		END  
		) turnover,   
		SUM(b.winlost - b.actual_stake) AS Winlost,    
		- SUM(b.winlost - b.actual_stake) AS LicenseeWL,  
		- SUM(b.awinlost + b.winlost - b.actual_stake + b.comm) Company  , 
		COUNT(b.transid) *   
		CASE   
		WHEN @drawfilter = 2 THEN  
		CASE   
		 WHEN b.statusID = 111 THEN 0  
		 ELSE 1   
		END  
		ELSE 1   
		END  
		BetCount ,
		SUM (playercomm) AS Playercomm  
	FROM   
		dbo.bettrans b WITH (NOLOCK)  
	WHERE   
		b.winlostdate BETWEEN @TempFromDate AND @TDate   
		AND Recommend IN ( SELECT custid FROM @tmpAg)   
		AND (Bettype < 31  OR (Bettype BETWEEN 121 AND 999))   
		AND b.statusID  IN (111, 112, 113)
		AND tpositiontaking <> 0 
	GROUP BY     
	 b.winlostdate,  b.currency, b.bettype, b.statusID  
END    
  
IF @FDate < @MoveBetsDay   
BEGIN  

	IF @TDate >= @MoveBetsDay  
		SET @TempToDate = dateadd(day,-1,@MoveBetsDay)
	ELSE  
		SET @TempToDate = @TDate  
		
	INSERT INTO #SAgWinLoss    
	SELECT   
		b.winlostdate,    
		b.currency,  
		b.sporttype,      
		SUM(b.turnover *  
		CASE   
			WHEN @drawfilter IN (2, 3) THEN  
			CASE   
				WHEN b.statusID = 111 THEN 0  
				WHEN b.statusID IN (114, 115) THEN 0.5  
			ELSE 1   
			END  
		ELSE 1   
		END  
		),       
		SUM(b.winlost),    
		- SUM(b.winlost) AS LicenseeWL ,  
		- SUM(b.awinlost + b.winlost + b.comm)  as Company   ,  
		SUM(b.betcount) *   
		CASE   
			WHEN @drawfilter = 2 THEN  
			CASE   
				WHEN b.statusID = 111 THEN 0  
				ELSE 1   
			END  
			ELSE 1   
		END  ,
		SUM (playercomm) AS Playercomm
	FROM   
		  bodb_Licensee.dbo.rptLicWinloss2 b WITH (NOLOCK)    
	WHERE    
		  b.Winlostdate BETWEEN @FDate AND @TempToDate    
		  AND b.sporttype = 0 --just only sportsbook
		  AND b.roleid = 2     
		  AND b.Recommend IN (SELECT custid FROM @tmpAg)   
		  AND b.statusID <> 101  
		  AND ISNULL(b.isBA,0) = 0  
	GROUP BY b.winlostdate,  b.currency, b.sporttype, b.statusID  
		
END   
IF @IsOld = 1   	
BEGIN 
	SELECT @MaxOldDate = MAX(winlostdate) FROM bodb_Licensee.dbo.rptLicWinloss_old (NOLOCK)  
			 IF @TDate >= @MaxOldDate  
				SET @TempToDate = @MaxOldDate  
			 ELSE  
				SET @TempToDate = @TDate  
				
	INSERT INTO #SAgWinLoss    
	SELECT   
		b.winlostdate,    
		b.currency,  
		b.sporttype,      
		SUM(  
		b.turnover *  
		CASE   
			WHEN @drawfilter IN (2, 3) THEN  
			CASE   
				WHEN b.statusID = 111  THEN 0  
				WHEN b.statusID IN (114, 115) THEN 0.5  
			ELSE 1   
			END  
		ELSE 1   
		END  
		),       
		SUM(b.winlost),    
		- SUM(b.winlost) AS LicenseeWL,  
		- SUM(b.awinlost + b.winlost + b.comm) as Company   ,  
		SUM(b.betcount) *   
		CASE   
			WHEN @drawfilter = 2 THEN  
			CASE   
				WHEN b.statusID = 111 THEN 0  
			ELSE 1   
			END  
		ELSE 1   
		END  ,
		SUM (playercomm) AS Playercomm
	FROM   bodb_Licensee.dbo.rptLicWinloss_old b WITH ( NOLOCK )    
	WHERE    
		b.Winlostdate BETWEEN @FDate AND @TempToDate    
		AND b.sporttype = 0 --just only sportsbook
		AND b.roleid = 2     
		AND b.Recommend IN (SELECT custid FROM @tmpAg)    
		AND b.statusID <> 101 
		AND ISNULL(b.isBA, 0) = 0  
	GROUP BY b.winlostdate, b.currency, b.sporttype, b.statusID 
END  
  

CREATE NONCLUSTERED INDEX IDX_Index_SA ON #SAgWinLoss(Currency)
 
IF @excludeTest = 1  
BEGIN  
	DELETE FROM #SAgWinLoss WHERE Currency = 20  
END   

-- Exchange by Date

DECLARE @ExDate smalldatetime

SELECT @ExDate = CASE 
					 WHEN DATEDIFF(month,@TDate,GETDATE()) <= 0 THEN GETDATE() 
					 ELSE DATEADD(day,-1,DATEADD(month,1,'01 '+SUBSTRING(CONVERT(VARCHAR(11),@TDate,106),4,8)))
				 END

SELECT * INTO #TempExchange 
FROM Lrf_f_GetExchangeDaily(@ExDate,@ExDate)
WHERE exchangeid IN (SELECT DISTINCT Currency FROM #SAgWinLoss)


SELECT     
	CASE   
	WHEN @ReportType = 1 THEN CONVERT(VARCHAR(8), w.winlostdate, 112)    
	WHEN @ReportType = 2 THEN CONVERT(VARCHAR(6), w.winlostdate, 112)    
	ELSE '0'   
	END ReportType,    
	Currency,     
	CASE   
	WHEN Currency = 51 THEN @VNDCurrencyName   
	ELSE e.Code   
	END currencyName,  
	e.EUR AS EURExRate,
	e.USD AS USDExRate,
	e.MYR AS MYRExRate,
	SUM(TurnOver) AS Turnover,     
	SUM(Winlost) AS Winlost,    
	SUM(LicenseeWL) AS LicenseeWL,  
	SUM(Company) AS Company,  
	SUM(Betcount) AS Betcount,  
	sum(Playercomm) AS Playercomm,

	-- BaseRM    
	SUM(TurnOver * e.MYR) AS TurnoverMYR,     
	SUM(Winlost * e.MYR) AS WinlostMYR,    
	SUM(LicenseeWL * e.MYR) AS LicenseeWLMYR,  
	SUM(Company * e.MYR) AS CompanyMYR,  
	sum(Playercomm * e.MYR) AS PlayercommMYR,

	-- BaseUSD    
	SUM(TurnOver * e.USD) AS TurnoverUSD,     
	SUM(Winlost * e.USD) AS WinlostUSD,    
	SUM(LicenseeWL * e.USD) AS LicenseeWLUSD,  
	SUM(Company * e.USD) AS CompanyUSD,  
	sum(Playercomm * e.USD) AS PlayercommUSD,

	-- BaseEUR    
	SUM(TurnOver * e.EUR) AS TurnoverEUR,     
	SUM(Winlost * e.EUR) AS WinlostEUR,    
	SUM(LicenseeWL * e.EUR) AS LicenseeWLEUR,  
	SUM(Company * e.EUR) AS CompanyEUR  ,
	sum(Playercomm * e.EUR) AS PlayercommEUR
FROM   
	 #SAgWinLoss w     
	 INNER JOIN #TempExchange e 
	 ON w.currency = e.ExchangeId
GROUP BY     
	 Currency,  
	 CASE   
		WHEN @ReportType = 1 THEN CONVERT(VARCHAR(8), w.winlostdate, 112)    
		WHEN @ReportType = 2 THEN CONVERT(VARCHAR(6), w.winlostdate, 112)    
		ELSE '0'   
	 END,   
	 CASE   
		WHEN Currency = 51 THEN @VNDCurrencyName   
		ELSE e.Code   
	 END,
	 e.EUR,
	 e.USD,
	 e.MYR  
ORDER BY ReportType    
   
DROP TABLE #SAgWinLoss
DROP TABLE #TempExchange
   
   
END     

GO
GRANT EXECUTE ON [dbo].[OAS_Report_LicenseeWinloss] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Report_LicenseeWinloss] TO [vnteam]