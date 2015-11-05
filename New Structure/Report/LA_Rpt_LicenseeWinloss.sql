USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LicenseeWinloss]    Script Date: 20/10/2015 13:00:00 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeWinloss] 
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
/*  Created:  Forrest.Nguyen
	Date: 20151020
	Original: LA_Rpt_LicenseeWinloss
	Feature: 44873
	DB: DB052.bodb02  
	Revisions:  
	Param's Explanation:  
		+ @PartyIDs	: a string of list PartyID, separate by ','
		+ @Currency	:  0- All Currencies
		+ @DrawFilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
		+ @excludeTest: add/remove currency UUS
		+ @ProductCodes	: Products code :
				. SB _ SportBook
				. NG _ Number Game
				...
		+ @IsConvert: 0-No Convert, 1-Convert
		+ @BaseCurrencyName: GBP, CNY, USD, EUR, MYR
*/
BEGIN
	SET NOCOUNT ON
	CREATE TABLE #Report (PartyID INT, ReportDate DATE, CurrencyID INT, Turnover MONEY, Winlost MONEY, LicenseeWL MONEY, WinlossRB MONEY, 
						AmtDueToBA MONEY, AmtDueToRB MONEY, CommBA MONEY, CommRB MONEY, Company MONEY, Betcount BIGINT)
						
	CREATE TABLE #Exchange(ExchangeId INT, ExchangeDate DATE, Code VARCHAR(20), USD FLOAT, EUR FLOAT, MYR FLOAT, GBP FLOAT, CNY FLOAT, Base FLOAT)
	
	DECLARE @ChargeInfo TABLE(PartyID INT, LicenseeID INT, ProductID INT,BetTypeId INT ,Rate MONEY, Fromdate DATE, Todate DATE)
	
	CREATE TABLE #Data (rptDate DATE, PartyID INT, ProductID INT, Currency INT,BetTypeId INT, Turnover MONEY, Winloss MONEY, AWinloss MONEY, AComm MONEY, Betcount BIGINT)
	
	INSERT INTO @ChargeInfo(PartyID, LicenseeID, ProductID, BetTypeId, Rate, Fromdate, Todate)
	SELECT DISTINCT PartyID, LicenseeID, ProductID, Bettype, DI_Rate, Fromdate, Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', @excludeTest)
	
	DECLARE @ChargeRateCount INT = (SELECT COUNT(*) FROM @ChargeInfo WHERE ProductID NOT IN (1, 3, 14))

	IF CHARINDEX('BA', @ProductCodes) <> 0
	BEGIN
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, Turnover, Winloss, AWinloss, AComm, Betcount)
		(
			SELECT b.rptDate, ci.PartyID, b.ProductID, b.currencyID
				, SUM(b.turnover * 
					CASE WHEN @drawfilter IN (2, 3) 
						THEN CASE WHEN b.StatusId = 111 THEN 0
							WHEN b.StatusId IN (114, 115)	THEN 0.5 ELSE 1	END
						ELSE 1
					END) Turnover
				, SUM(b.MemberWL) Winloss
				, 0 AS AWinloss
				, SUM(b.CommissionA) CommBA
				, SUM(b.BetCount * CASE WHEN @drawfilter = 2 AND b.StatusId = 111 THEN 0 ELSE 1 END) BetCount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN @ChargeInfo ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID = 3
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
				AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
			GROUP BY ci.PartyID, b.rptDate, b.ProductID, currencyID
		)
		
		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount)
		(
			SELECT ci.PartyID, b.rptDate, b.currency
				, SUM(b.turnover) Turnover
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
				INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, Rate FROM @ChargeInfo WHERE ProductID = 3) ci ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID				
			WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			GROUP BY ci.PartyID, b.rptDate, b.Currency
		)
	END
	
	IF CHARINDEX('MGC', @ProductCodes) <> 0
	BEGIN
		DELETE #Data
		
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, BetTypeId, Turnover, Winloss, AWinloss, AComm, Betcount)
		(
			SELECT b.rptDate, ci.PartyID, b.ProductID, b.currencyID, ci.BetTypeId
				, SUM(b.turnover * 
					CASE WHEN @drawfilter IN (2, 3) 
						THEN CASE WHEN b.StatusId = 111 THEN 0
							WHEN b.StatusId IN (114, 115)	THEN 0.5 ELSE 1	END
						ELSE 1
					END) Turnover
				, SUM(b.MemberWL)
				, 0
				, 0
				, SUM(b.betcount * CASE WHEN @drawfilter = 2 AND b.StatusId = 111 THEN 0 ELSE 1 END) BetCount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN @ChargeInfo ci ON b.SiteID = ci.LicenseeID AND ci.BetTypeId = b.Bettype AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID = 14
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
				AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
			GROUP BY ci.PartyID, b.rptDate, b.ProductID, currencyID, ci.BetTypeId
		)
		
		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount)
		(
			SELECT ci.PartyID, b.rptDate, b.currency
				, SUM(b.turnover) Turnover
				, SUM(b.Winloss) Winloss
				, -SUM(b.Winloss) AS LicenseeWL
				, 0 AS WinlossRB
				, 0 AS AmountDueToBA
				, 0 AS AmountDueToRB
				, 0 AS CommBA
				, 0 AS CommRB
				, -SUM(b.Winloss * ci.Rate) AS Company
				, SUM(b.betcount) AS betcount
			FROM #Data b
				INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, BetTypeId, Rate FROM @ChargeInfo WHERE ProductID = 14) ci 
				ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID AND ci.BetTypeId = b.BetTypeId			
			WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			GROUP BY ci.PartyID, b.rptDate, b.Currency
		)
	END
	
	IF CHARINDEX('RB', @ProductCodes) <> 0
	BEGIN
		DELETE #Data
		
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, BetTypeId, Turnover, Winloss, AWinloss, AComm, Betcount)
		(
			SELECT b.rptDate, ci.PartyID, b.ProductID, b.currencyID, ci.BetTypeId
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
				INNER JOIN @ChargeInfo ci ON b.SiteID = ci.LicenseeID AND ci.BetTypeId = b.Bettype AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @Fromdate AND @Todate
				AND b.ProductID = 1
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
				AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
			GROUP BY ci.PartyID, b.rptDate, b.ProductID, currencyID, ci.BetTypeId
		)
		
		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount)
		(
			SELECT ci.PartyID, b.rptDate, b.currency
				, SUM(b.turnover) Turnover
				, SUM(b.Winloss) Winloss
				, 0 AS LicenseeWL
				, SUM(b.AWinloss) AS WinlossRB
				, 0 AS AmountDueToBA
				, -SUM(b.Winloss + b.AWinloss + b.AComm) AS AmountDueToRB
				, 0 AS CommBA
				, SUM(b.AComm) AS CommRB
				, 0 AS Company
				, SUM(b.betcount) AS betcount
			FROM #Data b
				INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, BetTypeId, Rate FROM @ChargeInfo WHERE ProductID = 1) ci 
				ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID AND ci.BetTypeId = b.BetTypeId			
			WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
			GROUP BY ci.PartyID, b.rptDate, b.Currency
		)
	END

	IF @ChargeRateCount > 0
	BEGIN
		DELETE #Data
		
		INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, Turnover, Winloss, AWinloss, AComm, Betcount)
		(
			SELECT  b.rptDate, ci.PartyID, b.ProductID, b.currencyID
				, SUM(b.turnover * 
					CASE WHEN @drawfilter IN (2, 3) 
						THEN CASE WHEN b.StatusId = 111 THEN 0
							WHEN b.StatusId IN (114, 115)	THEN 0.5 ELSE 1	END
						ELSE 1
					END) Turnover
				, SUM(b.MemberWL)
				, 0
				, 0
				, SUM(b.betcount * CASE WHEN @drawfilter = 2 AND b.StatusId = 111 THEN 0 ELSE 1 END) BetCount
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN (SELECT DISTINCT PartyId, LicenseeId, ProductID FROM @ChargeInfo WHERE ProductID NOT IN (1, 3, 14)) ci ON b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductID
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.StatusId NOT IN (- 1, 101, 102, 103)
				AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
				AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
				AND b.customercategory NOT IN (27,28)
			GROUP BY b.rptDate, ci.PartyID, b.ProductID, b.CurrencyID
		)

		INSERT INTO #Report (PartyID, ReportDate, CurrencyID, Turnover, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount)
		SELECT ci.PartyID, rptDate, b.Currency
			, SUM(b.turnover) Turnover
			, SUM(b.Winloss) Winloss
			, -SUM(b.Winloss) AS LicenseeWL
			, 0 AS WinlossRB
			, 0 AS AmountDueToBA
			, 0 AS AmountDueToRB
			, 0 AS CommBA
			, 0 AS CommRB
			, -SUM(b.Winloss * ci.Rate) AS Company
			, SUM(b.betcount) AS betcount
		FROM #Data b WITH (NOLOCK)
			INNER JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, ProductID, Rate FROM @ChargeInfo WHERE ProductID NOT IN (1, 3, 14)) ci ON ci.PartyID = b.PartyID AND b.ProductID = ci.ProductID				
		WHERE b.rptDate BETWEEN ci.Fromdate AND ci.Todate
		GROUP BY ci.PartyID, b.rptDate, b.Currency
	END
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeId, Code, USD, EUR, MYR, GBP, CNY)
	SELECT DISTINCT ExchangeDate, ExchangeId, Code, USD, EUR, MYR, GBP, CNY
	FROM dbo.Lrf_f_GetExchangeDaily(@FromDate, @Todate)
	WHERE ExchangeId IN (SELECT CurrencyID FROM #Report)
	
	IF @IsConvert = 1
	BEGIN
		UPDATE #Exchange
		SET Base = ( CASE @BaseCurrencyName
						WHEN 'MYR' THEN MYR
						WHEN 'USD' THEN USD
						WHEN 'EUR' THEN EUR
						WHEN 'GBP' THEN GBP
						WHEN 'CNY' THEN CNY
						ELSE 1 
					 END)
	END
	ELSE IF @IsConvert = 0 AND @Currency <> 0
	BEGIN
		UPDATE #Exchange
		SET Base = 1
	END

	SELECT b.PartyID
		, CASE p.PartyName
		 	WHEN '18bb' THEN 'PIH'
		 	WHEN 'IBC'	THEN 'FDL'
		 	ELSE p.PartyName
		 	END AS PartyName
		, CONVERT(VARCHAR(6), b.ReportDate, 112) AS ReportDate
		, SUM(Betcount) AS TotalTransaction
		, CAST(SUM(Turnover * e.Base) AS MONEY) AS Turnover
		, CAST(SUM(Winlost * e.Base) AS MONEY) AS CustomerWinLoss
		, CAST(SUM(LicenseeWL * e.Base) AS MONEY) AS LicenseeWinLoss
		, CAST(SUM(WinlossRB * e.Base) AS MONEY) AS RacingWinLoss
		, CAST(SUM(AmtDueToBA * e.Base) AS MONEY) AS AmountDueToBA
		, CAST(SUM(AmtDueToRB * e.Base) AS MONEY) AS AmountDueToRacing
		, CAST(SUM(CommBA * e.Base) AS MONEY) AS BACommission
		, CAST(SUM(CommRB * e.Base) AS MONEY) AS RacingCommission
		, CAST(SUM(Company * e.Base) AS MONEY) AS AmountCompany
		--MYR
		, CAST(SUM(Turnover * e.MYR) AS MONEY) AS TurnoverMYR
		, CAST(SUM(Winlost * e.MYR) AS MONEY) AS CustomerWinLossMYR
		, CAST(SUM(LicenseeWL * e.MYR) AS MONEY) AS LicenseeWinLossMYR
		, CAST(SUM(WinlossRB * e.MYR) AS MONEY) AS RacingWinLossMYR
		, CAST(SUM(AmtDueToBA * e.MYR) AS MONEY) AS AmountDueToBAMYR
		, CAST(SUM(AmtDueToRB * e.MYR) AS MONEY) AS AmountDueToRacingMYR
		, CAST(SUM(CommBA * e.MYR) AS MONEY) AS BACommissionMYR
		, CAST(SUM(CommRB * e.MYR) AS MONEY) AS RacingCommissionMYR
		, CAST(SUM(Company * e.MYR) AS MONEY) AS AmountCompanyMYR
		--USD
		, CAST(SUM(Turnover * e.USD) AS MONEY) AS TurnoverUSD
		, CAST(SUM(Winlost * e.USD) AS MONEY) AS CustomerWinLossUSD
		, CAST(SUM(LicenseeWL * e.USD) AS MONEY) AS LicenseeWinLossUSD
		, CAST(SUM(WinlossRB * e.USD) AS MONEY) AS RacingWinLossUSD
		, CAST(SUM(AmtDueToBA * e.USD) AS MONEY) AS AmountDueToBAUSD
		, CAST(SUM(AmtDueToRB * e.USD) AS MONEY) AS AmountDueToRacingUSD
		, CAST(SUM(CommBA * e.USD) AS MONEY) AS BACommissionUSD
		, CAST(SUM(CommRB * e.USD) AS MONEY) AS RacingCommissionUSD
		, CAST(SUM(Company * e.USD) AS MONEY) AS AmountCompanyUSD
		--EUR
		, CAST(SUM(Turnover * e.EUR) AS MONEY) AS TurnoverEUR
		, CAST(SUM(Winlost * e.EUR) AS MONEY) AS CustomerWinLossEUR
		, CAST(SUM(LicenseeWL * e.EUR) AS MONEY) AS LicenseeWinLossEUR
		, CAST(SUM(WinlossRB * e.EUR) AS MONEY) AS RacingWinLossEUR
		, CAST(SUM(AmtDueToBA * e.EUR) AS MONEY) AS AmountDueToBAEUR
		, CAST(SUM(AmtDueToRB * e.EUR) AS MONEY) AS AmountDueToRacingEUR
		, CAST(SUM(CommBA * e.EUR) AS MONEY) AS BACommissionEUR
		, CAST(SUM(CommRB * e.EUR) AS MONEY) AS RacingCommissionEUR
		, CAST(SUM(Company * e.EUR) AS MONEY) AS AmountCompanyEUR
		--GBP
		, CAST(SUM(Turnover * e.GBP) AS MONEY) AS TurnoverGBP
		, CAST(SUM(Winlost * e.GBP) AS MONEY) AS CustomerWinLossGBP
		, CAST(SUM(LicenseeWL * e.GBP) AS MONEY) AS LicenseeWinLossGBP
		, CAST(SUM(WinlossRB * e.GBP) AS MONEY) AS RacingWinLossGBP
		, CAST(SUM(AmtDueToBA * e.GBP) AS MONEY) AS AmountDueToBAGBP
		, CAST(SUM(AmtDueToRB * e.GBP) AS MONEY) AS AmountDueToRacingGBP
		, CAST(SUM(CommBA * e.GBP) AS MONEY) AS BACommissionGBP
		, CAST(SUM(CommRB * e.GBP) AS MONEY) AS RacingCommissionGBP
		, CAST(SUM(Company * e.GBP) AS MONEY) AS AmountCompanyGBP
		--CNY
		, CAST(SUM(Turnover * e.CNY) AS MONEY) AS TurnoverCNY
		, CAST(SUM(Winlost * e.CNY) AS MONEY) AS CustomerWinLossCNY
		, CAST(SUM(LicenseeWL * e.CNY) AS MONEY) AS LicenseeWinLossCNY
		, CAST(SUM(WinlossRB * e.CNY) AS MONEY) AS RacingWinLossCNY
		, CAST(SUM(AmtDueToBA * e.CNY) AS MONEY) AS AmountDueToBACNY
		, CAST(SUM(AmtDueToRB * e.CNY) AS MONEY) AS AmountDueToRacingCNY
		, CAST(SUM(CommBA * e.CNY) AS MONEY) AS BACommissionCNY
		, CAST(SUM(CommRB * e.CNY) AS MONEY) AS RacingCommissionCNY
		, CAST(SUM(Company * e.CNY) AS MONEY) AS AmountCompanyCNY
	FROM #Report b
		INNER JOIN #Exchange e ON e.ExchangeDate = b.ReportDate AND e.ExchangeId = b.CurrencyID
		INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK) ON p.PartyID = b.PartyID
	GROUP BY b.PartyID, p.PartyName ,CONVERT(VARCHAR(6), b.ReportDate, 112)
	ORDER BY ReportDate ASC, CASE p.PartyName WHEN '18bb' THEN 'PIH' WHEN 'IBC' THEN 'FDL' ELSE p.PartyName END
	
	DROP TABLE #Exchange
	DROP TABLE #Report
	DROP TABLE #Data
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicenseeWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicenseeWinloss] TO bodbAdminNet 
