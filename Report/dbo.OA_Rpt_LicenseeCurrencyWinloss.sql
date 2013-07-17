USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[OA_Rpt_LicenseeCurrencyWinloss_xtest]    Script Date: 06/10/2013 06:30:42 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_Rpt_LicenseeCurrencyWinloss_xtest    Script Date: 2013-06-05 4:42:57 PM ******/
ALTER PROCEDURE [dbo].[OA_Rpt_LicenseeCurrencyWinloss]  
 @Licensee		VARCHAR(1000),
 @Currency		INT = 0,
 @FromDate	SMALLDATETIME,  
 @ToDate		SMALLDATETIME,
 @showSB		BIT=1,  
 @ShowRB		BIT=0,  
 @ShowNG		BIT=0, 
 @ShowBA		BIT=0,
 @ShowLC		BIT=0,
 @ShowVS		BIT=1,
 @ShowCS		BIT=1,
 @SportID		INT=0,
 @bettype		INT=0,
 @ReportType	TINYINT=0,  
 @MoveBetsDay SMALLDATETIME,
 @drawfilter SMALLINT = 1  ,
 @excludeTest BIT = 0,
 @Debug		BIT = 0

AS  
/*  Created: Henry  
	Date: 2011-11-18
    Task : Licensee Currency Winlost Report
    DB: DB052.bodb02  
   
    Revisions:  
	- 20120104@Henry: Enhance performance by using Dynamic Query
	- 20120214@Jim: change to use  table ExchangeDaily by use function Lrf_f_GetExchangeDaily
	- 20120803@Henry: fix the commission formula
	- 20120815@Henry: add live casino
	- 20120905@Henry: add Virtual Sports
	- 20121128@Henry: use new table LicenseeBATransaction_active to get bettrans BA tickets
	- 20130529@Jim: add RNG Casino 
	- 20130716@Jim: update matchid for RNG Casino and Bingo
		
	Param's Explanation:  
	  + @ReportType: 1-Live; 2-Non-Live; 0: All;  
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS
	  + @showSB: Show SportsBook bets
	  + @ShowRB: Show RB bets
	  + @ShowNG: Show Number game bets
	  + @ShowBA: Show Bet Aggregator bets (combined with Sportsbook or Number Game)
	  + @ShowLC: Show Live casino
	  + @ShowVS: Show Live Virtual Sport
	  + @ShowCS: Show Live  RNG Casino
	  + @MoveBetsDay: The day we move tickets to bettrans14
*/  
BEGIN  

declare @sql varchar(MAX)
declare @output varchar(MAX)
declare @TempFromDate DATETIME, @TempToDate DATETIME
DECLARE @VNDCurrencyName VARCHAR(20)

SELECT @VNDCurrencyName = currency FROM exchange (NOLOCK) WHERE ExchangeId = 51

SELECT @sql = 'SET NOCOUNT ON  ' + char(13)

--declare
SELECT @sql = @sql + '--Declare variable:' + char(13)

SELECT @sql = @sql + 
			'CREATE TABLE #tmpWinLoss(winlostdate DATETIME,LicenseeID INT,Currency	INT,TurnOver MONEY,Winlost MONEY,LicenseeWL MONEY,WinlossRB MONEY,AmtDueToBA MONEY,AmtDueToRB MONEY,CommBA MONEY,CommRB	MONEY,Company MONEY,Betcount BIGINT,Playercomm MONEY)'	+ char(13) +
			'CREATE INDEX IX_tmpWinloss ON #tmpWinLoss(LicenseeID,winlostdate,Currency)' + char(13) +
			'DECLARE @i INT ' + char(13) +
			'CREATE TABLE #tmpAg(LicenseeID INT,custID INT )' + char(13) +
			'CREATE UNIQUE CLUSTERED INDEX IX_tmpAg on #tmpAg (LicenseeID,CustID)' + char(13)

