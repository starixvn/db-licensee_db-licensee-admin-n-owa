USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LicWinloss_xtest]    Script Date: 01/12/2014 14:34:14 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicWinloss_xtest] 
	  @PartyIDs				VARCHAR(1000)	= ''
	, @Currency				INT				= 0
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME
	, @ProductCodes			VARCHAR(1000)
	, @DrawFilter			SMALLINT		= 1
	, @excludeTest			BIT				= 0
	, @IsConvert			BIT				= 0
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'

WITH RECOMPILE
AS
/*   Created:  Florent.Nguyen
	Date: 20140827
		Original: OA_Rpt_LicWinloss_Summary
	Task : LA Get Party Winloss
		DB: DB052.bodb02  
   
		Revisions:  
		- 20141021@Florent: get data from credit's licensee
		- 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
		- 20141226@Florent: Fix hafl-won, hafl-lose on Racing
		- 20150330@Florent: Fix case FDL licensee duplicate data
		- 20150703@Florent: add GBP
		- 20151013@Forrest: Up to date new flow
	Param's Explanation:  
		+ @PartyIDs	: a string of list PartyID, separate by ','
		+ @Currency	:  0- All Currencies
		+ @DrawFilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
		+ @excludeTest: add/remove currency UUS
		+ @ProductCodes	: Products code :
				. SB _ SportBook
				. NG _ Number Game
				...
*/
BEGIN
	SET NOCOUNT ON
	CREATE TABLE #Temp (PartyID INT, ProductID INT, ReportDate DATE, CurrencyID INT, TurnOver MONEY, Winlost MONEY, LicenseeWL MONEY, WinlossRB MONEY, 
						AmtDueToBA MONEY, AmtDueToRB MONEY, CommBA MONEY, CommRB MONEY, Company MONEY, Betcount BIGINT)
						
	CREATE TABLE #Exchange(ExchangeDate DATE, ExchangeID INT, CurrencyCode VARCHAR(10), Rate FLOAT)  
	
	DECLARE @ChargeInfo TABLE(PartyID INT, LicenseeID INT, ProductID INT, Rate MONEY, Fromdate DATE, Todate DATE)
	
	CREATE TABLE #Data (rptDate DATE, PartyID INT, ProductID INT, Currency INT, TurnOver MONEY, Winloss MONEY, AWinloss MONEY, AComm MONEY, Betcount BIGINT)
						
	CREATE TABLE #WinLoss (PartyID INT, ReportDate VARCHAR(6), TurnOver MONEY, Winlost MONEY ,LicenseeWL MONEY, WinlossRB MONEY, 
						   AmtDueToBA MONEY, AmtDueToRB MONEY, CommBA MONEY, CommRB MONEY, Company MONEY, Betcount BIGINT)
	
	INSERT INTO @ChargeInfo(PartyID, LicenseeID, ProductID, Rate, Fromdate, Todate)
	SELECT DISTINCT PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', @excludeTest)
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate AS Rate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	IF @IsConvert = 0
	BEGIN
		UPDATE #Exchange
		SET Rate = 1
	END
	
	IF CHARINDEX('BA', @ProductCodes) <> 0
	BEGIN
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, TurnOver, Winloss, AWinloss, AComm, Betcount)
		(
			SELECT b.rptDate, ci.PartyID, b.ProductID, b.currencyID
				, SUM(b.turnover * 
					CASE WHEN @drawfilter IN (2, 3) 
						THEN CASE WHEN b.StatusId = 111 THEN 0
							WHEN b.StatusId IN (114, 115)	THEN 0.5 ELSE 1	END
						ELSE 1
					END) TurnOver
				, SUM(b.MemberWL) Winloss
				, 0 AS AWinloss
				, SUM(b.CommissionA) CommBA
				, SUM(b.BetCount * CASE WHEN @drawfilter = 2 AND b.StatusId = 111 THEN 0 ELSE 1 END) BetCount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN @ChargeInfo ci ON b.SiteID = ci.LicenseeID
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID = 3
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
				AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
			GROUP BY ci.PartyID, b.rptDate, b.ProductID, currencyID
		)
		
		INSERT INTO #Temp (PartyID, ReportDate, CurrencyID, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount)
		(
			SELECT ci.PartyID, b.rptDate, b.currency
				, SUM(b.turnover) TurnOver
				, SUM(b.winloss) Winloss
				, 0 AS LicenseeWL
				, 0 AS WinlossRB
				, -SUM((b.winloss * ci.Rate ) + b.AComm) AS AmountDueToBA
				, 0 AS AmountDueToRB
				, SUM(b.AComm) AS CommBA
				, 0 AS CommRB
				, 0 AS Company
				, SUM(betcount) BetCount
			FROM #Data b
				INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, Rate FROM @ChargeInfo) ci ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID				
			WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
				AND ci.ProductID = 3
			GROUP BY ci.PartyID, b.rptDate, b.Currency
		)
	END
	
	IF (REPLACE(@ProductCodes, 'BA', '') != '' AND REPLACE(@ProductCodes, 'BA', '') != ',')
	BEGIN
		DELETE #Data
		
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, TurnOver, Winloss, AWinloss, AComm, Betcount)
		(
			SELECT  b.rptDate, ci.PartyID, b.ProductID, b.currencyID
				, SUM(b.turnover * 
					CASE WHEN b.bettype = 33 AND b.StatusId IN (114, 115) THEN 0.5 ELSE 1 END * 
					CASE WHEN @drawfilter IN (2, 3)	
							THEN CASE WHEN b.StatusId = 111 THEN 0 WHEN b.StatusId IN (114, 115) AND b.Bettype != 33
								THEN 0.5 ELSE 1
							END	ELSE 1
					END) TurnOver
				, SUM(b.MemberWL)
				, SUM(b.GrossWL)
				, SUM(b.CommissionA)
				, SUM(b.betcount * CASE WHEN @drawfilter = 2 AND b.StatusId = 111 THEN 0 ELSE 1 END) BetCount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN (SELECT DISTINCT PartyId, LicenseeId, ProductID FROM @ChargeInfo WHERE ProductID <> 3) ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
				AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
				AND b.customercategory NOT IN (27,28)
			GROUP BY b.rptDate, ci.PartyID, b.ProductID, b.CurrencyID
		)

		INSERT INTO #Temp (PartyID, ReportDate, CurrencyID, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount)
		SELECT ci.PartyID, rptDate, b.Currency
			, SUM(b.turnover) TurnOver
			, SUM(b.Winloss) Winloss
			, -SUM(CASE WHEN (b.ProductID <> 1) THEN b.Winloss ELSE 0 END) AS LicenseeWL
			, SUM(CASE WHEN b.ProductID = 1 THEN b.AWinloss ELSE 0 END) AS WinlossRB
			, 0 AS AmountDueToBA
			, -SUM(CASE WHEN b.ProductID = 1 THEN (b.Winloss + b.AWinloss + b.AComm) ELSE 0 END) AS AmountDueToRB
			, 0 AS CommBA
			, SUM(CASE WHEN b.ProductID = 1 THEN b.AComm ELSE 0 END) AS CommRB
			, -SUM(CASE WHEN b.ProductID <> 1 THEN ((b.Winloss * ci.Rate))ELSE 0 END) AS Company
			, SUM(b.betcount) AS betcount
		FROM #Data b WITH (NOLOCK)
			INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, Rate FROM @ChargeInfo) ci ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID				
		WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			AND ci.ProductID <> 3
		GROUP BY ci.PartyID, b.rptDate, b.Currency
	END

	INSERT INTO #WinLoss(PartyID, ReportDate, TurnOver, Winlost ,LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount)
	SELECT b.PartyID
		, CONVERT(VARCHAR(6), b.ReportDate, 112) AS ReportType
		, SUM(TurnOver * e.Rate) AS TurnOver
		, SUM(Winlost * e.Rate) AS Winlost
		, SUM(LicenseeWL * e.Rate) AS LicenseeWL
		, SUM(WinlossRB * e.Rate) AS WinlossRB
		, SUM(AmtDueToBA * e.Rate) AS AmtDueToBA
		, SUM(AmtDueToRB * e.Rate) AS AmtDueToRB
		, SUM(CommBA * e.Rate) AS CommBA
		, SUM(CommRB * e.Rate) AS CommRB
		, SUM(Company * e.Rate) AS Company
		, SUM(Betcount) AS Betcount
	FROM #Temp b
		INNER JOIN #Exchange e ON e.ExchangeDate = b.ReportDate AND e.ExchangeId = b.CurrencyID
	GROUP BY PartyID, CONVERT(VARCHAR(6), b.ReportDate, 112)
	
	SELECT w.PartyID	
		, CASE p.PartyName
		 	WHEN '18bb' THEN 'PIH'
		 	WHEN 'IBC'	THEN 'FDL'
		 	ELSE p.PartyName
		 	END AS PartyName
		, w.ReportDate
		, SUM(TurnOver) AS Turnover
		, SUM(Winlost) AS CustWinLoss
		, SUM(LicenseeWL) AS LicenseeWinLoss
		, SUM(WinlossRB) AS RacingWinLoss
		, SUM(CommBA) AS BACommission
		, SUM(CommRB) AS RacingCommission
		, SUM(AmtDuetoBA) AS AmountDueToBA
		, SUM(AmtDuetoRB) AS AmountDueToRacing
		, SUM(Company) AS AmountCompany
		, SUM(Betcount) AS TotalTransaction
	FROM #WinLoss w
		INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK) ON p.PartyID = w.PartyID
	GROUP BY w.PartyID, p.PartyName, w.ReportDate	
	ORDER BY w.ReportDate ASC, CASE p.PartyName WHEN '18bb' THEN 'PIH' WHEN 'IBC' THEN 'FDL' ELSE p.PartyName END
	
	DELETE #Exchange
	DELETE #Temp
	DELETE #Data
	DELETE #WinLoss
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicWinloss_xtest] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicWinloss_xtest] TO bodbAdminNet 
