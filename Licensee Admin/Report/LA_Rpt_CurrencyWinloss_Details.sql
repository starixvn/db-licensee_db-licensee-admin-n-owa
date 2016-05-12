USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_CurrencyWinloss_Details]    Script Date: 01/12/2014 14:33:41 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****** Object:  Stored Procedure dbo.OA_Rpt_LicenseeCurrencyWinloss_xtest    Script Date: 2013-06-05 4:42:57 PM ******/
ALTER PROCEDURE [dbo].[LA_Rpt_CurrencyWinloss_Details] 
     @PartyIDs				VARCHAR(5500)	= ''
	, @Currency				INT				= 0
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME
	, @ProductCodes			VARCHAR(1000)	= 'SB'
	, @SportType			INT				= 0
	, @Bettype				INT				= 0
	, @ReportBy				TINYINT			= 0
	, @drawfilter			SMALLINT		= 1
	, @excludeTest			BIT				= 0
	, @Debug				BIT				= 0
AS
/*  Created: Florent.Nguyen  
	Date: 2014-09-04
    Task : Licensee Currency Winlost Report
    DB: DB052.bodb02  
   
    Revisions:  	
	   - 20141021@Florent: show credit's licensee
	   - 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
	   - 20150703@Florent: add GBP
	Param's Explanation:  
	  + @ReportType: 1-Live; 2-Non-Live; 0: All;  
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS	  
*/
BEGIN
	DECLARE @sql VARCHAR(MAX)
	DECLARE @output VARCHAR(MAX)
	DECLARE @TempFromDate DATETIME
		,@TempToDate DATETIME
	DECLARE @VNDCurrencyName VARCHAR(20)

	SELECT @VNDCurrencyName = currency
	FROM exchange(NOLOCK)
	WHERE ExchangeId = 51

	IF LEN(@PartyIDs) = 0
		RETURN

	SELECT @sql = 'SET NOCOUNT ON  ' + CHAR(13)

	--declare
	SELECT @sql = @sql + '--Declare variable:' + CHAR(13)

	SELECT @sql = @sql + 'CREATE TABLE #tmpWinLoss(winlostdate DATETIME, PartyID INT, ProductID INT, Currency	INT,TurnOver MONEY,Winlost MONEY,LicenseeWL MONEY,WinlossRB MONEY,AmtDueToBA MONEY,AmtDueToRB MONEY,CommBA MONEY,CommRB	MONEY,Company MONEY,Betcount BIGINT,Playercomm MONEY)' + CHAR(13) + 
					 'CREATE INDEX IX_tmpWinloss ON #tmpWinLoss(PartyID,winlostdate,Currency)' + CHAR(13) + 
					 'DECLARE @i INT ' + CHAR(13) + 
				    'CREATE TABLE #Data (
							  rptDate	 Datetime
							 ,SiteID		 INT
							 ,PartyID		 INT
							 ,ProductID	 INT
							 ,Bettype		 INT
							 ,Status		 SMALLINT
							 ,CurrencyID	 INT
							 ,TurnOver	 MONEY
							 ,Winloss		 MONEY
							 ,WinlossA	 MONEY
							 ,CommissionA	 MONEY
							 ,CommissionP	 MONEY
							 ,Betcount	 BIGINT
							 )' + CHAR(13) +  
					'CREATE TABLE #tmpParty (
							 PartyID	    INT
							 ,LicenseeID   INT
							 ,isDeposit    INT
							 ,AffectedDate SMALLDATETIME
							 ,ProductID    INT 
							 ,Rate	    Money
							 ,Fromdate	    SMALLDATETIME
							 ,Todate	    SMALLDATETIME
							 )' + CHAR(13) + 
				    'INSERT INTO #tmpParty (PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, Rate, Fromdate, Todate)
					   SELECT PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, DI_Rate, Fromdate, Todate
					   FROM bodb_licensee.dbo.LA_f_ChargeInfo (''' + @PartyIDs + ''',''' +CONVERT(VARCHAR(10), @FromDate, 120) + ''',''' + CONVERT(VARCHAR(10), @ToDate, 120) + ''',''' + @ProductCodes + ''',''OA'+''','''+ +CONVERT(VARCHAR(10), @ExcludeTest, 120) + ''')' + CHAR(13) + 				
    'CREATE TABLE #Bettype (Bettype INT,ProductID INT)' + CHAR(13)
    
    SELECT @sql = @sql + ' INSERT INTO #Bettype(Bettype,ProductID)
    SELECT Bettype,ProductID
    FROM bodb_licensee.dbo.LA_f_BettypeProductMapping('''+ CONVERT(VARCHAR,@Bettype)+''','''+ @ProductCodes+''')'

	--'CREATE UNIQUE CLUSTERED INDEX IX_tmpAg on #tmpAg (LicenseeID,CustID)' + char(13)
	IF CHARINDEX('BA', @ProductCodes) <> 0
	BEGIN
		SELECT @sql = @sql + '--BA rpt_Betting_BA' + CHAR(13)

		SELECT @sql = @sql + 'INSERT INTO #tmpWinLoss' + CHAR(13) + 
				'SELECT b.rptDate,tp.PartyID, tp.ProductID,b.currencyID,SUM(b.turnover * ' + CASE 
				WHEN @drawfilter IN (2, 3)
					THEN 'CASE WHEN b.status = 111  THEN 0 WHEN b.status IN (114,115) THEN 0.5 ELSE 1 END'
				ELSE '1'
				END + '),' + CHAR(13) + 'SUM(b.winloss),0 as LicenseeWL,0 AS WinlossRB,' + CHAR(13) +
				
				'- SUM((b.winloss * tp.Rate )+ b.CommissionA) AS AmountDueToBA,' + CHAR(13) + 
				'0 as AmountDueToRB,SUM (CommissionA) as CommBA,0 as CommRB,0 as Company,' + CHAR(13) + 
				'SUM(b.betcount) * ' + CASE 
				WHEN @drawfilter = 2
					THEN 'CASE WHEN b.status = 111 THEN 0 ELSE 1 END'
				ELSE '1'
				END + ' Betcount' + CHAR(13) + 
				',SUM(b.CommissionP) as Playercomm' + CHAR(13) + 
				'FROM bodb_Licensee.dbo.rpt_Betting_BA b WITH ( NOLOCK )  ' + CHAR(13) + 
				'INNER JOIN #tmpParty tp ON b.siteid = tp.LicenseeID AND tp.ProductID = 3' + CHAR(13) + 
				'INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype AND tp.ProductID = bt.ProductID' + CHAR(13) + 
				'LEFT JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID' + CHAR(13) + 
				'WHERE b.rptDate BETWEEN tp.Fromdate and tp.ToDate' + CHAR(13) + 
				'AND b.status NOT IN (-1,103)' + CHAR(13) + CASE 
				WHEN @Currency <> 0
					THEN 'AND CurrencyID=' + convert(VARCHAR(10), @Currency)
				ELSE ''
				END + CHAR(13) + CASE 
				WHEN @excludeTest = 1
					THEN 'AND CurrencyID<>20'
				ELSE ''
				END + CHAR(13) + CASE 
				WHEN @SportType <> 0
					THEN 'AND b.bettype NOT IN (9,29) AND l.Sporttype =' + convert(VARCHAR(10), @SportType)
				ELSE ''
				END + CHAR(13) + CASE 
				WHEN @ReportBy = 1
					THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10) '
				WHEN @ReportBy = 2
					THEN 'AND b.IsLive=0 '
				ELSE ''
				END + CHAR(13) + 'GROUP BY  b.rptDate,  tp.PartyID, tp.ProductID, b.currencyID,b.status' + CHAR(13)
	END

	--exclude BA tickets
	IF (REPLACE(@ProductCodes, 'BA', '') != '' AND REPLACE(@ProductCodes, 'BA', '') != ',')
	BEGIN
		SELECT @sql = @sql + '--exclude BA rpt_Betting' + CHAR(13)
		SELECT @sql = @sql + 'SELECT DISTINCT p.PartyID,p.LicenseeID,p.ProductID,bt.Bettype 
						INTO #temp
						FROM #tmpParty p 
						   INNER JOIN #Bettype bt ON p.ProductID = bt.ProductID WHERE p.ProductID NOT IN (3)' + CHAR(13)
		SELECT @sql = @sql + 'INSERT INTO #Data
						  SELECT  b.rptDate	
							 ,b.SiteID
							 ,t.PartyID
							 ,t.ProductID	
							 ,b.Bettype
							 ,b.Status		
							 ,b.currencyID
							 ,SUM(b.turnover)
							 ,SUM(b.winloss)
							 ,SUM(b.winlossA)
							 ,SUM(b.CommissionA)
							 ,SUM(b.commissionP)
							 ,SUM(b.betcount)
						  FROM bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK)
						  INNER JOIN #temp t ON b.Bettype = t.Bettype AND b.SiteID = t.LicenseeID
						  LEFT JOIN dbo.League l(NOLOCK) ON b.leagueid = l.leagueid
						  WHERE b.rptDate BETWEEN ''' + CONVERT(VARCHAR(10), @fromdate, 120) + ''' AND ''' + CONVERT(VARCHAR(10), @ToDate, 120) + '''
							 AND b.STATUS NOT IN (- 1, 103)' + CHAR(13) + 
							 CASE 
							 WHEN @Currency <> 0
								    THEN 'AND CurrencyID=' + convert(VARCHAR(10), @Currency)
							 ELSE ''
							 END + CHAR(13) + CASE 
							 WHEN @excludeTest = 1
								    THEN 'AND CurrencyID<>20'
							 ELSE ''
							 END + CHAR(13) + CASE 
							 WHEN @SportType <> 0
								    THEN 'AND b.bettype NOT IN (9,29 ) AND b.bettype NOT BETWEEN 31 AND 120 AND l.Sporttype =' + convert(VARCHAR(10), @Sporttype)
							 ELSE ''
							 END + CHAR(13) + CASE 
							 WHEN @ReportBy = 1
								    THEN 'AND b.IsLive=1 AND b.bettype NOT IN (9,29,10,31,32,33) '
							 WHEN @ReportBy = 2
								    THEN 'AND b.IsLive=0 '
							 ELSE ''
							 END + CHAR(13) +
							 'AND b.customercategory NOT IN (27,28)
						GROUP BY  b.rptDate	
							 ,b.SiteID 
							 ,t.PartyID	 
							 ,t.ProductID	 
							 ,b.Bettype	 
							 ,Status		 
							 ,b.CurrencyID' + CHAR(13)
		SELECT @sql = @sql + 'INSERT INTO #tmpWinLoss' + CHAR(13) + 
				'SELECT b.rptDate,tp.PartyID, tp.ProductID,b.currencyID,SUM(b.turnover * CASE WHEN b.bettype=33 AND b.status IN (114,115) THEN 0.5 ELSE 1 END *' + CASE 
				WHEN @drawfilter IN (2, 3)
					THEN 'CASE WHEN b.status = 111  THEN 0 WHEN b.status IN (114,115) AND b.bettype <> 33 THEN 0.5 ELSE 1 END'
				ELSE '1'
				END + '),' + CHAR(13) + 'SUM(b.winloss),' + CHAR(13) + 
				'- SUM(CASE WHEN (b.bettype NOT BETWEEN 31 AND 33)  THEN b.winloss ELSE 0 END) AS LicenseeWL ,' + CHAR(13) +
				'SUM(CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.WinlossA ELSE 0 END) AS WinlossRB,' + CHAR(13) + 
				'0 as AmountDueToBA,' + CHAR(13) + 
				'- SUM ( CASE WHEN b.bettype BETWEEN 31 AND 33 THEN (b.winloss+b.winlossA+b.CommissionA) ELSE 0 END) as AmountDueToRB,' + CHAR(13) + 
				'0 as CommBA,' + CHAR(13) + 
				'SUM ( CASE WHEN b.bettype BETWEEN 31 AND 33 THEN CommissionA ELSE 0 END) as CommRB,' + CHAR(13) + 				
				'- SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN ((b.winloss * tp.Rate)) ELSE 0 END)  as Company   ,' + CHAR(13) + 
				'SUM(b.betcount) * ' + CASE 
				WHEN @drawfilter = 2
					THEN 'CASE WHEN b.status = 111 THEN 0 ELSE 1 END'
				ELSE '1'
				END + ' Betcount' + CHAR(13) + 
				',SUM(b.CommissionP) as Playercomm' + CHAR(13) + 
				'FROM #data b  ' + CHAR(13) + 
				'INNER JOIN #tmpParty tp ON b.siteid = tp.LicenseeID AND tp.ProductID NOT IN (3) AND b.ProductID = tp.ProductID' + CHAR(13) + 				
				'WHERE b.rptDate BETWEEN tp.FromDate and tp.Todate' + CHAR(13) + 				
				'GROUP BY  b.rptDate,  tp.PartyID, tp.ProductID, b.currencyID,b.status' + CHAR(13)
	END