--Get list of licensee and agentid to temp table
IF LTRIM(RTRIM(ISNULL(@Licensee,''))) <> ''
BEGIN
	SELECT @sql = @sql +
			'INSERT INTO #tmpAg (LicenseeID,custID) ' + char(13) +
			'SELECT LicenseeID,custID ' + char(13) +
			'FROM bodb_Licensee.dbo.LicenseeCust (NOLOCK) ' + char(13) +
			'WHERE LicenseeID IN (' + @Licensee + ')'  + char(13) +
			CASE WHEN @Currency<>0 THEN 'AND Currency=' + convert(varchar(10), @Currency) ELSE '' END + char(13) +
			CASE WHEN @excludeTest=1 THEN 'AND Currency<>20' ELSE '' END + char(13)
			
	SELECT @sql = @sql + 'DECLARE @Super AS TABLE (custid int primary key, currency int)' + char(13) 	
	--insert superIds to temp table
	SELECT @sql = @sql + 'INSERT INTO @Super(custid,currency)  ' + char(13) +
			'SELECT distinct srecommend,currency FROM custinfo WITH (NOLOCK) WHERE roleid=2 and recommend in (select custid from #tmpAg)' + char(13) 
	
END
ELSE
BEGIN
	RETURN;
END
	

IF @ToDate > @MoveBetsDay
BEGIN
	IF @FromDate <= @MoveBetsDay 
		SET @TempFromDate =  DATEADD(DAY,1,@MoveBetsDay)
	ELSE
		SET @TempFromDate = @FromDate
		
	IF @ShowBA=1
	BEGIN
		SELECT @sql = @sql + '--bettrans BA:' + char(13)
		SELECT @sql = @sql +
				'INSERT INTO #tmpWinLoss' + char(13) +
				'SELECT b.winlostdate,t.LicenseeID,s.currency,SUM(stake *' + char(13) +
					CASE WHEN @drawfilter IN (2,3) THEN ' CASE WHEN b.statusID = 111 THEN 0 WHEN (b.statusID = 112 OR b.statusID = 113)  AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5 ELSE 1 END' ELSE '1' END + ') turnover,' + char(13) +
					'SUM(b.winlost - b.actual_stake) AS Winlost,' + char(13) +
					'0 as LicenseeWL, 0 as WinlossRB,' + char(13) +
					'- SUM (b.winlost - b.actual_stake + awinlost + comm ) as AmountDueToBA,' + char(13) +
					'0 as AmountDueToRB,SUM (comm) as CommBA,0 as CommRB,0 as Company,' + char(13) +
					'COUNT(b.transid) * ' +  CASE WHEN @drawfilter = 2 THEN 'CASE WHEN b.statusID = 111 THEN 0 ELSE 1 END' ELSE '1' END + ' Betcount' + char(13) +
					',SUM(b.playercomm) as Playercomm' + char(13) +
				'FROM dbo.bettrans b WITH (NOLOCK,INDEX=IX_srecommend)' + char(13) +
					'INNER JOIN #tmpAg t ON b.recommend = t.custid' + char(13) +
					'INNER JOIN @Super s ON b.srecommend = s.custid' + char(13) +
					'INNER JOIN bodb_Licensee.dbo.LicenseeBATransaction_active BA WITH (NOLOCK) ON s.custid=ba.srecommend and b.transid = ba.transid'  + char(13) +
					'LEFT JOIN [match] m with(nolock) ON b.matchid = m.matchid' + char(13) +
					'LEFT JOIN outright o with(nolock) ON b.matchid = o.orid' + char(13) +
					'LEFT JOIN league l with(nolock) ON o.leagueid = l.leagueid' + char(13) +
				'WHERE b.winlostdate BETWEEN ''' + convert(varchar(10),@TempFromDate, 120) + ''' AND ''' + convert(varchar(10),@ToDate, 120) + '''' + char(13) +
					'AND b.statusID IN (111,112,113)' + char(13) +
					CASE WHEN @bettype<>0 THEN 'AND b.bettype = ' + convert(varchar(10), @Bettype)  ELSE '' END + char(13) +	
					CASE WHEN @SportID<>0 THEN 'AND ((b.bettype=10 AND l.Sporttype = ' + convert(varchar(10), @SportID) + ') OR (b.bettype NOT IN (9,29,10) AND m.sporttype = ' + convert(varchar(10), @SportID) + '))  ' ELSE '' END + char(13) +
					CASE 
						WHEN @ReportType=1 THEN 'AND b.Liveindicator=1 AND b.bettype NOT IN (9,29,10) '
						WHEN @ReportType=2 THEN 'AND b.liveindicator=0 '
						ELSE '' END + char(13) +
				'GROUP BY b.winlostdate, t.LicenseeID,s.currency, b.bettype  , b.statusID'	+ char(13)		
				
	END	
	IF (@ShowSB = 1 OR @ShowNG = 1 OR @ShowRB = 1 OR @ShowLC = 1 OR @ShowVS = 1 OR @ShowCS=1)
	BEGIN
		SELECT @sql = @sql + '--bettrans others exclude BA' + char(13)
		SELECT @sql = @sql +
				'INSERT INTO #tmpWinLoss' + char(13) +
				'SELECT b.winlostdate,t.LicenseeID,s.currency,SUM(CASE WHEN b.bettype in (33, 43) AND b.liveawayscore = 0 THEN stake/2 ELSE stake END *' + char(13) +
					CASE WHEN @drawfilter IN (2,3) THEN ' CASE WHEN b.statusID = 111 THEN 0 WHEN (b.statusID = 112 OR b.statusID = 113)  AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5 ELSE 1 END' ELSE '1' END + ') turnover,' + char(13) +
					'SUM(b.winlost - b.actual_stake) AS Winlost,' + char(13) +
					'- SUM(CASE WHEN (b.bettype NOT BETWEEN 31 AND 33)  THEN (b.winlost - b.actual_stake) ELSE 0 END) AS LicenseeWL ,' + char(13) +
					'SUM(CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.awinlost ELSE 0 END) AS WinlossRB,' + char(13) +
					'0 as AmountDueToBA,' + char(13) +
					'- SUM ( CASE WHEN b.bettype BETWEEN 31 AND 33 THEN (b.winlost - b.actual_stake + awinlost + comm) ELSE 0 END) as AmountDueToRB,' + char(13) +
					'0 as CommBA,' + char(13) +
					'SUM ( CASE WHEN b.bettype BETWEEN 31 AND 33 THEN (comm) ELSE 0 END) as CommRB,' + char(13) +
					'- SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN (b.awinlost + b.winlost - b.actual_stake + b.comm) ELSE 0 END)  as Company   ,' + char(13) +
					'COUNT(b.transid) * ' +  CASE WHEN @drawfilter = 2 THEN 'CASE WHEN b.statusID = 111 THEN 0 ELSE 1 END' ELSE '1' END + ' Betcount' + char(13) +
					',SUM(b.playercomm) as Playercomm' + char(13) +
				'FROM dbo.bettrans b WITH (NOLOCK,INDEX=IX_srecommend)' + char(13) +	
					'INNER JOIN #tmpAg t ON b.recommend = t.custid'	 + char(13) +
					'INNER JOIN @Super s ON b.srecommend = s.custid' + char(13) +
					'LEFT JOIN [match] m with(nolock) ON b.matchid = m.matchid'	 + char(13) +
					'LEFT JOIN outright o with(nolock) ON b.matchid = o.orid'	 + char(13) +
					'LEFT JOIN league l with(nolock) ON o.leagueid = l.leagueid'	 + char(13) +
					'LEFT JOIN bodb_Licensee.dbo.LicenseeBATransaction_active BA WITH (NOLOCK) ON s.custid=ba.srecommend and b.transid = ba.transid'	 + char(13) +
				'WHERE b.winlostdate BETWEEN ''' + convert(varchar(10),@TempFromDate, 120) + ''' AND ''' + convert(varchar(10),@ToDate, 120) + '''' + char(13) +
					'AND b.statusID IN (111,112,113)' + char(13) +
					--'AND b.matchid > 0 '	 + char(13) +
					'AND ( b.matchid > 0 AND b.bettype < ' + CASE WHEN @ShowSB=1 THEN + ' 31 OR b.bettype BETWEEN 121 AND 999' ELSE '0' END +
						CASE WHEN @ShowRB = 1 THEN ' OR b.bettype BETWEEN 31 AND 33' ELSE '' END + 
						CASE WHEN @ShowLC=1 THEN ' OR b.bettype BETWEEN 1101 AND 1199' ELSE ''END+char(13)+
						CASE WHEN @ShowVS=1 THEN ' OR b.bettype BETWEEN 1201 AND 1299' ELSE ''END+char(13)+
						CASE WHEN @ShowNG = 1 THEN ' OR b.bettype BETWEEN 81 AND 120' ELSE '' END + ')' + char(13) +
						CASE WHEN @ShowCS=1 THEN 'OR (b.bettype =71 AND b.matchid=71)' ELSE '' END +char(13)+
					CASE WHEN @bettype <> 0 THEN ' AND b.bettype = ' + convert(varchar(10), @Bettype)  ELSE '' END + char(13) +
					'AND BA.transid IS NULL'	 + char(13) +	
					CASE WHEN @SportID<>0 THEN 'AND ((b.bettype=10 AND l.Sporttype = ' + convert(varchar(10), @SportID) + ') OR (b.bettype NOT IN (9,29,10) AND b.bettype NOT BETWEEN 31 AND 120 AND m.sporttype = ' + convert(varchar(10), @SportID) + '))  ' ELSE '' END + char(13) +
					CASE 
						WHEN @ReportType=1 THEN 'AND b.Liveindicator=1 AND b.bettype NOT IN (9,29,10,31,32,33) '
						WHEN @ReportType=2 THEN 'AND b.liveindicator=0 '
						ELSE '' END + char(13) +
				'GROUP BY b.winlostdate, t.LicenseeID,s.currency, b.bettype  , b.statusID'	+ char(13)		
	END
END		

IF @FromDate <= @MoveBetsDay 
BEGIN
	IF @ToDate >= @MoveBetsDay
			SET @TempToDate = @MoveBetsDay
		ELSE
			SET  @TempToDate = @ToDate
	IF @ShowBA=1 
	BEGIN
		SELECT @sql = @sql + '--BA rpt_Betting_BA' + char(13)
		SELECT @sql = @sql +
				'INSERT INTO #tmpWinLoss' + char(13) +
				'SELECT b.rptDate,b.siteID,b.currencyID,SUM(b.turnover * '  +
					CASE WHEN @drawfilter IN (2,3) THEN 'CASE WHEN b.status = 111  THEN 0 WHEN b.status IN (114,115) THEN 0.5 ELSE 1 END' ELSE '1' END + '),' +  char(13) +
					'SUM(b.winloss),0 as LicenseeWL,0 AS WinlossRB,' + char(13) +
					'- SUM (b.winloss+b.WinlossA+b.CommissionA) as AmountDueToBA,' + char(13) +
					'0 as AmountDueToRB,SUM (CommissionA) as CommBA,0 as CommRB,0 as Company,' + char(13) +
					'SUM(b.betcount) * ' +  CASE WHEN @drawfilter = 2 THEN 'CASE WHEN b.status = 111 THEN 0 ELSE 1 END' ELSE '1' END + ' Betcount' + char(13) +
					',SUM(b.CommissionP) as Playercomm' + char(13) +
				'FROM bodb_Licensee.dbo.rpt_Betting_BA b WITH ( NOLOCK )  ' + char(13) +
					'INNER JOIN (SELECT VAL FROM strSplit(''' + @Licensee + ''','','')) s ON b.siteid = s.VAL'  + char(13) +
					'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + char(13) +
				'WHERE b.rptDate BETWEEN ''' + convert(varchar(10),@FromDate, 120) + ''' AND ''' + convert(varchar(10),@TempToDate, 120) + '''' + char(13) + 
					'AND b.status NOT IN (-1,103)' + char(13) +
					CASE WHEN @Currency <> 0 THEN 'AND CurrencyID=' + convert(varchar(10), @Currency) ELSE '' END + char(13) +
					CASE WHEN @excludeTest=1 THEN 'AND CurrencyID<>20' ELSE '' END + char(13) +
					CASE WHEN @bettype <> 0 THEN 'AND b.bettype=' + convert(varchar(10), @bettype) ELSE '' END + char(13) +
					CASE WHEN @SportID <> 0 THEN 'AND b.bettype NOT IN (9,29) AND l.Sporttype =' + convert(varchar(10), @SportID) ELSE '' END + char(13) +
					CASE 
						WHEN @ReportType=1 THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10) '
						WHEN @ReportType=2 THEN 'AND b.IsLive=0 '
						ELSE '' END + char(13) +
				'GROUP BY  b.rptDate,  b.siteID,   b.currencyID,b.status' +  char(13) 
				
	END		
	
	--exclude BA tickets
	IF (@showSB = 1 or @ShowRB = 1 or @ShowNG = 1 or @ShowLC = 1 or @ShowVS = 1 or @ShowCS=1)
	BEGIN
		SELECT @sql = @sql + '--exclude BA rpt_Betting' + char(13)
		SELECT @sql = @sql +
				'INSERT INTO #tmpWinLoss' + char(13) +
				'SELECT b.rptDate,b.siteID,b.currencyID,SUM(b.turnover * CASE WHEN b.bettype=33 AND b.status IN (114,115) THEN 0.5 ELSE 1 END *'  +
					CASE WHEN @drawfilter IN (2,3) THEN 'CASE WHEN b.status = 111  THEN 0 WHEN b.status IN (114,115) AND b.bettype <> 33 THEN 0.5 ELSE 1 END' ELSE '1' END + '),' +  char(13) +
					'SUM(b.winloss),' + char(13) +
					'- SUM(CASE WHEN (b.bettype NOT BETWEEN 31 AND 33)  THEN b.winloss ELSE 0 END) AS LicenseeWL ,'+ char(13) +
					'SUM(CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.WinlossA ELSE 0 END) AS WinlossRB,' + char(13) +
					'0 as AmountDueToBA,' + char(13) +
					'- SUM ( CASE WHEN b.bettype BETWEEN 31 AND 33 THEN (b.winloss+b.winlossA+b.CommissionA) ELSE 0 END) as AmountDueToRB,' + char(13) +
					'0 as CommBA,' + char(13) +
					'SUM ( CASE WHEN b.bettype BETWEEN 31 AND 33 THEN CommissionA ELSE 0 END) as CommRB,' + char(13) +
					'- SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN b.winlossA + b.winloss + b.CommissionA ELSE 0 END)  as Company   ,' + char(13) +
					'SUM(b.betcount) * ' +  CASE WHEN @drawfilter = 2 THEN 'CASE WHEN b.status = 111 THEN 0 ELSE 1 END' ELSE '1' END + ' Betcount' + char(13) +
					',SUM(b.CommissionP) as Playercomm' + char(13) +
				'FROM bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK )  ' + char(13) +
					'INNER JOIN (SELECT VAL FROM strSplit(''' + @Licensee + ''','','')) s ON b.siteid = s.VAL'  + char(13) +
					'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + char(13) +
				'WHERE b.rptDate BETWEEN ''' + convert(varchar(10),@FromDate, 120) + ''' AND ''' + convert(varchar(10),@TempToDate, 120) + '''' + char(13) + 
					'AND b.status NOT IN (-1,103)' + char(13) +
					'AND (b.bettype < ' + CASE WHEN @ShowSB=1 THEN + ' 31 OR b.bettype BETWEEN 121 AND 999' ELSE '0' END +
					CASE WHEN @ShowRB = 1 THEN ' OR b.bettype BETWEEN 31 AND 33' ELSE '' END + 
					CASE WHEN @ShowLC=1 THEN ' OR b.bettype BETWEEN 1101 AND 1199' ELSE ''END+char(13)+
					CASE WHEN @ShowVS=1 THEN ' OR b.bettype BETWEEN 1201 AND 1299' ELSE ''END+char(13)+
					CASE WHEN @ShowCS=1 THEN ' OR b.bettype =71' ELSE ''END+char(13)+
					CASE WHEN @ShowNG = 1 THEN ' OR b.bettype BETWEEN 81 AND 120' ELSE '' END + ')' + char(13) +
					CASE WHEN @Currency <> 0 THEN 'AND CurrencyID=' + convert(varchar(10), @Currency) ELSE '' END + char(13) +
					CASE WHEN @excludeTest=1 THEN 'AND CurrencyID<>20' ELSE '' END + char(13) +
					CASE WHEN @bettype <> 0 THEN 'AND b.bettype=' + convert(varchar(10), @bettype) ELSE '' END + char(13) +
					CASE WHEN @SportID <> 0 THEN 'AND b.bettype NOT IN (9,29 ) AND b.bettype NOT BETWEEN 31 AND 120 AND l.Sporttype =' + convert(varchar(10), @SportID) ELSE '' END + char(13) +
					CASE 
						WHEN @ReportType=1 THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10,31,32,33) '
						WHEN @ReportType=2 THEN 'AND b.IsLive=0 '
						ELSE '' END + char(13) +
				'GROUP BY  b.rptDate,  b.siteID,   b.currencyID,b.status' +  char(13) 
	END
			
END			

SELECT @sql = @sql + '--Output data from temp table' + char(13)

SELECT @sql = @sql  +char(13)+
							' SELECT * INTO #TempExchange FROM Lrf_f_GetExchangeDaily('''+convert(varchar(10),@FromDate, 120)+''','''+convert(varchar(10),@ToDate, 120)+''')'+char(13)+
							'WHERE exchangeid IN (SELECT DISTINCT Currency FROM #tmpWinLoss)'+char(13)

SELECT @output = 
			'SELECT '  + char(13) +
				'r.ResellerName,'  + char(13) +
				'l.LicenseeName,'  + char(13) +
				'CASE WHEN Currency = 51 THEN ''' + @VNDCurrencyName + ''' ELSE e.Code END currencyName,' + char(13) +
				'SUM(TurnOver)	AS Turnover,'  + char(13) +
				'SUM(Winlost)		AS Winlost,'  + char(13) +
				'SUM(LicenseeWL) AS LicenseeWL,'  + char(13) +
				'SUM(WinlossRB)	AS WinlossRB,'  + char(13) +
				'SUM(CommBA) AS CommBA,'  + char(13) +
				'SUM(CommRB) AS CommRB,'  + char(13) +
				'SUM(AmtDuetoBA) AS AmtDuetoBA,'  + char(13) +
				'SUM(AmtDuetoRB) AS AmtDuetoRB,'  + char(13) +
				'SUM(Company) AS Company,'  + char(13) +
				'SUM(Betcount)	AS Betcount,'  + char(13) +
				'SUM(Playercomm)	AS Playercomm,'  + char(13) +
				
				'CAST(SUM(TurnOver*e.MYR) AS MONEY)	AS TurnoverMYR, '  + char(13) +
				'CAST(SUM(Winlost*e.MYR) AS MONEY)	AS WinlostMYR,'  + char(13) +
				'CAST(SUM(LicenseeWL*e.MYR) AS MONEY) AS LicenseeWLMYR,'  + char(13) +
				'CAST(SUM(WinlossRB*e.MYR) AS MONEY)	AS WinlossRBMYR,'  + char(13) +
				'CAST(SUM(CommBA * e.MYR) AS MONEY) AS CommBAMYR,'  + char(13) +
				'CAST(SUM(CommRB * e.MYR) AS MONEY) AS CommRBMYR,'  + char(13) +
				'CAST(SUM(AmtDuetoBA*e.MYR) AS MONEY) AS AmtDuetoBAMYR,'  + char(13) +
				'CAST(SUM(AmtDuetoRB*e.MYR) AS MONEY) AS AmtDuetoRBMYR,'  + char(13) +
				'CAST(SUM(Company * e.MYR) AS MONEY) AS CompanyMYR,'  + char(13) +
				'CAST(SUM(Playercomm * e.MYR) AS MONEY)	AS PlayercommMYR,'  + char(13) +
				
				'CAST(SUM(TurnOver*e.USD) AS MONEY)	AS TurnoverUSD, '  + char(13) +
				'CAST(SUM(Winlost*e.USD) AS MONEY)	AS WinlostUSD,'  + char(13) +
				'CAST(SUM(LicenseeWL*e.USD) AS MONEY) AS LicenseeWLUSD,'  + char(13) +
				'CAST(SUM(WinlossRB*e.USD) AS MONEY)	AS WinlossRBUSD,'  + char(13) +
				'CAST(SUM(CommBA * e.USD) AS MONEY) AS CommBAUSD,'  + char(13) +
				'CAST(SUM(CommRB * e.USD) AS MONEY) AS CommRBUSD,'  + char(13) +
				'CAST(SUM(AmtDuetoBA*e.USD) AS MONEY) AS AmtDuetoBAUSD,'  + char(13) +
				'CAST(SUM(AmtDuetoRB*e.USD) AS MONEY) AS AmtDuetoRBUSD,'  + char(13) +
				'CAST(SUM(Company * e.USD) AS MONEY) AS CompanyUSD,'  + char(13) +
				'CAST(SUM(Playercomm * e.USD) AS MONEY)	AS PlayercommUSD,'  + char(13) +
				
				'CAST(SUM(TurnOver*e.EUR) AS MONEY)	AS TurnoverEUR, '  + char(13) +
				'CAST(SUM(Winlost*e.EUR) AS MONEY)	AS WinlostEUR,'  + char(13) +
				'CAST(SUM(LicenseeWL*e.EUR) AS MONEY) AS LicenseeWLEUR,'  + char(13) +
				'CAST(SUM(WinlossRB*e.EUR) AS MONEY)	AS WinlossRBEUR,'  + char(13) +
				'CAST(SUM(CommBA * e.EUR) AS MONEY) AS CommBAEUR,'  + char(13) +
				'CAST(SUM(CommRB * e.EUR) AS MONEY) AS CommRBEUR,'  + char(13) +
				'CAST(SUM(AmtDuetoBA*e.EUR) AS MONEY) AS AmtDuetoBAEUR,'  + char(13) +
				'CAST(SUM(AmtDuetoRB*e.EUR) AS MONEY) AS AmtDuetoRBEUR,'  + char(13) +
				'CAST(SUM(Company * e.EUR) AS MONEY) AS CompanyEUR,'  + char(13) +
				'CAST(SUM(Playercomm * e.EUR) AS MONEY)	AS PlayercommEUR'  + char(13) +
			'FROM #tmpWinLoss w'  + char(13) +	
				'INNER JOIN #TempExchange e'+char(13)+
				'ON w.winlostdate = e.ExchangeDate AND w.currency = e.ExchangeId'  + char(13) +
				'INNER JOIN bodb_Licensee.dbo.Licensees l WITH (NOLOCK) ON w.LicenseeID = l.LicenseeID'  + char(13) +
				'INNER JOIN bodb_Licensee.dbo.LicenseeReseller lr WITH (NOLOCK) ON lr.LicenseeID = w.LicenseeID'  + char(13) +
				'INNER JOIN bodb_Licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = lr.ResellerID'  + char(13) +
			'WHERE r.ResellerID <> 3'  + char(13) +
			'GROUP BY r.ResellerName,l.LicenseeName,CASE WHEN Currency = 51 THEN ''' + @VNDCurrencyName + ''' ELSE e.Code END '  + char(13) +
			'ORDER BY r.ResellerName,l.LicenseeName'  + char(13) +
			
			'DROP TABLE #tmpWinLoss' + char(13)+
			'DROP TABLE #tmpAg' + char(13) +
			'DROP TABLE #TempExchange'+char(13) 
			
			
IF (@debug = 1) 
BEGIN
	print @sql
	print @output
END

ELSE EXEC(@sql + @output)
 
END

GO
GRANT EXECUTE ON [dbo].[OA_Rpt_LicenseeCurrencyWinloss] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_Rpt_LicenseeCurrencyWinloss] TO [vnteam]  