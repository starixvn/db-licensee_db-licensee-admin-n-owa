USE [bodb02]
GO
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[OAS_Rpt_AGCasinoWinloss] 
	 @PartyIDs 		VARCHAR(1000)
	,@Currency 		INT 			= 0
	,@FromDate 		SMALLDATETIME
	,@ToDate 			SMALLDATETIME
	,@drawfilter 		SMALLINT 		= 1
AS
/*  
    Created: Florent.Nguyen
    Date: 2014-09-24
    Task : AG Win Loss report 
    DB: DBACC.bodb02  
    Revisions:  
		- 20141031@Florent: Apply new Structure Using SystemMapping
	Param's Explanation:  
*/
/*
OAS_Rpt_AGCasinoWinloss_xtest @PartyIDs = '15,16,17,18'
	,@FromDate = '08-01-2014'
	,@ToDate = '09-30-2014'
	,@drawfilter = 3

*/
SET NOCOUNT ON

BEGIN
	CREATE TABLE #tmpResult (
		PartyID INT
		,PartyName NVARCHAR(100)
		,Winlostdate DATETIME
		,Currency INT
		,TurnOver MONEY
		,TotalTrans INT
		,Winlost MONEY
		,LicenseeWinlost MONEY
		)

	CREATE TABLE #tmpAg (
		CustId INT
		,Currency INT
		,PartyID INT
		,PartyName NVARCHAR(100)
		,FromDate DATETIME
		,Todate DATETIME
		)

	DECLARE @VNDCurrencyName VARCHAR(20)

	SELECT @VNDCurrencyName = currency
	FROM dbo.Exchange WITH (NOLOCK)
	WHERE ExchangeId = 51

	DECLARE @sql VARCHAR(8000)

	SET @sql = 'SELECT CustID,Currency,PartyID,PartyName,FromDate,ToDate
			 FROM OPENQUERY( DBLIC,''SELECT CustID,Currency,p.PartyID,p.PartyName,
								CASE WHEN ''''' + CONVERT(VARCHAR(10), @Fromdate, 120) + ''''' <= ci.FromDate THEN ci.FromDate ELSE ''''' + CONVERT(VARCHAR(10), @Fromdate, 120) + ''''' END AS FromDate,
								CASE WHEN ''''' + CONVERT(VARCHAR(10), @ToDate, 120) + '''''  >= ci.ToDate THEN ci.ToDate ELSE ''''' + CONVERT(VARCHAR(10), @ToDate, 120) + '''''  END AS ToDate
								FROM bodb_Licensee.dbo.LicenseeCust lc WITH (NOLOCK)
								    INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK) ON lc.LicenseeID = p.OldRefID AND p.PartyType = 1	
								    INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON ci.FromParty = p.PartyID
								    INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 4
				    WHERE Currency <> 20 AND p.PartyID IN (' + @PartyIDs + 
		') AND ci.ChargeType = 1 AND ci.ProductID = 10
						AND ( ''''' + CONVERT(VARCHAR(10), @Fromdate, 120) + ''''' BETWEEN ci.FromDate AND ci.ToDate OR ''''' + CONVERT(VARCHAR(10), @ToDate, 120) + ''''' BETWEEN ci.FromDate AND ci.ToDate)
						AND (' + CAST(@Currency AS VARCHAR) + ' = 0 OR lc.Currency = ' + CAST(@Currency AS VARCHAR) + ')''
				    )'

	INSERT INTO #tmpAg (
		CustID
		,Currency
		,PartyID
		,PartyName
		,FromDate
		,Todate
		)
	EXECUTE (@sql)

	--select @sql
	INSERT INTO #tmpResult (
		PartyID
		,PartyName
		,Winlostdate
		,Currency
		,TurnOver
		,TotalTrans
		,Winlost
		,LicenseeWinlost
		)
	SELECT ag.PartyID
		,ag.PartyName
		,c.Winlostdate
		,co.Currency
		,SUM(c.TurnOver - CASE 
				WHEN @drawfilter IN (1, 2)
					THEN c.DrawTO
				ELSE 0
				END) AS TurnOver
		,SUM(c.BetCount - CASE 
				WHEN @drawfilter = 1
					THEN c.DrawBetCount
				ELSE 0
				END) AS TotalTrans
		,SUM(c.Winlost) AS Winlost
		,- SUM(c.Winlost) AS LicenseeWinlost
	FROM bodb_report.dbo.rptDepWinlost_AGCasino c WITH (NOLOCK)
	INNER JOIN dbo.Custinfo co WITH (NOLOCK) ON c.CustID = co.CustID
	INNER JOIN #tmpAg ag ON co.recommend = ag.CustID
	WHERE c.Winlostdate BETWEEN ag.FromDate AND ag.Todate
	GROUP BY c.Winlostdate
		,co.Currency
		,ag.PartyID
		,ag.PartyName

	SELECT ExchangeDate
		,ExchangeId
		,Code
		,USD
		,EUR
		,CNY
	INTO #TempExchange
	FROM Lrf_f_GetExchangeDaily(@FromDate, @ToDate)
	WHERE exchangeid IN (
			SELECT DISTINCT Currency
			FROM #tmpResult
			)

	DECLARE @ParentID INT
		,@Maxfee INT

	SELECT ci.ChargeID
		,ci.Rate
		,ci.FromParty
		,ci.ToParty
		,ci.FromDate
		,ci.ToDate
		,ci.MinAmount
		,ci.MaxAmount
	INTO #ChargeInfo
	FROM DBLIC.bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK)
	INNER JOIN DBLIC.bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID
		AND cs.SystemID = 4
	WHERE ProductID = 10
		AND ChargeType = 1

	--get AG revenue
	SELECT @Maxfee = Max(MaxAmount)
	FROM #ChargeInfo
	WHERE FromParty = 1

	SELECT @ParentID = OW.ChargeID
	FROM (
		SELECT CASE 
				WHEN sum(r.LicenseeWinlost * e.CNY) < 0
					THEN 0
				ELSE sum(r.LicenseeWinlost * e.CNY)
				END AS total
		FROM #tmpResult r
		INNER JOIN #TempExchange e ON r.Winlostdate = e.ExchangeDate
			AND r.currency = e.ExchangeId
		) t1
	LEFT JOIN #ChargeInfo OW ON OW.FromParty = 1 --OW
		AND CASE 
			WHEN t1.total > @Maxfee
				THEN @Maxfee + 1
			ELSE t1.total
			END BETWEEN ISNULL(OW.MinAmount, 0) AND ISNULL(OW.MaxAmount, @Maxfee + 1)

	SELECT @ParentID = ISNULL(@ParentID, - 1)

	SELECT r.PartyID
		,r.PartyName
		,CONVERT(VARCHAR(6), winlostdate, 112) AS Winlostdate
		,r.Currency
		,e.EUR AS EUR
		--,@AGRevenue AS amtDueToAG
		,CASE 
			WHEN Currency = 51
				THEN @VNDCurrencyName
			ELSE e.Code
			END CurrencyName
		,SUM(r.TotalTrans) AS BetCount
		,SUM(r.TurnOver) AS TurnOver
		,SUM(r.LicenseeWinlost) AS LicenseeWinlost
		,SUM(r.LicenseeWinlost * ISNULL(DI.Rate, 0)) AS amtDueToOW
		,SUM(r.LicenseeWinlost * ISNULL(OW.Rate, 0)) AS amtDueToAG
		---USD
		,SUM(r.TurnOver * e.USD) AS TurnOverUSD
		,SUM(r.LicenseeWinlost * e.USD) AS LicenseeWinlostUSD
		,SUM(r.LicenseeWinlost * ISNULL(DI.Rate, 0) * e.USD) AS amtDueToOWUSD
		,SUM(r.LicenseeWinlost * ISNULL(OW.Rate, 0) * e.USD) AS amtDueToAGUSD
		---EUR
		,SUM(r.TurnOver * e.EUR) AS TurnOverEUR
		,SUM(r.LicenseeWinlost * e.EUR) AS LicenseeWinlostEUR
		,SUM(r.LicenseeWinlost * ISNULL(DI.Rate, 0) * e.EUR) AS amtDueToOWEUR
		,SUM(r.LicenseeWinlost * ISNULL(OW.Rate, 0) * e.EUR) AS amtDueToAGEUR
	FROM #tmpResult r
	INNER JOIN #TempExchange e ON r.Winlostdate = e.ExchangeDate
		AND r.currency = e.ExchangeId
	LEFT JOIN #ChargeInfo DI ON r.PartyID = DI.FromParty
		AND r.winlostdate BETWEEN DI.FromDate AND DI.ToDate
	LEFT JOIN #ChargeInfo OW ON OW.ChargeID = @ParentID
	GROUP BY r.PartyID
		,r.PartyName
		,CONVERT(VARCHAR(6), winlostdate, 112)
		,r.Currency
		,e.EUR
		,CASE 
			WHEN Currency = 51
				THEN @VNDCurrencyName
			ELSE e.Code
			END

	---------
	DROP TABLE #tmpResult
	DROP TABLE #tmpAg
	DROP TABLE #TempExchange
	DROP TABLE #ChargeInfo
END
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Rpt_AGCasinoWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[OAS_Rpt_AGCasinoWinloss] TO bodbAdminNet 