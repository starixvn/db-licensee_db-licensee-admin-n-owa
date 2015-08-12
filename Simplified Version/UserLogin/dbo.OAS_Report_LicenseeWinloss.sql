   
CREATE PROCEDURE [dbo].[OAS_Report_LicenseeWinloss]    
 @ID    INT,  
 @Type   TINYINT,  
 @Currency  INT    = 0,  
 @FromDate  SMALLDATETIME,    
 @ToDate   SMALLDATETIME,     
 @ReportType  TINYINT   = 1,    
 @MoveBetsDay SMALLDATETIME,  
 @IsOld   BIT    = 0,  
 @drawfilter  SMALLINT  = 1  ,  
 @excludeTest BIT    = 0  
AS    
  
/*  
 * Created by : [20111219@Kos]  
 * Task  : Get win loss report of operator or licensee  
 * DB   : DB052.bodb_Licensee  
 * Revisions :  
 *  
 * Param's Explanation:    
 *  - @ID   : Licensee ID or operator ID  
 *  - @Type   : 1 : licensee, 2 : operator  
 *  - @Currency  : Currency  
 *  - @FromDate  : From date  
 *  - @ToDate  : To date  
 *  - @ReportType : 1-Daily; 2-Monthly;  
 *  - @MoveBetsDay : The day we move tickets to bettrans14   
 *  - @IsOld  : 0 - query in table rptLicWinloss, 1 - query in table rptLicWinloss_old.   
 *  - @drawfilter : 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)  
 *  - @excludeTest : remove currency UUS  
 */  
  
BEGIN    
SET NOCOUNT ON    
  
DECLARE @SAgWinLoss AS TABLE (    
 winlostdate  DATETIME,    
 CustID   INT,     
 Currency  INT,  
 sporttype  INT,    
 TurnOver  MONEY,      
 Winlost   MONEY,    
 LicenseeWL  MONEY, --Sportbook and NumberGame  
 WinlossRB  MONEY,  
 AmtDueToBA  MONEY,     
 AmtDueToRB  MONEY,  
 CommBA   MONEY,     
 CommRB   MONEY,     
 Company   MONEY,  
 Betcount  BIGINT  
)    
  
DECLARE @TmpCond  TABLE( sporttype INT, bettype INT)    
DECLARE @TmpCondSumWL TABLE( sporttype INT, bettype INT)    
DECLARE @tmpAg   TABLE( custID INT PRIMARY KEY)    
DECLARE @VNDCurrencyName VARCHAR(20)  
  
SELECT @VNDCurrencyName = currency FROM exchange (NOLOCK) WHERE ExchangeId = 51  
  
-- Get all customer of the licensee or all licensees of the operator  
IF @Type = 1  
BEGIN  
 INSERT INTO @tmpAg (custID)   
 SELECT custID   
 FROM bodb_Licensee.dbo.LicenseeCust WITH (NOLOCK)   
 WHERE LicenseeID = @ID AND (@Currency = 0 OR Currency = @Currency)  
END  
ELSE IF @Type = 2  
BEGIN  
 INSERT INTO @tmpAg (custID)   
 SELECT DISTINCT lc.custID   
 FROM bodb_Licensee.dbo.LicenseeCust lc WITH (NOLOCK)   
 INNER JOIN bodb_Licensee.dbo.LicenseeReseller lr WITH (NOLOCK) ON lc.LicenseeID = lr.LicenseeID  
 INNER JOIN bodb_Licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = lr.ResellerID  
 WHERE r.ResellerID = @ID AND r.ResellerType = 2 AND (@Currency = 0 OR lc.Currency = @Currency)  
END  
  
--rptLicWinloss    
INSERT INTO @TmpCondSumWL(sporttype, bettype)    
VALUES(0,0)    
  
DECLARE @TempFromDate DATETIME   
DECLARE @TempToDate DATETIME   
DECLARE @MaxOldDate DATETIME  
  
