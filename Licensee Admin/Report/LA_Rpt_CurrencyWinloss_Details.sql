/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet,bodbLicenseeNet" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[LA_Rpt_CurrencyWinloss_Details]
	@PartyIDs			VARCHAR(MAX)	= ''
	, @CurrencyIds		VARCHAR(MAX)	= ''
	, @FromDate			DATETIME
	, @ToDate			DATETIME
	, @ProductCodes		VARCHAR(MAX)	= 'SB'
	, @SportType		INT				= 0
	, @Bettype			INT				= 0
	, @ReportBy			TINYINT			= 0
	, @drawfilter		SMALLINT		= 1
AS
/*  Created: Florent.Nguyen
	Date: 2014-09-04
	Task: Licensee Currency Winlost Report
	DB: DBEXT-bodb02

	Revisions:
	   - 20141021@Florent: show credit's licensee
	   - 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
	   - 20150703@Florent: add GBP
	   - 20160505@Bruce: Remove dynamic sql
	   - 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
	   - 20170801@Kenny: Filter data for Microgaming [RedmineID: #79311]
	   - 20180130@Bruce: integrate Exchange product [#87754]
	   - 20180515@Scofield: Incorporate 9wickets data [#94950]
	   - 20180716@bruce: add new group TEST for credit [#98126]
	   - 20180703@Parsons: Integrate Pragmatic Win Loss [#94108]
	   - 20180815@Scofield: Remove "Exclude Test Data" checkbox [#98623]
	   - 20180907@Bruce: Support multiple currency [#101160]
	   - 20181119@bruce: Integrate Bidme games (GD product) [#103695]
	   - 20190322@Parsons: Integrate-PP-Promotion-Prize [#109014]
	   - 20191205@Parsons: PP tournament [#123958]
	   - 20191225@Bruce: billing term by currency [#120005]
	   - 20200303@Mason: Suport HID currency [#128856]
	   - 20200409@Parsons: Integrate SA Gaming [#129276]
	   - 20200601@Parsons: Amend Currency WL report [#135055] 
	   - 20200824@Parsons: Implement PP JP Changes In Reports Phase 2 [#139055]
	   - 20201021@Happy: Arcadia Gaming offers Bonus [#143597]
	   - 20201111@Happy: Changing OddsSpread for licensee [#142345]
	   - 20201209@Mason: Saba.club - Offer Freebet tickets [#141423]
	   - 20210108@Mason: Saba.club - Integrate Slot Game [#147977]
	   - 20210712@Danny: Vgaming - Free bets and Jackpot prize integration [#156185]
	   - 20210812@Percy: Integrate Bitcoin - apply core function GroupProduct [RedmineID: #159691]
	   - 20210824@Percy: Enhance performance [RedmineID: #160672]

	Param's Explanation:
	  + @ReportType: 1-Live; 2-Non-Live; 0: All;
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @GD_Tip				SMALLINT = 1706,
			@PP_Contribution	SMALLINT = 4297,
			@SBC_Contribution	SMALLINT = 1698,
			@VGA_Contribution	SMALLINT = 3898,
			@OddSpread_BetType	SMALLINT = 999

	DECLARE @PP_ProductId	INT = 32,
			@SBC_ProductId	INT = 42,
			@VGA_ProductId	INT	= 66
	-- currency list
	--
	DECLARE @IsAllCurrency BIT = 0
	DECLARE @Currency TABLE(CurrencyId INT)

	-- all currency
	--
	SET @CurrencyIds = ISNULL(@CurrencyIds,'')
	IF @CurrencyIds = ''
		SET @IsAllCurrency = 1
	ELSE
		INSERT INTO @Currency SELECT val FROM dbo.strSplit(@CurrencyIds, ',')

	CREATE TABLE #Products (GroupProductId INT, ProductId INT, ProductName VARCHAR(50), ProductCode VARCHAR(20))

	INSERT INTO #Products (GroupProductId, ProductId, ProductCode, ProductName)
	SELECT 0, 0, 'SB', 'Sportsbook' WHERE ',' + @ProductCodes + ',' LIKE '%,SB,%'
	UNION ALL
	SELECT ISNULL(g.GroupProductId, p.ProductId), p.ProductId, p.ProductPrefix, p.ProductName
	FROM bodb_Licensee.dbo.Product3rd p WITH (NOLOCK)
		LEFT JOIN bodb_Licensee.dbo.LA_f_GroupProduct() g ON p.ProductId = g.ProductId
	WHERE ',' + @ProductCodes + ',' LIKE '%,' + p.ProductPrefix + ',%'

	INSERT INTO #Products (GroupProductId, ProductId, ProductCode, ProductName)
	SELECT g.GroupProductId, g.ProductId, p.ProductPrefix, p.ProductName
	FROM #Products pl
		INNER JOIN bodb_Licensee.dbo.LA_f_GroupProduct() g ON pl.ProductId = g.GroupProductId
		INNER JOIN bodb_Licensee.dbo.Product3rd p WITH (NOLOCK) ON g.ProductId = p.ProductId
		LEFT JOIN #Products t ON g.ProductId = t.ProductId
	WHERE t.ProductId IS NULL

	SET @ProductCodes = NULL
	SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM #Products

	CREATE TABLE #tmpWinLoss (
		Winlostdate		DATETIME,
		PartyID			INT,
		Currency		INT,
		TurnOver		MONEY,
		Winlost			MONEY,
		LicenseeWL		MONEY,
		AmtDueToBA		MONEY,
		CommBA			MONEY,
		Company			MONEY,
		Betcount		BIGINT,
		Playercomm		MONEY,
		OddsSpreadCost	MONEY
	)

	CREATE INDEX IX_tmpWinloss ON #tmpWinLoss(PartyID, Winlostdate, Currency)

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
		,ChargeType		SMALLINT
		,ChargeId		INT
	)

	INSERT INTO #tmpParty (PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, Rate, Fromdate, Todate, Bettype, ChargeType,ChargeId)
	(
		SELECT DISTINCT PartyID, LicenseeID, isDeposit, AffectedDate, ProductID, 
						CASE WHEN ISNULL(isDeposit, 0) = 1 THEN DI_Rate ELSE 0 END,
						Fromdate, Todate,
						CASE WHEN ci.ProductId IN (14,17) THEN ISNULL(sbr.Bettype, ci.Bettype) ELSE -1 END,
						CASE WHEN ci.ProductID IN(11,39) THEN ci.ChargeType ELSE 1 END,
						ci.ChargeID
		FROM		bodb_licensee.dbo.LA_f_ChargeInfo (@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
		LEFT JOIN   bodb_licensee.dbo.Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype AND (
					(ci.ProductId NOT IN (14,17)) OR 
					(ci.ProductID = 14 AND sbr.Bettype BETWEEN 2001 AND 2007) OR
					(ci.ProductID = 17 AND sbr.Bettype BETWEEN 2008 AND 2009))
	)
	CREATE INDEX IX_tmpParty ON #tmpParty(LicenseeID, ProductID)

	CREATE TABLE #Bettype (Bettype INT, ProductId INT, GroupProductId INT, PRIMARY KEY (Bettype, ProductId, GroupProductId))
	INSERT INTO #Bettype (Bettype, ProductId, GroupProductId)
	SELECT DISTINCT b.Bettype, b.ProductId, p.GroupProductId
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(@Bettype, @ProductCodes) b
		INNER JOIN #Products p ON b.ProductId = p.ProductId

	IF EXISTS (SELECT 1 FROM #Products WHERE ProductCode='BA')
	BEGIN
		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, Currency, TurnOver, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company,Betcount, Playercomm)
		(
			SELECT	b.rptDate,
					tp.PartyID,
					b.currencyID,
					SUM(b.Turnover * (CASE	WHEN @drawfilter IN (2, 3) AND b.[Status] = 111			THEN 0
											WHEN @drawfilter IN (2, 3) AND b.[Status] IN (114,115)	THEN 0.5
											ELSE 1 END)),
					SUM(b.winloss),
					0 as LicenseeWL,
					- SUM((b.winloss * tp.Rate )+ b.CommissionA),
					SUM (CommissionA),
					0 as Company,
					SUM(b.BetCount * (CASE	WHEN @drawfilter = 2 AND b.[Status] = 111 THEN 0 ELSE 1 END)),
					SUM(b.CommissionP)
			FROM bodb_licenseereport.dbo.rpt_Betting_BA b WITH ( NOLOCK )
				INNER JOIN #tmpParty tp ON b.siteid = tp.LicenseeID AND tp.ProductID = 3
				INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype AND tp.ProductID = bt.ProductID
				LEFT JOIN dbo.League l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
			WHERE	(b.rptDate BETWEEN tp.Fromdate AND tp.ToDate) AND
					 b.[Status] NOT IN (-1, 101, 102, 103) AND
					(@IsAllCurrency = 1 OR b.CurrencyID IN (SELECT c.CurrencyId FROM @Currency c)) AND
					(b.CurrencyID<>20) AND
					(@SportType = 0 OR (b.bettype NOT IN (9,29) AND l.Sporttype = @SportType)) AND
					((@ReportBy = 0) OR
					 (@ReportBy = 1 AND b.IsLive=1 AND b.bettype NOT IN (9,29,10)) OR
					 (@ReportBy = 2 AND b.IsLive=0))
			GROUP BY b.rptDate, tp.PartyID, b.currencyID
		)
	END

	IF (EXISTS (SELECT 1 FROM #Products WHERE ProductCode IN ('AGC','GD','VG','BX')) AND @SportType = 0 AND @ReportBy = 0 AND @Bettype = 0)
	BEGIN
		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, Currency, TurnOver, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company, Betcount, Playercomm)
		(
			SELECT b.rptDate,p.PartyID,b.CurrencyId
					,SUM(b.Turnover * 
									(CASE	WHEN @drawfilter IN (2, 3) AND b.[StatusId] = 111  THEN 0
											WHEN @drawfilter IN (2, 3) AND b.[StatusId] IN (114,115) THEN 0.5
											ELSE 1 
									 END))
					,SUM(b.MemberWL + CASE WHEN b.ProductID=31 THEN b.CommissionP ELSE 0 END)
					,SUM(-b.MemberWL - CASE WHEN b.ProductID=31 THEN b.CommissionP ELSE 0 END)
					,0 AS AmtDueToBA
					,0 AS CommBA
					,SUM(-b.MemberWL * ISNULL(cc.rate,p.Rate) - CASE WHEN b.ProductID=31 THEN (b.CommissionA + b.CommissionP) ELSE 0 END) AS Company
					,SUM(b.Betcount * (CASE WHEN @drawfilter = 2 AND b.[StatusId] = 111 THEN 0 ELSE 1 END))
					,SUM(b.commissionP)
			FROM bodb_licenseereport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #tmpParty p ON b.SiteID = p.LicenseeID AND p.ProductID=b.ProductID AND b.rptDate BETWEEN p.Fromdate AND p.Todate
			LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cc WITH (NOLOCK) ON cc.ChargeID = p.ChargeId AND b.CurrencyId=cc.CurrencyID
			WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate) AND
					 b.StatusId NOT IN (-1, 101, 102, 103) AND
					(@IsAllCurrency = 1 OR b.CurrencyID IN (SELECT c.CurrencyId FROM @Currency c)) AND
					(b.CurrencyID<>20) AND
					b.CustomerCategory NOT IN (27,28) AND
					p.ProductID IN (10,11,12,31) AND
					p.ChargeType = 1 AND -- gross win
					b.bettype <> @GD_Tip
			GROUP BY b.rptDate
					,p.PartyID
					,b.CurrencyID

			UNION ALL
			-- GD tip
			SELECT b.rptDate,p.PartyID,b.CurrencyId,0,0,0,0,0
					,SUM(-b.MemberWL * p.Rate) AS Company
					,0 AS Betcount
					,0 AS commissionP
			FROM bodb_licenseereport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #tmpParty p ON b.SiteID = p.LicenseeID AND p.ProductID=b.ProductID AND b.rptDate BETWEEN p.Fromdate AND p.Todate
			WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate) AND
					(@IsAllCurrency = 1 OR b.CurrencyID IN (SELECT c.CurrencyId FROM @Currency c)) AND
					(b.CurrencyID<>20) AND
					p.ProductID = 11 AND
					b.Bettype = @GD_Tip AND 
					p.ChargeType = 12 -- GD tip sharing
			GROUP BY b.rptDate
					,p.PartyID
					,b.CurrencyID
		)
	END

	IF EXISTS (SELECT TOP 1 1 FROM #Products WHERE ProductCode IN ('MGCLC','MGCRNG'))
	BEGIN
		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, Currency, TurnOver, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company, Betcount, Playercomm)
		(
			SELECT b.RptDate, p.PartyId, b.CurrencyID
				, SUM(b.Turnover * (CASE	WHEN @drawfilter IN (2, 3) AND b.[Status] = 111			THEN 0
											WHEN @drawfilter IN (2, 3) AND b.[Status] IN (114,115)	THEN 0.5
											ELSE 1 END))
				, SUM(b.WinLoss) Winloss
				, -SUM(b.WinLoss) AS LicenseeWL
				, 0 AS AmtDueToBA
				, 0 AS CommBA
				, -SUM(b.WinLoss* p.Rate) AS Company
				, SUM(b.BetCount * (CASE WHEN @drawfilter = 2 AND b.[Status] = 111 THEN 0 ELSE 1 END))
				, 0 as Playercomm
			FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
			INNER JOIN #tmpParty p ON p.LicenseeId=b.SiteId AND p.Bettype = b.Bettype
			LEFT JOIN dbo.League l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
			WHERE b.RptDate BETWEEN p.FromDate AND p.ToDate
				AND (b.CurrencyID<>20)
				AND b.Status NOT IN (-1, 101, 102, 103)
				AND (@IsAllCurrency = 1 OR b.CurrencyID IN (SELECT c.CurrencyId FROM @Currency c))
				AND (@SportType = 0 OR l.Sporttype = @SportType)
				AND (@Bettype = 0 OR b.bettype = @Bettype)
				AND p.ProductId IN (14,17)
			GROUP BY p.PartyId, b.rptDate, b.CurrencyID
		)
	END

	IF EXISTS (SELECT TOP 1 1 FROM #Products WHERE ProductCode NOT IN ('BA','MGCLC','MGCRNG','AGC','GD','VG','BX','RB'))
	BEGIN
		--exclude RB,BA,MGCLC, MGCRNG,AGC,GD,VG,BX
		DELETE #Bettype WHERE ProductID IN (1,3,14,17,10,11,12,31)
		DELETE #tmpParty WHERE ProductID IN (1,3,14,17,10,11,12,31)

		CREATE TABLE #Licensees (LicenseeId INT PRIMARY KEY)
		INSERT INTO #Licensees (LicenseeId)
		SELECT DISTINCT LicenseeId FROM #tmpParty

		DELETE bt
		FROM #Bettype bt
			INNER JOIN bodb_licensee.dbo.LA_f_ExcludedBettypeListSel('','999,4297,1698,3898') eb ON bt.Bettype = eb.BettypeId

		CREATE TABLE #tmpData (rptDate DATE, LicenseeId INT, CurrencyId INT, ProductId INT, LeagueId INT, Bettype INT
			,BetCount INT, Turnover MONEY, Winloss MONEY, WinlossA MONEY, CommissionP MONEY)

		IF @SportType = 0 AND @Bettype = 0 AND @ReportBy = 0
		BEGIN
			INSERT INTO #tmpData (rptDate, LicenseeId, CurrencyId, ProductId, BetCount, Turnover, Winloss, WinlossA, CommissionP)
			SELECT r.rptDate, r.SiteId, r.CurrencyId, r.ProductId
				,SUM(r.BetCount * CASE
									WHEN r.Bettype IN (999,4297,1698,3898) THEN 0
									WHEN @drawfilter = 2 AND r.StatusId = 111 THEN 0
									ELSE 1 END) AS BetCount
				,SUM(r.Turnover * CASE
									WHEN r.Bettype = 999 THEN 0
									WHEN @drawfilter IN (2, 3) AND r.StatusId = 111 THEN 0
									WHEN @drawfilter IN (2, 3) AND r.StatusId IN (114, 115) THEN 0.5
									ELSE 1 END) AS Turnover
				,SUM(r.MemberWL * CASE
									WHEN r.Bettype IN (999,4297,1698,3898) THEN 0
									ELSE 1 END) AS Winloss
				,SUM(CASE WHEN r.Bettype IN (999,4297,1698,3898) THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) WinlossA
				,SUM(CASE WHEN r.ProductId = 32 THEN 0 ELSE r.CommissionP END) AS CommissionP
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct r WITH (NOLOCK)
				LEFT JOIN bodb_licensee.dbo.LA_f_ExcludedBettypeListSel('','999,4297,1698,3898') b ON r.Bettype = b.BettypeId
			WHERE r.rptDate BETWEEN @FromDate AND @ToDate
				AND r.StatusId IN (111, 112, 113, 114, 115)
				AND r.CustomerCategory NOT IN (27, 28)
				AND r.CurrencyId <> 20
				AND EXISTS (SELECT 1 FROM #Licensees p WHERE r.SiteId = p.LicenseeId)
				AND (@CurrencyIds = '' OR ',' + @CurrencyIds + ',' LIKE '%,' + CONVERT(VARCHAR(20), r.CurrencyId) + ',%')
				AND ISNULL(r.TicketType, 0) <> 2
				AND b.BettypeId IS NULL
			GROUP BY r.rptDate, r.SiteId, r.CurrencyId, r.ProductId
		END
		ELSE
		BEGIN
			INSERT INTO #tmpData (rptDate, LicenseeId, CurrencyId, ProductId, LeagueId, Bettype, BetCount, Turnover, Winloss, WinlossA, CommissionP)
			SELECT r.rptDate, r.SiteId, r.CurrencyId, bt.ProductId, r.LeagueId
				,CASE WHEN r.Bettype NOT IN (9, 29) AND r.Bettype NOT BETWEEN 31 AND 120 THEN 1 ELSE 0 END AS Bettype
				,SUM(r.BetCount * CASE
									WHEN r.Bettype IN (999,4297,1698,3898) THEN 0
									WHEN @drawfilter = 2 AND r.Status = 111 THEN 0
									ELSE 1 END) AS BetCount
				,SUM(r.Turnover * CASE
									WHEN r.Bettype = 999 THEN 0
									WHEN @drawfilter IN (2, 3) AND r.Status = 111 THEN 0
									WHEN @drawfilter IN (2, 3) AND r.Status IN (114, 115) THEN 0.5
									ELSE 1 END) AS Turnover
				,SUM(r.Winloss * CASE
									WHEN r.Bettype IN (999,4297,1698,3898) THEN 0
									ELSE 1 END) AS Winloss
				,SUM(CASE WHEN r.Bettype IN (999,4297,1698,3898) THEN ISNULL(-r.WinLossA, 0) ELSE 0 END) WinlossA
				,SUM(CASE WHEN bt.ProductId = 32 THEN 0 ELSE r.CommissionP END) AS CommissionP
			FROM bodb_LicenseeReport.dbo.rpt_Betting r WITH (NOLOCK)
				INNER JOIN #Bettype bt ON r.Bettype = bt.Bettype
			WHERE r.rptDate BETWEEN @FromDate AND @ToDate
				AND r.Status IN (111, 112, 113, 114, 115)
				AND r.CustomerCategory NOT IN (27, 28)
				AND r.CurrencyId <> 20
				AND EXISTS (SELECT 1 FROM #Licensees p WHERE r.SiteId = p.LicenseeId)
				AND (@CurrencyIds = '' OR ',' + @CurrencyIds + ',' LIKE '%,' + CONVERT(VARCHAR(20), r.CurrencyId) + ',%')
				AND ISNULL(r.TicketType, 0) <> 2
				AND (
					@ReportBy = 0
					OR (@ReportBy = 1 AND r.IsLive = 1 AND r.bettype NOT IN (9, 29, 10))
					OR (@ReportBy = 2 AND r.IsLive = 0)
				)
			GROUP BY r.rptDate, r.SiteId, r.CurrencyId, bt.ProductId, r.LeagueId
				,CASE WHEN r.Bettype NOT IN (9, 29) AND r.Bettype NOT BETWEEN 31 AND 120 THEN 1 ELSE 0 END

			IF @SportType <> 0
				DELETE d
				FROM #tmpData d
					LEFT JOIN dbo.League l WITH(NOLOCK) ON d.leagueid = l.leagueid AND l.Sporttype = @Sporttype AND d.Bettype = 1
				WHERE l.leagueid IS NULL
		END

		;WITH cte_Data AS
		(
			SELECT b.rptDate, b.LicenseeId, b.CurrencyId, b.ProductId
					,SUM(b.Turnover) AS Turnover
					,SUM(b.Winloss)	AS MemberWL
					,SUM(b.BetCount) AS BetCount
					,SUM(CommissionP) AS Playercomm
					,SUM(WinlossA) AS WinlossA
			FROM #tmpData b
			GROUP BY b.rptDate, b.LicenseeId, b.CurrencyId, b.ProductId
		)
		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, Currency, TurnOver, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company, Betcount, Playercomm, OddsSpreadCost)
		SELECT a.rptDate
			   ,p.PartyID
			   ,a.CurrencyID
			   ,TurnOver
			   ,MemberWL
			   ,-MemberWL
			   ,0
			   ,0
			   ,(-MemberWL - CASE WHEN a.ProductID IN (@PP_ProductId, @SBC_ProductId, @VGA_ProductId) THEN WinlossA ELSE 0 END) * ISNULL(cc.Rate, p.Rate)
			   ,Betcount
			   ,Playercomm
			   ,CASE WHEN a.ProductID = 0 THEN WinlossA ELSE 0 END
		FROM cte_Data a
		INNER JOIN #tmpParty p ON p.LicenseeId = a.LicenseeId AND a.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ProductId=a.ProductId AND p.ChargeType = 1
		LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cc WITH (NOLOCK) ON cc.ChargeID = p.ChargeId AND a.CurrencyId=cc.CurrencyID

		DROP TABLE #tmpData
		DROP TABLE #Licensees
	END

	SELECT DISTINCT ExchangeDate, ExchangeId, Code, USD, EUR, MYR, GBP
	INTO #TempExchange
	FROM Lrf_f_GetExchangeDaily(@FromDate, @ToDate)
	
	UPDATE #TempExchange
	SET Code = (CASE ExchangeId
					WHEN 51 THEN 'INH'
					WHEN 75 THEN 'PTU'
					WHEN 76 THEN 'PS'
					WHEN 77 THEN 'PTH' 
					WHEN 92 THEN 'HID'
					ELSE Code
				END)
	WHERE ExchangeId IN (51, 75, 76, 77, 92)
	
	SELECT	w.PartyID,
			CASE WHEN p.PartyName ='18bb' THEN 'PIH'
				WHEN p.PartyName ='IBC' THEN 'FDL'
				ELSE p.PartyName
			END AS PartyName,
			e.Code AS currencyName,
			SUM(TurnOver) AS Turnover,
			SUM(Winlost) AS Winlost,
			SUM(LicenseeWL) AS LicenseeWL,
			SUM(CommBA) AS CommBA,
			SUM(AmtDuetoBA) AS AmtDuetoBA,
			SUM(Company) AS Company,
			SUM(Betcount) AS Betcount,
			SUM(Playercomm) AS Playercomm,
			SUM(OddsSpreadCost) AS OddsSpreadCost,
			SUM(TurnOver * e.MYR) AS TurnoverMYR,
			SUM(Winlost * e.MYR) AS WinlostMYR,
			SUM(LicenseeWL * e.MYR) AS LicenseeWLMYR,
			SUM(CommBA * e.MYR) AS CommBAMYR,
			SUM(AmtDuetoBA*e.MYR) AS AmtDuetoBAMYR,
			SUM(Company * e.MYR) AS CompanyMYR,
			SUM(Playercomm * e.MYR) AS PlayercommMYR,
			SUM(OddsSpreadCost * e.MYR) AS OddsSpreadCostMYR,
			SUM(TurnOver * e.USD) AS TurnoverUSD,
			SUM(Winlost * e.USD) AS WinlostUSD,
			SUM(LicenseeWL * e.USD) AS LicenseeWLUSD,
			SUM(CommBA * e.USD) AS CommBAUSD,
			SUM(AmtDuetoBA * e.USD) AS AmtDuetoBAUSD,
			SUM(Company * e.USD) AS CompanyUSD,
			SUM(Playercomm * e.USD) AS PlayercommUSD,
			SUM(OddsSpreadCost * e.USD) AS OddsSpreadCostUSD,
			SUM(TurnOver * e.EUR) AS TurnoverEUR,
			SUM(Winlost * e.EUR) AS WinlostEUR,
			SUM(LicenseeWL * e.EUR) AS LicenseeWLEUR,
			SUM(CommBA * e.EUR) AS CommBAEUR,
			SUM(AmtDuetoBA*e.EUR) AS AmtDuetoBAEUR,
			SUM(Company * e.EUR) AS CompanyEUR,
			SUM(Playercomm * e.EUR) AS PlayercommEUR,
			SUM(OddsSpreadCost * e.EUR) AS OddsSpreadCostEUR,
			SUM(TurnOver * e.GBP) AS TurnoverGBP,
			SUM(Winlost * e.GBP) AS WinlostGBP,
			SUM(LicenseeWL * e.GBP) AS LicenseeWLGBP,
			SUM(CommBA * e.GBP) AS CommBAGBP,
			SUM(AmtDuetoBA * e.GBP) AS AmtDuetoBAGBP,
			SUM(Company * e.GBP) AS CompanyGBP,
			SUM(Playercomm * e.GBP) AS PlayercommGBP,
			SUM(OddsSpreadCost * e.GBP) AS OddsSpreadCostGBP
	FROM #tmpWinLoss w
		INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH(NOLOCK) ON p.PartyID = w.PartyID
		INNER JOIN #TempExchange e ON w.Winlostdate = e.ExchangeDate AND w.currency = e.ExchangeId
	GROUP BY w.PartyID, p.PartyName, e.Code
	ORDER BY w.PartyID, p.PartyName

	DROP TABLE #Bettype
	DROP TABLE #Products
	DROP TABLE #TempExchange
	DROP TABLE #tmpParty
	DROP TABLE #tmpWinLoss
END
GO