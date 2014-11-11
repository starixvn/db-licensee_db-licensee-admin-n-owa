USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROC [dbo].[OAS_Report_LicenseeWinloss] 
	 @PartyID 	INT
	,@Currency 	INT 			= 0
	,@FromDate 	SMALLDATETIME
	,@ToDate 		SMALLDATETIME
	,@ReportType 	TINYINT 		= 2
	,@MoveBetsDay 	SMALLDATETIME
	,@IsOld 		BIT 			= 0
	,@drawfilter 	SMALLINT 		= 0
	,@excludeTest 	BIT 			= 1
AS
/*  
 * Created by : 20131223@Francis 
 * Task  : Get Winloss report for Sportbook (compatible with the new structure)
 * DB   : DB052.bodb02
 * Revisions :  
	- 20140327@Florent: remove paging
	- 20140410@Francis: Fix showing data out of time-range bug
	- 20140410@Francis: Alter @drawfilter param's value to 0,1,2
	- 20141105@Florent: Apply new struct support multi-System
 * 
 * Param's Explanation:    
 *  - @ID   : Party ID  (include: LicenseeID, ResellerID)
 *  - @Currency  : CurrencyID 
 *  - @FromDate  : From date  
 *  - @ToDate  : To date  
 *  - @ReportType : 1-Daily; 2-Monthly;  
 *  - @MoveBetsDay : The day we move tickets to bettrans14   
 *  - @IsOld  : 0 - query in table rptLicWinloss, 1 - query in table rptLicWinloss_old.   
 *  - @drawfilter : 'No Draw' filter is supportted (0:Normal 1:No Draw 2:No Draw for Turnover only)  
 *  - @excludeTest : remove currency UUS  
 exec OAS_Report_LicenseeWinloss_xtest 14,0,'2014-09-01','2014-09-30',2,'2014-09-20',0,0,0
 */