IF @ToDate > @MoveBetsDay  
BEGIN  
 IF @FromDate <= @MoveBetsDay   
  SET @TempFromDate = DATEADD(DAY, 1, @MoveBetsDay)  
 ELSE  
  SET @TempFromDate = @FromDate  
  
 --SB   
 INSERT INTO @SAgWinLoss  
 SELECT     
  b.winlostdate,    
  b.srecommend,     
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
  0 AS WinlossRB,  
  0 AS AmountDueToBA,  
  0 AS AmountDueToRB,  
  0 AS CommBA,  
  0 AS CommRB,  
  - SUM(b.swinlost + b.mwinlost + b.awinlost + b.winlost - b.actual_stake + b.scomm) Company  ,  
  COUNT(b.transid) *   
  CASE   
   WHEN @drawfilter = 2 THEN  
    CASE   
     WHEN b.statusID = 111 THEN 0  
     ELSE 1   
    END  
   ELSE 1   
  END  
  BetCount   
 FROM   
  dbo.bettrans b WITH (NOLOCK)  
 WHERE   
  b.winlostdate BETWEEN @TempFromDate AND @ToDate   
  AND Recommend IN ( SELECT custid FROM @tmpAg)   
  AND (Bettype < 31  OR (Bettype BETWEEN 121 AND 999))   
  AND b.ruben = 1   
  AND b.statusID NOT IN (101, 102, 103)   
  AND tpositiontaking <> 0 --exclude BA tickets  
 GROUP BY     
  b.winlostdate, b.srecommend, b.currency, b.bettype, statusID  
    
END    
  
IF @FromDate <= @MoveBetsDay   
BEGIN  
 IF @ToDate >= @MoveBetsDay  
  SET @TempToDate = @MoveBetsDay  
 ELSE  
  SET @TempToDate = @ToDate  
    
 --exclude BA tickets  
 INSERT INTO @SAgWinLoss    
 SELECT   
  b.winlostdate,    
  b.srecommend,     
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
  - SUM(CASE WHEN (b.sporttype = 0 OR b.sporttype = 161)  THEN b.winlost ELSE 0 END) AS LicenseeWL ,  
  SUM(CASE WHEN b.sporttype = 151 THEN b.awinlost ELSE 0 END) AS WinlossRB,  
  0 as AmountDueToBA,  
  - SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost + b.comm) ELSE 0 END) as AmountDueToRB,  
  0 as CommBA,  
  SUM ( CASE WHEN b.sporttype = 151 THEN (comm - playercomm) ELSE 0 END) as CommRB,  
  - SUM(CASE WHEN b.sporttype <> 151 THEN b.swinlost + b.mwinlost + b.awinlost + b.winlost + b.scomm ELSE 0 END)  as Company   ,  
  SUM(b.betcount) *   
  CASE   
   WHEN @drawfilter = 2 THEN  
    CASE   
     WHEN b.statusID = 111 THEN 0  
     ELSE 1   
    END  
   ELSE 1   
  END  
 FROM   
  bodb_Licensee.dbo.rptLicWinloss2 b WITH (NOLOCK)    
  INNER JOIN @TmpCondSumWL t ON b.sporttype = t.sporttype AND b.bettype = 0  
 WHERE    
  b.Winlostdate BETWEEN @FromDate AND @TempToDate    
  AND b.roleid = 2     
  AND b.Recommend IN (SELECT custid FROM @tmpAg)   
  AND b.statusID <> 101 --exclude REJECT bets  
  AND ISNULL(b.isBA,0) = 0  
 GROUP BY b.winlostdate, b.srecommend, b.currency, b.sporttype, b.statusID  
   
END   
IF @IsOld = 1   
BEGIN  
 SELECT @MaxOldDate = MAX(winlostdate) FROM bodb_Licensee.dbo.rptLicWinloss_old (NOLOCK)  
 IF @ToDate >= @MaxOldDate  
  SET @TempToDate = @MaxOldDate  
 ELSE  
  SET @TempToDate = @ToDate  
   
 INSERT INTO @SAgWinLoss    
 SELECT   
  b.winlostdate,    
  b.srecommend,     
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
  - SUM(CASE WHEN (b.sporttype = 0 OR b.sporttype = 161)  THEN b.winlost ELSE 0 END) AS LicenseeWL,  
  SUM(CASE WHEN b.sporttype = 151 THEN b.awinlost ELSE 0 END) AS WinlossRB,  
  0 as AmountDueToBA,  
  - SUM ( CASE WHEN b.sporttype = 151 THEN (b.winlost+b.awinlost + b.comm) ELSE 0 END) AS AmountDueToRB,  
  0 as CommBA,  
  SUM ( CASE WHEN b.sporttype = 151 THEN (comm - playercomm) ELSE 0 END) AS CommRB,  
  - SUM(CASE WHEN b.sporttype <> 151 THEN b.swinlost + b.mwinlost + b.awinlost + b.winlost + b.scomm ELSE 0 END) as Company   ,  
  SUM(b.betcount) *   
  CASE   
   WHEN @drawfilter = 2 THEN  
    CASE   
     WHEN b.statusID = 111 THEN 0  
     ELSE 1   
    END  
   ELSE 1   
  END  
 FROM   
  bodb_Licensee.dbo.rptLicWinloss_old b WITH ( NOLOCK )    
  INNER JOIN @TmpCondSumWL t ON b.sporttype = t.sporttype AND b.bettype = 0  
 WHERE    
  b.Winlostdate BETWEEN @FromDate AND @TempToDate    
  AND b.roleid = 2     
  AND b.Recommend IN (SELECT custid FROM @tmpAg)    
  AND b.statusID <> 101 --exclude REJECT bets  
  AND ISNULL(b.isBA, 0) = 0  
 GROUP BY b.winlostdate, b.srecommend, b.currency, b.sporttype, b.statusID  
   
