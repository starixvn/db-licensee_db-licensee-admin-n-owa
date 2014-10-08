USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LicWinloss]    Script Date: 08/10/2014 11:22:41 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicWinloss] 
      @PartyIDs	VARCHAR(1000)	 = ''
	,@Currency	INT			 = 0
	,@FromDate	SMALLDATETIME
	,@ToDate		SMALLDATETIME
	,@ProductCodes VARCHAR(1000)
	,@SportType	INT			 = 0
	,@Bettype		INT			 = 0
	,@ReportBy	TINYINT		 = 1
	,@DrawFilter	SMALLINT		 = 1
	,@excludeTest	BIT			 = 0
AS
/*   Created:  Florent.Nguyen
	Date: 20140827
     Original: OA_Rpt_LicWinloss_Summary
	Task : LA Get Party Winloss
     DB: DB052.bodb02  
   
     Revisions:  
	
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
	CREATE TABLE #WinLoss (
		LicenseeID INT
		,ReportType VARCHAR(6)
		,TurnOver MONEY
		,Winlost MONEY
		,LicenseeWL MONEY
		,WinlossRB MONEY
		,AmtDueToBA MONEY
		,AmtDueToRB MONEY
		,CommBA MONEY
		,CommRB MONEY
		,Company MONEY
		,Playercomm MONEY
		,Betcount BIGINT
		,TurnOverMYR MONEY
		,WinlostMYR MONEY
		,LicenseeWLMYR MONEY
		,WinlossRBMYR MONEY
		,AmtDueToBAMYR MONEY
		,AmtDueToRBMYR MONEY
		,CommBAMYR MONEY
		,CommRBMYR MONEY
		,CompanyMYR MONEY
		,PlayercommMYR MONEY
		,TurnOverUSD MONEY
		,WinlostUSD MONEY
		,LicenseeWLUSD MONEY
		,WinlossRBUSD MONEY
		,AmtDueToBAUSD MONEY
		,AmtDueToRBUSD MONEY
		,CommBAUSD MONEY
		,CommRBUSD MONEY
		,CompanyUSD MONEY
		,PlayercommUSD MONEY
		,TurnOverEUR MONEY
		,WinlostEUR MONEY
		,LicenseeWLEUR MONEY
		,WinlossRBEUR MONEY
		,AmtDueToBAEUR MONEY
		,AmtDueToRBEUR MONEY
		,CommBAEUR MONEY
		,CommRBEUR MONEY
		,CompanyEUR MONEY
		,PlayercommEUR MONEY
		)

	CREATE TABLE #Temp (
		LicenseeID INT
		,ReportType INT
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
		,Playercomm MONEY
		,Betcount BIGINT
		)

	CREATE TABLE #Bettype (Bettype INT)

	IF @Bettype != 0
		INSERT INTO #Bettype
		SELECT @Bettype
	ELSE
	BEGIN
		IF CHARINDEX('SB', @ProductCodes) <> 0
			OR CHARINDEX('BA', @ProductCodes) <> 0
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid < 31
				OR typeid BETWEEN 121 AND 999
				OR typeid BETWEEN 1301 AND 1399
		END

		IF CHARINDEX('RB', @ProductCodes) <> 0
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid BETWEEN 31 AND 33
		END

		IF CHARINDEX('NG', @ProductCodes) <> 0
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid BETWEEN 81 AND 120
		END

		IF CHARINDEX('LC', @ProductCodes) <> 0
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid BETWEEN 1101 AND 1199
		END

		IF CHARINDEX('VS', @ProductCodes) <> 0
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid BETWEEN 1201 AND 1299
		END

		IF CHARINDEX('CS', @ProductCodes) <> 0
		BEGIN
			INSERT INTO #Bettype
			SELECT typeid
			FROM dbo.bettype WITH (NOLOCK)
			WHERE typeid = 71
		END
	END

	DECLARE @tmpParty TABLE (
		PartyID INT
		,LicenseeID INT
		,ParentID INT
		,ParentName VARCHAR(100)
		,AffectedDate DATETIME
		,Fromdate DATETIME
		,Todate DATETIME
		)

	/*
    CREATE table #PartyList
    (
	   PartyID INT,
	   PartyName VARCHAR(100),
	   ParentID INT
    )
    INSERT INTO #PartyList
    EXEC bodb_licensee.dbo.LA_PartyListSel
*/
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
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK)
	INNER JOIN bodb_licensee.dbo.Licensees l(NOLOCK) ON p.OldRefID = l.LicenseeID
		AND p.PartyType = 1
	LEFT JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
	WHERE p.PartyID IN (
			SELECT VAL
			FROM strSplit(@PartyIDs, ',')
			)
		AND (
			l.AffectedDate IS NOT NULL
			OR pd.IsDeposit = 0
			)

	DECLARE @_FromDate SMALLDATETIME
		,@_ToDate SMALLDATETIME

	IF (
			EXISTS (
				SELECT TOP 1 1
				FROM @tmpParty
				WHERE AffectedDate > Fromdate
				)
			AND @excludeTest = 1
			)
	BEGIN
		UPDATE @tmpParty
		SET Fromdate = AffectedDate
		WHERE AffectedDate > Fromdate
	END

	SELECT @_FromDate = @FromDate
		,@_ToDate = @ToDate

	CREATE TABLE #Exchange (
		ExchangeDate INT
		,ExchangeId INT
		,USD FLOAT
		,EUR FLOAT
		,MYR FLOAT
		,PRIMARY KEY (
			ExchangeDate
			,ExchangeId
			)
		)

	INSERT INTO #Exchange (
		ExchangeDate
		,ExchangeId
		,USD
		,EUR
		,MYR
		)
	SELECT DISTINCT CONVERT(VARCHAR(6), ExchangeDate, 112)
		,ExchangeId
		,USD
		,EUR
		,MYR
	FROM Lrf_f_GetExchangeDaily(@_FromDate, @_ToDate)
	WHERE exchangeid IN (SELECT DISTINCT Currency FROM bodb_Licensee.dbo.LicenseeCust lc WITH (NOLOCK) WHERE 
		lc.LicenseeID IN (SELECT LicenseeID FROM  @tmpParty))	
	AND (@Currency = 0
		OR ExchangeId = @Currency)

	IF CHARINDEX('BA', @ProductCodes) <> 0
	BEGIN
		INSERT INTO #Temp (
			LicenseeID
			,ReportType
			,Currency
			,TurnOver
			,Winlost
			,LicenseeWL
			,WinlossRB
			,AmtDueToBA
			,AmtDueToRB
			,CommBA
			,CommRB
			,Company
			,Playercomm
			,Betcount
			)
		SELECT b.siteID
			,CONVERT(VARCHAR(6), b.rptDate, 112) ReportType
			,b.currencyID
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
			,SUM(commissionP) AS Playercomm
			,SUM(betcount) * CASE 
				WHEN @drawfilter = 2
					AND b.STATUS = 111
					THEN 0
				ELSE 1
				END BetCount
		FROM bodb_Licensee.dbo.rpt_Betting_BA b WITH (NOLOCK)
		INNER JOIN @tmpParty p ON b.SiteID = p.LicenseeID
		INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
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
		GROUP BY b.siteID
			,CONVERT(VARCHAR(6), b.rptDate, 112)
			,STATUS
			,currencyID
	END

	IF (REPLACE(@ProductCodes, 'BA', '') != '' AND REPLACE(@ProductCodes, 'BA', '') != ',')
	BEGIN
		INSERT INTO #Temp (
			LicenseeID
			,ReportType
			,Currency
			,TurnOver
			,Winlost
			,LicenseeWL
			,WinlossRB
			,AmtDueToBA
			,AmtDueToRB
			,CommBA
			,CommRB
			,Company
			,Playercomm
			,Betcount
			)
		SELECT b.siteID
			,CONVERT(VARCHAR(6), b.rptDate, 112) ReportType
			,b.currencyID
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
					WHEN (b.Bettype NOT BETWEEN 31 AND 33)
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
			,SUM(commissionP) AS Playercomm
			,SUM(b.betcount) * CASE 
				WHEN @drawfilter = 2
					AND b.STATUS = 111
					THEN 0
				ELSE 1
				END BetCount
		FROM bodb_Licensee.dbo.rpt_Betting b WITH (
				NOLOCK
				,INDEX = IX_Sport
				)
		INNER JOIN @tmpParty p ON p.LicenseeID = b.SiteID
		INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
		LEFT JOIN dbo.League l(NOLOCK) ON b.leagueid = l.leagueid
		WHERE b.rptDate BETWEEN p.Fromdate AND p.Todate
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
		GROUP BY b.siteID
			,CONVERT(VARCHAR(6), b.rptDate, 112)
			,b.STATUS
			,b.currencyID
	END

	INSERT INTO #WinLoss
	SELECT LicenseeID
		,ReportType
		,TurnOver
		,Winlost
		,LicenseeWL
		,WinlossRB
		,AmtDueToBA
		,AmtDueToRB
		,CommBA
		,CommRB
		,Company
		,Playercomm
		,Betcount
		,TurnOver * e.MYR TurnOverMYR
		,Winlost * e.MYR WinlostMYR
		,LicenseeWL * e.MYR LicenseeWLMYR
		,WinlossRB * e.MYR WinlossRBMYR
		,AmtDueToBA * e.MYR AmtDueToBAMYR
		,AmtDueToRB * e.MYR AmtDueToRBMYR
		,CommBA * e.MYR CommBAMYR
		,CommRB * e.MYR CommRBMYR
		,Company * e.MYR CompanyMYR
		,Playercomm * e.MYR PlayercommMYR
		,TurnOver * e.USD TurnOverUSD
		,Winlost * e.USD WinlostUSD
		,LicenseeWL * e.USD LicenseeWLUSD
		,WinlossRB * e.USD WinlossRBUSD
		,AmtDueToBA * e.USD AmtDueToBAUSD
		,AmtDueToRB * e.USD AmtDueToRBUSD
		,CommBA * e.USD CommBAUSD
		,CommRB * e.USD CommRBUSD
		,Company * e.USD CompanyUSD
		,Playercomm * e.USD PlayercommUSD
		,TurnOver * e.EUR TurnOverEUR
		,Winlost * e.EUR WinlostEUR
		,LicenseeWL * e.EUR LicenseeWLEUR
		,WinlossRB * e.EUR WinlossRBEUR
		,AmtDueToBA * e.EUR AmtDueToBAEUR
		,AmtDueToRB * e.EUR AmtDueToRBEUR
		,CommBA * e.EUR CommBAEUR
		,CommRB * e.EUR CommRBEUR
		,Company * e.EUR CompanyEUR
		,Playercomm * e.EUR PlayercommEUR
	FROM #Temp b
	LEFT JOIN #Exchange e ON e.ExchangeDate = ReportType
		AND e.exchangeid = b.currency
END

SELECT --w.LicenseeID 
	t.PartyID
	,l.LicenseeName AS PartyName
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
INNER JOIN bodb_Licensee.dbo.Licensees l(NOLOCK) ON l.LicenseeID = w.LicenseeID
LEFT JOIN @tmpParty t ON w.LicenseeID = t.LicenseeID
GROUP BY --w.LicenseeID
	t.PartyID
	,l.LicenseeName
	,w.ReportType
ORDER BY l.LicenseeName
	,ReportType

DROP TABLE #WinLoss
DROP TABLE #Exchange
DROP TABLE #Temp
DROP TABLE #Bettype

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicWinloss] TO bodbAdminNet 
