USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LicWinloss_Details]    Script Date: 9/8/2014 5:13:36 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicWinloss_Details] @PartyID INT
	,@Currency INT = 0
	,@FromDate SMALLDATETIME
	,@ToDate SMALLDATETIME
	,@ProductCode VARCHAR(10)
	,@SportType INT = 0
	,@Bettype INT = 0
	,@ReportBy TINYINT = 1
	,@DrawFilter SMALLINT = 1
	,@ExcludeTest BIT = 0
AS
/*   Created:  Florent.Nguyen
	Date: 20140827
     Original: OA_Rpt_LicWinloss2
	Task : LA Get Party Winloss Details
     DB: DB052.bodb02  
   
     Revisions:  
	
	Param's Explanation:  
	  + @PartyIDs	: a string of list PartyID, separate by ','
	  + @Currency	:  0- All Currencies
	  + @ReportBy: 1-Daily; 2-Monthly;  
	  + @DrawFilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: add/remove currency UUS
	  + @ProductCode	: Products code :
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

	CREATE TABLE #SAgWinLoss (
		winlostdate DATETIME
		,Currency INT
		,TurnOver MONEY
		,Winlost MONEY
		,LicenseeWL MONEY
		,WinlossRB MONEY
		,AmtDueToBA MONEY
		,AmtDueToRB MONEY
		,CommBA MONEY
		,CommRB MONEY
		,Company MONEY
		,Betcount BIGINT
		,Playercomm MONEY
		)

	DECLARE @VNDCurrencyName VARCHAR(20)
	DECLARE @site VARCHAR(50)

	SELECT @VNDCurrencyName = currency
	FROM exchange(NOLOCK)
	WHERE ExchangeId = 51

	--Get Bettype
	CREATE TABLE #Bettype (Bettype INT)

	IF @Bettype != 0
		INSERT INTO #Bettype
		SELECT @Bettype
	ELSE
	BEGIN
		IF @ProductCode = 'SB'
			OR @ProductCode = 'BA'
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid < 31
				OR typeid BETWEEN 121 AND 999
				OR typeid BETWEEN 1301 AND 1399
		END

		IF @ProductCode = 'RB'
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid BETWEEN 31 AND 33
		END

		IF @ProductCode = 'NG'
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid BETWEEN 81 AND 120
		END

		IF @ProductCode = 'LC'
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid BETWEEN 1101 AND 1199
		END

		IF @ProductCode = 'VS'
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid BETWEEN 1201 AND 1299
		END

		IF @ProductCode = 'CS'
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid = 71
		END
	END

	--Get list of Party - Licensee
	DECLARE @tmpParty TABLE (
		PartyID INT
		,LicenseeID INT
		,AffectedDate DATETIME
		,Fromdate DATETIME
		,Todate DATETIME
		)

	INSERT INTO @tmpParty (
		PartyID
		,LicenseeID
		,AffectedDate
		,Fromdate
		,Todate
		)
	SELECT p.PartyID
		,l.LicenseeID
		,l.AffectedDate
		,@FromDate
		,@ToDate
	FROM bodb_Licensee.dbo.OAS_Party p(NOLOCK)
	INNER JOIN bodb_licensee.dbo.Licensees l(NOLOCK) ON p.OldRefID = l.LicenseeID
		AND p.PartyType = 1
	WHERE p.PartyID = @PartyID
		AND l.AffectedDate IS NOT NULL

	DECLARE @_FromDate SMALLDATETIME
		,@_ToDate SMALLDATETIME

	IF (EXISTS (
			SELECT TOP 1 1
			FROM @tmpParty
			WHERE AffectedDate > Fromdate
			) AND @excludeTest = 1)
	BEGIN
		UPDATE @tmpParty
		SET Fromdate = AffectedDate
		WHERE AffectedDate > Fromdate
	END

	BEGIN
		IF @ProductCode = 'BA'
		BEGIN
			INSERT INTO #SAgWinLoss
			SELECT b.rptDate
				,b.CurrencyID
				,SUM(b.turnover * CASE 
						WHEN @drawfilter IN (2, 3)
							THEN CASE 
									WHEN b.STATUS = 111
										THEN 0
									WHEN b.STATUS IN (114, 115)
										THEN 0.5
									ELSE 1
									END
						ELSE 1
						END) TurnOver
				,SUM(b.winloss) Winloss
				,0 AS LicenseeWL
				,0 AS WinlossRB
				,- SUM(b.winloss + b.winlossA + b.CommissionA) AS AmountDueToBA
				,0 AS AmountDueToRB
				,SUM(b.CommissionA) AS CommBA
				,0 AS CommRB
				,0 AS Company
				,SUM(betcount) * CASE 
					WHEN @drawfilter = 2
						AND b.STATUS = 111
						THEN 0
					ELSE 1
					END BetCount
				,SUM(commissionP) AS Playercomm
			FROM bodb_Licensee.dbo.rpt_Betting_BA b WITH (NOLOCK)
			INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
			INNER JOIN @tmpParty p ON b.SiteID = p.LicenseeID
			LEFT JOIN dbo.League l(NOLOCK) ON b.leagueid = l.leagueid
			WHERE b.rptDate BETWEEN p.Fromdate AND p.Todate
				AND b.STATUS NOT IN (- 1, 103)
				AND (
					@SportType = 0
					OR (
						@SportType <> 0
						AND l.sporttype = @SportType
						)
					)
				AND (
					@Currency = 0
					OR (
						@Currency <> 0
						AND b.CurrencyID = @Currency
						)
					)
				AND (
					@excludeTest = 0
					OR (
						@excludeTest = 1
						AND b.CurrencyID <> 20
						)
					)
			GROUP BY b.rptdate
				,b.currencyID
				,b.STATUS
		END
		ELSE
		BEGIN
			INSERT INTO #SAgWinLoss
			SELECT b.rptDate
				,b.CurrencyID
				,SUM(b.turnover * CASE 
						WHEN b.bettype = 33
							AND b.STATUS IN (114, 115)
							THEN 0.5
						ELSE 1
						END * CASE 
						WHEN @drawfilter IN (2, 3)
							THEN CASE 
									WHEN b.STATUS = 111
										THEN 0
									WHEN b.STATUS IN (114, 115)
										THEN 0.5
									ELSE 1
									END
						ELSE 1
						END) TurnOver
				,SUM(b.winloss) Winloss
				,- SUM(CASE 
						WHEN (b.bettype NOT BETWEEN 31 AND 33)
							THEN b.winloss
						ELSE 0
						END) AS LicenseeWL
				,SUM(CASE 
						WHEN b.bettype BETWEEN 31 AND 33
							THEN b.winlossA
						ELSE 0
						END) AS WinlossRB
				,0 AS AmountDueToBA
				,- SUM(CASE 
						WHEN b.bettype BETWEEN 31 AND 33
							THEN (b.winloss + b.winlossA + b.CommissionA)
						ELSE 0
						END) AS AmountDueToRB
				,0 AS CommBA
				,SUM(CASE 
						WHEN b.bettype BETWEEN 31 AND 33
							THEN b.CommissionA
						ELSE 0
						END) AS CommRB
				,- SUM(CASE 
						WHEN b.bettype NOT BETWEEN 31 AND 33
							THEN (b.winloss + b.winlossA + b.CommissionA)
						ELSE 0
						END) AS Company
				,SUM(b.betcount) * CASE 
					WHEN @drawfilter = 2
						THEN CASE 
								WHEN b.STATUS = 111
									THEN 0
								ELSE 1
								END
					ELSE 1
					END BetCount
				,SUM(commissionP) AS Playercomm
			FROM bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK)
			INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
			INNER JOIN @tmpParty p ON b.SiteID = p.LicenseeID
			LEFT JOIN dbo.League l(NOLOCK) ON b.leagueid = l.leagueid
			WHERE b.rptdate BETWEEN p.Fromdate AND p.Todate
				AND b.STATUS NOT IN (- 1, 103)
				AND (
					@SportType = 0
					OR (
						@SportType <> 0
						AND b.bettype NOT BETWEEN 31 AND 120
						AND l.sporttype = @SportType
						)
					)
				AND (
					@Currency = 0
					OR (
						@Currency <> 0
						AND b.CurrencyID = @Currency
						)
					)
				AND (
					@excludeTest = 0
					OR (
						@excludeTest = 1
						AND b.CurrencyID <> 20
						)
					)
			GROUP BY b.rptdate
				,b.currencyID
				,b.STATUS
		END
	END

	CREATE NONCLUSTERED INDEX IDX_Index_SA ON #SAgWinLoss (Currency)

	SELECT *
	INTO #TempExchange
	FROM Lrf_f_GetExchangeDaily(@FromDate, @Todate)
	WHERE exchangeid IN (
			SELECT DISTINCT Currency
			FROM #SAgWinLoss
			)

	SELECT CASE 
			WHEN @ReportBy = 1
				THEN CONVERT(VARCHAR(8), w.winlostdate, 112)
			WHEN @ReportBy = 2
				THEN CONVERT(VARCHAR(6), w.winlostdate, 112)
			ELSE '0'
			END ReportType
		,w.Currency
		,CASE 
			WHEN Currency = 51
				THEN @VNDCurrencyName
			ELSE e.Code
			END currencyName
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
		,SUM(playercomm) AS Playercomm
		,
		--BaseRM  
		CAST(SUM(TurnOver * e.MYR) AS MONEY) AS TurnoverMYR
		,CAST(SUM(Winlost * e.MYR) AS MONEY) AS WinlostMYR
		,CAST(SUM(LicenseeWL * e.MYR) AS MONEY) AS LicenseeWLMYR
		,CAST(SUM(WinlossRB * e.MYR) AS MONEY) AS WinlossRBMYR
		,CAST(SUM(CommBA * e.MYR) AS MONEY) AS CommBAMYR
		,CAST(SUM(CommRB * e.MYR) AS MONEY) AS CommRBMYR
		,CAST(SUM(AmtDuetoBA * e.MYR) AS MONEY) AS AmtDuetoBAMYR
		,CAST(SUM(AmtDuetoRB * e.MYR) AS MONEY) AS AmtDuetoRBMYR
		,CAST(SUM(Company * e.MYR) AS MONEY) AS CompanyMYR
		,CAST(SUM(playercomm * e.MYR) AS MONEY) AS PlayercommMYR
		,
		--BaseUSD  
		CAST(SUM(TurnOver * e.USD) AS MONEY) AS TurnoverUSD
		,CAST(SUM(Winlost * e.USD) AS MONEY) AS WinlostUSD
		,CAST(SUM(LicenseeWL * e.USD) AS MONEY) AS LicenseeWLUSD
		,CAST(SUM(WinlossRB * e.USD) AS MONEY) AS WinlossRBUSD
		,CAST(SUM(CommBA * e.USD) AS MONEY) AS CommBAUSD
		,CAST(SUM(CommRB * e.USD) AS MONEY) AS CommRBUSD
		,CAST(SUM(AmtDuetoBA * e.USD) AS MONEY) AS AmtDuetoBAUSD
		,CAST(SUM(AmtDuetoRB * e.USD) AS MONEY) AS AmtDuetoRBUSD
		,CAST(SUM(Company * e.USD) AS MONEY) AS CompanyUSD
		,CAST(SUM(playercomm * e.USD) AS MONEY) AS PlayercommUSD
		,
		--BaseEUR  
		CAST(SUM(TurnOver * e.EUR) AS MONEY) AS TurnoverEUR
		,CAST(SUM(Winlost * e.EUR) AS MONEY) AS WinlostEUR
		,CAST(SUM(LicenseeWL * e.EUR) AS MONEY) AS LicenseeWLEUR
		,CAST(SUM(WinlossRB * e.EUR) AS MONEY) AS WinlossRBEUR
		,CAST(SUM(CommBA * e.EUR) AS MONEY) AS CommBAEUR
		,CAST(SUM(CommRB * e.EUR) AS MONEY) AS CommRBEUR
		,CAST(SUM(AmtDuetoBA * e.EUR) AS MONEY) AS AmtDuetoBAEUR
		,CAST(SUM(AmtDuetoRB * e.EUR) AS MONEY) AS AmtDuetoRBEUR
		,CAST(SUM(Company * e.EUR) AS MONEY) AS CompanyEUR
		,CAST(SUM(playercomm * e.EUR) AS MONEY) AS PlayercommEUR
	FROM #SAgWinLoss w
	INNER JOIN #TempExchange e ON w.winlostdate = e.ExchangeDate
		AND w.currency = e.ExchangeId
	GROUP BY Currency
		,CASE 
			WHEN @ReportBy = 1
				THEN CONVERT(VARCHAR(8), w.winlostdate, 112)
			WHEN @ReportBy = 2
				THEN CONVERT(VARCHAR(6), w.winlostdate, 112)
			ELSE '0'
			END
		,CASE 
			WHEN Currency = 51
				THEN @VNDCurrencyName
			ELSE e.Code
			END
	ORDER BY ReportType

	DROP TABLE #SAgWinLoss
	DROP TABLE #TempExchange
	DROP TABLE #Bettype
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicWinloss_Details] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicWinloss_Details] TO bodbAdminNet 
