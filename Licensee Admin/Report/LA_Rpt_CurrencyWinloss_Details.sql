/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet,bodbLicenseeNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE [dbo].[LA_Rpt_CurrencyWinloss_Details]
	@PartyIDs			VARCHAR(5500)	= ''
	, @Currency			INT				= 0
	, @FromDate			SMALLDATETIME
	, @ToDate			SMALLDATETIME
	, @ProductCodes		VARCHAR(1000)	= 'SB'
	, @SportType		INT				= 0
	, @Bettype			INT				= 0
	, @ReportBy			TINYINT			= 0
	, @drawfilter		SMALLINT		= 1
	, @excludeTest		BIT				= 0
AS
/*  Created: Florent.Nguyen
	Date: 2014-09-04
	Task : Licensee Currency Winlost Report
	DB: DB052.bodb02  

	Revisions:
	   - 20141021@Florent: show credit's licensee
	   - 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
	   - 20150703@Florent: add GBP
	   - 20160505@Bruce: Remove dynamic sql
	   - 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
	   - 20170801@Kenny: Filter data for Microgaming [RedmineID: #79311]
	   - 20180130@Bruce: integrate Exchange product [#87754]
	   - 20180515@Scofield: Incorporate 9wickets data [#94950]

	Param's Explanation:
	  + @ReportType: 1-Live; 2-Non-Live; 0: All;
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @ProductList TABLE (ProductCode VARCHAR(20))

	INSERT INTO @ProductList
	SELECT Val FROM dbo.strSplit(@ProductCodes, ',')

	CREATE TABLE #tmpWinLoss (
		Winlostdate		DATETIME,
		PartyID			INT,
		ProductID		INT,
		Currency		INT,
		TurnOver		MONEY,
		Winlost			MONEY,
		LicenseeWL		MONEY,
		WinlossRB		MONEY,
		AmtDueToBA		MONEY,
		AmtDueToRB		MONEY,
		CommBA			MONEY,
		CommRB			MONEY,
		Company			MONEY,
		Betcount		BIGINT,
		Playercomm		MONEY
	)

	CREATE INDEX IX_tmpWinloss ON #tmpWinLoss(PartyID, Winlostdate, Currency)

	CREATE TABLE #Data (
		rptDate			DATETIME
		,SiteID			INT
		,PartyID		INT
		,ProductID		INT
		,Bettype		INT
		,[Status]		SMALLINT
		,CurrencyID		INT
		,TurnOver		MONEY
		,Winloss		MONEY
		,WinlossA		MONEY
		,CommissionA	MONEY
		,CommissionP	MONEY
		,Betcount		BIGINT
	)

	CREATE TABLE #tmpParty (
		PartyID			INT
		,LicenseeID		INT
		,isDeposit		INT
		,AffectedDate	SMALLDATETIME
		,ProductID		INT
		,Rate			MONEY
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
		,Bettype		INT
	)

	INSERT INTO #tmpParty (PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, Rate, Fromdate, Todate, Bettype)
	(
		SELECT DISTINCT PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, DI_Rate, Fromdate, Todate,
						CASE WHEN ci.ProductId IN (14,17) THEN ISNULL(sbr.Bettype, ci.Bettype) ELSE -1 END
		FROM		bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', @ExcludeTest) ci
		LEFT JOIN   bodb_licensee..Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype AND (
					(ci.ProductId NOT IN (14,17)) OR 
					(ci.ProductID = 14 AND sbr.Bettype BETWEEN 2001 AND 2007) OR
					(ci.ProductID = 17 AND sbr.Bettype BETWEEN 2008 AND 2009))
	)

	CREATE TABLE #Bettype (Bettype INT, ProductID INT)

	INSERT INTO #Bettype(Bettype,ProductID)
	SELECT Bettype,ProductID
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(@Bettype, @ProductCodes)

	IF EXISTS (SELECT 1 FROM @ProductList WHERE ProductCode='BA')
	BEGIN
		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, ProductID, Currency, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company,Betcount, Playercomm)
		(
			SELECT	b.rptDate,
					tp.PartyID,
					tp.ProductID,
					b.currencyID,
					SUM(b.Turnover) * (CASE	WHEN @drawfilter IN (2, 3) AND b.[Status] = 111			THEN 0
											WHEN @drawfilter IN (2, 3) AND b.[Status] IN (114,115)	THEN 0.5
											ELSE 1 END),
					SUM(b.winloss),
					0 as LicenseeWL,
					0 AS WinlossRB,
					- SUM((b.winloss * tp.Rate )+ b.CommissionA),
					0 as AmountDueToRB,
					SUM (CommissionA),
					0 as CommRB,
					0 as Company,
					SUM(b.BetCount) * (CASE	WHEN @drawfilter = 2 AND b.[Status] = 111 THEN 0 ELSE 1 END),
					SUM(b.CommissionP)
			FROM bodb_licenseereport.dbo.rpt_Betting_BA b WITH ( NOLOCK )
				INNER JOIN #tmpParty tp ON b.siteid = tp.LicenseeID AND tp.ProductID = 3
				INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype AND tp.ProductID = bt.ProductID
				LEFT JOIN dbo.League l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
			WHERE	(b.rptDate BETWEEN tp.Fromdate AND tp.ToDate) AND
					 b.[Status] NOT IN (-1, 101, 102, 103) AND
					(@Currency = 0 OR @Currency = b.CurrencyID) AND
					(@excludeTest = 0 OR b.CurrencyID<>20) AND
					(@SportType = 0 OR (b.bettype NOT IN (9,29) AND l.Sporttype = @SportType)) AND
					((@ReportBy = 0) OR
					 (@ReportBy = 1 AND b.IsLive=1 AND b.bettype NOT IN (9,29,10)) OR
					 (@ReportBy = 2 AND b.IsLive=0))
			GROUP BY b.rptDate, tp.PartyID, tp.ProductID, b.currencyID, b.[Status]
		)
	END

	IF EXISTS (SELECT 1 FROM @ProductList WHERE ProductCode IN ('AGC','GD','VG','BX'))
	BEGIN
		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, ProductID, Currency, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount, Playercomm)
		(
			SELECT b.rptDate,p.PartyID,p.ProductID,b.CurrencyId
					,SUM(b.Turnover * 
						(CASE WHEN b.Bettype=33 AND b.[StatusId] IN (114,115) THEN 0.5 ELSE 1 END) *
						(CASE WHEN @drawfilter IN (2, 3) AND b.[StatusId] = 111  THEN 0
							  WHEN @drawfilter IN (2, 3) AND b.[StatusId] IN (114,115) THEN 0.5
							  ELSE 1 END))
					,SUM(b.MemberWL + CASE WHEN b.ProductID=31 THEN b.CommissionP ELSE 0 END)
					,SUM(-b.MemberWL - CASE WHEN b.ProductID=31 THEN b.CommissionP ELSE 0 END)
					,0 AS WinlossRB
					,0 AS AmtDueToBA
					,0 AS AmtDueToRB
					,0 AS CommBA
					,0 AS CommRB
					,SUM(-b.MemberWL * p.Rate - CASE WHEN b.ProductID=31 THEN (b.CommissionA + b.CommissionP) ELSE 0 END) AS Company
					,SUM(b.Betcount) * (CASE WHEN @drawfilter = 2 AND b.[StatusId] = 111 THEN 0 ELSE 1 END)
					,SUM(b.commissionP)
			FROM bodb_licenseereport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #tmpParty p ON b.SiteID = p.LicenseeID AND p.ProductID=b.ProductID AND b.rptDate BETWEEN p.Fromdate AND p.Todate
			WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate) AND
					 b.StatusId NOT IN (-1, 101, 102, 103) AND
					(@Currency = 0 OR @Currency = b.CurrencyID) AND
					(@excludeTest = 0 OR b.CurrencyID<>20) AND
					@SportType = 0 AND
					@ReportBy = 0 AND
					@Bettype = 0 AND
					b.CustomerCategory NOT IN (27,28) AND
					p.ProductID IN (10,11,12,31)
			GROUP BY b.rptDate
					,p.PartyID
					,p.ProductID
					,b.[StatusId]
					,b.CurrencyID
		)
	END

	IF EXISTS (SELECT TOP 1 1 FROM @ProductList WHERE ProductCode IN ('MGCLC','MGCRNG'))
	BEGIN
		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, ProductID, Currency, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company, Betcount, Playercomm)
		(
			SELECT b.RptDate, p.PartyId, p.ProductID, b.CurrencyID
				, SUM(b.Turnover) * (CASE	WHEN @drawfilter IN (2, 3) AND b.[Status] = 111			THEN 0
											WHEN @drawfilter IN (2, 3) AND b.[Status] IN (114,115)	THEN 0.5
											ELSE 1 END)
				, SUM(b.WinLoss) Winloss
				, -SUM(b.WinLoss) AS LicenseeWL
				, 0 AS WinlossRB
				, 0 AS AmtDueToBA
				, 0 AS AmtDueToRB
				, 0 AS CommBA
				, 0 AS CommRB
				, -SUM(b.WinLoss* p.Rate) AS Company
				, SUM(b.BetCount) * (CASE WHEN @drawfilter = 2 AND b.[Status] = 111 THEN 0 ELSE 1 END)
				, 0 as Playercomm
			FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
			INNER JOIN #tmpParty p ON p.LicenseeId=b.SiteId AND p.Bettype=b.Bettype AND b.RptDate BETWEEN p.FromDate AND p.ToDate
			LEFT JOIN dbo.League l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
			WHERE b.RptDate BETWEEN p.FromDate AND p.ToDate
				AND (@excludeTest = 0 OR b.CurrencyID<>20)
				AND b.Status NOT IN (-1, 101, 102, 103)
				AND (@Currency = 0 OR @Currency = b.CurrencyID)
				AND (@SportType = 0 OR l.Sporttype = @SportType)
				AND (@Bettype = 0 OR b.bettype = @Bettype)
				AND p.ProductId IN (14,17)
			GROUP BY p.PartyId, b.rptDate, b.CurrencyID, p.ProductID,b.[Status]
		)
	END

	IF EXISTS (SELECT TOP 1 1 FROM @ProductList WHERE ProductCode NOT IN ('BA','MGCLC','MGCRNG','AGC','GD','VG','BX'))
	BEGIN
		--exclude BA rpt_Betting
		SELECT DISTINCT p.PartyID, p.LicenseeID, p.ProductID, bt.Bettype
		INTO #PartyBettypeMapping
		FROM #tmpParty p
		INNER JOIN #Bettype bt ON p.ProductID = bt.ProductID
		WHERE p.ProductID NOT IN (3,14,17,10,11,12,31)
		
		DELETE #Data
		
		INSERT INTO #Data(rptDate, SiteID, PartyID, ProductID, Bettype, [Status], CurrencyID, TurnOver, Winloss, WinlossA, CommissionA, CommissionP, Betcount)
		(
			SELECT	b.rptDate
					,b.SiteID
					,t.PartyID
					,t.ProductID
					,b.Bettype
					,b.[Status]
					,b.CurrencyID
					,SUM(b.Turnover)
					,SUM(b.WinLoss)
					,SUM(b.WinLossA)
					,SUM(b.CommissionA)
					,SUM(b.CommissionP)
					,SUM(b.BetCount)
			FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
			INNER JOIN #PartyBettypeMapping t ON b.Bettype = t.Bettype AND b.SiteID = t.LicenseeID
			LEFT JOIN dbo.League l WITH(NOLOCK) ON b.LeagueID = l.leagueid
			WHERE	(b.rptDate BETWEEN @Fromdate AND @ToDate) AND
					 b.[Status] NOT IN (-1, 101, 102, 103) AND
					(@Currency = 0 OR @Currency = b.CurrencyID) AND
					(@excludeTest = 0 OR b.CurrencyID<>20) AND
					(@SportType = 0 OR (b.bettype NOT IN (9,29) AND (b.bettype NOT BETWEEN 31 AND 120) AND l.Sporttype = @Sporttype)) AND
					((@ReportBy = 0) OR
					 (@ReportBy = 1 AND b.IsLive=1 AND b.bettype NOT IN (9,29,10,31,32,33)) OR
					 (@ReportBy = 2 AND b.IsLive=0)) AND
					b.CustomerCategory NOT IN (27,28)
			GROUP BY b.rptDate
					,b.SiteID
					,t.PartyID
					,t.ProductID
					,b.Bettype
					,b.[Status]
					,b.CurrencyID
		)

		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, ProductID, Currency, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA, AmtDueToRB, CommBA, CommRB, Company,Betcount, Playercomm)
		(
			SELECT	b.rptDate,
					tp.PartyID,
					tp.ProductID,
					b.CurrencyID,
					SUM(b.Turnover * 
						(CASE WHEN b.Bettype=33 AND b.[Status] IN (114,115) THEN 0.5 ELSE 1 END) *
						(CASE WHEN @drawfilter IN (2, 3) AND b.[Status] = 111  THEN 0
								WHEN @drawfilter IN (2, 3) AND b.[Status] IN (114,115) AND b.bettype <> 33 THEN 0.5
								ELSE 1 END)),
					SUM(b.winloss),
					-SUM(CASE WHEN b.bettype NOT IN (31,32, 33) THEN b.winloss ELSE 0 END) AS LicenseeWL,
					SUM(CASE WHEN b.bettype IN (31,32, 33) THEN b.WinlossA ELSE 0 END) AS WinlossRB,
					0 as AmountDueToBA,
					- SUM (CASE WHEN b.bettype IN (31,32, 33) THEN (b.winloss + b.winlossA + b.CommissionA) ELSE 0 END) AS AmountDueToRB,
					0 as CommBA,
					SUM ( CASE WHEN b.bettype IN (31,32, 33) THEN CommissionA ELSE 0 END) as CommRB,
					-SUM(CASE WHEN b.bettype NOT IN (31,32, 33) THEN (b.winloss * tp.Rate) ELSE 0 END) AS Company,
					SUM(b.Betcount) * (CASE WHEN @drawfilter = 2 AND b.[Status] = 111 THEN 0 ELSE 1 END),
					SUM(b.CommissionP)
			FROM #Data b WITH (NOLOCK)
			INNER JOIN #tmpParty tp ON b.SiteID = tp.LicenseeID AND tp.ProductID NOT IN (3,14,17,10,11,12) AND b.ProductID = tp.ProductID
			WHERE b.rptDate BETWEEN tp.FromDate AND tp.Todate
			GROUP BY  b.rptDate, tp.ProductID, tp.PartyID, b.currencyID, b.[Status]
		)

		DROP TABLE #PartyBettypeMapping
	END

	SELECT DISTINCT ExchangeDate, ExchangeId, Code, USD, EUR, MYR, GBP
	INTO #TempExchange
	FROM Lrf_f_GetExchangeDaily(@FromDate, @ToDate)
	
	SELECT	w.PartyID,
			CASE WHEN p.PartyName ='18bb' THEN 'PIH'
				WHEN p.PartyName ='IBC' THEN 'FDL'
				ELSE p.PartyName
			END AS PartyName,
			CASE WHEN Currency = 51 THEN 'INH' 
				WHEN Currency = 75 THEN 'PTU'
				WHEN Currency = 76 THEN 'PS'
				WHEN Currency = 77 THEN 'PTH'
				ELSE e.Code END currencyName,
			SUM(TurnOver) AS Turnover,
			SUM(Winlost) AS Winlost,
			SUM(LicenseeWL) AS LicenseeWL,
			SUM(WinlossRB) AS WinlossRB,
			SUM(CommBA) AS CommBA,
			SUM(CommRB) AS CommRB,
			SUM(AmtDuetoBA) AS AmtDuetoBA,
			SUM(AmtDuetoRB) AS AmtDuetoRB,
			SUM(Company) AS Company,
			SUM(Betcount) AS Betcount,
			SUM(Playercomm) AS Playercomm,
			SUM(TurnOver * e.MYR) AS TurnoverMYR,
			SUM(Winlost * e.MYR) AS WinlostMYR,
			SUM(LicenseeWL * e.MYR) AS LicenseeWLMYR,
			SUM(WinlossRB * e.MYR) AS WinlossRBMYR,
			SUM(CommBA * e.MYR) AS CommBAMYR,
			SUM(CommRB * e.MYR) AS CommRBMYR,
			SUM(AmtDuetoBA*e.MYR) AS AmtDuetoBAMYR,
			SUM(AmtDuetoRB*e.MYR) AS AmtDuetoRBMYR,
			SUM(Company * e.MYR) AS CompanyMYR,
			SUM(Playercomm * e.MYR) AS PlayercommMYR,
			SUM(TurnOver * e.USD) AS TurnoverUSD,
			SUM(Winlost * e.USD) AS WinlostUSD,
			SUM(LicenseeWL * e.USD) AS LicenseeWLUSD,
			SUM(WinlossRB * e.USD) AS WinlossRBUSD,
			SUM(CommBA * e.USD) AS CommBAUSD,
			SUM(CommRB * e.USD) AS CommRBUSD,
			SUM(AmtDuetoBA * e.USD) AS AmtDuetoBAUSD,
			SUM(AmtDuetoRB * e.USD) AS AmtDuetoRBUSD,
			SUM(Company * e.USD) AS CompanyUSD,
			SUM(Playercomm * e.USD) AS PlayercommUSD,
			SUM(TurnOver * e.EUR) AS TurnoverEUR,
			SUM(Winlost * e.EUR) AS WinlostEUR,
			SUM(LicenseeWL * e.EUR) AS LicenseeWLEUR,
			SUM(WinlossRB * e.EUR) AS WinlossRBEUR,
			SUM(CommBA * e.EUR) AS CommBAEUR,
			SUM(CommRB * e.EUR) AS CommRBEUR,
			SUM(AmtDuetoBA*e.EUR) AS AmtDuetoBAEUR,
			SUM(AmtDuetoRB*e.EUR) AS AmtDuetoRBEUR,
			SUM(Company * e.EUR) AS CompanyEUR,
			SUM(Playercomm * e.EUR) AS PlayercommEUR,
			SUM(TurnOver * e.GBP) AS TurnoverGBP,
			SUM(Winlost * e.GBP) AS WinlostGBP,
			SUM(LicenseeWL * e.GBP) AS LicenseeWLGBP,
			SUM(WinlossRB * e.GBP) AS WinlossRBGBP,
			SUM(CommBA * e.GBP) AS CommBAGBP,
			SUM(CommRB * e.GBP) AS CommRBGBP,
			SUM(AmtDuetoBA * e.GBP) AS AmtDuetoBAGBP,
			SUM(AmtDuetoRB * e.GBP) AS AmtDuetoRBGBP,
			SUM(Company * e.GBP) AS CompanyGBP,
			SUM(Playercomm * e.GBP) AS PlayercommGBP
	FROM #tmpWinLoss w
		INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID = w.PartyID
		INNER JOIN #TempExchange e ON w.Winlostdate = e.ExchangeDate AND w.currency = e.ExchangeId
	GROUP BY w.PartyID, p.PartyName, 
		CASE WHEN Currency = 51 THEN 'INH' 
			WHEN Currency = 75 THEN 'PTU'
			WHEN Currency = 76 THEN 'PS'
			WHEN Currency = 77 THEN 'PTH'
			ELSE e.Code END
	ORDER BY w.PartyID, p.PartyName

	DROP TABLE #tmpWinLoss
	DROP TABLE #Bettype
	DROP TABLE #tmpParty
	DROP TABLE #Data
	DROP TABLE #TempExchange
END
GO

