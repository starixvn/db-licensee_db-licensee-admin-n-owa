USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LicenseeWinloss_Details]    Script Date: 01/12/2014 14:34:39 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeWinloss_Details] 
	  @PartyID				INT
	, @Currency				INT				= 0
	, @FromDate				SMALLDATETIME	
	, @ToDate				SMALLDATETIME	
	, @ProductCodes			VARCHAR(1000)	
	, @SportType			INT				= 0
	, @Bettype				INT				= 0
	, @ReportBy				TINYINT			= 1
	, @DrawFilter			SMALLINT		= 1
	, @ExcludeTest			BIT				= 0
	, @IsConvert			BIT				= 0
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'

AS
/*   Created:  Florent.Nguyen
	Date: 20140827
     Original: OA_Rpt_LicWinloss2
	Task : LA Get Party Winloss Details
     DB: DB052.bodb02  
   
     Revisions:  
	   - 20141021@Florent: get data from credit's licensee
	   - 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
	   - 20150703@Florent: add GBP
	   - 20151019@Forrest: Add Microgaming and Update new Data Flow
	Param's Explanation:  
	  + @PartyIDs	: a string of list PartyID, separate by ','
	  + @Currency	:  0- All Currencies
	  + @ReportBy: 1-Daily; 2-Monthly;  
	  + @DrawFilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: add/remove currency UUS
	  + @ProductCodes	: Products code :
				. SB _ SportBook
				. NG _ Number Game
				...
	  +@SportType	:
				0  : selected all sporttype 
	  +@Bettype : 
			0: selected all bettype
*/
BEGIN
	SET NOCOUNT ON

	CREATE TABLE #SAgWinLoss (winlostdate DATE ,Currency INT, TurnOver MONEY, Winlost MONEY ,LicenseeWL MONEY, WinlossRB MONEY
		, AmtDueToBA MONEY, AmtDueToRB MONEY, CommBA MONEY, CommRB MONEY, Company MONEY, Betcount BIGINT, Playercomm MONEY)

	DECLARE @VNDCurrencyName VARCHAR(20), @site VARCHAR(50)

	SELECT @VNDCurrencyName = currency
	FROM dbo.Exchange (NOLOCK)
	WHERE ExchangeId = 51

	--Get Bettype     
	CREATE TABLE #Bettype (Bettype INT, ProductID INT)
    INSERT INTO #Bettype(Bettype, ProductID)
	SELECT Bettype, ProductID
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(@Bettype, @ProductCodes)

	--Get list of Party - Licensee
	CREATE TABLE #tmpParty (PartyID INT ,LicenseeID INT, IsDeposit INT, AffectedDate DATE, ProductID INT ,Rate MONEY ,Fromdate DATE ,Todate DATE)
	INSERT INTO #tmpParty (PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, Rate, Fromdate, Todate)
	SELECT DISTINCT PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, DI_Rate, Fromdate, Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo (@PartyID,@FromDate,@ToDate,@ProductCodes,'OA',@excludeTest)
	
    IF CHARINDEX('BA', @ProductCodes) <> 0
    BEGIN
		INSERT INTO #SAgWinLoss(winlostdate, Currency, TurnOver, Winlost, LicenseeWL, WinlossRB
			, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount, Playercomm)
		(
			SELECT rptDate, CurrencyID, TurnOver, Winloss, LicenseeWL, WinlossRB
				, AmountDueToBA  * p.Rate
				, AmountDueToRB, CommBA, CommRB
				, Company
				, Betcount, Playercomm
			FROM (
				SELECT SiteId, b.rptDate, b.CurrencyID, p.ProductID
					 , SUM(b.turnover 
							* CASE WHEN b.bettype = 33 AND b.Status IN (114, 115) THEN 0.5 ELSE 1 END
							* CASE WHEN @DrawFilter IN (2, 3) 
								THEN CASE WHEN b.Status = 111 THEN 0
										WHEN b.Status IN (114, 115) THEN 0.5
										ELSE 1 END
								ELSE 1 END
							) AS TurnOver
					, SUM(b.winloss) Winloss
					, 0 AS LicenseeWL
					, 0 AS WinlossRB		  
					, -SUM((b.winloss) + b.CommissionA) AS AmountDueToBA
					, 0 AS AmountDueToRB
					, SUM(b.CommissionA) AS CommBA
					, 0 AS CommRB
					, 0 AS Company
					, SUM(betcount * CASE WHEN @DrawFilter = 2 AND b.Status = 111 THEN 0 ELSE 1 END) BetCount
					, SUM(commissionP) AS Playercomm
				FROM bodb_Licensee.dbo.rpt_Betting_BA b WITH (NOLOCK)
					INNER JOIN (
						SELECT LicenseeID, ProductID
						FROM #tmpParty
						WHERE ProductID IN (3)
						GROUP BY LicenseeID, ProductID
					)p ON p.LicenseeID = b.SiteID
					INNER JOIN #Bettype bt ON bt.Bettype = b.Bettype AND p.ProductID = bt.ProductID
				LEFT JOIN dbo.League l(NOLOCK) ON b.leagueid = l.leagueid
				WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.Bettype IN (SELECT Bettype FROM #Bettype)
					AND b.STATUS NOT IN (- 1, 103)
					AND (@SportType = 0 OR (@SportType <> 0	AND l.sporttype = @SportType))
					AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
					AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
				GROUP BY b.rptdate, SiteId, b.CurrencyID, b.[Status], p.ProductID
			)tmp INNER JOIN #tmpParty p ON tmp.SiteId = p.LicenseeID AND tmp.ProductID = p.ProductID
			WHERE p.ProductID IN (3)
				AND tmp.rptDate BETWEEN p.Fromdate AND p.Todate
		)
    END
    
	IF (REPLACE(@ProductCodes, 'BA', '') != '' AND REPLACE(@ProductCodes, 'BA', '') != ',')
	BEGIN
		  --get data
	    INSERT INTO #SAgWinLoss(winlostdate, Currency, TurnOver, Winlost, LicenseeWL, WinlossRB
			, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount, Playercomm)
		(
			SELECT rptDate, CurrencyID, TurnOver, Winloss, LicenseeWL, WinlossRB
				, AmountDueToBA, AmountDueToRB, CommBA, CommRB
				, Company * p.Rate
				, Betcount, Playercomm
			FROM (
				SELECT SiteId, b.rptDate, b.CurrencyID, bt.ProductID
					 , SUM(b.turnover 
						* CASE WHEN b.bettype = 33 AND b.Status IN (114, 115) THEN 0.5 ELSE 1 END -- Haft-won, haft-lose for Racing
						* CASE WHEN @DrawFilter IN (2, 3) 
							THEN CASE WHEN b.Status = 111 THEN 0
									WHEN b.Status IN (114, 115) AND b.Bettype != 33 THEN 0.5 -- Haft-won, haft-lose for not Racing
									ELSE 1 END
							ELSE 1 END
						) AS TurnOver
					 , SUM(b.winloss) Winloss
					 , -SUM(CASE WHEN (b.bettype NOT BETWEEN 31 AND 33) THEN b.winloss ELSE 0 END) AS LicenseeWL
					 , SUM(CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.WinLossA ELSE 0 END) AS WinlossRB
					 , 0 AS AmountDueToBA
					 , -SUM(CASE WHEN b.bettype BETWEEN 31 AND 33
								THEN (b.winloss + b.WinLossA + b.CommissionA)
								ELSE 0 END) AS AmountDueToRB
					 , 0 AS CommBA
					 , SUM(CASE WHEN b.bettype BETWEEN 31 AND 33
								THEN b.CommissionA
								ELSE 0 END) AS CommRB
					 ,- SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33						  
								THEN ((b.winloss))
								ELSE 0 END) AS Company
					 , SUM(betcount * CASE WHEN @DrawFilter = 2 AND b.Status = 111 THEN 0 ELSE 1 END) BetCount
					 , SUM(b.CommissionP) AS Playercomm
				FROM bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK)
					INNER JOIN (
						SELECT LicenseeID
						FROM #tmpParty
						WHERE ProductID NOT IN (3)
						GROUP BY LicenseeID
					)p ON p.LicenseeID = b.SiteID
					INNER JOIN #Bettype bt ON bt.Bettype = b.Bettype
					LEFT JOIN dbo.League l(NOLOCK) ON b.leagueid = l.leagueid
				WHERE b.rptDate BETWEEN @FromDate AND @ToDate
					AND b.[Status] NOT IN (- 1, 103)
					AND b.customercategory NOT IN (27,28)
					AND (@SportType = 0	OR (@SportType <> 0 AND b.bettype NOT BETWEEN 31 AND 120  AND l.sporttype = @SportType))
					AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
					AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
				GROUP BY b.rptdate, SiteId, b.CurrencyID, b.[Status], bt.ProductID
			)tmp INNER JOIN #tmpParty p ON tmp.SiteId = p.LicenseeID AND tmp.ProductID = p.ProductID
			WHERE p.ProductID NOT IN (3)
				AND tmp.rptDate BETWEEN p.Fromdate AND p.Todate
		)
	END

	CREATE TABLE #TempExchange (ExchangeId INT, ExchangeDate DATE, Code VARCHAR(20), USD FLOAT, EUR FLOAT, MYR FLOAT, GBP FLOAT, CNY FLOAT)
	INSERT INTO #TempExchange(ExchangeDate, ExchangeId, Code, USD, EUR, MYR, GBP, CNY)
	SELECT DISTINCT ExchangeDate, ExchangeId, Code, USD, EUR, MYR, GBP, CNY
	FROM dbo.Lrf_f_GetExchangeDaily(@FromDate, @Todate)
	WHERE ExchangeId IN (SELECT Currency FROM #SAgWinLoss)

	--=====Currency Name
	DECLARE @temp AS TABLE (currency INT)
	INSERT INTO @temp
	SELECT DISTINCT Currency 
	FROM #SAgWinLoss

	DECLARE @temp1 AS TABLE (currency INT, CurrencyName VARCHAR(20), CurrencyCode VARCHAR(20))
	INSERT INTO @temp1(currency, CurrencyName, CurrencyCode)
	SELECT t.currency, e.currency, e.Code
	FROM @temp t
	INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON t.currency = e.exchangeid

	UPDATE t1
	SET CurrencyCode = t1.CurrencyCode + ' (' + CurrencyName + ')'
	FROM @temp1 t1
	INNER JOIN (
	   SELECT CurrencyCode
	    FROM @temp1
	    GROUP BY CurrencyCode
	    HAVING COUNT(1) > 1
	) t2 ON t1.CurrencyCode = t2.CurrencyCode

	--============================final select================================
	SELECT CASE WHEN @ReportBy = 1 THEN CONVERT(VARCHAR(8), w.winlostdate, 112)
			WHEN @ReportBy = 2 THEN CONVERT(VARCHAR(6), w.winlostdate, 112)
			ELSE '0' END ReportType
		, w.Currency
		, CASE WHEN w.Currency = 51 THEN @VNDCurrencyName			  
			  WHEN w.Currency = 20 THEN e.Code			
			ELSE ISNULL(t.CurrencyCode,e.Code) END AS currencyName
		, SUM(TurnOver) AS Turnover
		, SUM(Winlost) AS Winlost
		, SUM(LicenseeWL) AS LicenseeWL
		, SUM(WinlossRB) AS WinlossRB
		, SUM(CommBA) AS CommBA
		, SUM(CommRB) AS CommRB
		, SUM(AmtDuetoBA) AS AmtDuetoBA
		, SUM(AmtDuetoRB) AS AmtDuetoRB
		, SUM(Company) AS Company
		, SUM(Betcount) AS Betcount
		, SUM(playercomm) AS Playercomm
		--BaseRM  
		, CAST(SUM(TurnOver * e.MYR) AS MONEY) AS TurnoverMYR
		, CAST(SUM(Winlost * e.MYR) AS MONEY) AS WinlostMYR
		, CAST(SUM(LicenseeWL * e.MYR) AS MONEY) AS LicenseeWLMYR
		, CAST(SUM(WinlossRB * e.MYR) AS MONEY) AS WinlossRBMYR
		, CAST(SUM(CommBA * e.MYR) AS MONEY) AS CommBAMYR
		, CAST(SUM(CommRB * e.MYR) AS MONEY) AS CommRBMYR
		, CAST(SUM(AmtDuetoBA * e.MYR) AS MONEY) AS AmtDuetoBAMYR
		, CAST(SUM(AmtDuetoRB * e.MYR) AS MONEY) AS AmtDuetoRBMYR
		, CAST(SUM(Company * e.MYR) AS MONEY) AS CompanyMYR
		, CAST(SUM(playercomm * e.MYR) AS MONEY) AS PlayercommMYR
		--BaseUSD  
		, CAST(SUM(TurnOver * e.USD) AS MONEY) AS TurnoverUSD
		, CAST(SUM(Winlost * e.USD) AS MONEY) AS WinlostUSD
		, CAST(SUM(LicenseeWL * e.USD) AS MONEY) AS LicenseeWLUSD
		, CAST(SUM(WinlossRB * e.USD) AS MONEY) AS WinlossRBUSD
		, CAST(SUM(CommBA * e.USD) AS MONEY) AS CommBAUSD
		, CAST(SUM(CommRB * e.USD) AS MONEY) AS CommRBUSD
		, CAST(SUM(AmtDuetoBA * e.USD) AS MONEY) AS AmtDuetoBAUSD
		, CAST(SUM(AmtDuetoRB * e.USD) AS MONEY) AS AmtDuetoRBUSD
		, CAST(SUM(Company * e.USD) AS MONEY) AS CompanyUSD
		, CAST(SUM(playercomm * e.USD) AS MONEY) AS PlayercommUSD
		--BaseEUR  
		, CAST(SUM(TurnOver * e.EUR) AS MONEY) AS TurnoverEUR
		, CAST(SUM(Winlost * e.EUR) AS MONEY) AS WinlostEUR
		, CAST(SUM(LicenseeWL * e.EUR) AS MONEY) AS LicenseeWLEUR
		, CAST(SUM(WinlossRB * e.EUR) AS MONEY) AS WinlossRBEUR
		, CAST(SUM(CommBA * e.EUR) AS MONEY) AS CommBAEUR
		, CAST(SUM(CommRB * e.EUR) AS MONEY) AS CommRBEUR
		, CAST(SUM(AmtDuetoBA * e.EUR) AS MONEY) AS AmtDuetoBAEUR
		, CAST(SUM(AmtDuetoRB * e.EUR) AS MONEY) AS AmtDuetoRBEUR
		, CAST(SUM(Company * e.EUR) AS MONEY) AS CompanyEUR
		, CAST(SUM(playercomm * e.EUR) AS MONEY) AS PlayercommEUR
		--BaseGBP 
		, CAST(SUM(TurnOver * e.GBP) AS MONEY) AS TurnoverGBP
		, CAST(SUM(Winlost * e.GBP) AS MONEY) AS WinlostGBP
		, CAST(SUM(LicenseeWL * e.GBP) AS MONEY) AS LicenseeWLGBP
		, CAST(SUM(WinlossRB * e.GBP) AS MONEY) AS WinlossRBGBP
		, CAST(SUM(CommBA * e.GBP) AS MONEY) AS CommBAGBP
		, CAST(SUM(CommRB * e.GBP) AS MONEY) AS CommRBGBP
		, CAST(SUM(AmtDuetoBA * e.GBP) AS MONEY) AS AmtDuetoBAGBP
		, CAST(SUM(AmtDuetoRB * e.GBP) AS MONEY) AS AmtDuetoRBGBP
		, CAST(SUM(Company * e.GBP) AS MONEY) AS CompanyGBP
		, CAST(SUM(playercomm * e.EUR) AS MONEY) AS PlayercommEUR
		--BaseCNY 
		, CAST(SUM(TurnOver * e.CNY) AS MONEY) AS TurnoverCNY
		, CAST(SUM(Winlost * e.CNY) AS MONEY) AS WinlostCNY
		, CAST(SUM(LicenseeWL * e.CNY) AS MONEY) AS LicenseeWLCNY
		, CAST(SUM(WinlossRB * e.CNY) AS MONEY) AS WinlossRBCNY
		, CAST(SUM(CommBA * e.CNY) AS MONEY) AS CommBACNY
		, CAST(SUM(CommRB * e.CNY) AS MONEY) AS CommRBCNY
		, CAST(SUM(AmtDuetoBA * e.CNY) AS MONEY) AS AmtDuetoBACNY
		, CAST(SUM(AmtDuetoRB * e.CNY) AS MONEY) AS AmtDuetoRBCNY
		, CAST(SUM(Company * e.CNY) AS MONEY) AS CompanyCNY
		, CAST(SUM(playercomm * e.EUR) AS MONEY) AS PlayercommEUR
	FROM #SAgWinLoss w
		INNER JOIN #TempExchange e ON w.winlostdate = e.ExchangeDate AND w.currency = e.ExchangeId
		LEFT JOIN @temp1 t ON w.Currency = t.currency
	GROUP BY w.Currency
		, 
		  CASE WHEN @ReportBy = 1 THEN CONVERT(VARCHAR(8), w.winlostdate, 112)
			WHEN @ReportBy = 2 THEN CONVERT(VARCHAR(6), w.winlostdate, 112)
			ELSE '0' END
		, CASE WHEN w.Currency = 51 THEN @VNDCurrencyName		
			  WHEN w.Currency = 20 THEN e.Code				
			ELSE ISNULL(t.CurrencyCode,e.Code) END 
	ORDER BY ReportType ASC

	DROP TABLE #SAgWinLoss
	DROP TABLE #TempExchange
	DROP TABLE #Bettype
	DROP TABLE #tmpParty	
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicenseeWinloss_Details] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicenseeWinloss_Details] TO bodbAdminNet 