BEGIN
	SET NOCOUNT ON

	CREATE TABLE #SAgWinLoss (
		winlostdate DATETIME
		,CustID INT
		,Currency INT
		,sporttype INT
		,TurnOver MONEY
		,Winlost MONEY
		,LicenseeWL MONEY
		,Company MONEY
		,Betcount BIGINT
		,Playercomm MONEY
		)

	DECLARE @tmpAg TABLE (
		 custID INT PRIMARY KEY
		,Rate MONEY
		,FromDate SMALLDATETIME
		,ToDate SMALLDATETIME
		)
	DECLARE @VNDCurrencyName VARCHAR(20)

	SELECT @VNDCurrencyName = currency
	FROM exchange(NOLOCK)
	WHERE ExchangeId = 51

	INSERT INTO @tmpAg (
		custID
		,Rate
		,FromDate
		,ToDate
		)
	SELECT DISTINCT lc.CustID
		,ci.Rate
		,CASE 
			WHEN @FromDate <= ci.FromDate
				THEN ci.FromDate
			ELSE @FromDate
			END
		,CASE 
			WHEN @ToDate >= ci.ToDate
				THEN ci.ToDate
			ELSE @ToDate
			END
	FROM bodb_Licensee.dbo.LicenseeCust lc(NOLOCK)
	INNER JOIN bodb_licensee.dbo.OAS_Party p(NOLOCK) ON lc.LicenseeID = p.OldRefID
		AND p.PartyType = 1
	INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci(NOLOCK) ON ci.FromParty = p.PartyID
	INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs(NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 4
	WHERE p.PartyID = @PartyID
		AND ci.ChargeType = 1
		AND ci.ProductID = 0
		AND (
			@FromDate BETWEEN ci.FromDate AND ci.ToDate
			OR @ToDate BETWEEN ci.FromDate AND ci.ToDate
			)
		AND (
			@Currency = 0
			OR lc.Currency = @Currency
			)

	DECLARE @TempFromDate DATETIME
	DECLARE @TempToDate DATETIME
	DECLARE @MaxOldDate DATETIME
	DECLARE @FDate SMALLDATETIME
	DECLARE @TDate SMALLDATETIME

	IF (@FromDate <= (SELECT TOP 1 FromDate FROM @tmpAg))
		SET @FromDate = (
				SELECT TOP 1 FromDate
				FROM @tmpAg
				)

	IF (@ToDate >= (SELECT TOP 1 ToDate FROM @tmpAg ))
		SET @ToDate = (
				SELECT TOP 1 ToDate
				FROM @tmpAg
				)

	--to Deal With Parameter Sniffing
	SELECT @FDate = @FromDate
		,@TDate = @ToDate

	IF @TDate > @MoveBetsDay
	BEGIN
		IF @FDate <= @MoveBetsDay
			SET @TempFromDate = DATEADD(DAY, 1, @MoveBetsDay)
		ELSE
			SET @TempFromDate = @FDate

		--SportBook   
		INSERT INTO #SAgWinLoss
		SELECT b.winlostdate
			,b.srecommend
			,b.currency
			,0 AS sporttype
			,SUM(stake * CASE 
					WHEN @drawfilter IN (1, 2)
						THEN CASE 
								WHEN b.statusID = 111
									THEN 0
								WHEN (
										b.statusID = 112
										OR b.statusID = 113
										)
									AND ABS(modds) = 0.25
									AND b.bettype IN (1, 3, 7, 8, 17, 18)
									THEN 0.5
								ELSE 1
								END
					ELSE 1
					END) turnover
			,SUM(b.winlost - b.actual_stake) AS Winlost
			,- SUM(b.winlost - b.actual_stake) AS LicenseeWL
			--,- SUM(b.awinlost + b.winlost - b.actual_stake + b.comm) Company
			,- SUM((b.winlost - b.actual_stake) * ag.Rate + b.comm) Company
			,COUNT(b.transid) * CASE 
				WHEN @drawfilter = 1
					THEN CASE 
							WHEN b.statusID = 111
								THEN 0
							ELSE 1
							END
				ELSE 1
				END BetCount
			,SUM(playercomm) AS Playercomm
		FROM dbo.bettrans b WITH (NOLOCK)
			 INNER JOIN @tmpAg ag ON b.recommend = ag.CustID
		WHERE b.winlostdate BETWEEN @TempFromDate AND @TDate
			/*AND Recommend IN (
				SELECT custid
				FROM @tmpAg
				)*/
			AND (Bettype < 31  OR (Bettype BETWEEN 121 AND 999) OR (Bettype BETWEEN 1301 AND 1399)) 
			AND b.ruben = 1
			AND b.statusID NOT IN (101, 102, 103)
			AND tpositiontaking <> 0
		GROUP BY b.winlostdate
			,b.srecommend
			,b.currency
			,b.bettype
			,b.statusID
	END

	IF @FDate <= @MoveBetsDay
	BEGIN
		IF @TDate >= @MoveBetsDay
			SET @TempToDate = @MoveBetsDay
		ELSE
			SET @TempToDate = @TDate

		INSERT INTO #SAgWinLoss
		SELECT b.winlostdate
			,b.srecommend
			,b.currency
			,b.sporttype
			,SUM(b.turnover * CASE 
					WHEN @drawfilter IN (1, 2)
						THEN CASE 
								WHEN b.statusID = 111
									THEN 0
								WHEN b.statusID IN (114, 115)
									THEN 0.5
								ELSE 1
								END
					ELSE 1
					END)
			,SUM(b.winlost)
			,- SUM(b.winlost) AS LicenseeWL
			--,- SUM(b.awinlost + b.winlost + b.comm) AS Company
			,- SUM((b.winlost * ag.Rate ) + b.comm)  as Company 
			,SUM(b.betcount) * CASE 
				WHEN @drawfilter = 1
					THEN CASE 
							WHEN b.statusID = 111
								THEN 0
							ELSE 1
							END
				ELSE 1
				END
			,SUM(playercomm) AS Playercomm
		FROM bodb_Licensee.dbo.rptLicWinloss2 b WITH (NOLOCK)
			INNER JOIN @tmpAg ag ON b.recommend = ag.CustID
		WHERE b.Winlostdate BETWEEN @FDate AND @TempToDate
			AND b.sporttype = 0 --just only sportsbook
			AND b.roleid = 2
			/*AND b.Recommend IN (
				SELECT custid
				FROM @tmpAg
				)
			 */
			AND b.statusID <> 101
			AND ISNULL(b.isBA, 0) = 0
		GROUP BY b.winlostdate
			,b.srecommend
			,b.currency
			,b.sporttype
			,b.statusID
	END

	IF @IsOld = 1
	BEGIN
		SELECT @MaxOldDate = MAX(winlostdate)
		FROM bodb_Licensee.dbo.rptLicWinloss_old(NOLOCK)

		IF @TDate >= @MaxOldDate
			SET @TempToDate = @MaxOldDate
		ELSE
			SET @TempToDate = @TDate

		INSERT INTO #SAgWinLoss
		SELECT b.winlostdate
			,b.srecommend
			,b.currency
			,b.sporttype
			,SUM(b.turnover * CASE 
					WHEN @drawfilter IN (1, 2)
						THEN CASE 
								WHEN b.statusID = 111
									THEN 0
								WHEN b.statusID IN (114, 115)
									THEN 0.5
								ELSE 1
								END
					ELSE 1
					END)
			,SUM(b.winlost)
			,- SUM(b.winlost) AS LicenseeWL
			--,- SUM(b.awinlost + b.winlost + b.comm) AS Company
			,- SUM((b.winlost * ag.Rate) + b.comm) as Company
			,SUM(b.betcount) * CASE 
				WHEN @drawfilter = 1
					THEN CASE 
							WHEN b.statusID = 111
								THEN 0
							ELSE 1
							END
				ELSE 1
				END
			,SUM(playercomm) AS Playercomm
		FROM bodb_Licensee.dbo.rptLicWinloss_old b WITH (NOLOCK)
			 INNER JOIN @tmpAg ag ON b.recommend = ag.CustID 
		WHERE b.Winlostdate BETWEEN @FDate AND @TempToDate
			AND b.sporttype = 0 --just only sportsbook
			AND b.roleid = 2
			/*AND b.Recommend IN (
				SELECT custid
				FROM @tmpAg
				)*/
			AND b.statusID <> 101
			AND ISNULL(b.isBA, 0) = 0
		GROUP BY b.winlostdate
			,b.srecommend
			,b.currency
			,b.sporttype
			,b.statusID
	END

	CREATE NONCLUSTERED INDEX IDX_Index_SA ON #SAgWinLoss (Currency)

	IF @excludeTest = 1
	BEGIN
		DELETE
		FROM #SAgWinLoss
		WHERE Currency = 20
	END

	-- Exchange by Date
	DECLARE @ExDate SMALLDATETIME

	SELECT @ExDate = CONVERT(VARCHAR(10), CASE 
				WHEN DATEDIFF(month, @TDate, GETDATE()) <= 0
					THEN GETDATE()
				ELSE DATEADD(day, - 1, DATEADD(month, 1, '01 ' + SUBSTRING(CONVERT(VARCHAR(11), @TDate, 106), 4, 8)))
				END, 120)

	SELECT *
	INTO #Exchange1
	FROM Lrf_f_GetExchangeDaily(@ExDate, @ExDate) -- get exchange rate in last day of month
	WHERE exchangeid IN (
			SELECT DISTINCT Currency
			FROM #SAgWinLoss
			)

	SELECT *
	INTO #Exchange
	FROM Lrf_f_GetExchangeDaily(@FromDate, @ToDate)
	WHERE exchangeid IN (
			SELECT DISTINCT Currency
			FROM #SAgWinLoss
			)

	--return the result 	
	BEGIN
		SELECT CASE 
				WHEN @ReportType = 1
					THEN CONVERT(VARCHAR(8), w.winlostdate, 112)
				WHEN @ReportType = 2
					THEN CONVERT(VARCHAR(6), w.winlostdate, 112)
				ELSE '0'
				END ReportType
			,Currency
			,CASE 
				WHEN w.Currency = 51
					THEN @VNDCurrencyName
				WHEN w.Currency = 20
					THEN 'UUS'
				ELSE e.Code
				END currencyName
			,ISNULL(e1.EUR, 0) AS EURExRate
			,ISNULL(e1.USD, 0) AS USDExRate
			,ISNULL(e1.MYR, 0) AS MYRExRate
			,SUM(TurnOver) AS Turnover
			,SUM(Winlost) AS Winlost
			,SUM(LicenseeWL) AS LicenseeWL
			,SUM(Company) AS Company
			,SUM(Betcount) AS Betcount
			,sum(Playercomm) AS Playercomm
			,
			-- BaseRM    
			SUM(TurnOver * e.MYR) AS TurnoverMYR
			,SUM(Winlost * e.MYR) AS WinlostMYR
			,SUM(LicenseeWL * e.MYR) AS LicenseeWLMYR
			,SUM(Company * e.MYR) AS CompanyMYR
			,sum(Playercomm * e.MYR) AS PlayercommMYR
			,
			-- BaseUSD    
			SUM(TurnOver * e.USD) AS TurnoverUSD
			,SUM(Winlost * e.USD) AS WinlostUSD
			,SUM(LicenseeWL * e.USD) AS LicenseeWLUSD
			,SUM(Company * e.USD) AS CompanyUSD
			,sum(Playercomm * e.USD) AS PlayercommUSD
			,
			-- BaseEUR    
			SUM(TurnOver * e.EUR) AS TurnoverEUR
			,SUM(Winlost * e.EUR) AS WinlostEUR
			,SUM(LicenseeWL * e.EUR) AS LicenseeWLEUR
			,SUM(Company * e.EUR) AS CompanyEUR
			,sum(Playercomm * e.EUR) AS PlayercommEUR
		FROM #SAgWinLoss w
		INNER JOIN #Exchange e ON w.currency = e.ExchangeId
			AND w.winlostdate = e.ExchangeDate
		LEFT JOIN #Exchange1 e1 ON w.currency = e1.ExchangeId
		GROUP BY Currency
			,CASE 
				WHEN @ReportType = 1
					THEN CONVERT(VARCHAR(8), w.winlostdate, 112)
				WHEN @ReportType = 2
					THEN CONVERT(VARCHAR(6), w.winlostdate, 112)
				ELSE '0'
				END
			,CASE 
				WHEN w.Currency = 51
					THEN @VNDCurrencyName
				WHEN w.Currency = 20
					THEN 'UUS'
				ELSE e.Code
				END
			,ISNULL(e1.EUR, 0)
			,ISNULL(e1.USD, 0)
			,ISNULL(e1.MYR, 0)
		ORDER BY ReportType
	END

	DROP TABLE #SAgWinLoss
	DROP TABLE #Exchange
	DROP TABLE #Exchange1
END
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Report_LicenseeWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[OAS_Report_LicenseeWinloss] TO bodbAdminNet 