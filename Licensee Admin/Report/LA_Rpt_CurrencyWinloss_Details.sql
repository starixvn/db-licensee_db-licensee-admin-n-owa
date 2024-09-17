/*<info serverAlias="DBEXT-bodb02" executers="wsv_nap,wsv_lap" isFunction="0" isNested="0"></info>*/
USE bodb02
GO

ALTER PROCEDURE [dbo].[LA_Rpt_CurrencyWinloss_Details]
	@PartyIDs			VARCHAR(MAX)	= ''
	,@CurrencyIds		VARCHAR(MAX)	= ''
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@ProductCodes		VARCHAR(MAX)	= 'SB'
	,@SportType			INT				= 0
	,@Bettype			INT				= 0
	,@ReportBy			TINYINT			= 0
	,@drawfilter		SMALLINT		= 1
	,@LicenseeStatusIds	VARCHAR(100)	
	,@PlatformId		TINYINT = 0
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
	   - 20211115@Percy: Return IsShowOddsSpread [RedmineID: #164411]
	   - 20211026@Danny: Treat SLT as a part of SB based on cutoff date [RedmineID: #163181]
	   - 20211212@Percy: Set OddsSpread = 0 if negative value [RedmineID: #165849]
	   - 20210824@Danny: filter licensee status from OIC [#159296]
	   - 20220110@Danny: SG - Jackpot prize integration [#167089]
	   - 20201025@Danny: Support USDT as base currency [RedmineID: #177718]
	   - 20221209@Danny: Show USD (USDT) instead of USD only [RedmineID: #180313]
	   - 20221226@Danny: Fiat currency Base to USDT = 0 [RedmineID: #180703]
	   - 20221003@Malcolm: Add platform filter [RedmineID: #165707]
	   - 20220227@Danny: Incorporate USDTJP currency [RedmineID: #183461]
	   - 20230217@Danny: Remove hard-code bettype And ProductID [#183739]
	   - 20230510@Danny: New commercial terms for 12B [RedmineID: #186543]
	   - 20230823@Danny: Incorporate US$KH currency [RedmineID: #192544]
	   - 20230919@Danny: Support Jollysport licensees [RedmineID: #193214]
	   - 20240314@Danny: AGC - JP, Contribution, Promotion prize integration [#197268]
	   - 20240924@Danny: exclude BTS currency [RedmineID: #210422]
	   - 20240913@Sally: Support Odds Boost Voucher [#209884]

	Param's Explanation:
	  + @ReportType: 1-Live; 2-Non-Live; 0: All;
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @GD_Tip	SMALLINT = 1706, @ExchangeTerm_CutOffDate	SMALLDATETIME

	DECLARE @JPContrib_ProductList TABLE(ProductID INT)
	INSERT INTO @JPContrib_ProductList
	SELECT DISTINCT ProductId
	FROM bodb_licensee.dbo.LA_f_GroupBettype() where TypeID = 2

	DECLARE @BaseCurrencyId INT, @BaseCurrencyName VARCHAR(10)
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
		INSERT INTO @Currency SELECT value FROM STRING_SPLIT(@CurrencyIds, ',')

	CREATE TABLE #Products (GroupProductId INT, ProductId INT, ProductName VARCHAR(50), ProductCode VARCHAR(20), FromDate DATE, ToDate DATE)
	INSERT INTO #Products (GroupProductId, ProductId, ProductName, ProductCode, FromDate, ToDate)
	SELECT GroupProductId, ProductId, ProductName, ProductCode , FromDate, ToDate
	FROM bodb_Licensee.dbo.LA_f_GroupProduct(@ProductCodes, @FromDate, @ToDate) g

	SET @ProductCodes = NULL
	SELECT @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM #Products

	-- Handle licensee status
	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
		    INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END

	SELECT @PartyIds = PartyIDs FROM bodb_Licensee.dbo.LA_f_PartyListByStatusSel(@PartyIDs, @LicenseeStatusIds)
	-- End Handle licensee status

	SELECT @ExchangeTerm_CutOffDate = f.CutoffDate FROM bodb_licensee.dbo.LA_f_GetCutOffDate() f WHERE f.TypeName = 'ExchangeTerms'

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
		OddsSpreadCost	MONEY,
		OddsBoostBonus	MONEY
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

	CREATE TABLE #PartyList (PartyId INT, BaseCurrencyId INT, BaseCurrencyName VARCHAR(10))
	INSERT INTO #PartyList (PartyId)
	SELECT DISTINCT PartyId FROM #tmpParty

	UPDATE p
	SET p.BaseCurrencyId = ISNULL(bc.BaseCurrencyId, 6), p.BaseCurrencyName = ISNULL(CASE WHEN e.Code = 'UST' THEN 'USDT' ELSE e.Code END, 'EUR')
	FROM #PartyList p
		LEFT JOIN bodb_licensee.dbo.OAS_PartyBaseCurrency bc WITH (NOLOCK) ON p.PartyId = bc.PartyId AND bc.FromDate <= @ToDate AND bc.ToDate >= @FromDate
		LEFT JOIN dbo.Exchange e WITH (NOLOCK) ON bc.BaseCurrencyId = e.ExchangeId

	DECLARE @BaseCurrency TABLE (BaseCurrencyId INT, BaseCurrencyName VARCHAR(10))
	INSERT INTO @BaseCurrency (BaseCurrencyId, BaseCurrencyName)
	SELECT DISTINCT BaseCurrencyId, BaseCurrencyName FROM #PartyList

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
					(b.CurrencyID NOT IN ( SELECT x.ExchangeID FROM bodb_licensee.dbo.LA_f_ExcludedCurrencyListSel() x)) AND
					(@SportType = 0 OR (b.bettype NOT IN (9,29) AND l.Sporttype = @SportType)) AND
					((@ReportBy = 0) OR
					 (@ReportBy = 1 AND b.IsLive=1 AND b.bettype NOT IN (9,29,10)) OR
					 (@ReportBy = 2 AND b.IsLive=0))
			GROUP BY b.rptDate, tp.PartyID, b.currencyID
		)
	END

	IF (EXISTS (SELECT 1 FROM #Products WHERE ProductCode IN ('AGC','GD','VG','BX')) AND @SportType = 0 AND @ReportBy = 0 AND @Bettype = 0)
	BEGIN
		; WITH b AS
		(
			SELECT b.rptDate,
					p.PartyID,
					b.CurrencyId Currency
					,b.ProductID
					,SUM( CASE WHEN gb.Bettype IS NOT NULL THEN 0 ELSE b.Turnover END * 
									(CASE	WHEN @drawfilter IN (2, 3) AND b.[StatusId] = 111  THEN 0
											WHEN @drawfilter IN (2, 3) AND b.[StatusId] IN (114,115) THEN 0.5
											ELSE 1 
									 END))  TurnOver
					,SUM(CASE WHEN gb.Bettype IS NOT NULL THEN 0 ELSE b.MemberWL + CASE WHEN b.ProductID=31 THEN b.CommissionP ELSE 0 END END) Winlost
					,SUM(CASE WHEN gb.Bettype IS NOT NULL THEN 0 ELSE-b.MemberWL - CASE WHEN b.ProductID=31 THEN b.CommissionP ELSE 0 END END) LicenseeWL
					,0 AS AmtDueToBA
					,0 AS CommBA
					,SUM(CASE WHEN gb.Bettype IS NOT NULL THEN 0 ELSE b.Betcount END * (CASE WHEN @drawfilter = 2 AND b.[StatusId] = 111 THEN 0 ELSE 1 END)) Betcount
					,SUM(b.commissionP)  Playercomm
					,SUM(b.CommissionA) Acomm
					,SUM(CASE WHEN gb.TypeId = 2 THEN -GrossWL ELSE 0 END) AS LicenseeContrib
			FROM bodb_licenseereport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #tmpParty p ON b.SiteID = p.LicenseeID AND p.ProductID=b.ProductID AND b.rptDate BETWEEN p.Fromdate AND p.Todate
			LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cc WITH (NOLOCK) ON cc.ChargeID = p.ChargeId AND b.CurrencyId=cc.CurrencyID
			LEFT JOIN bodb_licensee.dbo.LA_f_GroupBettype() gb ON b.Bettype = gb.Bettype 
			WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate) AND
					 b.StatusId NOT IN (-1, 101, 102, 103) AND
					(@IsAllCurrency = 1 OR b.CurrencyID IN (SELECT c.CurrencyId FROM @Currency c)) AND
					(b.CurrencyID NOT IN ( SELECT x.ExchangeID FROM bodb_licensee.dbo.LA_f_ExcludedCurrencyListSel() x)) AND
					b.CustomerCategory NOT IN (27,28) AND
					p.ProductID IN (10,11,12,31) AND
					p.ChargeType = 1 AND -- gross win
					b.bettype <> @GD_Tip 

			GROUP BY b.rptDate
					,p.PartyID
					,b.CurrencyID
					,b.ProductID
		)

		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, Currency, TurnOver, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company, Betcount, Playercomm)
		(
			SELECT b.rptDate,p.PartyID,b.Currency
					,SUM(b.Turnover)
					,SUM(b.Winlost)
					,SUM(b.LicenseeWL)
					,0 AS AmtDueToBA
					,0 AS CommBA
					, SUM(
						CASE WHEN b.ProductID=31 THEN CASE WHEN b.rptDate < @ExchangeTerm_CutOffDate THEN -b.Winlost * ISNULL(cc.Rate,p.Rate) - (b.Acomm + b.Playercomm)
													  ELSE  -(b.Winlost +  b.Playercomm) * ISNULL(cc.Rate,p.Rate) END
							 WHEN b.ProductID = 10 THEN (-b.Winlost - b.LicenseeContrib)  * ISNULL(cc.Rate,p.Rate)
						ELSE -b.Winlost * ISNULL(cc.rate,p.Rate) END
					 ) Company
					,SUM(b.Betcount)
					,SUM(b.Playercomm)
			FROM  b WITH (NOLOCK)
			INNER JOIN #tmpParty p ON b.PartyID = p.PartyID AND p.ProductID=b.ProductID AND b.rptDate BETWEEN p.Fromdate AND p.Todate
			LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cc WITH (NOLOCK) ON cc.ChargeID = p.ChargeId AND b.Currency=cc.CurrencyID
			GROUP BY b.rptDate
					,p.PartyID
					,b.Currency

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
					(b.CurrencyID NOT IN ( SELECT x.ExchangeID FROM bodb_licensee.dbo.LA_f_ExcludedCurrencyListSel() x)) AND
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
				AND (b.CurrencyID NOT IN ( SELECT x.ExchangeID FROM bodb_licensee.dbo.LA_f_ExcludedCurrencyListSel() x))
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
		SELECT DISTINCT LicenseeId FROM #tmpParty WHERE LicenseeId IS NOT NULL

		DELETE bt
		FROM #Bettype bt
			INNER JOIN bodb_licensee.dbo.LA_f_GroupBettype() eb ON bt.Bettype = eb.Bettype AND eb.TypeID NOT IN (7,2,11) -- 7:OddsSpread Adjustment, 2:Jackpot Contribution, 11:Odds Boost Adjustment

		CREATE TABLE #tmpData (rptDate DATE, LicenseeId INT, CurrencyId INT, ProductId INT, LeagueId INT, Bettype INT
			,BetCount INT, Turnover MONEY, Winloss MONEY, WinlossA MONEY, CommissionP MONEY, OddsBoostBonus MONEY)

		IF @SportType = 0 AND @Bettype = 0 AND @ReportBy = 0
		BEGIN
			INSERT INTO #tmpData (rptDate, LicenseeId, CurrencyId, ProductId, BetCount, Turnover, Winloss, WinlossA, CommissionP, OddsBoostBonus)
			SELECT r.rptDate, r.SiteId, r.CurrencyId, r.ProductId
				,SUM(r.BetCount * CASE
									WHEN b.TypeID IN (7,2,11) THEN 0
									WHEN @drawfilter = 2 AND r.StatusId = 111 THEN 0
									ELSE 1 END) AS BetCount
				,SUM(r.Turnover * CASE
									WHEN b.TypeID IN (7,11) THEN 0
									WHEN @drawfilter IN (2, 3) AND r.StatusId = 111 THEN 0
									WHEN @drawfilter IN (2, 3) AND r.StatusId IN (114, 115) THEN 0.5
									ELSE 1 END) AS Turnover
				,SUM(r.MemberWL * CASE
									WHEN b.TypeID IN (7,2,11) THEN 0
									ELSE 1 END) AS Winloss
				,SUM(CASE WHEN b.TypeID IN (7,2) THEN ISNULL(-r.GrossWL, 0) ELSE 0 END) WinlossA
				,SUM(CASE WHEN r.ProductId = 32 THEN 0 ELSE r.CommissionP END) AS CommissionP
				,SUM(CASE WHEN b.TypeId = 11 THEN ISNULL(r.ValidBetAmount, 0) ELSE 0 END) OddsBoostBonus
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct r WITH (NOLOCK)
					LEFT JOIN bodb_licensee.dbo.LA_f_GroupBettype() b ON r.Bettype = b.Bettype 
			WHERE r.rptDate BETWEEN @FromDate AND @ToDate
				AND r.StatusId IN (111, 112, 113, 114, 115)
				AND r.CustomerCategory NOT IN (27, 28)
				AND r.CurrencyId NOT IN ( SELECT x.ExchangeID FROM bodb_licensee.dbo.LA_f_ExcludedCurrencyListSel() x)
				AND EXISTS (SELECT 1 FROM #Licensees p WHERE r.SiteId = p.LicenseeId)
				AND (@CurrencyIds = '' OR ',' + @CurrencyIds + ',' LIKE '%,' + CONVERT(VARCHAR(20), r.CurrencyId) + ',%')
				AND ISNULL(r.TicketType, 0) <> 2
				AND (b.Bettype IS NULL OR b.TypeID IN (7,2,11)) -- 7:OddsSpread Adjustment, 2:Jackpot Contribution, 11:Odds Boost Adjustment
			GROUP BY r.rptDate, r.SiteId, r.CurrencyId, r.ProductId
		END
		ELSE
		BEGIN
			INSERT INTO #tmpData (rptDate, LicenseeId, CurrencyId, ProductId, LeagueId, Bettype, BetCount, Turnover, Winloss, WinlossA, CommissionP, OddsBoostBonus)
			SELECT r.rptDate, r.SiteId, r.CurrencyId, bt.ProductId, r.LeagueId
				,CASE WHEN r.Bettype NOT IN (9, 29) AND r.Bettype NOT BETWEEN 31 AND 120 THEN 1 ELSE 0 END AS Bettype
				,SUM(r.BetCount * CASE
									WHEN t.TypeID IN (7,2,11) THEN 0
									WHEN @drawfilter = 2 AND r.Status = 111 THEN 0
									ELSE 1 END) AS BetCount
				,SUM(r.Turnover * CASE
									WHEN t.TypeID IN (7,11) THEN 0
									WHEN @drawfilter IN (2, 3) AND r.Status = 111 THEN 0
									WHEN @drawfilter IN (2, 3) AND r.Status IN (114, 115) THEN 0.5
									ELSE 1 END) AS Turnover
				,SUM(r.Winloss * CASE
									WHEN t.TypeID IN (7,2) THEN 0
									ELSE 1 END) AS Winloss
				,SUM(CASE WHEN t.TypeID IN (7,2) THEN ISNULL(-r.WinLossA, 0) ELSE 0 END) WinlossA
				,SUM(CASE WHEN bt.ProductId = 32 THEN 0 ELSE r.CommissionP END) AS CommissionP
				,SUM(CASE WHEN t.TypeId = 11 THEN ISNULL(r.oddsspread, 0) ELSE 0 END) OddsBoostBonus
			FROM bodb_LicenseeReport.dbo.rpt_Betting r WITH (NOLOCK)
				INNER JOIN #Bettype bt ON r.Bettype = bt.Bettype
				LEFT JOIN bodb_licensee.dbo.LA_f_GroupBettype() t ON r.Bettype = t.Bettype AND t.TypeID IN (7,2,11) -- 7:OddsSpread Adjustment, 2:Jackpot Contribution, 11:Odds Boost Adjustment
			WHERE r.rptDate BETWEEN @FromDate AND @ToDate
				AND r.Status IN (111, 112, 113, 114, 115)
				AND r.CustomerCategory NOT IN (27, 28)
				AND r.CurrencyId NOT IN ( SELECT x.ExchangeID FROM bodb_licensee.dbo.LA_f_ExcludedCurrencyListSel() x)
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
			SELECT b.rptDate, b.LicenseeId, b.CurrencyId, p.GroupProductId AS ProductId
					,SUM(b.Turnover) AS Turnover
					,SUM(b.Winloss)	AS MemberWL
					,SUM(b.BetCount) AS BetCount
					,SUM(CommissionP) AS Playercomm
					,SUM(WinlossA) AS WinlossA
					,SUM(b.OddsBoostBonus) AS OddsBoostBonus
			FROM #tmpData b
				INNER JOIN #Products p ON b.ProductId = p.ProductId AND b.rptDate BETWEEN p.FromDate AND p.ToDate
			GROUP BY b.rptDate, b.LicenseeId, b.CurrencyId, p.GroupProductId
		)
		INSERT INTO #tmpWinLoss(Winlostdate, PartyID, Currency, TurnOver, Winlost, LicenseeWL, AmtDueToBA, CommBA, Company, Betcount, Playercomm, OddsSpreadCost, OddsBoostBonus)
		SELECT a.rptDate
			   ,p.PartyID
			   ,a.CurrencyID
			   ,TurnOver
			   ,MemberWL
			   ,-MemberWL
			   ,0
			   ,0
			   ,(-MemberWL - CASE WHEN jp.ProductID IS NOT NULL THEN WinlossA ELSE 0 END + a.OddsBoostBonus) * ISNULL(cc.Rate, p.Rate) --  SB Service Fee =(Licensee WL + Odds Boost Bonus) * SB charge rate
			   ,Betcount
			   ,Playercomm
			   ,CASE WHEN a.ProductID = 0 THEN WinlossA ELSE 0 END
			   ,CASE WHEN a.ProductID = 0 THEN OddsBoostBonus ELSE 0 END AS OddsBoostBonus
		FROM cte_Data a
		INNER JOIN #tmpParty p ON p.LicenseeId = a.LicenseeId AND a.rptDate BETWEEN p.FromDate AND p.ToDate AND p.ProductId=a.ProductId AND p.ChargeType = 1
		LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cc WITH (NOLOCK) ON cc.ChargeID = p.ChargeId AND a.CurrencyId=cc.CurrencyID
		LEFT JOIN @JPContrib_ProductList jp ON jp.ProductID = a.ProductID

		DROP TABLE #tmpData
		DROP TABLE #Licensees
	END

	-- Exchange rate
	BEGIN
		CREATE TABLE #ExchangeRate (BaseCurrencyId INT, ExchangeDate DATETIME, ExchangeId INT, Code VARCHAR(65), USD FLOAT, EUR FLOAT, MYR FLOAT, GBP FLOAT, USDT FLOAT, Rate FLOAT)
		INSERT INTO #ExchangeRate (ExchangeDate, ExchangeId, USD, EUR, MYR, GBP, USDT, Code)
		SELECT ExchangeDate, ExchangeId, USD, EUR, MYR, GBP, USDT
			,CASE ExchangeId
				WHEN 142 THEN 'USDT'
				WHEN 96 THEN 'USD (USDT)'
				WHEN 206 THEN 'USD (USDT)'
				WHEN 202 THEN 'USD (USDTJP)'
				WHEN 208 THEN 'USD (US$KH)'
				WHEN 209 THEN 'MP'
				ELSE Code END
		FROM Lrf_f_GetExchangeDaily(@FromDate, @ToDate)

		DECLARE @SpeicialCurrrency TABLE (ExchangeId INT, CurrencyCode VARCHAR(65))
		INSERT INTO @SpeicialCurrrency (ExchangeId, CurrencyCode)
		SELECT DISTINCT ExchangeId, Code
		FROM #ExchangeRate
		WHERE ExchangeId IN (142,96,206,202,208,209)

		DECLARE @Exchange TABLE (Currency INT, CurrencyName VARCHAR(20), CurrencyCode VARCHAR(65))
		INSERT INTO @Exchange(Currency, CurrencyName , CurrencyCode)
		SELECT e.ExchangeId, e.currency, 
				CASE WHEN  e.ExchangeId = 51 THEN 'INH'
					WHEN  e.ExchangeId =75 THEN 'PTU'
					WHEN  e.ExchangeId =76 THEN 'PS'
					WHEN  e.ExchangeId =77 THEN 'PTH'
					WHEN  e.ExchangeId =92 THEN 'HID'
					WHEN  s.ExchangeId IS NOT NULL THEN s.CurrencyCode
				ELSE e.Code END
		FROM Exchange e WITH (NOLOCK)
		LEFT JOIN @SpeicialCurrrency s ON e.ExchangeId = s.ExchangeId
		WHERE e.ExchangeId IN (SELECT t.Currency FROM #tmpWinLoss t)

		UPDATE e
		SET CurrencyCode = e.CurrencyCode + ' (' + CurrencyName + ')' 
		FROM @Exchange e
		WHERE e.CurrencyCode IN (	SELECT x.CurrencyCode 
									FROM @Exchange x
									WHERE x.Currency NOT IN (SELECT t.ExchangeId FROM @SpeicialCurrrency t)
										AND x.Currency NOT IN (51,75,76,77,92)
									GROUP BY x.CurrencyCode 
									HAVING COUNT(1) > 1
								) 

	END
	
	-- Fiat to Crypto
		UPDATE e
		SET USDT = 0
		FROM #ExchangeRate e 
		INNER JOIN bodb02.dbo.Exchange ex WITH (NOLOCK) ON e.ExchangeId = ex.ExchangeId AND ex.CurrencyType = 0


	-- Result
	BEGIN
		CREATE TABLE #Result (PartyId INT, PartyName VARCHAR(50), CurrencyName VARCHAR(20), BetCount INT
			,Turnover MONEY, Winlost MONEY, LicenseeWL MONEY, CommBA MONEY, AmtDuetoBA MONEY, Company MONEY, Playercomm MONEY, OddsSpreadCost MONEY, OddsBoostBonus MONEY
			,TurnoverMYR MONEY, WinlostMYR MONEY, LicenseeWLMYR MONEY, CommBAMYR MONEY, AmtDuetoBAMYR MONEY, CompanyMYR MONEY, PlayercommMYR MONEY, OddsSpreadCostMYR MONEY, OddsBoostBonusMYR MONEY
			,TurnoverUSD MONEY, WinlostUSD MONEY, LicenseeWLUSD MONEY, CommBAUSD MONEY, AmtDuetoBAUSD MONEY, CompanyUSD MONEY, PlayercommUSD MONEY, OddsSpreadCostUSD MONEY, OddsBoostBonusUSD MONEY
			,TurnoverEUR MONEY, WinlostEUR MONEY, LicenseeWLEUR MONEY, CommBAEUR MONEY, AmtDuetoBAEUR MONEY, CompanyEUR MONEY, PlayercommEUR MONEY, OddsSpreadCostEUR MONEY, OddsBoostBonusEUR MONEY
			,TurnoverGBP MONEY, WinlostGBP MONEY, LicenseeWLGBP MONEY, CommBAGBP MONEY, AmtDuetoBAGBP MONEY, CompanyGBP MONEY, PlayercommGBP MONEY, OddsSpreadCostGBP MONEY, OddsBoostBonusGBP MONEY
			,TurnoverUSDT MONEY, WinlostUSDT MONEY, LicenseeWLUSDT MONEY, CommBAUSDT MONEY, AmtDuetoBAUSDT MONEY, CompanyUSDT MONEY, PlayercommUSDT MONEY, OddsSpreadCostUSDT MONEY, OddsBoostBonusUSDT MONEY
			,IsShowOddsSpread BIT, IsShowOddsBoostBonus BIT
			)

		INSERT INTO #Result (PartyId, PartyName, CurrencyName, BetCount
			,Turnover, Winlost, LicenseeWL, CommBA, AmtDuetoBA, Company, Playercomm, OddsSpreadCost, OddsBoostBonus
			,TurnoverMYR, WinlostMYR, LicenseeWLMYR, CommBAMYR, AmtDuetoBAMYR, CompanyMYR, PlayercommMYR, OddsSpreadCostMYR, OddsBoostBonusMYR 
			,TurnoverUSD, WinlostUSD, LicenseeWLUSD, CommBAUSD, AmtDuetoBAUSD, CompanyUSD, PlayercommUSD, OddsSpreadCostUSD, OddsBoostBonusUSD 
			,TurnoverEUR, WinlostEUR, LicenseeWLEUR, CommBAEUR, AmtDuetoBAEUR, CompanyEUR, PlayercommEUR, OddsSpreadCostEUR, OddsBoostBonusEUR 
			,TurnoverGBP, WinlostGBP, LicenseeWLGBP, CommBAGBP, AmtDuetoBAGBP, CompanyGBP, PlayercommGBP, OddsSpreadCostGBP, OddsBoostBonusGBP 
			,TurnoverUSDT, WinlostUSDT, LicenseeWLUSDT, CommBAUSDT, AmtDuetoBAUSDT, CompanyUSDT, PlayercommUSDT, OddsSpreadCostUSDT, OddsBoostBonusUSDT)
		SELECT w.PartyId
			,CASE
				WHEN p.PartyName ='18bb' THEN 'PIH'
				WHEN p.PartyName ='IBC' THEN 'FDL'
				ELSE p.PartyName
			END AS PartyName
			,eg.CurrencyCode AS currencyName
			,SUM(w.Betcount) AS Betcount
			-- Original
			,SUM(w.TurnOver) AS Turnover
			,SUM(w.Winlost) AS Winlost
			,SUM(w.LicenseeWL) AS LicenseeWL
			,SUM(w.CommBA) AS CommBA
			,SUM(w.AmtDuetoBA) AS AmtDuetoBA
			,SUM(w.Company) AS Company
			,SUM(w.Playercomm) AS Playercomm
			,SUM(w.OddsSpreadCost) AS OddsSpreadCost
			,SUM(w.OddsBoostBonus) AS OddsBoostBonus
			-- MYR
			,SUM(w.TurnOver * e.MYR) AS TurnoverMYR
			,SUM(w.Winlost * e.MYR) AS WinlostMYR
			,SUM(w.LicenseeWL * e.MYR) AS LicenseeWLMYR
			,SUM(w.CommBA * e.MYR) AS CommBAMYR
			,SUM(w.AmtDuetoBA*e.MYR) AS AmtDuetoBAMYR
			,SUM(w.Company * e.MYR) AS CompanyMYR
			,SUM(w.Playercomm * e.MYR) AS PlayercommMYR
			,SUM(w.OddsSpreadCost * e.MYR) AS OddsSpreadCostMYR
			,SUM(w.OddsBoostBonus * e.MYR) AS OddsBoostBonusMYR
			-- USD
			,SUM(w.TurnOver * e.USD) AS TurnoverUSD
			,SUM(w.Winlost * e.USD) AS WinlostUSD
			,SUM(w.LicenseeWL * e.USD) AS LicenseeWLUSD
			,SUM(w.CommBA * e.USD) AS CommBAUSD
			,SUM(w.AmtDuetoBA * e.USD) AS AmtDuetoBAUSD
			,SUM(w.Company * e.USD) AS CompanyUSD
			,SUM(w.Playercomm * e.USD) AS PlayercommUSD
			,SUM(w.OddsSpreadCost * e.USD) AS OddsSpreadCostUSD
			,SUM(w.OddsBoostBonus * e.USD) AS OddsBoostBonusUSD
			-- EUR
			,SUM(w.TurnOver * e.EUR) AS TurnoverEUR
			,SUM(w.Winlost * e.EUR) AS WinlostEUR
			,SUM(w.LicenseeWL * e.EUR) AS LicenseeWLEUR
			,SUM(w.CommBA * e.EUR) AS CommBAEUR
			,SUM(w.AmtDuetoBA*e.EUR) AS AmtDuetoBAEUR
			,SUM(w.Company * e.EUR) AS CompanyEUR
			,SUM(w.Playercomm * e.EUR) AS PlayercommEUR
			,SUM(w.OddsSpreadCost * e.EUR) AS OddsSpreadCostEUR
			,SUM(w.OddsBoostBonus * e.EUR) AS OddsBoostBonusEUR
			-- GBP
			,SUM(w.TurnOver * e.GBP) AS TurnoverGBP
			,SUM(w.Winlost * e.GBP) AS WinlostGBP
			,SUM(w.LicenseeWL * e.GBP) AS LicenseeWLGBP
			,SUM(w.CommBA * e.GBP) AS CommBAGBP
			,SUM(w.AmtDuetoBA * e.GBP) AS AmtDuetoBAGBP
			,SUM(w.Company * e.GBP) AS CompanyGBP
			,SUM(w.Playercomm * e.GBP) AS PlayercommGBP
			,SUM(w.OddsSpreadCost * e.GBP) AS OddsSpreadCostGBP
			,SUM(w.OddsBoostBonus * e.GBP) AS OddsBoostBonusGBP
			-- USDT
			,SUM(w.TurnOver * e.USDT) AS TurnoverUSDT
			,SUM(w.Winlost * e.USDT) AS WinlostUSDT
			,SUM(w.LicenseeWL * e.USDT) AS LicenseeWLUSDT
			,SUM(w.CommBA * e.USDT) AS CommBAUSDT
			,SUM(w.AmtDuetoBA * e.USDT) AS AmtDuetoBAUSDT
			,SUM(w.Company * e.USDT) AS CompanyUSDT
			,SUM(w.Playercomm * e.USDT) AS PlayercommUSDT
			,SUM(w.OddsSpreadCost * e.USDT) AS OddsSpreadCostUSDT
			,SUM(w.OddsBoostBonus * e.USDT) AS OddsBoostBonusUSDT
		FROM #tmpWinLoss w
			INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK) ON p.PartyId = w.PartyId
			INNER JOIN #ExchangeRate e ON w.Winlostdate = e.ExchangeDate AND w.currency = e.ExchangeId
			INNER JOIN @Exchange eg ON e.ExchangeId = eg.Currency
		GROUP BY w.PartyId
			,CASE
				WHEN p.PartyName ='18bb' THEN 'PIH'
				WHEN p.PartyName ='IBC' THEN 'FDL'
				ELSE p.PartyName
			END
			,eg.CurrencyCode
		
		-- Set OddsSpreadCost = 0 if value is negative
		DELETE #ExchangeRate
		
		WHILE EXISTS (SELECT 1 FROM @BaseCurrency)
		BEGIN
			SELECT @BaseCurrencyId = NULL, @BaseCurrencyName = NULL
			SELECT TOP 1 @BaseCurrencyId = BaseCurrencyId, @BaseCurrencyName = BaseCurrencyName FROM @BaseCurrency
			
			INSERT INTO #ExchangeRate (BaseCurrencyId, ExchangeDate, ExchangeId, Rate)
			SELECT DISTINCT @BaseCurrencyId, ExchangeDate, ExchangeId, BaseCurrencyRate
			FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
			WHERE ExchangeId IN (SELECT Currency FROM #tmpWinLoss)

			DELETE @BaseCurrency WHERE BaseCurrencyId = @BaseCurrencyId
		END

		UPDATE r
		SET -- OddsSpreadCost update
			r.OddsSpreadCost = CASE WHEN t.IsShowOddsSpread = 1 THEN r.OddsSpreadCost ELSE 0 END
			,r.OddsSpreadCostMYR = CASE WHEN t.IsShowOddsSpread = 1 THEN r.OddsSpreadCostMYR ELSE 0 END
			,r.OddsSpreadCostUSD = CASE WHEN t.IsShowOddsSpread = 1 THEN r.OddsSpreadCostUSD ELSE 0 END
			,r.OddsSpreadCostEUR = CASE WHEN t.IsShowOddsSpread = 1 THEN r.OddsSpreadCostEUR ELSE 0 END
			,r.OddsSpreadCostGBP = CASE WHEN t.IsShowOddsSpread = 1 THEN r.OddsSpreadCostGBP ELSE 0 END
			,r.OddsSpreadCostUSDT = CASE WHEN t.IsShowOddsSpread = 1 THEN r.OddsSpreadCostUSDT ELSE 0 END
			,r.IsShowOddsSpread = t.IsShowOddsSpread
			-- OddsBoostBonus update
			,r.OddsBoostBonus = CASE WHEN t.IsShowOddsBoostBonus = 1 THEN r.OddsBoostBonus ELSE 0 END
			,r.OddsBoostBonusMYR = CASE WHEN t.IsShowOddsBoostBonus = 1 THEN r.OddsBoostBonusMYR ELSE 0 END
			,r.OddsBoostBonusUSD = CASE WHEN t.IsShowOddsBoostBonus = 1 THEN r.OddsBoostBonusUSD ELSE 0 END
			,r.OddsBoostBonusEUR = CASE WHEN t.IsShowOddsBoostBonus = 1 THEN r.OddsBoostBonusEUR ELSE 0 END
			,r.OddsBoostBonusGBP = CASE WHEN t.IsShowOddsBoostBonus = 1 THEN r.OddsBoostBonusGBP ELSE 0 END
			,r.OddsBoostBonusUSDT = CASE WHEN t.IsShowOddsBoostBonus = 1 THEN r.OddsBoostBonusUSDT ELSE 0 END		
			,r.IsShowOddsBoostBonus = t.IsShowOddsBoostBonus
		FROM #Result r
			INNER JOIN (
				SELECT r.PartyId
					,CASE WHEN SUM(r.OddsSpreadCost * e.Rate) <= 0 THEN 0 ELSE 1 END AS IsShowOddsSpread
					,CASE WHEN SUM(r.OddsBoostBonus * e.Rate) = 0 THEN 0 ELSE 1 END AS IsShowOddsBoostBonus
				FROM #tmpWinLoss r
					INNER JOIN #PartyList p ON r.PartyId = p.PartyId
					INNER JOIN #ExchangeRate e ON p.BaseCurrencyId = e.BaseCurrencyId AND r.currency = e.ExchangeId AND r.Winlostdate = e.ExchangeDate
				GROUP BY r.PartyId
			) t ON r.PartyId = t.PartyId
	END

	-- Return data
	SELECT PartyId, PartyName, CurrencyName, BetCount
		,Turnover, Winlost, LicenseeWL, CommBA, AmtDuetoBA, Company, Playercomm, OddsSpreadCost, OddsBoostBonus
		,TurnoverMYR, WinlostMYR, LicenseeWLMYR, CommBAMYR, AmtDuetoBAMYR, CompanyMYR, PlayercommMYR, OddsSpreadCostMYR, OddsBoostBonusMYR
		,TurnoverUSD, WinlostUSD, LicenseeWLUSD, CommBAUSD, AmtDuetoBAUSD, CompanyUSD, PlayercommUSD, OddsSpreadCostUSD, OddsBoostBonusUSD
		,TurnoverEUR, WinlostEUR, LicenseeWLEUR, CommBAEUR, AmtDuetoBAEUR, CompanyEUR, PlayercommEUR, OddsSpreadCostEUR, OddsBoostBonusEUR
		,TurnoverGBP, WinlostGBP, LicenseeWLGBP, CommBAGBP, AmtDuetoBAGBP, CompanyGBP, PlayercommGBP, OddsSpreadCostGBP, OddsBoostBonusGBP
		,TurnoverUSDT, WinlostUSDT, LicenseeWLUSDT, CommBAUSDT, AmtDuetoBAUSDT, CompanyUSDT, PlayercommUSDT, OddsSpreadCostUSDT, OddsBoostBonusUSDT
		,IsShowOddsSpread
		,IsShowOddsBoostBonus
	FROM #Result
	ORDER BY PartyId

	DROP TABLE #Bettype
	DROP TABLE #ExchangeRate
	DROP TABLE #PartyList
	DROP TABLE #Products
	DROP TABLE #Result
	DROP TABLE #tmpParty
	DROP TABLE #tmpWinLoss
END
GO