END  
  
--exclude betcount = 0 AND turnover = 0  
DELETE FROM @SAgWinLoss  
WHERE Betcount = 0 AND TurnOver = 0  
  
IF @excludeTest = 1  
BEGIN  
 DELETE FROM @SAgWinLoss WHERE Currency = 20  
END   
  
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
 SUM(TurnOver) AS Turnover,     
 SUM(Winlost) AS Winlost,    
 SUM(LicenseeWL) AS LicenseeWL,  
 SUM(WinlossRB) AS WinlossRB,  
 SUM(CommBA)  AS CommBA,  
 SUM(CommRB)  AS CommRB,  
 SUM(AmtDuetoBA) AS AmtDuetoBA,  
 SUM(AmtDuetoRB) AS AmtDuetoRB,  
 SUM(Company) AS Company,  
 SUM(Betcount) AS Betcount,  
  
 -- BaseRM    
 SUM(TurnOver * e.MYR) AS TurnoverMYR,     
 SUM(Winlost * e.MYR) AS WinlostMYR,    
 SUM(LicenseeWL * e.MYR) AS LicenseeWLMYR,  
 SUM(WinlossRB * e.MYR) AS WinlossRBMYR,  
 SUM(CommBA * e.MYR)  AS CommBAMYR,  
 SUM(CommRB * e.MYR)  AS CommRBMYR,  
 SUM(AmtDuetoBA * e.MYR) AS AmtDuetoBAMYR,  
 SUM(AmtDuetoRB * e.MYR) AS AmtDuetoRBMYR,  
 SUM(Company * e.MYR) AS CompanyMYR,  
  
 -- BaseUSD    
 SUM(TurnOver * e.USD) AS TurnoverUSD,     
 SUM(Winlost * e.USD) AS WinlostUSD,    
 SUM(LicenseeWL * e.USD) AS LicenseeWLUSD,  
 SUM(WinlossRB * e.USD) AS WinlossRBUSD,  
 SUM(CommBA * e.USD)  AS CommBAUSD,  
 SUM(CommRB * e.USD)  AS CommRBUSD,  
 SUM(AmtDuetoBA * e.USD) AS AmtDuetoBAUSD,  
 SUM(AmtDuetoRB * e.USD) AS AmtDuetoRBUSD,  
 SUM(Company * e.USD) AS CompanyUSD,  
  
 -- BaseEUR    
 SUM(TurnOver * e.EUR) AS TurnoverEUR,     
 SUM(Winlost * e.EUR) AS WinlostEUR,    
 SUM(LicenseeWL * e.EUR) AS LicenseeWLEUR,  
 SUM(WinlossRB * e.EUR) AS WinlossRBEUR,  
 SUM(CommBA * e.EUR)  AS CommBAEUR,  
 SUM(CommRB * e.EUR)  AS CommRBEUR,  
 SUM(AmtDuetoBA * e.EUR) AS AmtDuetoBAEUR,  
 SUM(AmtDuetoRB * e.EUR) AS AmtDuetoRBEUR,  
 SUM(Company * e.EUR) AS CompanyEUR  
FROM   
 @SAgWinLoss w     
 INNER JOIN ExchangeDaily e WITH (NOLOCK) ON w.winlostdate = e.ExchangeDate AND w.currency = e.ExchangeId  
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
 END  
ORDER BY ReportType    
   
END     
  GO
GRANT EXECUTE ON [dbo].[OAS_Report_LicenseeWinloss] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Report_LicenseeWinloss] TO [vnteam]   