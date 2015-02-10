USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LicWinloss]    Script Date: 01/12/2014 14:34:14 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicWinloss] 
	  @PartyIDs			VARCHAR(1000)	= ''
	, @Currency			INT				= 0
	, @FromDate			SMALLDATETIME
	, @ToDate			SMALLDATETIME
	, @ProductCodes		VARCHAR(1000)
	, @SportType		INT				= 0
	, @Bettype			INT				= 0
	, @ReportBy			TINYINT			= 1
	, @DrawFilter		SMALLINT		= 1
	, @excludeTest		BIT				= 0

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
	SET @ReportBy = 2 -- only allow monthly  

	----DECLARE  	
	CREATE TABLE #WinLoss (PartyID INT, ReportType VARCHAR(6), TurnOver MONEY, Winlost MONEY ,LicenseeWL MONEY
		, WinlossRB MONEY, AmtDueToBA MONEY, AmtDueToRB MONEY, CommBA MONEY, CommRB MONEY, Company MONEY, Playercomm MONEY
		, Betcount BIGINT, TurnOverMYR MONEY, WinlostMYR MONEY, LicenseeWLMYR MONEY, WinlossRBMYR MONEY, AmtDueToBAMYR MONEY
		, AmtDueToRBMYR MONEY, CommBAMYR MONEY, CommRBMYR MONEY, CompanyMYR MONEY, PlayercommMYR MONEY,TurnOverUSD MONEY
		, WinlostUSD MONEY, LicenseeWLUSD MONEY, WinlossRBUSD MONEY, AmtDueToBAUSD MONEY, AmtDueToRBUSD MONEY, CommBAUSD MONEY
		, CommRBUSD MONEY, CompanyUSD MONEY, PlayercommUSD MONEY, TurnOverEUR MONEY, WinlostEUR MONEY, LicenseeWLEUR MONEY
		, WinlossRBEUR MONEY, AmtDueToBAEUR MONEY, AmtDueToRBEUR MONEY, CommBAEUR MONEY, CommRBEUR MONEY, CompanyEUR MONEY, PlayercommEUR MONEY)

	CREATE TABLE #Temp (PartyID INT, ProductID INT, rptDate DATE, Currency INT,TurnOver MONEY, Winlost MONEY, LicenseeWL MONEY
		, WinlossRB MONEY, AmtDueToBA MONEY, AmtDueToRB MONEY, CommBA MONEY, CommRB MONEY, Company MONEY, Playercomm MONEY, Betcount BIGINT)

	CREATE TABLE #Data (rptDate DATE, SiteID INT, PartyID INT, ProductID INT, Bettype INT, Status SMALLINT, Currency INT, TurnOver MONEY
		, Winloss MONEY, AWinloss MONEY, AComm MONEY, PComm MONEY, Betcount BIGINT)

	CREATE TABLE #Bettype (Bettype INT,ProductID INT)

	DECLARE @tmpParty TABLE(PartyID INT, LicenseeID INT, ProductID INT, Rate MONEY, Fromdate DATE, Todate DATE)

	INSERT INTO #Bettype(Bettype, ProductID)
	SELECT Bettype,ProductID FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(@Bettype,@ProductCodes)

	INSERT INTO @tmpParty(PartyID, LicenseeID, ProductID, Rate, Fromdate, Todate)
	SELECT DISTINCT PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', @excludeTest)
		
	CREATE TABLE #Exchange (ExchangeDate DATE, ExchangeId INT, USD FLOAT, EUR FLOAT, MYR FLOAT)
	INSERT INTO #Exchange (ExchangeDate, ExchangeId, USD, EUR, MYR)
	SELECT DISTINCT ExchangeDate, ExchangeId, USD, EUR, MYR
	FROM Lrf_f_GetExchangeDaily(@FromDate, @ToDate)

	IF CHARINDEX('BA', @ProductCodes) <> 0
	BEGIN
		--filter by @sport
		IF @SportType <> 0
		BEGIN
			INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, TurnOver, Winloss, AWinloss, AComm, PComm, Betcount)
			(
				SELECT b.rptDate, p.PartyID, bt.ProductID, b.currencyID
					, SUM(b.turnover * 
						CASE WHEN @drawfilter IN (2, 3) 
							THEN CASE WHEN b.STATUS = 111 THEN 0
								WHEN b.STATUS IN (114, 115)	THEN 0.5 ELSE 1	END
							ELSE 1
						END) TurnOver
					, SUM(b.winloss) Winloss
					, 0 AS AWinloss --AmountDueToBA = -sum(winloss * rate) + AComm
					, SUM(b.CommissionA) AS CommBA
					, 0 AS Playercomm --SUM(commissionP) AS Playercomm --will be remove later
					, SUM(betcount * CASE WHEN @drawfilter = 2 AND b.Status = 111 THEN 0 ELSE 1 END) BetCount
				FROM bodb_Licensee.dbo.rpt_Betting_BA b WITH (NOLOCK)
					INNER JOIN @tmpParty p ON b.SiteID = p.LicenseeID and p.ProductID = 3
					INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
					INNER JOIN dbo.League l(NOLOCK) ON b.leagueid = l.leagueid
				WHERE b.rptDate BETWEEN @Fromdate AND @Todate
					AND b.Status NOT IN (- 1, 103)
					AND l.sporttype = @SportType
					--AND (@SportType = 0	OR (@SportType <> 0	AND l.sporttype = @SportType))
					AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
					AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
				GROUP BY p.PartyID, b.rptDate, bt.ProductID, currencyID
			)

			INSERT INTO #Temp (PartyID, rptDate, Currency, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA
				, AmtDueToRB, CommBA, CommRB, Company, Playercomm, Betcount)
			(
				SELECT p.PartyID, b.rptDate, b.currency
					, SUM(b.turnover) TurnOver
					, SUM(b.winloss) Winloss
					, 0 AS LicenseeWL
					, 0 AS WinlossRB
					, -SUM((b.winloss * p.Rate ) + b.AComm) AS AmountDueToBA
					, 0 AS AmountDueToRB
					, SUM(b.AComm) AS CommBA
					, 0 AS CommRB
					, 0 AS Company
					, SUM(PComm) AS Playercomm
					, SUM(betcount) BetCount
				FROM #Data b
					--INNER JOIN dbo.League l(NOLOCK) ON b.leagueid = l.leagueid
					INNER JOIN @tmpParty p ON p.PartyID = b.PartyID AND b.ProductID = p.ProductID				
				WHERE b.rptDate BETWEEN p.Fromdate AND p.Todate
					AND p.ProductID = 3
				GROUP BY p.PartyID, b.rptDate, b.Currency
			)
		END
		ELSE --get all sports
		BEGIN
			INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, TurnOver, Winloss, AWinloss, AComm, PComm, Betcount)
			(
				SELECT b.rptDate, p.PartyID, bt.ProductID, b.currencyID
					, SUM(b.turnover * 
						CASE WHEN @drawfilter IN (2, 3) 
							THEN CASE WHEN b.STATUS = 111 THEN 0
								WHEN b.STATUS IN (114, 115)	THEN 0.5 ELSE 1	END
							ELSE 1
						END) TurnOver
					, SUM(b.winloss) Winloss
					, 0 AS AWinloss --AmountDueToBA = -sum(winloss * rate) + AComm
					, SUM(b.CommissionA) AS CommBA
					, 0 AS Playercomm --SUM(commissionP) AS Playercomm
					, SUM(betcount * CASE WHEN @drawfilter = 2 AND b.Status = 111 THEN 0 ELSE 1 END) BetCount
				FROM bodb_Licensee.dbo.rpt_Betting_BA b WITH (NOLOCK)
					INNER JOIN @tmpParty p ON b.SiteID = p.LicenseeID and p.ProductID = 3
					INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
				WHERE b.rptDate BETWEEN @Fromdate AND @Todate
					AND b.Status NOT IN (- 1, 103)
					AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
					AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
				GROUP BY p.PartyID, b.rptDate, bt.ProductID, currencyID
			)

			INSERT INTO #Temp (PartyID, rptDate, Currency, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA
				, AmtDueToRB, CommBA, CommRB, Company, Playercomm, Betcount)
			(
				SELECT p.PartyID, b.rptDate, b.currency
					, SUM(b.turnover) TurnOver
					, SUM(b.winloss) Winloss
					, 0 AS LicenseeWL
					, 0 AS WinlossRB
					, -SUM((b.winloss * p.Rate ) + b.AComm) AS AmountDueToBA
					, 0 AS AmountDueToRB
					, SUM(b.AComm) AS CommBA
					, 0 AS CommRB
					, 0 AS Company
					, SUM(PComm) AS Playercomm
					, SUM(betcount) BetCount
				FROM #Data b
					INNER JOIN @tmpParty p ON p.PartyID = b.PartyID AND b.ProductID = p.ProductID				
				WHERE b.rptDate BETWEEN p.Fromdate AND p.Todate
					AND p.ProductID = 3
				GROUP BY p.PartyID, b.rptDate, b.Currency
			)
		END
	END
	
	--Filter again
	IF (REPLACE(@ProductCodes, 'BA', '') != '' AND REPLACE(@ProductCodes, 'BA', '') != ',')
	BEGIN
		DELETE #Data
		IF @SportType <> 0
		BEGIN
			INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, TurnOver, Winloss, AWinloss, AComm, PComm, Betcount)
			(
				SELECT  b.rptDate, p.PartyID, bt.ProductID, b.currencyID
					, SUM(b.turnover * 
						CASE WHEN b.bettype = 33 AND b.STATUS IN (114, 115) THEN 0.5 ELSE 1 END * 
						CASE WHEN @drawfilter IN (2, 3)	
								THEN CASE WHEN b.STATUS = 111 THEN 0 WHEN b.STATUS IN (114, 115) AND b.Bettype != 33
									THEN 0.5 ELSE 1
								END	ELSE 1
						END) TurnOver
					, SUM(b.winloss)
					, SUM(b.winlossA)
					, SUM(b.CommissionA)
					, 0 AS Playercomm --SUM(b.commissionP)
					, SUM(b.betcount * CASE WHEN @drawfilter = 2 AND b.STATUS = 111 THEN 0	ELSE 1 END) BetCount
				FROM bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK)
					INNER JOIN(
						SELECT DISTINCT PartyId, LicenseeId FROM @tmpParty WHERE ProductID <> 3
					) p ON b.SiteID = p.LicenseeID
					INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
					INNER JOIN dbo.League l(NOLOCK) ON b.leagueid = l.leagueid
				WHERE b.rptDate BETWEEN @FromDate AND @ToDate
					AND b.Status NOT IN (- 1, 103)
					AND b.bettype NOT BETWEEN 31 AND 120 AND l.sporttype = @SportType
					AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
					AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
					AND b.customercategory NOT IN (27,28)
				GROUP BY b.rptDate, PartyID, bt.ProductID, b.CurrencyID
			)

			INSERT INTO #Temp (PartyID, rptDate, Currency, TurnOver, Winlost, LicenseeWL
				, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Playercomm, Betcount)
			(
				SELECT p.PartyID--, p.ProductID
					, rptDate --CONVERT(VARCHAR(6), b.rptDate, 112) ReportType			
					, b.Currency
					, SUM(b.turnover) TurnOver
					, SUM(b.Winloss) Winloss
					, -SUM(CASE 
							WHEN (b.ProductID <> 1)
								THEN b.Winloss
							ELSE 0
							END) AS LicenseeWL
					, SUM(CASE 
							WHEN b.ProductID = 1
								THEN b.AWinloss
							ELSE 0
							END) AS WinlossRB
					, 0 AS AmountDueToBA
					, -SUM(CASE 
							WHEN b.ProductID = 1
								THEN (b.Winloss + b.AWinloss + b.AComm)						
							ELSE 0
							END) AS AmountDueToRB
					, 0 AS CommBA
					, SUM(CASE 
							WHEN b.ProductID = 1
								THEN b.AComm
							ELSE 0
							END) AS CommRB
					, -SUM(CASE 
							WHEN b.ProductID <> 1						
								THEN ((b.Winloss * p.Rate))
							ELSE 0
							END) AS Company
					, SUM(b.PComm) AS Playercomm
					, SUM(b.betcount) AS betcount
				FROM #Data b WITH (NOLOCK)
					--INNER JOIN dbo.League l(NOLOCK) ON b.leagueid = l.leagueid
					INNER JOIN @tmpParty p ON p.PartyID = b.PartyID AND b.ProductID = p.ProductID				
				WHERE b.rptDate BETWEEN p.Fromdate AND p.Todate
					AND p.ProductID <> 3
				GROUP BY p.PartyID, b.rptDate, b.Currency
			)

		END
		ELSE
		BEGIN
			INSERT INTO #Data(rptDate, PartyID, ProductID, Currency, TurnOver, Winloss, AWinloss, AComm, PComm, Betcount)
			(
				SELECT  b.rptDate, p.PartyID, bt.ProductID, b.currencyID
					, SUM(b.turnover * 
						CASE WHEN b.bettype = 33 AND b.STATUS IN (114, 115) THEN 0.5 ELSE 1 END * 
						CASE WHEN @drawfilter IN (2, 3)	
								THEN CASE WHEN b.STATUS = 111 THEN 0 WHEN b.STATUS IN (114, 115) AND b.Bettype != 33
									THEN 0.5 ELSE 1
								END	ELSE 1
						END) TurnOver
					, SUM(b.winloss)
					, SUM(b.winlossA)
					, SUM(b.CommissionA)
					, 0 AS Playercomm --SUM(b.commissionP)
					, SUM(b.betcount * 
					CASE WHEN @drawfilter = 2 AND b.STATUS = 111 THEN 0	ELSE 1 END) BetCount
				FROM bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK)
					INNER JOIN(
						SELECT DISTINCT PartyId, LicenseeId FROM @tmpParty WHERE ProductID <> 3
					) p ON b.SiteID = p.LicenseeID
					INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
				WHERE b.rptDate BETWEEN @FromDate AND @ToDate
					AND b.Status NOT IN (- 1, 103)
					AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))
					AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20))
					AND b.customercategory NOT IN (27,28)
				GROUP BY b.rptDate, PartyID, bt.ProductID, b.CurrencyID
			)

			INSERT INTO #Temp (PartyID, rptDate, Currency, TurnOver, Winlost, LicenseeWL
				, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Playercomm, Betcount)
			SELECT p.PartyID--, p.ProductID
				, rptDate --CONVERT(VARCHAR(6), b.rptDate, 112) ReportType			
				, b.Currency
				, SUM(b.turnover) TurnOver
				, SUM(b.Winloss) Winloss
				, -SUM(CASE 
						WHEN (b.ProductID <> 1)
							THEN b.Winloss
						ELSE 0
						END) AS LicenseeWL
				, SUM(CASE 
						WHEN b.ProductID = 1
							THEN b.AWinloss
						ELSE 0
						END) AS WinlossRB
				, 0 AS AmountDueToBA
				, -SUM(CASE 
						WHEN b.ProductID = 1
							THEN (b.Winloss + b.AWinloss + b.AComm)						
						ELSE 0
						END) AS AmountDueToRB
				, 0 AS CommBA
				, SUM(CASE 
						WHEN b.ProductID = 1
							THEN b.AComm
						ELSE 0
						END) AS CommRB
				, -SUM(CASE 
						WHEN b.ProductID <> 1						
							THEN ((b.Winloss * p.Rate))
						ELSE 0
						END) AS Company
				, SUM(b.PComm) AS Playercomm
				, SUM(b.betcount) AS betcount
			FROM #Data b WITH (NOLOCK)
				INNER JOIN @tmpParty p ON p.PartyID = b.PartyID AND b.ProductID = p.ProductID				
			WHERE b.rptDate BETWEEN p.Fromdate AND p.Todate
				AND p.ProductID <> 3
			GROUP BY p.PartyID, b.rptDate, b.Currency
		END
		
	END

	INSERT INTO #WinLoss
	SELECT b.PartyID
		--,b.ProductID
		, CONVERT(VARCHAR(6), b.rptDate, 112) AS ReportType
		, SUM(TurnOver) AS TurnOver
		, SUM(Winlost) AS Winlost
		, SUM(LicenseeWL) AS LicenseeWL
		, SUM(WinlossRB) AS WinlossRB
		, SUM(AmtDueToBA) AS AmtDueToBA
		, SUM(AmtDueToRB) AS AmtDueToRB
		, SUM(CommBA) AS CommBA
		, SUM(CommRB) AS CommRB
		, SUM(Company) AS Company
		, SUM(Playercomm) AS Playercomm
		, SUM(Betcount) AS Betcount
		, SUM(TurnOver * e.MYR) AS TurnOverMYR
		, SUM(Winlost * e.MYR) AS WinlostMYR
		, SUM(LicenseeWL * e.MYR) AS LicenseeWLMYR
		, SUM(WinlossRB * e.MYR) AS WinlossRBMYR
		, SUM(AmtDueToBA * e.MYR) AS AmtDueToBAMYR
		, SUM(AmtDueToRB * e.MYR) AS AmtDueToRBMYR
		, SUM(CommBA * e.MYR) AS CommBAMYR
		, SUM(CommRB * e.MYR) AS CommRBMYR
		, SUM(Company * e.MYR) AS CompanyMYR
		, SUM(Playercomm * e.MYR) AS PlayercommMYR
		, SUM(TurnOver * e.USD) AS TurnOverUSD
		, SUM(Winlost * e.USD) AS WinlostUSD
		, SUM(LicenseeWL * e.USD) AS LicenseeWLUSD
		, SUM(WinlossRB * e.USD) AS WinlossRBUSD
		, SUM(AmtDueToBA * e.USD) AS AmtDueToBAUSD
		, SUM(AmtDueToRB * e.USD) AS AmtDueToRBUSD
		, SUM(CommBA * e.USD) AS CommBAUSD
		, SUM(CommRB * e.USD) AS CommRBUSD
		, SUM(Company * e.USD) AS CompanyUSD
		, SUM(Playercomm * e.USD) AS PlayercommUSD
		, SUM(TurnOver * e.EUR) AS TurnOverEUR
		, SUM(Winlost * e.EUR) AS WinlostEUR
		, SUM(LicenseeWL * e.EUR) AS LicenseeWLEUR
		, SUM(WinlossRB * e.EUR) AS WinlossRBEUR
		, SUM(AmtDueToBA * e.EUR) AS AmtDueToBAEUR
		, SUM(AmtDueToRB * e.EUR) AS AmtDueToRBEUR
		, SUM(CommBA * e.EUR) AS CommBAEUR
		, SUM(CommRB * e.EUR) AS CommRBEUR
		, SUM(Company * e.EUR) AS CompanyEUR
		, SUM(Playercomm * e.EUR) AS PlayercommEUR
	FROM #Temp b
		INNER JOIN #Exchange e ON e.ExchangeDate = rptDate AND e.ExchangeId = b.Currency
	GROUP BY PartyID, CONVERT(VARCHAR(6), b.rptDate, 112)

	SELECT w.PartyID	
		,CASE p.PartyName
			WHEN '18bb' THEN 'PIH'
			WHEN 'IBC'	THEN 'FDL'
			ELSE p.PartyName
			END AS PartyName
		,w.ReportType
		,SUM(TurnOver) AS Turnover
		,SUM(Winlost) AS Winlost
		,SUM(LicenseeWL) AS LicenseeWL
		,SUM(WinlossRB) AS WinlossRB
		,SUM(CommBA) AS CommBA
		,SUM(CommRB) AS CommRB
		,SUM(AmtDuetoBA) AS AmtDuetoBA
		,SUM(AmtDuetoRB) AS AmtDuetoRB
		,SUM(Company) AS Company
		,SUM(Betcount) AS Betcount
		,SUM(Playercomm) AS Playercomm
		,
		--BaseRM  
		SUM(TurnOverMYR) AS TurnoverMYR
		,SUM(WinlostMYR) AS WinlostMYR
		,SUM(LicenseeWLMYR) AS LicenseeWLMYR
		,SUM(WinlossRBMYR) AS WinlossRBMYR
		,SUM(CommBAMYR) AS CommBAMYR
		,SUM(CommRBMYR) AS CommRBMYR
		,SUM(AmtDuetoBAMYR) AS AmtDuetoBAMYR
		,SUM(AmtDuetoRBMYR) AS AmtDuetoRBMYR
		,SUM(CompanyMYR) AS CompanyMYR
		,SUM(PlayercommMYR) AS PlayercommMYR
		,
		--BaseUSD  
		SUM(TurnOverUSD) AS TurnoverUSD
		,SUM(WinlostUSD) AS WinlostUSD
		,SUM(LicenseeWLUSD) AS LicenseeWLUSD
		,SUM(WinlossRBUSD) AS WinlossRBUSD
		,SUM(CommBAUSD) AS CommBAUSD
		,SUM(CommRBUSD) AS CommRBUSD
		,SUM(AmtDuetoBAUSD) AS AmtDuetoBAUSD
		,SUM(AmtDuetoRBUSD) AS AmtDuetoRBUSD
		,SUM(CompanyUSD) AS CompanyUSD
		,SUM(PlayercommUSD) AS PlayercommUSD
		,
		--BaseEUR  
		SUM(TurnOverEUR) AS TurnoverEUR
		,SUM(WinlostEUR) AS WinlostEUR
		,SUM(LicenseeWLEUR) AS LicenseeWLEUR
		,SUM(WinlossRBEUR) AS WinlossRBEUR
		,SUM(CommBAEUR) AS CommBAEUR
		,SUM(CommRBEUR) AS CommRBEUR
		,SUM(AmtDuetoBAEUR) AS AmtDuetoBAEUR
		,SUM(AmtDuetoRBEUR) AS AmtDuetoRBEUR
		,SUM(CompanyEUR) AS CompanyEUR
		,SUM(PlayercommEUR) AS PlayercommEUR
	FROM #WinLoss w
		INNER JOIN bodb_Licensee.dbo.OAS_Party p (NOLOCK) ON p.PartyID = w.PartyID
	GROUP BY w.PartyID, p.PartyName, w.ReportType	
	ORDER BY ReportType ASC, CASE p.PartyName WHEN '18bb' THEN 'PIH' WHEN 'IBC' THEN 'FDL' ELSE p.PartyName END

	DROP TABLE #WinLoss
	DROP TABLE #Exchange
	DROP TABLE #Temp
	DROP TABLE #Bettype
	--DROP TABLE #tmpParty
	DROP TABLE #Data
	--DROP TABLE #PartyBettype
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicWinloss] TO bodbAdminNet 
