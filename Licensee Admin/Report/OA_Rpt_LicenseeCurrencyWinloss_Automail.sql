/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[OA_Rpt_LicenseeCurrencyWinloss_Automail]  
 @Licensee        VARCHAR(1000),
 @Currency        INT = 0,
 @FromDate        SMALLDATETIME,  
 @ToDate        SMALLDATETIME,
 @showSB        BIT=1,  
 @ShowRB        BIT=1,  
 @ShowNG        BIT=1, 
 @ShowBA        BIT=1,
 @ShowLC        BIT=1,
 @ShowVS        BIT=1,
 @SportID        INT=0,
 @bettype        INT=0,
 @ReportType    TINYINT=0,  
 @MoveBetsDay SMALLDATETIME,
 @drawfilter SMALLINT = 1  ,
 @excludeTest BIT = 1,
 @Debug        BIT = 0

AS  
/*  Created: Henry  
    Date: 2011-11-18
    Task : Licensee Currency Winlost Report for monthly automail
    DB: DB052.bodb02  
   
    Revisions:  
        -20120814@Henry: add ShowLiveCasino 
        -20160726@Francis: Move SP to bodb_LicenseeReport - [Redmine: #60449]
		- 20181031@Patrick: DB052 indexes revolution [RedmineID: #103572]
		- 20181206@bruce: Implement E-sport 2, HP5 [#105723]
        
    Param's Explanation:  
      + @ReportType: 1-Live; 2-Non-Live; 0: All;  
      +    @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
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

declare @sql varchar(MAX)
declare @sql2 varchar(MAX)
declare @output varchar(MAX)
declare @TempFromDate DATETIME, @TempToDate DATETIME
DECLARE @VNDCurrencyName VARCHAR(20)

SELECT @VNDCurrencyName = currency FROM exchange (NOLOCK) WHERE ExchangeId = 51

SELECT @sql = 'SET NOCOUNT ON  ' + char(13)

SELECT @sql2 = ''
--declare
SELECT @sql = @sql + '--Declare variable:' + char(13)

SELECT @sql = @sql + 
            'CREATE TABLE #tmpWinLoss(winlostdate DATETIME,LicenseeID INT,Currency    INT,TurnOverSB MONEY,TurnOverNG MONEY,TurnOverRB MONEY,TurnOverLC MONEY, TurnOverVS MONEY,TurnOverBA MONEY,MemWinlossSB MONEY,MemWinlossNG MONEY,MemWinlossRB MONEY,MemWinlossLC MONEY, MemWinlossVS MONEY,MemWinlossBA MONEY,WinlossSB MONEY,WinlossNG MONEY,WinlossRB MONEY, WinlossLC MONEY, WinlossVS MONEY, AmtDueToBA MONEY,AmtDueToRB MONEY,CommBA MONEY,CommRB    MONEY,AmtDueToSB MONEY,AmtDueToNG MONEY,AmtDueToLC MONEY, AmtDueToVS MONEY,Betcount BIGINT,Playercomm MONEY)'    + char(13) +
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
                'SELECT b.winlostdate,t.LicenseeID,b.currency,0 as TurnOverSB,0 as TurnOverNG,0 as TurnOverRB,0 as TurnoverLC, 0 as TurnoverVS,  ' + char(13) +
                    'SUM(stake *' + CASE WHEN @drawfilter IN (2,3) THEN ' CASE WHEN b.statusID = 111 THEN 0 WHEN (b.statusID = 112 OR b.statusID = 113)  AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5 ELSE 1 END' ELSE '1' END + ') turnoverBA,' + char(13) +
                    '0 as MemWinlossSB, 0 as MemWinlossNG, 0 as MemWinlossRB, 0 as MemWinlossLC, 0 as MemWinlossVS,'+ char(13) +
                    'SUM(b.winlost - b.actual_stake) AS MemWinlossBA,' + char(13) +
                    '0 as WinlossSB, 0 as WinlossNG, 0 as WinlossRB,0 as WinlossLC, 0 as WinlossVS,' + char(13) +
                    '- SUM (b.winlost - b.actual_stake + awinlost + comm ) as AmountDueToBA,' + char(13) +
                    '0 as AmountDueToRB,SUM (comm) as CommBA,0 as CommRB,0 as AmtDueToSB, 0 as AmtDueToNG, 0 as AmtDueToLC,0 as AmtDueToVS,' + char(13) +
                    'COUNT(b.transid) * ' +  CASE WHEN @drawfilter = 2 THEN 'CASE WHEN b.statusID = 111 THEN 0 ELSE 1 END' ELSE '1' END + ' Betcount' + char(13) +
                    ',SUM(b.playercomm) as Playercomm' + char(13) +
                'FROM dbo.bettrans b WITH (NOLOCK,INDEX=PK_bettrans)' + char(13) +
                    'INNER JOIN bodb_Licensee.dbo.LicenseeBATransaction_active BA WITH (NOLOCK) ON b.transid = BA.transid' + char(13) +
                    'INNER JOIN #tmpAg t ON b.recommend = t.custid' + char(13) +
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
                'GROUP BY b.winlostdate, t.LicenseeID,b.currency, b.bettype  , b.statusID'    + char(13)        
                
    END    
    IF @ShowSB = 1 OR @ShowNG = 1 OR @ShowRB = 1 OR @ShowLC=1 OR @ShowVS=1
    BEGIN
        SELECT @sql = @sql + '--bettrans others exclude BA' + char(13)
        SELECT @sql = @sql +
                'INSERT INTO #tmpWinLoss' + char(13) +
                'SELECT b.winlostdate,t.LicenseeID,b.currency,' + char(13) +
                    'SUM(CASE WHEN (b.bettype<31 OR b.bettype BETWEEN 121 AND 999 OR b.bettype BETWEEN 9001 AND 9399 ORb.bettype BETWEEN 1301 AND 1399) THEN stake ELSE 0 END *' + char(13) +
                    CASE WHEN @drawfilter IN (2,3) THEN ' CASE WHEN b.statusID = 111 THEN 0 WHEN (b.statusID = 112 OR b.statusID = 113)  AND ABS(modds) = 0.25 AND b.bettype IN(1,3,7,8,17,18) THEN 0.5 ELSE 1 END' ELSE '1' END + ') turnoverSB,' + char(13) +
                    
                    'SUM(CASE WHEN (b.bettype BETWEEN 81 AND 120 OR b.bettype BETWEEN 8101 AND 8120) THEN stake ELSE 0 END *' + char(13) +
                    CASE WHEN @drawfilter IN (2,3) THEN ' CASE WHEN b.statusID = 111 THEN 0 ELSE 1 END' ELSE '1' END + ') turnoverNG,' + char(13) +
                
                    'SUM(CASE WHEN b.bettype BETWEEN 31 AND 33 THEN CASE WHEN b.bettype in (33, 43) AND b.liveawayscore = 0 THEN stake/2 ELSE stake END ELSE 0 END *' + char(13) +
                    CASE WHEN @drawfilter IN (2,3) THEN ' CASE WHEN b.statusID = 111 THEN 0  ELSE 1 END' ELSE '1' END + ') turnoverRB,' + char(13) +
                    
                    'SUM(CASE WHEN b.bettype BETWEEN 1101 AND 1199 THEN stake ELSE 0 END *' + char(13) +
                    CASE WHEN @drawfilter IN (2,3) THEN ' CASE WHEN b.statusID = 111 THEN 0  ELSE 1 END' ELSE '1' END + ') turnoverLC,' + char(13) +
                    
                    'SUM(CASE WHEN b.bettype BETWEEN 1201 AND 1299 THEN stake ELSE 0 END *' + char(13) +
                    CASE WHEN @drawfilter IN (2,3) THEN ' CASE WHEN b.statusID = 111 THEN 0  ELSE 1 END' ELSE '1' END + ') turnoverVS,' + char(13) +
                    
                    
                    '0 as turnoverBA,' + char(13) +
                    
                    'SUM(CASE WHEN (b.bettype<31 OR b.bettype BETWEEN 121 AND 999 OR b.bettype BETWEEN 9001 AND 9399 ORb.bettype BETWEEN 1301 AND 1399)  THEN (b.winlost - b.actual_stake) ELSE 0 END ) AS MemWinlossSB,' + char(13) +
                    'SUM(CASE WHEN (b.bettype BETWEEN 81 AND 120 OR b.bettype BETWEEN 8101 AND 8120)  THEN (b.winlost - b.actual_stake) ELSE 0 END ) AS MemWinlossNG,' + char(13) +
                    'SUM(CASE WHEN b.bettype BETWEEN 31 AND 33 THEN (b.winlost - b.actual_stake) ELSE 0 END ) AS MemWinlossRB,' + char(13) +
                    'SUM(CASE WHEN b.bettype BETWEEN 1101 AND 1199 THEN (b.winlost - b.actual_stake) ELSE 0 END ) AS MemWinlossLC,' + char(13) +
                    'SUM(CASE WHEN b.bettype BETWEEN 1201 AND 1299 THEN (b.winlost - b.actual_stake) ELSE 0 END ) AS MemWinlossVS,' + char(13) +
                    
                    '0 AS MemWinlossBA,' + char(13) +
                    
                    '- SUM(CASE WHEN (b.bettype<31 OR b.bettype BETWEEN 121 AND 999 OR b.bettype BETWEEN 9001 AND 9399 ORb.bettype BETWEEN 1301 AND 1399)  THEN (b.winlost - b.actual_stake) ELSE 0 END) AS WinlossSB ,' + char(13) +
                    '- SUM(CASE WHEN (b.bettype BETWEEN 81 AND 120 OR b.bettype BETWEEN 8101 AND 8120)  THEN (b.winlost - b.actual_stake) ELSE 0 END) AS WinlossNG ,' + char(13) +
                    'SUM(CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.awinlost ELSE 0 END) AS WinlossRB,' + char(13) +
                    '- SUM(CASE WHEN b.bettype BETWEEN 1101 AND 1199 THEN (b.winlost - b.actual_stake) ELSE 0 END) AS WinlossLC,' + char(13) +
                    '- SUM(CASE WHEN b.bettype BETWEEN 1201 AND 1299 THEN (b.winlost - b.actual_stake) ELSE 0 END) AS WinlossVS,' + char(13) +
                    '0 as AmountDueToBA,' + char(13) +
                    '- SUM ( CASE WHEN b.bettype BETWEEN 31 AND 33 THEN (b.winlost - b.actual_stake + awinlost + comm) ELSE 0 END) as AmountDueToRB,' + char(13) +
                    '0 as CommBA,' + char(13) +
                    'SUM ( CASE WHEN b.bettype BETWEEN 31 AND 33 THEN (comm) ELSE 0 END) as CommRB,' + char(13) +
                    '- SUM(CASE WHEN (b.bettype<31 OR b.bettype BETWEEN 121 AND 999 OR b.bettype BETWEEN 9001 AND 9399 ORb.bettype BETWEEN 1301 AND 1399) THEN (b.awinlost + b.winlost - b.actual_stake + b.comm) ELSE 0 END)  as AmtDueToSB,' + char(13) +
                    '- SUM(CASE WHEN (b.bettype BETWEEN 81 AND 120 OR b.bettype BETWEEN 8101 AND 8120) THEN (b.awinlost + b.winlost - b.actual_stake + b.comm) ELSE 0 END)  as AmtDueToNG,' + char(13) +
                    '- SUM(CASE WHEN (b.bettype BETWEEN 1101 AND 1199) THEN (b.awinlost + b.winlost - b.actual_stake + b.comm) ELSE 0 END)  as AmtDueToLC,' + char(13) +
                    '- SUM(CASE WHEN (b.bettype BETWEEN 1201 AND 1299) THEN (b.awinlost + b.winlost - b.actual_stake + b.comm) ELSE 0 END)  as AmtDueToVS,' + char(13) +
                    'COUNT(b.transid) * ' +  CASE WHEN @drawfilter = 2 THEN 'CASE WHEN b.statusID = 111 THEN 0 ELSE 1 END' ELSE '1' END + ' Betcount' + char(13) +
                    ',SUM(b.playercomm) as Playercomm' + char(13) +
                'FROM dbo.bettrans b WITH (NOLOCK,INDEX=IX_recommend)' + char(13) +    
                    'INNER JOIN #tmpAg t ON b.recommend = t.custid'     + char(13) +
                    'LEFT JOIN [match] m with(nolock) ON b.matchid = m.matchid'     + char(13) +
                    'LEFT JOIN outright o with(nolock) ON b.matchid = o.orid'     + char(13) +
                    'LEFT JOIN league l with(nolock) ON o.leagueid = l.leagueid'     + char(13) +
                    'LEFT JOIN bodb_Licensee.dbo.LicenseeBATransaction_active BA WITH (NOLOCK) ON b.recommend=BA.recommend AND b.transid = BA.transid'     + char(13) +
                'WHERE b.winlostdate BETWEEN ''' + convert(varchar(10),@TempFromDate, 120) + ''' AND ''' + convert(varchar(10),@ToDate, 120) + '''' + char(13) +
                    'AND b.statusID IN (111,112,113)' + char(13) +
                    'AND b.matchid > 0 '     + char(13) +
                    'AND (b.bettype < ' + CASE WHEN @ShowSB=1 THEN + ' 31 OR b.bettype BETWEEN 121 AND 999 OR b.bettype BETWEEN 9001 AND 9399 ORb.bettype BETWEEN 1301 AND 1399' ELSE '0' END +
                        CASE WHEN @ShowRB = 1 THEN ' OR b.bettype BETWEEN 31 AND 33' ELSE '' END + 
                        CASE WHEN @ShowLC = 1 THEN ' OR b.bettype BETWEEN 1101 AND 1199' ELSE '' END + 
                        CASE WHEN @ShowVS = 1 THEN ' OR b.bettype BETWEEN 1201 AND 1299' ELSE '' END + 
                        CASE WHEN @ShowNG = 1 THEN ' OR b.bettype BETWEEN 81 AND 120 OR b.bettype BETWEEN 8101 AND 8120' ELSE '' END + ')' + char(13) +
                    CASE WHEN @bettype <> 0 THEN ' AND b.bettype = ' + convert(varchar(10), @Bettype)  ELSE '' END + char(13) +
                    'AND BA.transid IS NULL'     + char(13) +    
                    CASE WHEN @SportID<>0 THEN 'AND ((b.bettype=10 AND l.Sporttype = ' + convert(varchar(10), @SportID) + ') OR (b.bettype NOT IN (9,29,10) AND b.bettype NOT BETWEEN 31 AND 120 AND m.sporttype = ' + convert(varchar(10), @SportID) + '))  ' ELSE '' END + char(13) +
                    CASE 
                        WHEN @ReportType=1 THEN 'AND b.Liveindicator=1 AND b.bettype NOT IN (9,29,10,31,32,33) '
                        WHEN @ReportType=2 THEN 'AND b.liveindicator=0 '
                        ELSE '' END + char(13) + ' AND b.bettype NOT IN (901, 902, 903,904, 911, 912, 913, 914) ' +
                'GROUP BY b.winlostdate, t.LicenseeID,b.currency, b.bettype  , b.statusID'    + char(13)        
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
        SELECT @sql2 = @sql2 + '--BA rpt_Betting_BA' + char(13)
        SELECT @sql2 = @sql2 +
                'INSERT INTO #tmpWinLoss' + char(13) +
                'SELECT b.rptDate,b.siteID,b.currencyID,0 as TurnOverSB,0 as TurnOverNG,0 as TurnOverRB,0 as TurnOverLC, 0 as TurnoverVS,SUM(b.turnover * '  +
                    CASE WHEN @drawfilter IN (2,3) THEN 'CASE WHEN b.status = 111  THEN 0 WHEN b.status IN (114,115) THEN 0.5 ELSE 1 END' ELSE '1' END + ') TurnOverBA,' +  char(13) +
                    '0 as MemWinlossSB, 0 as MemWinlossNG, 0 as MemWinlossRB, 0 as MemWinlossLC, 0 as MemWinlossVS,'+ char(13) +
                    'SUM(b.winloss) MemWinlossBA,0 as WinlossSB, 0 as WinlossNG,0 AS WinlossRB, 0 AS WinlossLC,0 as WinlossVS, ' + char(13) +
                    '- SUM (b.winloss+b.WinlossA+b.CommissionA) as AmountDueToBA,' + char(13) +
                    '0 as AmountDueToRB,SUM (CommissionA) as CommBA,0 as CommRB,0 as AmtDueToSB, 0 as AmtDueToNG,0 as AmtDueToLC,0 as AmtDueToVS,' + char(13) +
                    'SUM(b.betcount) * ' +  CASE WHEN @drawfilter = 2 THEN 'CASE WHEN b.status = 111 THEN 0 ELSE 1 END' ELSE '1' END + ' Betcount' + char(13) +
                    ',SUM(b.CommissionP) as Playercomm' + char(13) +
                'FROM bodb_LicenseeReport.dbo.rpt_Betting_BA b WITH ( NOLOCK )  ' + char(13) +
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
    IF (@showSB = 1 or @ShowRB = 1 or @ShowNG = 1 OR @ShowLC=1 OR @ShowVS=1)
    BEGIN
        SELECT @sql2 = @sql2 + '--exclude BA rpt_Betting' + char(13)
        SELECT @sql2 = @sql2 +
                'INSERT INTO #tmpWinLoss' + char(13) +
                'SELECT b.rptDate,b.siteID,b.currencyID,'  + char(13) +
                    'SUM(CASE WHEN (b.bettype<31 OR b.bettype BETWEEN 121 AND 999) THEN turnover ELSE 0 END *' + char(13) +
                    CASE WHEN @drawfilter IN (2,3) THEN 'CASE WHEN b.status = 111  THEN 0 WHEN b.status IN (114,115) THEN 0.5 ELSE 1 END' ELSE '1' END + ') turnoverSB,' +  char(13) +
                
                    'SUM(CASE WHEN (b.bettype BETWEEN 81 AND 120 OR b.bettype BETWEEN 8101 AND 8120) THEN turnover ELSE 0 END *' + char(13) +
                    CASE WHEN @drawfilter IN (2,3) THEN 'CASE WHEN b.status = 111  THEN 0 WHEN b.status IN (114,115) THEN 0.5 ELSE 1 END' ELSE '1' END + ') turnoverNG,' +  char(13) +
                
                    'SUM(CASE WHEN (b.bettype BETWEEN 31 AND 33) THEN turnover ELSE 0 END * CASE WHEN b.bettype=33 AND b.status IN (114,115) THEN 0.5 ELSE 1 END *' + char(13) +
                    CASE WHEN @drawfilter IN (2,3) THEN 'CASE WHEN b.status = 111  THEN 0 WHEN b.status IN (114,115) AND b.bettype <> 33 THEN 0.5 ELSE 1 END' ELSE '1' END + ') turnoverRB,' +  char(13) +
                    
                    'SUM(CASE WHEN (b.bettype BETWEEN 1101 AND 1199) THEN turnover ELSE 0 END *' + char(13) +
                    CASE WHEN @drawfilter IN (2,3) THEN 'CASE WHEN b.status = 111  THEN 0 WHEN b.status IN (114,115)  THEN 0.5 ELSE 1 END' ELSE '1' END + ') turnoverLC,' +  char(13) +
                    
                    'SUM(CASE WHEN (b.bettype BETWEEN 1201 AND 1299) THEN turnover ELSE 0 END *' + char(13) +
                    CASE WHEN @drawfilter IN (2,3) THEN 'CASE WHEN b.status = 111  THEN 0 WHEN b.status IN (114,115)  THEN 0.5 ELSE 1 END' ELSE '1' END + ') turnoverVS,' +  char(13) +
                    
                    
                    '0 as turnoverBA,' + char(13) +
                    
                    'SUM(CASE WHEN (b.bettype<31 OR b.bettype BETWEEN 121 AND 999 OR b.bettype BETWEEN 9001 AND 9399 ORb.bettype BETWEEN 1301 AND 1399)  THEN (b.winloss) ELSE 0 END ) AS MemWinlossSB,' + char(13) +
                    'SUM(CASE WHEN (b.bettype BETWEEN 81 AND 120 OR b.bettype BETWEEN 8101 AND 8120)  THEN (b.winloss) ELSE 0 END ) AS MemWinlossNG,' + char(13) +
                    'SUM(CASE WHEN b.bettype BETWEEN 31 AND 33 THEN (b.winloss) ELSE 0 END ) AS MemWinlossRB,' + char(13) +
                    'SUM(CASE WHEN (b.bettype BETWEEN 1101 AND 1199)  THEN (b.winloss) ELSE 0 END ) AS MemWinlossLC,' + char(13) +
                    'SUM(CASE WHEN (b.bettype BETWEEN 1201 AND 1299)  THEN (b.winloss) ELSE 0 END ) AS MemWinlossVS,' + char(13) +
                    
                    '0 AS MemWinlossBA,' + char(13) +
                    
                    
                    '- SUM(CASE WHEN (b.bettype<31 OR b.bettype BETWEEN 121 AND 999 OR b.bettype BETWEEN 9001 AND 9399 ORb.bettype BETWEEN 1301 AND 1399)  THEN b.winloss ELSE 0 END) AS WinlossSB ,'+ char(13) +
                    '- SUM(CASE WHEN (b.bettype BETWEEN 81 AND 120 OR b.bettype BETWEEN 8101 AND 8120)  THEN b.winloss ELSE 0 END) AS WinlossNG ,'+ char(13) +
                    'SUM(CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.WinlossA ELSE 0 END) AS WinlossRB,' + char(13) +
                    '- SUM(CASE WHEN (b.bettype BETWEEN 1101 AND 1199)  THEN b.winloss ELSE 0 END) AS WinlossLC ,'+ char(13) +
                    '- SUM(CASE WHEN (b.bettype BETWEEN 1201 AND 1299)  THEN b.winloss ELSE 0 END) AS WinlossVS ,'+ char(13) +
                    '0 as AmountDueToBA,' + char(13) +
                    '- SUM ( CASE WHEN b.bettype BETWEEN 31 AND 33 THEN (b.winloss+b.winlossA+b.CommissionA) ELSE 0 END) as AmountDueToRB,' + char(13) +
                    '0 as CommBA,' + char(13) +
                    'SUM ( CASE WHEN b.bettype BETWEEN 31 AND 33 THEN CommissionA ELSE 0 END) as CommRB,' + char(13) +
                    '- SUM(CASE WHEN (b.bettype<31 OR b.bettype BETWEEN 121 AND 999 OR b.bettype BETWEEN 9001 AND 9399 ORb.bettype BETWEEN 1301 AND 1399) THEN b.winlossA + b.winloss + b.CommissionA ELSE 0 END)  as AmtDueToSB   ,' + char(13) +
                    '- SUM(CASE WHEN (b.bettype BETWEEN 81 AND 120 OR b.bettype BETWEEN 8101 AND 8120) THEN b.winlossA + b.winloss + b.CommissionA ELSE 0 END)  as AmtDueToNG   ,' + char(13) +
                    '- SUM(CASE WHEN (b.bettype BETWEEN 1101 AND 1199) THEN b.winlossA + b.winloss + b.CommissionA ELSE 0 END)  as AmtDueToLC   ,' + char(13) +
                    '- SUM(CASE WHEN (b.bettype BETWEEN 1201 AND 1299) THEN b.winlossA + b.winloss + b.CommissionA ELSE 0 END)  as AmtDueToVS   ,' + char(13) +
                    'SUM(b.betcount) * ' +  CASE WHEN @drawfilter = 2 THEN 'CASE WHEN b.status = 111 THEN 0 ELSE 1 END' ELSE '1' END + ' Betcount' + char(13) +
                    ',SUM(b.CommissionP) as Playercomm' + char(13) +
                'FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH ( NOLOCK )  ' + char(13) +
                    'INNER JOIN (SELECT VAL FROM strSplit(''' + @Licensee + ''','','')) s ON b.siteid = s.VAL'  + char(13) +
                    'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + char(13) +
                'WHERE b.rptDate BETWEEN ''' + convert(varchar(10),@FromDate, 120) + ''' AND ''' + convert(varchar(10),@TempToDate, 120) + '''' + char(13) + 
                    'AND b.status NOT IN (-1,103)' + char(13) +
                    'AND (b.bettype < ' + CASE WHEN @ShowSB=1 THEN + ' 31 OR b.bettype BETWEEN 121 AND 999 OR b.bettype BETWEEN 9001 AND 9399 ORb.bettype BETWEEN 1301 AND 1399' ELSE '0' END +
                        CASE WHEN @ShowRB = 1 THEN ' OR b.bettype BETWEEN 31 AND 33' ELSE '' END + 
                        CASE WHEN @ShowLC = 1 THEN ' OR b.bettype BETWEEN 1101 AND 1199' ELSE '' END + 
                        CASE WHEN @ShowVS = 1 THEN ' OR b.bettype BETWEEN 1201 AND 1299' ELSE '' END + 
                        CASE WHEN @ShowNG = 1 THEN ' OR b.bettype BETWEEN 81 AND 120 OR b.bettype BETWEEN 8101 AND 8120' ELSE '' END + ')' + char(13) +
                    CASE WHEN @Currency <> 0 THEN 'AND CurrencyID=' + convert(varchar(10), @Currency) ELSE '' END + char(13) +
                    CASE WHEN @excludeTest=1 THEN 'AND CurrencyID<>20' ELSE '' END + char(13) +
                    CASE WHEN @bettype <> 0 THEN 'AND b.bettype=' + convert(varchar(10), @bettype) ELSE '' END + char(13) +
                    CASE WHEN @SportID <> 0 THEN 'AND b.bettype NOT IN (9,29 ) AND b.bettype NOT BETWEEN 31 AND 120 AND l.Sporttype =' + convert(varchar(10), @SportID) ELSE '' END + char(13) +
                    CASE 
                        WHEN @ReportType=1 THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10,31,32,33) '
                        WHEN @ReportType=2 THEN 'AND b.IsLive=0 '
                        ELSE '' END + char(13) + ' AND b.bettype NOT IN (901, 902, 903,904, 911, 912, 913, 914) ' +
                'GROUP BY  b.rptDate,  b.siteID,   b.currencyID,b.status' +  char(13) 
    END
            
END            

SELECT @sql2 = @sql2 + '--Output data from temp table' + char(13)

SELECT @sql2 = @sql2  +char(13)+
                            ' SELECT * INTO #TempExchange FROM Lrf_f_GetExchangeDaily('''+convert(varchar(10),@FromDate, 120)+''','''+convert(varchar(10),@ToDate, 120)+''')'+char(13)+
                            'WHERE exchangeid IN (SELECT DISTINCT Currency FROM #tmpWinLoss)'+char(13)

SELECT @output = 
            'SELECT '  + char(13) +
                'r.ResellerName,'  + char(13) +
                'l.LicenseeName,'  + char(13) +
                'CASE WHEN Currency = 51 THEN ''' + @VNDCurrencyName + ''' ELSE e.Code END currencyName,' + char(13) +
                'SUM(TurnOverSB)    AS TurnoverSB,'  + char(13) +
                'SUM(TurnOverNG)    AS TurnoverNG,'  + char(13) +
                'SUM(TurnOverRB)    AS TurnoverRB,'  + char(13) +
                'SUM(TurnOverLC)    AS TurnoverLC,'  + char(13) +
                'SUM(TurnOverVS)    AS TurnoverVS,'  + char(13) +
                'SUM(TurnOverBA)    AS TurnoverBA,'  + char(13) +
                'SUM(MemWinlossSB)        AS MemWinlossSB,'  + char(13) +
                'SUM(MemWinlossNG)        AS MemWinlossNG,'  + char(13) +
                'SUM(MemWinlossRB)        AS MemWinlossRB,'  + char(13) +
                'SUM(MemWinlossLC)        AS MemWinlossLC,'  + char(13) +
                'SUM(MemWinlossVS)        AS MemWinlossVS,'  + char(13) +
                'SUM(MemWinlossBA)        AS MemWinlossBA,'  + char(13) +
                'SUM(WinlossSB)        AS WinlossSB,'  + char(13) +
                'SUM(WinlossNG) AS WinlossNG,'  + char(13) +
                'SUM(WinlossRB)    AS WinlossRB,'  + char(13) +
                'SUM(WinlossLC)    AS WinlossLC,'  + char(13) +
                'SUM(WinlossVS)    AS WinlossVS,'  + char(13) +
                'SUM(CommBA) AS CommBA,'  + char(13) +
                'SUM(CommRB) AS CommRB,'  + char(13) +
                'SUM(AmtDuetoBA) AS AmtDuetoBA,'  + char(13) +
                'SUM(AmtDuetoRB) AS AmtDuetoRB,'  + char(13) +
                'SUM(AmtDuetoSB) AS AmtDuetoSB,'  + char(13) +
                'SUM(AmtDuetoNG) AS AmtDuetoNG,'  + char(13) +
                'SUM(AmtDuetoLC) AS AmtDuetoLC,'  + char(13) +
                'SUM(AmtDuetoVS) AS AmtDuetoVS,'  + char(13) +
                'SUM(Betcount)    AS Betcount,'  + char(13) +
                'SUM(Playercomm)    AS Playercomm,'  + char(13) +
                
                'CAST(SUM(TurnOverSB* e.MYR) AS MONEY)    AS TurnoverSBMYR,'  + char(13) +
                'CAST(SUM(TurnOverNG* e.MYR) AS MONEY)    AS TurnoverNGMYR,'  + char(13) +
                'CAST(SUM(TurnOverRB* e.MYR) AS MONEY)    AS TurnoverRBMYR,'  + char(13) +
                'CAST(SUM(TurnOverLC* e.MYR) AS MONEY)    AS TurnoverLCMYR,'  + char(13) +
                'CAST(SUM(TurnOverVS* e.MYR) AS MONEY)    AS TurnoverVSMYR,'  + char(13) +
                'CAST(SUM(TurnOverBA* e.MYR) AS MONEY)    AS TurnoverBAMYR,'  + char(13) +
                'CAST(SUM(MemWinlossSB* e.MYR) AS MONEY)        AS MemWinlossSBMYR,'  + char(13) +
                'CAST(SUM(MemWinlossNG* e.MYR) AS MONEY)        AS MemWinlossNGMYR,'  + char(13) +
                'CAST(SUM(MemWinlossRB* e.MYR) AS MONEY)        AS MemWinlossRBMYR,'  + char(13) +
                'CAST(SUM(MemWinlossLC* e.MYR) AS MONEY)        AS MemWinlossLCMYR,'  + char(13) +
                'CAST(SUM(MemWinlossVS* e.MYR) AS MONEY)        AS MemWinlossVSMYR,'  + char(13) +
                'CAST(SUM(MemWinlossBA* e.MYR) AS MONEY)        AS MemWinlossBAMYR,'  + char(13) +
                
                'CAST(SUM(WinlossSB * e.MYR) AS MONEY)        AS WinlossSBMYR,'  + char(13) +
                'CAST(SUM(WinlossNG * e.MYR) AS MONEY) AS WinlossNGMYR,'  + char(13) +
                'CAST(SUM(WinlossRB*e.MYR) AS MONEY)    AS WinlossRBMYR,'  + char(13) +
                'CAST(SUM(WinlossLC*e.MYR) AS MONEY)    AS WinlossLCMYR,'  + char(13) +
                'CAST(SUM(WinlossVS*e.MYR) AS MONEY)    AS WinlossVSMYR,'  + char(13) +
                'CAST(SUM(CommBA * e.MYR) AS MONEY) AS CommBAMYR,'  + char(13) +
                'CAST(SUM(CommRB * e.MYR) AS MONEY) AS CommRBMYR,'  + char(13) +
                'CAST(SUM(AmtDuetoBA*e.MYR) AS MONEY) AS AmtDuetoBAMYR,'  + char(13) +
                'CAST(SUM(AmtDuetoRB*e.MYR) AS MONEY) AS AmtDuetoRBMYR,'  + char(13) +
                'CAST(SUM(AmtDuetoSB * e.MYR) AS MONEY) AS AmtDuetoSBMYR,'  + char(13) +
                'CAST(SUM(AmtDuetoNG * e.MYR) AS MONEY) AS AmtDuetoNGMYR,'  + char(13) +
                'CAST(SUM(AmtDuetoLC * e.MYR) AS MONEY) AS AmtDuetoLCMYR,'  + char(13) +
                'CAST(SUM(AmtDuetoVS * e.MYR) AS MONEY) AS AmtDuetoVSMYR,'  + char(13) +
                'CAST(SUM(Playercomm * e.MYR) AS MONEY)    AS PlayercommMYR,'  + char(13) +
                
                'CAST(SUM(TurnOverSB* e.USD) AS MONEY)    AS TurnoverSBUSD,'  + char(13) +
                'CAST(SUM(TurnOverNG* e.USD) AS MONEY)    AS TurnoverNGUSD,'  + char(13) +
                'CAST(SUM(TurnOverRB* e.USD) AS MONEY)    AS TurnoverRBUSD,'  + char(13) +
                'CAST(SUM(TurnOverLC* e.USD) AS MONEY)    AS TurnoverLCUSD,'  + char(13) +
                'CAST(SUM(TurnOverVS* e.USD) AS MONEY)    AS TurnoverVSUSD,'  + char(13) +
                'CAST(SUM(TurnOverBA* e.USD) AS MONEY)    AS TurnoverBAUSD,'  + char(13) +
                'CAST(SUM(MemWinlossSB* e.USD) AS MONEY)        AS MemWinlossSBUSD,'  + char(13) +
                'CAST(SUM(MemWinlossNG* e.USD) AS MONEY)        AS MemWinlossNGUSD,'  + char(13) +
                'CAST(SUM(MemWinlossRB* e.USD) AS MONEY)        AS MemWinlossRBUSD,'  + char(13) +
                'CAST(SUM(MemWinlossLC* e.USD) AS MONEY)        AS MemWinlossLCUSD,'  + char(13) +
                'CAST(SUM(MemWinlossVS* e.USD) AS MONEY)        AS MemWinlossVSUSD,'  + char(13) +
                'CAST(SUM(MemWinlossBA* e.USD) AS MONEY)        AS MemWinlossBAUSD,'  + char(13) +
                'CAST(SUM(WinlossSB * e.USD) AS MONEY)        AS WinlossSBUSD,'  + char(13) +
                'CAST(SUM(WinlossNG * e.USD) AS MONEY) AS WinlossNGUSD,'  + char(13) +
                'CAST(SUM(WinlossRB*e.USD) AS MONEY)    AS WinlossRBUSD,'  + char(13) +
                'CAST(SUM(WinlossLC*e.USD) AS MONEY)    AS WinlossLCUSD,'  + char(13) +
                'CAST(SUM(WinlossVS*e.USD) AS MONEY)    AS WinlossVSUSD,'  + char(13) +
                'CAST(SUM(CommBA * e.USD) AS MONEY) AS CommBAUSD,'  + char(13) +
                'CAST(SUM(CommRB * e.USD) AS MONEY) AS CommRBUSD,'  + char(13) +
                'CAST(SUM(AmtDuetoBA*e.USD) AS MONEY) AS AmtDuetoBAUSD,'  + char(13) +
                'CAST(SUM(AmtDuetoRB*e.USD) AS MONEY) AS AmtDuetoRBUSD,'  + char(13) +
                'CAST(SUM(AmtDuetoSB * e.USD) AS MONEY) AS AmtDuetoSBUSD,'  + char(13) +
                'CAST(SUM(AmtDuetoNG * e.USD) AS MONEY) AS AmtDuetoNGUSD,'  + char(13) +
                'CAST(SUM(AmtDuetoLC * e.USD) AS MONEY) AS AmtDuetoLCUSD,'  + char(13) +
                'CAST(SUM(AmtDuetoVS * e.USD) AS MONEY) AS AmtDuetoVSUSD,'  + char(13) +
                'CAST(SUM(Playercomm * e.USD) AS MONEY)    AS PlayercommUSD,'  + char(13) +
                
                'CAST(SUM(TurnOverSB* e.EUR) AS MONEY)    AS TurnoverSBEUR,'  + char(13) +
                'CAST(SUM(TurnOverNG* e.EUR) AS MONEY)    AS TurnoverNGEUR,'  + char(13) +
                'CAST(SUM(TurnOverRB* e.EUR) AS MONEY)    AS TurnoverRBEUR,'  + char(13) +
                'CAST(SUM(TurnOverLC* e.EUR) AS MONEY)    AS TurnoverLCEUR,'  + char(13) +
                'CAST(SUM(TurnOverVS* e.EUR) AS MONEY)    AS TurnoverVSEUR,'  + char(13) +
                'CAST(SUM(TurnOverBA* e.EUR) AS MONEY)    AS TurnoverBAEUR,'  + char(13) +
                'CAST(SUM(MemWinlossSB* e.EUR) AS MONEY)        AS MemWinlossSBEUR,'  + char(13) +
                'CAST(SUM(MemWinlossNG* e.EUR) AS MONEY)        AS MemWinlossNGEUR,'  + char(13) +
                'CAST(SUM(MemWinlossRB* e.EUR) AS MONEY)        AS MemWinlossRBEUR,'  + char(13) +
                'CAST(SUM(MemWinlossLC* e.EUR) AS MONEY)        AS MemWinlossLCEUR,'  + char(13) +
                'CAST(SUM(MemWinlossVS* e.EUR) AS MONEY)        AS MemWinlossVSEUR,'  + char(13) +
                'CAST(SUM(MemWinlossBA* e.EUR) AS MONEY)        AS MemWinlossBAEUR,'  + char(13) +
                'CAST(SUM(WinlossSB * e.EUR) AS MONEY)        AS WinlossSBEUR,'  + char(13) +
                'CAST(SUM(WinlossNG * e.EUR) AS MONEY) AS WinlossNGEUR,'  + char(13) +
                'CAST(SUM(WinlossRB*e.EUR) AS MONEY)    AS WinlossRBEUR,'  + char(13) +
                'CAST(SUM(WinlossLC*e.EUR) AS MONEY)    AS WinlossLCEUR,'  + char(13) +
                'CAST(SUM(WinlossVS*e.EUR) AS MONEY)    AS WinlossVSEUR,'  + char(13) +
                'CAST(SUM(CommBA * e.EUR) AS MONEY) AS CommBAEUR,'  + char(13) +
                'CAST(SUM(CommRB * e.EUR) AS MONEY) AS CommRBEUR,'  + char(13) +
                'CAST(SUM(AmtDuetoBA*e.EUR) AS MONEY) AS AmtDuetoBAEUR,'  + char(13) +
                'CAST(SUM(AmtDuetoRB*e.EUR) AS MONEY) AS AmtDuetoRBEUR,'  + char(13) +
                'CAST(SUM(AmtDuetoSB * e.EUR) AS MONEY) AS AmtDuetoSBEUR,'  + char(13) +
                'CAST(SUM(AmtDuetoNG * e.EUR) AS MONEY) AS AmtDuetoNGEUR,'  + char(13) +
                'CAST(SUM(AmtDuetoLC * e.EUR) AS MONEY) AS AmtDuetoLCEUR,'  + char(13) +
                'CAST(SUM(AmtDuetoVS * e.EUR) AS MONEY) AS AmtDuetoVSEUR,'  + char(13) +
                'CAST(SUM(Playercomm * e.EUR) AS MONEY)    AS PlayercommEUR'  + char(13) +
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
    PRINT (@sql)
    PRINT (@sql2)
    PRINT (@output)
END
ELSE EXEC(@sql +  @sql2 + @output)
 
END
GO