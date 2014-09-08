USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_CurrencyWinloss_Details]    Script Date: 9/8/2014 5:19:55 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_Rpt_LicenseeCurrencyWinloss_xtest    Script Date: 2013-06-05 4:42:57 PM ******/
ALTER PROCEDURE [dbo].[LA_Rpt_CurrencyWinloss_Details]  
 @PartyIDs		VARCHAR(1000),
 @Currency		INT = 0,
 @FromDate	SMALLDATETIME,  
 @ToDate		SMALLDATETIME,
 @ProductCode	 Varchar(100) = 'SB',
 @SportType		INT=0,
 @Bettype		INT=0,
 @ReportBy	TINYINT=0,  
 @drawfilter SMALLINT = 1  ,
 @excludeTest BIT = 0,
 @Debug		BIT = 0

AS  
/*  Created: Florent.Nguyen  
	Date: 2014-09-04
    Task : Licensee Currency Winlost Report
    DB: DB052.bodb02  
   
    Revisions:  	
		
	Param's Explanation:  
	  + @ReportType: 1-Live; 2-Non-Live; 0: All;  
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS	  
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
			'CREATE TABLE #tmpParty (
						    PartyID INT
						    ,LicenseeID INT
						    ,ParentID INT
						    ,ParentName Varchar(100)
						    ,AffectedDate DATETIME
						    ,Fromdate DATETIME
						    ,Todate DATETIME
						    )

					   DECLARE @PartyList  table 
					   (
						  PartyID INT,
						  PartyName VARCHAR(100),
						  ParentID INT
					   )
					   INSERT INTO @PartyList
					   EXEC bodb_licensee.dbo.LA_PartyListSel ' + char(13) +			  
				    'INSERT INTO #tmpParty (
						PartyID
						,ParentID
						,ParentName
						,LicenseeID
						,AffectedDate
						,Fromdate
						,Todate
						)
					SELECT p.PartyID
						 ,pl.ParentID
						 ,parent.PartyName
						,l.LicenseeID
						,l.AffectedDate
						,''' + CONVERT (varchar(10),@fromdate,120)+ '''
						,'''+ CONVERT (varchar(10),@ToDate,120)+ '''
					FROM @PartyList pl
					INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON pl.PartyID=p.PartyID
					INNER JOIN bodb_licensee.dbo.Licensees l(NOLOCK) ON p.OldRefID = l.LicenseeID
						AND p.PartyType = 1
					LEFT JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
					LEFT JOIN (SELECT PartyID,PartyName FROM @PartyList WHERE ParentID = 0) parent ON pl.ParentID = parent.PartyID
					WHERE p.PartyID IN ( '+ @PartyIDs +')
						AND l.AffectedDate IS NOT NULL OR pd.IsDeposit = 0' + char(13) + 
		  'IF EXISTS (
				   SELECT TOP 1 1
				   FROM #tmpParty
				   WHERE AffectedDate > Fromdate
				   )
			  BEGIN
				  UPDATE #tmpParty
				  SET Fromdate = AffectedDate
				  WHERE AffectedDate > Fromdate
			  END'+ char(13) + 
		  'CREATE TABLE #Bettype (Bettype INT)'+ char(13) 

		   IF @Bettype != 0
			   SELECT @sql = @sql + 'INSERT INTO #Bettype' + char(13) + 
			   'SELECT '+ COnvert(varchar(100),@Bettype) +  char(13) 
		   ELSE
		   BEGIN
			   IF @ProductCode = 'SB'
				   OR @ProductCode = 'BA'
			   BEGIN
			    SELECT @sql = @sql + 'INSERT INTO #Bettype'+  char(13) + 
			    'SELECT typeid
			    FROM dbo.bettype WITH (NOLOCK)
			    WHERE typeid < 31
				    OR typeid BETWEEN 121 AND 999
				    OR typeid BETWEEN 1301 AND 1399'
			   END

			   IF @ProductCode = 'RB'
			   BEGIN
				    SELECT @sql = @sql + 'INSERT INTO #Bettype
				   SELECT typeid
				   FROM dbo.bettype WITH (NOLOCK)
				   WHERE typeid BETWEEN 31 AND 33'
			   END

			   IF @ProductCode = 'NG'
			   BEGIN
				    SELECT @sql = @sql + 'INSERT INTO #Bettype
				   SELECT typeid
				   FROM dbo.bettype WITH (NOLOCK)
				   WHERE typeid BETWEEN 81 AND 120'
			   END

			   IF @ProductCode = 'LC'
			   BEGIN
				    SELECT @sql = @sql + 'INSERT INTO #Bettype
				   SELECT typeid
				   FROM dbo.bettype WITH (NOLOCK)
				   WHERE typeid BETWEEN 1101 AND 1199'
			   END

			   IF @ProductCode = 'VS'
			   BEGIN
				    SELECT @sql = @sql + 'INSERT INTO #Bettype
				   SELECT typeid
				   FROM dbo.bettype WITH (NOLOCK)
				   WHERE typeid BETWEEN 1201 AND 1299'
			   END

			   IF @ProductCode = 'CS'
			   BEGIN
				    SELECT @sql = @sql + 'INSERT INTO #Bettype
				   SELECT typeid
				   FROM dbo.bettype WITH (NOLOCK)
				   WHERE typeid = 71'
			   END
		   END
			--'CREATE UNIQUE CLUSTERED INDEX IX_tmpAg on #tmpAg (LicenseeID,CustID)' + char(13)
	IF @ProductCode = 'BA' 
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
					'INNER JOIN @tmpParty tp ON b.siteid = tp.LicenseeID'  + char(13) +
					'INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype'  + char(13) +
					'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + char(13) +
				'WHERE b.rptDate BETWEEN tp.Fromdate and tp.ToDate' + char(13) + 
					'AND b.status NOT IN (-1,103)' + char(13) +
					CASE WHEN @Currency <> 0 THEN 'AND CurrencyID=' + convert(varchar(10), @Currency) ELSE '' END + char(13) +
					CASE WHEN @excludeTest=1 THEN 'AND CurrencyID<>20' ELSE '' END + char(13) +
					CASE WHEN @SportType <> 0 THEN 'AND b.bettype NOT IN (9,29) AND l.Sporttype =' + convert(varchar(10), @SportType) ELSE '' END + char(13) +
					CASE 
						WHEN @ReportBy = 1 THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10) '
						WHEN @ReportBy = 2 THEN 'AND b.IsLive=0 '
						ELSE '' END + char(13) +
				'GROUP BY  b.rptDate,  b.siteID,   b.currencyID,b.status' +  char(13) 
				
	END	
	--exclude BA tickets
	ELSE
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
				     'INNER JOIN #tmpParty tp ON b.siteid = tp.LicenseeID'  + char(13) +
					'INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype'  + char(13) +
					'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + char(13) +
				'WHERE b.rptDate BETWEEN tp.FromDate and tp.Todate' + char(13) + 
					'AND b.status NOT IN (-1,103)' + char(13) +					
					CASE WHEN @Currency <> 0 THEN 'AND CurrencyID=' + convert(varchar(10), @Currency) ELSE '' END + char(13) +
					CASE WHEN @excludeTest=1 THEN 'AND CurrencyID<>20' ELSE '' END + char(13) +
					CASE WHEN @SportType <> 0 THEN 'AND b.bettype NOT IN (9,29 ) AND b.bettype NOT BETWEEN 31 AND 120 AND l.Sporttype =' + convert(varchar(10), @Sporttype) ELSE '' END + char(13) +
					CASE 
						WHEN @ReportBy = 1 THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10,31,32,33) '
						WHEN @ReportBy = 2 THEN 'AND b.IsLive=0 '
						ELSE '' END + char(13) +
				'GROUP BY  b.rptDate,  b.siteID,   b.currencyID,b.status' +  char(13) 
	END
			
END			

SELECT @sql = @sql + '--Output data from temp table' + char(13)

SELECT @sql = @sql  +char(13)+
		' SELECT * INTO #TempExchange FROM Lrf_f_GetExchangeDaily('''+convert(varchar(10),@FromDate, 120)+''','''+convert(varchar(10),@ToDate, 120)+''')' + char(13)

SELECT @output = 
			'SELECT '  + char(13) +			
				't.PartyID,' + char(13) +
				'l.LicenseeName AS PartyName,'  + char(13) +
				't.ParentName,'+ char(13) +
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
				'INNER JOIN bodb_Licensee.dbo.Licensees l(NOLOCK) ON l.LicenseeID = w.LicenseeID' + char(13) +	
				'LEFT JOIN #tmpParty t ON w.LicenseeID = t.LicenseeID ' + char(13) +	
				'INNER JOIN #TempExchange e'+char(13)+
				'ON w.winlostdate = e.ExchangeDate AND w.currency = e.ExchangeId'  + char(13) +			
			'GROUP BY t.PartyID,l.LicenseeName,t.ParentName,CASE WHEN Currency = 51 THEN ''' + @VNDCurrencyName + ''' ELSE e.Code END '  + char(13) +
			'ORDER BY t.PartyID,l.LicenseeName,t.ParentName'  + char(13) +
			
			'DROP TABLE #tmpWinLoss' + char(13)+
			'DROP TABLE #Bettype' + char(13) +
			'DROP TABLE #tmpParty' + char(13) +
			'DROP TABLE #TempExchange'+char(13) 
			
			
IF (@debug = 1) 
BEGIN
	print @sql
	print @output
END

ELSE EXEC(@sql + @output)
 
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_CurrencyWinloss_Details] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_CurrencyWinloss_Details] TO bodbAdminNet 