END

SELECT @sql = @sql + '--Output data from temp table' + CHAR(13)

SELECT @sql = @sql + CHAR(13) + ' SELECT DISTINCT ExchangeDate, ExchangeId, Code, USD, EUR, MYR, GBP INTO #TempExchange FROM Lrf_f_GetExchangeDaily(''' + convert(VARCHAR(10), @FromDate, 120) + ''',''' + convert(VARCHAR(10), @ToDate, 120) + ''')' + CHAR(13)

SELECT @output = 'SELECT ' + CHAR(13) + 
			  'w.PartyID,' + CHAR(13) + 
			  'CASE WHEN p.PartyName =''18bb'' THEN ''PIH''
					 WHEN p.PartyName =''IBC'' THEN ''FDL''
					 ELSE p.PartyName
					 END AS PartyName,'  + char(13) +
			  'CASE WHEN Currency = 51 THEN ''' + @VNDCurrencyName + ''' ELSE e.Code END currencyName,' + CHAR(13) + 
			  'SUM(TurnOver)	AS Turnover,' + CHAR(13) + 
			  'SUM(Winlost)		AS Winlost,' + CHAR(13) + 
			  'SUM(LicenseeWL) AS LicenseeWL,' + CHAR(13) + 
			  'SUM(WinlossRB)	AS WinlossRB,' + CHAR(13) + 
			  'SUM(CommBA) AS CommBA,' + CHAR(13) + 
			  'SUM(CommRB) AS CommRB,' + CHAR(13) + 
			  'SUM(AmtDuetoBA) AS AmtDuetoBA,' + CHAR(13) + 
			  'SUM(AmtDuetoRB) AS AmtDuetoRB,' + CHAR(13) + 
			  'SUM(Company) AS Company,' + CHAR(13) + 
			  'SUM(Betcount)	AS Betcount,' + CHAR(13) + 
			  'SUM(Playercomm)	AS Playercomm,' + CHAR(13) + 
			  'SUM(TurnOver*e.MYR) 	AS TurnoverMYR, ' + CHAR(13) + 
			  'SUM(Winlost*e.MYR) 	AS WinlostMYR,' + CHAR(13) + 
			  'SUM(LicenseeWL*e.MYR)  AS LicenseeWLMYR,' + CHAR(13) + 
			  'SUM(WinlossRB*e.MYR) 	AS WinlossRBMYR,' + CHAR(13) + 
			  'SUM(CommBA * e.MYR)  AS CommBAMYR,' + CHAR(13) + 
			  'SUM(CommRB * e.MYR)  AS CommRBMYR,' + CHAR(13) + 
			  'SUM(AmtDuetoBA*e.MYR)  AS AmtDuetoBAMYR,' + CHAR(13) + 
			  'SUM(AmtDuetoRB*e.MYR)  AS AmtDuetoRBMYR,' + CHAR(13) + 
			  'SUM(Company * e.MYR)  AS CompanyMYR,' + CHAR(13) + 
			  'SUM(Playercomm * e.MYR) 	AS PlayercommMYR,' + CHAR(13) + 
			  'SUM(TurnOver*e.USD) 	AS TurnoverUSD, ' + CHAR(13) + 
			  'SUM(Winlost*e.USD) 	AS WinlostUSD,' + CHAR(13) + 
			  'SUM(LicenseeWL*e.USD)  AS LicenseeWLUSD,' + CHAR(13) + 
			  'SUM(WinlossRB*e.USD) 	AS WinlossRBUSD,' + CHAR(13) + 
			  'SUM(CommBA * e.USD)  AS CommBAUSD,' + CHAR(13) + 
			  'SUM(CommRB * e.USD)  AS CommRBUSD,' + CHAR(13) + 
			  'SUM(AmtDuetoBA*e.USD)  AS AmtDuetoBAUSD,' + CHAR(13) + 
			  'SUM(AmtDuetoRB*e.USD)  AS AmtDuetoRBUSD,' + CHAR(13) + 
			  'SUM(Company * e.USD)  AS CompanyUSD,' + CHAR(13) + 
			  'SUM(Playercomm * e.USD) 	AS PlayercommUSD,' + CHAR(13) + 
			  'SUM(TurnOver*e.EUR) 	AS TurnoverEUR, ' + CHAR(13) + 
			  'SUM(Winlost*e.EUR) 	AS WinlostEUR,' + CHAR(13) + 
			  'SUM(LicenseeWL*e.EUR)  AS LicenseeWLEUR,' + CHAR(13) + 
			  'SUM(WinlossRB*e.EUR) 	AS WinlossRBEUR,' + CHAR(13) + 
			  'SUM(CommBA * e.EUR)  AS CommBAEUR,' + CHAR(13) + 
			  'SUM(CommRB * e.EUR)  AS CommRBEUR,' + CHAR(13) + 
			  'SUM(AmtDuetoBA*e.EUR)  AS AmtDuetoBAEUR,' + CHAR(13) + 
			  'SUM(AmtDuetoRB*e.EUR)  AS AmtDuetoRBEUR,' + CHAR(13) + 
			  'SUM(Company * e.EUR)  AS CompanyEUR,' + CHAR(13) + 
			  'SUM(Playercomm * e.EUR) 	AS PlayercommEUR,' + CHAR(13) + 
			  --GBP
			  'SUM(TurnOver*e.GBP) 	AS TurnoverGBP, ' + CHAR(13) + 
			  'SUM(Winlost*e.GBP) 	AS WinlostGBP,' + CHAR(13) + 
			  'SUM(LicenseeWL*e.GBP)  AS LicenseeWLGBP,' + CHAR(13) + 
			  'SUM(WinlossRB*e.GBP) 	AS WinlossRBGBP,' + CHAR(13) + 
			  'SUM(CommBA * e.GBP)  AS CommBAGBP,' + CHAR(13) + 
			  'SUM(CommRB * e.GBP)  AS CommRBGBP,' + CHAR(13) + 
			  'SUM(AmtDuetoBA*e.GBP)  AS AmtDuetoBAGBP,' + CHAR(13) + 
			  'SUM(AmtDuetoRB*e.GBP)  AS AmtDuetoRBGBP,' + CHAR(13) + 
			  'SUM(Company * e.GBP)  AS CompanyGBP,' + CHAR(13) + 
			  'SUM(Playercomm * e.GBP) 	AS PlayercommGBP' + CHAR(13) + 
			  'FROM #tmpWinLoss w' + CHAR(13) + 
				 'INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID = w.PartyID' + CHAR(13) + 				 
				 'INNER JOIN #TempExchange e' + CHAR(13) + 
				 'ON w.winlostdate = e.ExchangeDate AND w.currency = e.ExchangeId' + CHAR(13) + 
			  'GROUP BY w.PartyID,p.PartyName,CASE WHEN Currency = 51 THEN ''' + @VNDCurrencyName + ''' ELSE e.Code END ' + CHAR(13) + 
			  'ORDER BY w.PartyID,p.PartyName' + CHAR(13) + 
			  'DROP TABLE #tmpWinLoss' + CHAR(13) + 
			  'DROP TABLE #Bettype' + CHAR(13) + 
			  'DROP TABLE #tmpParty' + CHAR(13) + 
			  'DROP TABLE #Data' + char(13) +
			  'DROP TABLE #Temp' + char(13) +
			  'DROP TABLE #TempExchange' + CHAR(13)

IF (@debug = 1)
BEGIN
	PRINT @sql
	PRINT @output
END
ELSE
	EXEC (@sql + @output)
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_CurrencyWinloss_Details] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_CurrencyWinloss_Details] TO bodbAdminNet 

