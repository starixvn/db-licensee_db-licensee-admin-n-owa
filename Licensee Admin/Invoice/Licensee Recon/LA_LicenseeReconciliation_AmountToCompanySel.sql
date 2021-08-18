/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[LA_LicenseeReconciliation_AmountToCompanySel]
	@PartyIds		VARCHAR(4000),
	@FromDate		DATE,
	@ToDate			DATE,
	@BaseCurrency	VARCHAR(5),
	@Environment	VARCHAR(50) = 'DEV',
	@IsShowSettlementDetail	BIT = 0,
	@IsSyncProductWithInvoice BIT = 0,
	@IsGroupByPartyId BIT = 0
AS
/*	Header:
	Task : Generate invoice amount for licensee
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20190723@Bruce: Create Sp [#111586]
		- 20190927@Bruce: Remove prepayment section and Include CardClub [#120220]
		- 20191017@Bruce: Group by party id [#122229]
		- 20191209@Bruce: Include PP tournament [123958]
		- 20200117@Mason: Setup billing terms by Currency  [#120005]
		- 20200309@Parsons: Intergrate SpadeGaming [#123959]
		- 20200316@Parsons: Integrate Virtual Games [#125222]
		- 20200323@Parsons: Intergrate Indo 4D [#130910]
		- 20200412@Parsons: Integrate SA Gaming [#129276]
		- 20200411@Parsons: Integrate Table Games [#131166]
		- 20200422@Parsons: Integrate Saba.club [#132730]
		- 20200507@Parsons: Integrate Sexy Gaming for deposit licensees [#132665]
		- 20200528@Parsons: Special handling for INH market [#128570] 
		- 20200624@Parsons: Keep Negative Licensing Fee for 2 special licensees 9wickets, 9Wsports [#136334] 
		- 20200727@Parsons: Implement PP Jackpot [RedmineID: #137306] 
		- 20200813@Parsons: Implement Group Min Fee [#134492]
		- 20200909@Parsons: Implement PG Soft [RedmineID: #138983]
		- 20200930@Parsons: Implement Joker Games [RedmineID: #141421]
		- 20201104@Parsons: Arcadia Gaming - Add Bonus feature [#143597]
	    - 20201118@Parsons: Changing OddsSpread for licensee [#142345]
	    - 20201217@Parsons: Saba.club - Offer Freebet tickets [#141423]
		- 20201223@Happy: Implement WM [#141357]
		- 20201223@Parsons: Integrate Leap Gaming Virtual Sports [#145339]
		- 20201230@Parsons: Integrate Gold Diamond Gaming [#145340]
		- 20201231@Parsons: Integrate Big Gaming [#145342]
		- 20210106@Happy: Integrate MaxGame [#147375]
	    - 20210201@Parsons: Saba.club - Integrate Slot Game [#147977]
		- 20210406@Parsons: Support duo base currency [RedmineID: #152089]
		- 20210407@Mason: Integrate new Sport Lottery [#150866]
		- 20210407@Percy: Support duo base currency - Change code for Collection Summary [RedmineID: #152089]
		- 20210506@Percy: Integrate
			. Pragmatic Live Casino [RedmineID: #150971]
			. Habanero [RedmineID: #150636]
			. Creative Gaming [RedmineID: #152139]
		- 20210513@Percy: Apply function to get Joint Venture Party List - Keep negative licensee fee [RedmineID: #154992]
		- 20210609@Danny: Support AE Sexy Promotion [RedmineID: #152089]
		- 20210306@Danny: Integrate VGaming [#154080]
		- 20210614@Danny: Integrate AdvantPlay [#154787]
		- 20210614@Danny: Integrate AdvantPlay Mini [#155207]
		- 20210705@Percy: Add ContributionDiscount column [RedmineID: #157549]
		- 20210720@Sophia: Add Saba Promotion - 17005 - Promotion for Licensee [Redmine: #155388]
		- 20210726@Danny: Vgaming - Free bets and Jackpot prize integration [#156185]
		- 20210727@Percy: Return ProductId for Detail Mode [RedmineID: #155593]
		- 20210812@Percy: Integrate Bitcoin - apply core function GroupProduct [RedmineID: #159691]
		- 20210813@Percy: Remove check negative amount of ContributionDiscount [RedmineID: #159294]
*/
BEGIN
	SET NOCOUNT ON

	IF @ToDate > GETDATE() SET @ToDate = GETDATE()

	DECLARE @AmountTypeSoftwareFee INT = 1,
		@AmountTypeDiscount INT = 4,
		@AmountTypeRebate INT = 6,
		@DeductAgainstInvoice INT = 24

	DECLARE @GDTip_ChargeType			SMALLINT = 12
		,@CommissionShare_ChargeType	SMALLINT = 6
		,@CashinShare_ChargeType		SMALLINT = 7
		,@CashoutComm_ChargeType		SMALLINT = 5
		,@SabaPromotion_Bettype			SMALLINT = 17000
		,@PPContribution_Bettype		SMALLINT = 4297
		,@PPJackpotPrize_Bettype		SMALLINT = 4298
		,@PPTournament_Bettype		SMALLINT = 4299
		,@PromotionPrize_Bettype	SMALLINT = 4300
		,@GDTip_Bettype				SMALLINT = 1706
		,@SAGTip_Bettype			SMALLINT = 3007
		,@CC_ArcadiaBonus_Bettype	SMALLINT = 1906
		,@SB_AdjustedOdds_Bettype	SMALLINT = 999
		,@SBC_Contribution SMALLINT = 1698
		,@SBC_JackpotPrize SMALLINT = 1699
		,@SXG_LuckyDraw    SMALLINT = 3150
		,@SPR_SabaPromotion SMALLINT = 17005 
		,@VGA_Contribution SMALLINT = 3898
		,@VGA_JackpotPrize SMALLINT = 3899
		,@BA	SMALLINT = 3
		,@GD	SMALLINT = 11
		,@CB	SMALLINT = 15
		,@CO	SMALLINT = 25
		,@BX	SMALLINT = 31
		,@PP	SMALLINT = 32
		,@CC	SMALLINT = 34
		,@SPR	SMALLINT = 37
		,@SBC	SMALLINT = 42
		,@SXG   SMALLINT = 45
		,@VGA   SMALLINT = 66

/*-----------------
 * Settings
 *-----------------*/
	-- get base currency
	--
	DECLARE @baseCurrencyId INT = (
		SELECT Currencyid 
		FROM OPENQUERY(DBCUST, 'EXEC CustDB.dbo.LA_BaseCurrency_Sel') 
		WHERE CurrencyName = @BaseCurrency
	)

	-- supported products
	CREATE TABLE #Products (GroupProductId INT, ProductId INT, ProductCode VARCHAR(100), ProductName VARCHAR(100))
	INSERT INTO #Products (GroupProductId, ProductId, ProductCode, ProductName)
	SELECT 0, 0, 'SB', 'Sportsbook'
	UNION ALL
	SELECT ISNULL(g.GroupProductId, p.ProductId), p.ProductId, p.ProductPrefix, p.ProductName
	FROM dbo.Product3rd p WITH (NOLOCK)
		LEFT JOIN dbo.LA_f_GroupProduct() g ON p.ProductId = g.ProductId
	WHERE p.ProductId NOT IN (
		1, 4, 7, 9, 12, 14, 17, 30, 33 -- inactive
		,16 -- Hosting (setting only)
		,13, 23 -- BT, NG2
		,46, 47, 50, 52 -- don't offer
	)

	DECLARE @ProductCodes VARCHAR(MAX)
	SELECT  @ProductCodes = COALESCE(@ProductCodes + ',', '') + ProductCode FROM #Products

	-- get party list
	--
	DECLARE @partyList TABLE(PartyId INT, PartyName	VARCHAR(50), LicenseeCode VARCHAR(50), IsSelected BIT, GroupMinFeeId INT)
	-- set selected = true
	-- put each party to its individual group(indicated by -partyid)
	INSERT INTO @partyList(PartyId, PartyName, IsSelected, GroupMinFeeId, LicenseeCode)
	SELECT p.PartyID, p.PartyName
		, 1 AS IsSelected
		, -p.PartyID AS PartyGroupId
		, CASE WHEN ISNULL(bc.LicenseeCode,'') = '' THEN CAST(p.PartyID AS VARCHAR(10)) ELSE UPPER(bc.LicenseeCode) END
	FROM dbo.OAS_Party p WITH(NOLOCK)
	INNER JOIN dbo.OAS_PartyBaseCurrency bc WITH(NOLOCK) ON p.PartyID = bc.PartyID AND FromDate <= @ToDate AND ToDate >= @FromDate
	WHERE p.PartyID IN(SELECT val FROM dbo.strSplit(@PartyIds, ','))

	-- to calculate minfee: need to select all party in same group
	-- get actual party group id
	;WITH cte_GroupMinFeeSetting AS
	(
		SELECT TOP(1) WITH TIES h.GroupMinFeeID, a.PartyID
		FROM @PartyList p
			INNER JOIN dbo.LA_GroupMinFeeAssignment a WITH(NOLOCK) ON p.PartyId = a.PartyId
			INNER JOIN dbo.LA_GroupMinFeeHeader h WITH(NOLOCK) ON a.GroupMinFeeId = h.GroupMinFeeId
		WHERE @FromDate BETWEEN h.FromDate AND h.ToDate
		ORDER BY ROW_NUMBER() OVER(PARTITION BY a.PartyID ORDER BY h.ToDate DESC)
	)
	UPDATE p
	SET GroupMinFeeId = a.GroupMinFeeId
	FROM @PartyList p
	INNER JOIN cte_GroupMinFeeSetting a ON p.PartyId = a.PartyId

	-- include party in same group for minfee calculation
	INSERT INTO @PartyList(PartyId, GroupMinFeeId, IsSelected)
	SELECT DISTINCT a.PartyId, a.GroupMinFeeId,0
	FROM dbo.LA_GroupMinFeeAssignment a WITH(NOLOCK)
		INNER JOIN @PartyList c ON a.GroupMinFeeId = c.GroupMinFeeId
	WHERE NOT EXISTS (SELECT TOP 1 b.PartyId FROM @PartyList b WHERE a.PartyId = b.PartyId)

	-- discount settings
	--
	DECLARE @Rebate INT = 2
	DECLARE @DiscountIndividualFee INT = 1
	DECLARE @DiscountIndividualGrosswin INT = 3
	DECLARE @DiscountByGroupFee INT = 11
	DECLARE @DiscountByGroupGrosswin INT = 13

	-- calculation type
	DECLARE @ToBeDiscounted INT = 0
	DECLARE @ToBeCalculated INT = 1
	DECLARE @CalculateAndDiscount INT = 10
	
	BEGIN
		;WITH cte_DiscountGroup AS(
			SELECT DISTINCT a.DiscountGroupId, a.PartyID
			FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON p.DiscountGroupId=a.DiscountGroupId
			INNER JOIN @partyList b ON a.PartyID=b.PartyId
			WHERE p.ProductId IN (SELECT c.ProductId FROM #Products c)
				AND p.CalculationType IN (@ToBeDiscounted, @CalculateAndDiscount)
		)
		-- put parties in discount group to its own group
		-- put parties of individual discount group to new unique virtual group, indicate by discountid & partyid
		SELECT DISTINCT h.DiscountGroupId, h.DiscountGroupType, a.PartyID, p.ProductId, p.CalculationType, a.IsApplyDiscount, h.CurrencyId, h.FromDate,
			CASE
				WHEN h.DiscountGroupType IN (@DiscountIndividualFee, @DiscountIndividualGrosswin) THEN (CAST(h.DiscountGroupId AS INT) * 100000) + a.PartyID
				ELSE h.DiscountGroupId
			END CalculationGroup
		INTO #tmpDiscountSettings
		FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
		INNER JOIN cte_DiscountGroup c ON c.DiscountGroupId = h.DiscountGroupId
		INNER JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON p.DiscountGroupId = h.DiscountGroupId
		INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
			AND (
				-- discount by group: get all party in same group
				h.DiscountGroupType IN (@DiscountByGroupFee,@DiscountByGroupGrosswin) OR
				-- discount by individual party: get only selected party
				a.PartyID = c.PartyID
			)
		WHERE h.DiscountGroupType != @Rebate AND h.FromDate <= @ToDate AND @FromDate <= h.ToDate

		-- only 1 discount per month for product/party
		-- remove duplicated discount settings
		--
		;WITH cte_Discount AS (
			SELECT DiscountGroupType, PartyID, ProductId, MAX(FromDate) FromDate
			FROM #tmpDiscountSettings
			GROUP BY DiscountGroupType, PartyID, ProductId
			HAVING COUNT(1) > 1
		)
		DELETE d FROM #tmpDiscountSettings d INNER JOIN cte_Discount c ON d.FromDate < c.FromDate
			AND c.PartyID = d.PartyID 
			AND c.ProductId = d.ProductId
			AND c.DiscountGroupType = d.DiscountGroupType

		-- include more parties from discount settings
		--
		INSERT INTO @partyList(PartyId,GroupMinFeeId,IsSelected)
		SELECT DISTINCT a.PartyID, -a.PartyID, 0
		FROM #tmpDiscountSettings a
		LEFT JOIN @partyList b ON a.PartyID = b.PartyId
		WHERE b.PartyId IS NULL AND a.CalculationType IN (@ToBeCalculated, @CalculateAndDiscount)

		-- discount by currency
		DECLARE @tmpDiscountCurrency TABLE(DiscountGroupId SMALLINT, PartyId INT, CurrencyId INT)

		INSERT INTO @tmpDiscountCurrency(DiscountGroupId, PartyId, CurrencyId)
		SELECT c.DiscountGroupId, c.PartyID, c.CurrencyId
		FROM dbo.LA_DiscountGroupCurrency c WITH(NOLOCK)
		WHERE c.DiscountGroupId IN (SELECT DISTINCT d.DiscountGroupId FROM #tmpDiscountSettings d)
	END

	-- update party list id
	--
	SET @PartyIds = NULL
	SELECT @PartyIds = COALESCE((@PartyIds + ',' + CAST(PartyId AS VARCHAR(10))), CAST(PartyId AS VARCHAR(10)))
	FROM (SELECT DISTINCT b.PartyId FROM @partyList b) a

	-- charge info
	--
	SELECT DISTINCT ci.ChargeId ,ci.PartyID, ci.LicenseeID, ci.ProductID, CAST(ci.DI_Rate AS DECIMAL(6,5)) AS Rate, ci.Fromdate, ci.ToDate,ci.ChargeType
	INTO #tmpChargeInfo
	FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
	WHERE DI_Rate > 0

	CREATE INDEX IX_tmpChargeInfo ON #tmpChargeInfo(LicenseeID, ProductID)

	 -- exchange
	SELECT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate
	INTO #tmpExchange
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrency)
	WHERE ExchangeDate BETWEEN @FromDate AND @ToDate

	CREATE INDEX IX_tmpExchange ON #tmpExchange(ExchangeDate)

	-- minfee settings
	--
	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FromDate), 0)
	DECLARE @LastDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FromDate) + 1, 0))
	DECLARE @Month TINYINT = MONTH(@FromDate)
	DECLARE @DaysInMonth INT = DATEDIFF(DAY, @FirstDate, @LastDate) + 1

	DECLARE @tmpMinFee TABLE (
		FeeType			TINYINT,
		PartyId			INT,
		ProductId		INT,
		CurrencyId		INT,
		FeeAmount		MONEY,
		FromDate		DATETIME,
		ToDate			DATETIME,
		FeeUnderWaiveTime MONEY,
		FeeOutOfWaiveTime MONEY,
		MinFeeAmount	MONEY,
		MinFeeId		INT
	)

	BEGIN
		-- minfee
		INSERT INTO @tmpMinFee(FeeType ,PartyId,ProductId, CurrencyId ,FeeAmount ,FromDate ,ToDate, MinFeeId, FeeUnderWaiveTime, FeeOutOfWaiveTime)
		SELECT mf.FeeTypeId,
			mf.PartyId,
			mf.ProductId,
			mf.CurrencyId,
			mf.FeeAmount,
			CASE WHEN @FromDate >= mf.FromDate THEN @FromDate ELSE mf.FromDate END AS FromDate,
			CASE WHEN @ToDate < mf.ToDate THEN @ToDate ELSE mf.ToDate END AS ToDate,
			mf.MinFeeId,
			0,0
		FROM dbo.LA_MinFee mf WITH(NOLOCK)
		INNER JOIN @partyList p ON mf.PartyId = p.PartyId
		INNER JOIN #Products c ON mf.ProductId=c.ProductID
		WHERE mf.FeeTypeId = 1 AND @FromDate <= mf.ToDate AND mf.FromDate <= @ToDate

		-- waive
		INSERT INTO @tmpMinFee(FeeType ,PartyId,ProductId, FromDate ,ToDate, MinFeeId)
		SELECT w.FeeTypeId,
			w.PartyId,
			w.ProductId,
			CASE WHEN w.FromDate < m.FromDate THEN m.FromDate ELSE w.FromDate END,
			CASE WHEN w.ToDate > m.ToDate THEN m.ToDate ELSE w.ToDate END,
			m.MinFeeId
		FROM dbo.LA_MinFee w WITH(NOLOCK)
		INNER JOIN @tmpMinFee m ON w.PartyId=m.PartyId AND w.ProductId=m.ProductId
		WHERE w.FeeTypeId = 2 AND w.FromDate <= m.ToDate AND m.FromDate <= w.ToDate

		-- exchange minfee amount to base currency
		UPDATE m SET m.FeeAmount = m.FeeAmount * e.Rate
		FROM @tmpMinFee m
		INNER JOIN #tmpExchange e ON m.ToDate = e.ExchangeDate AND m.CurrencyId = e.ExchangeID

		-- calculate minfee amount(exclude waive time)
		-- (days in charged - days in waived) * FeeAmount / days in month
		;WITH waivedDays AS (
			SELECT MinFeeId, SUM(DATEDIFF(DAY, FromDate,ToDate) + 1) WaivedDays
			FROM @tmpMinFee WHERE FeeType = 2 GROUP BY MinFeeId
		)
		UPDATE m SET m.MinFeeAmount = ((DATEDIFF(DAY, m.FromDate,m.ToDate) + 1) - ISNULL(w.WaivedDays,0)) * CAST(m.FeeAmount AS DECIMAL(20,10)) / @DaysInMonth
		FROM @tmpMinFee m
		LEFT JOIN waivedDays w ON m.MinFeeId=w.MinFeeId
		WHERE m.FeeType = 1
	END
/*-----------------
 * Winloss data
 *-----------------*/
	BEGIN
		CREATE TABLE #tmpBettingByProduct (rptDate DATETIME, SiteId INT, ProductId INT, Bettype INT, CurrencyId INT, TicketType TINYINT
			,CommissionA MONEY, CommissionP MONEY, WinPrizeAmount MONEY, CashOutAmount MONEY, BuyBackAmount MONEY
			,Turnover MONEY, LicWinloss MONEY, GrossWL MONEY, TurnoverForCommision MONEY)

		CREATE CLUSTERED INDEX IX_tmpBettingByProduct ON #tmpBettingByProduct(rptDate, SiteId, ProductId)

		INSERT INTO #tmpBettingByProduct (rptDate, SiteId, ProductId, Bettype, CurrencyId, TicketType
			,CommissionA, CommissionP, WinPrizeAmount, CashOutAmount, BuyBackAmount, Turnover, LicWinloss, GrossWL, TurnoverForCommision)
		SELECT b.rptDate,b.SiteId,p.GroupProductId,b.Bettype,b.CurrencyId,ISNULL(b.TicketType, 0)
			,SUM(ISNULL(b.CommissionA, 0))
			,SUM(ISNULL(b.CommissionP, 0))
			,SUM(ISNULL(b.WinPrizeAmount, 0))
			,SUM(ISNULL(b.CashOutAmount, 0))
			,SUM(ISNULL(b.BuyBackAmount, 0))
			,SUM(ISNULL(b.Turnover, 0))
			,SUM(ISNULL(-b.MemberWL, 0)) AS LicWinloss
			,SUM(CASE WHEN b.Bettype IN (999, 1698, 4297, 17005, 3898) THEN ISNULL(-b.GrossWL, 0) ELSE 0 END) AS GrossWL
			,SUM(CASE WHEN ISNULL(b.TicketType, 0) = 0 THEN ISNULL(b.Turnover, 0) ELSE ISNULL(b.ExtraAmount, 0) END) AS TurnoverForCommision
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #Products p ON b.ProductId = p.ProductId
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.SiteID IN (SELECT DISTINCT c.LicenseeID FROM #tmpChargeInfo c)
			AND b.customercategory NOT IN (27, 28)
			AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
		GROUP BY b.rptDate,b.SiteId,p.GroupProductId,b.Bettype,b.CurrencyId,ISNULL(b.TicketType, 0)

		-- calculate amount to company
		-- excludes: golddeluxe bidme tip, PP JP & Prize, colossus bet
		--
		CREATE TABLE #tmpWinlossData (rptDate DATETIME, PartyId INT, ProductId INT, CurrencyId INT
			, Winloss MONEY, AmountToCompany MONEY, Promotion MONEY, ExtraAmount MONEY, Contribution MONEY, ContributionDiscount MONEY, JackPotPrize MONEY, PromotionPrize MONEY)
		
		INSERT INTO #tmpWinlossData (rptDate, PartyId, ProductId, CurrencyId, Winloss, AmountToCompany, Promotion, ExtraAmount, Contribution, ContributionDiscount, JackPotPrize, PromotionPrize)
		SELECT b.rptDate, p.PartyId, p.ProductId, b.CurrencyId
			,SUM((b.LicWinloss + (CASE WHEN b.ProductID = 31 THEN b.CommissionA ELSE 0 END)) * e.Rate) AS Winloss
			,SUM((((b.LicWinloss - CASE WHEN b.ProductID IN (32, 42, 66) THEN GrossWL ELSE 0 END) * ISNULL(cr.Rate, p.Rate) - 
				(CASE
					WHEN b.ProductID = 3 THEN ISNULL(b.CommissionA, 0)
					WHEN b.ProductID = 31 THEN (b.CommissionA + b.CommissionP)
					ELSE 0
				END)
				) + CASE WHEN b.ProductID = 0 THEN GrossWL ELSE 0 END) * e.Rate) AS AmountToCompany
			,0 AS Promotion
			,0 AS ExtraAmount
			,0 AS Contribution
			,0 AS ContributionDiscount
			,0 AS JackPotPrize
			,0 AS PromotionPrize
		FROM #tmpBettingByProduct b
		INNER JOIN #tmpChargeInfo p ON b.ProductId = p.ProductID AND p.LicenseeId = b.SiteId AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
		INNER JOIN #tmpExchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
		LEFT JOIN LA_ChargeRateByCurrency cr WITH (NOLOCK) ON p.ChargeId = cr.ChargeId AND b.CurrencyId = cr.CurrencyId
		LEFT JOIN LA_f_ExcludedBettypeListSel('11,32,34,39,42,45,66', '4297,1698,3898') eb ON b.Bettype = eb.BettypeID
		WHERE p.ChargeType NOT IN (
				@CashoutComm_ChargeType,
				@CommissionShare_ChargeType,
				@CashinShare_ChargeType,
				@GDTip_ChargeType
			)
			AND eb.BettypeID IS NULL
			AND	b.TicketType <> 2 -- Free_Bets_TicketType 
		GROUP BY b.rptDate, p.PartyId, p.ProductId, b.CurrencyId
		-- includes extra values: gdtip, PP JP & Prize
		--
		INSERT INTO #tmpWinlossData (rptDate, PartyId, ProductId, CurrencyId, Winloss, AmountToCompany, ExtraAmount, Promotion, Contribution, ContributionDiscount, JackPotPrize, PromotionPrize)
		SELECT b.rptDate, p.PartyId, p.ProductId, b.CurrencyId
			,0 AS Winloss
			,0 AS AmountToCompany
			,SUM(CASE WHEN b.Bettype IN (1706, 3007) THEN b.LicWinloss * ISNULL(cr.Rate, p.Rate) * e.Rate ELSE 0 END) ExtraAmount
			,SUM(CASE WHEN b.ProductId = 37 THEN CASE WHEN b.Bettype = 17005 THEN -b.GrossWL ELSE -b.LicWinloss END * e.Rate ELSE 0 END) Promotion
			,SUM(CASE WHEN b.ProductId <> 37 THEN b.GrossWL ELSE 0 END * e.Rate) AS Contribution
			,SUM(CASE WHEN b.ProductId <> 37 THEN b.GrossWL ELSE 0 END * ISNULL(cr.Rate, p.Rate) * e.Rate) AS ContributionDiscount
			,SUM(CASE WHEN b.Bettype IN (4298, 1699, 3899) THEN -b.LicWinloss * e.Rate ELSE 0 END) JackPotPrize
			,SUM(CASE WHEN b.TicketType = 2 OR b.Bettype IN (4299, 4300, 1906, 3150) THEN -b.LicWinloss * e.Rate ELSE 0 END) PromotionPrize
		FROM #tmpBettingByProduct b
		INNER JOIN #tmpChargeInfo p ON p.LicenseeId = b.SiteId AND b.ProductId = (CASE WHEN p.ProductID = 0 THEN @SPR ELSE p.ProductID END)
		LEFT JOIN LA_ChargeRateByCurrency cr WITH (NOLOCK) ON p.ChargeId = cr.ChargeId AND b.CurrencyId = cr.CurrencyId
		INNER JOIN #tmpExchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
		LEFT JOIN LA_f_ExcludedBettypeListSel('11,32,34,39,42,45,66', '') eb ON b.Bettype = eb.BettypeID
		WHERE b.rptDate BETWEEN p.FromDate AND p.ToDate
			AND (p.ProductID IN (0, @PP, @CC, @SBC, @SXG, @VGA) OR p.ChargeType = @GDTip_ChargeType)
			AND (b.ProductID = 37 OR eb.BettypeID IS NOT NULL OR b.TicketType = 2)
		GROUP BY b.rptDate, p.PartyId, p.ProductId, b.CurrencyId

		-- CB
		BEGIN
			SELECT cb.PartyID,b.rptdate,b.CurrencyId,  
				SUM(ISNULL(TurnoverForCommision,0)) TurnoverForCommision,  
				SUM(ISNULL(WinPrizeAmount,0)) WinningPrize,  
				SUM(ISNULL(CashOutAmount,0)) CashoutAmount,  
				SUM(ISNULL(BuyBackAmount,0)) CashInAmount,  
				SUM(ISNULL(Turnover,0)) Turnover,  
				CAST(0 AS MONEY) AS CommisionShare,  
				CAST(0 AS MONEY) AS CashoutShare  
			INTO #tmpDataCB  
			FROM #tmpBettingByProduct b  
			JOIN #tmpChargeInfo cb ON b.SiteID = cb.LicenseeId AND b.ProductId = cb.ProductID AND b.rptDate BETWEEN cb.FromDate AND cb.ToDate  
			WHERE b.ProductId = @CB AND cb.ChargeType= @CommissionShare_ChargeType -- to remove duplicate we use one of (6,7)  
			GROUP BY b.rptdate, b.CurrencyId, cb.PartyID  

			UPDATE #tmpDataCB SET  
				CommisionShare = td.TurnoverForCommision * cm.Rate,  
				CashoutShare = td.CashInAmount * ci.Rate  
			FROM #tmpDataCB td  
			JOIN #tmpChargeInfo AS cm ON cm.ProductID = @CB AND cm.ChargeType = @CommissionShare_ChargeType 
				AND (td.rptDate BETWEEN cm.FromDate AND cm.ToDate) AND cm.PartyID = td.PartyID
			JOIN #tmpChargeInfo AS ci ON cm.ProductID = @CB AND ci.ChargeType = @CashinShare_ChargeType 
				AND (td.rptDate BETWEEN ci.FromDate AND ci.ToDate) AND ci.PartyID = td.PartyID

			INSERT INTO #tmpWinlossData(PartyID,rptDate,ProductID,CurrencyId,Winloss,ExtraAmount,AmountToCompany)  
			SELECT PartyID, @FromDate, @CB,0,0,0
				,SUM((Turnover - WinningPrize - CashoutAmount - CommisionShare - CashoutShare) * e.Rate)  
			FROM #tmpDataCB tcb  
			INNER JOIN #tmpExchange e ON tcb.rptDate = e.ExchangeDate AND tcb.CurrencyId = e.ExchangeID  
			GROUP BY PartyID  

			DROP TABLE #tmpDataCB  
		END
		
		-- CO  
		BEGIN
			INSERT INTO #tmpWinlossData(PartyID,rptDate,ProductID,CurrencyId,Winloss,ExtraAmount,AmountToCompany)  
			SELECT d.PartyID,@FromDate,@CO,0,0,0
				,SUM((TicketsPayout - BuyBackAmountSB - BuyBackAmountBA - CashoutCommission) * e.Rate)  
			FROM (  
				SELECT p.PartyID, b.Winlostdate, b.Currency,  
					SUM(b.BuyBackAmt) AS BuyBackAmountSB,  
					SUM(b.BABuyBackAmt) AS BuyBackAmountBA,  
					SUM(b.TicketPayout) AS TicketsPayout,  
					SUM(b.BuyBackAmt * p.Rate) AS CashoutCommission  
				FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)  
				INNER JOIN #tmpChargeInfo p ON b.SiteId = p.LicenseeId AND b.ProductId = p.ProductID AND b.Winlostdate BETWEEN p.FromDate AND p.ToDate  
				WHERE b.Winlostdate BETWEEN @FromDate AND @ToDate  
					AND b.ProductID = @CO  
					AND b.Currency <> 20  
					AND b.RoleID = 1 -- Member Level  
				GROUP BY p.PartyID, b.Winlostdate, b.Currency  
			) d  
			INNER JOIN #tmpExchange e ON d.Winlostdate = e.ExchangeDate AND d.Currency = e.ExchangeID  
			GROUP BY d.PartyID  

			-- insert product don't have any ticket  
			INSERT INTO #tmpWinlossData (PartyID,rptDate,ProductID,CurrencyId,Winloss,AmountToCompany,ExtraAmount)  
			SELECT DISTINCT p.PartyId,@ToDate,c.ProductId,6, 0,0,0-- default eur = 6  
			FROM @partyList p   
			INNER JOIN #Products pd ON 1=1  
			INNER JOIN dbo.OAS_ChargeInfo c WITH(NOLOCK) ON c.ProductID = pd.ProductID AND p.PartyId = c.FromParty  
			WHERE c.ToDate >= @FromDate  
		END
		 
		-- create result table
		--
		SELECT a.PartyID,a.ProductId
			,CAST(SUM(ISNULL(a.AmountToCompany,0)) AS MONEY)	AmountToCompany
			,SUM(ISNULL(a.ExtraAmount,0))						ExtraAmount
			,SUM(ISNULL(a.Promotion,0))							Promotion
			,SUM(ISNULL(a.Contribution,0))					    Contribution
			,SUM(ISNULL(a.ContributionDiscount,0))				ContributionDiscount
			,SUM(ISNULL(a.JackPotPrize,0))						JackPotPrize
			,SUM(ISNULL(a.PromotionPrize,0))					PromotionPrize
			,CAST(SUM(ISNULL(a.Winloss,0)) AS MONEY)			Winloss
			,CAST(0 AS MONEY) LicensingFee
			,CAST(0 AS MONEY) Discount
			,CAST(0 AS MONEY) Rebate
			,CAST(0 AS MONEY) MinFee
			,CAST(0 AS BIT) IsApplyMinfeeToDiscount
		INTO #tmpResult
		FROM #tmpWinlossData a  
		GROUP BY a.PartyID, a.ProductId

		-- treat negative LicensingFee as 0, except Joint Venture Parties or BA, CB, CO, BX
		UPDATE r
		SET r.LicensingFee = CASE WHEN r.AmountToCompany < 0 AND jvp.PartyId IS NULL AND r.ProductID NOT IN (@BA,@CB,@CO,@BX) THEN 0 ELSE r.AmountToCompany END
		FROM #tmpResult r
			LEFT JOIN dbo.LA_f_JVPartyListSel() jvp ON r.PartyId = jvp.PartyId
	END
/*-----------------
 * minfee
 *-----------------*/
IF @IsShowSettlementDetail = 0
BEGIN
	-- sum data to 2 parts
	--
	-- 1. under waive time
	-- 2. out of waive time
	;WITH Fee AS(
		SELECT m.MinFeeId
			, SUM(CASE WHEN w.ProductId IS NULL THEN 0 ELSE t.AmountToCompany END) FeeUnderWaiveTime
			, SUM(CASE WHEN w.ProductId IS NULL THEN t.AmountToCompany ELSE 0 END) FeeOutOfWaiveTime
		FROM #tmpWinlossData t
		INNER JOIN @tmpMinFee m ON t.ProductId = m.ProductId AND t.PartyId = m.PartyId AND t.rptDate BETWEEN m.FromDate AND m.ToDate
		LEFT JOIN @tmpMinFee w ON w.FeeType=2 AND w.MinFeeId=m.MinFeeId AND t.rptDate BETWEEN w.FromDate AND w.ToDate
		WHERE m.FeeType=1
		GROUP BY  m.MinFeeId
	)
	UPDATE mf SET
		FeeUnderWaiveTime = CASE WHEN f.FeeUnderWaiveTime < 0 THEN 0 ELSE f.FeeUnderWaiveTime END,
		FeeOutOfWaiveTime = CASE WHEN f.FeeOutOfWaiveTime < 0 THEN 0 ELSE f.FeeOutOfWaiveTime END
	FROM @tmpMinFee mf INNER JOIN Fee f ON mf.MinFeeId=f.MinFeeId
	WHERE mf.FeeType=1

	-- calculate total minfee by group
	DECLARE @TotalMinFees TABLE(GroupMinFeeId INT, ProductId INT, TotalMinFee MONEY)
	
	INSERT INTO @TotalMinFees(GroupMinFeeId, ProductId, TotalMinFee)
	SELECT TOP(1) WITH TIES mfd.GroupMinFeeID, ProductId, mfd.MinimumFee * e.Rate AS GroupMinFee
	FROM dbo.LA_GroupMinFeeDetail mfd WITH(NOLOCK)
		INNER JOIN @PartyList p ON mfd.GroupMinFeeID = p.GroupMinFeeId
		INNER JOIN #tmpExchange e ON e.ExchangeId = mfd.CurrencyId AND e.exchangedate = @ToDate
	WHERE @FromDate BETWEEN mfd.FromDate AND mfd.ToDate
	ORDER BY ROW_NUMBER() OVER(PARTITION BY mfd.GroupMinFeeID order by mfd.ToDate DESC)

	-- apply minfee if amount to company do not reach the goal
	-- 3.3.1 actual licensing fee as usual	
	UPDATE r SET LicensingFee = CASE
			WHEN p.GroupMinFeeId <= 0 AND a.FeeOutOfWaiveTime < a.MinFeeAmount
				THEN a.MinFeeAmount + a.FeeUnderWaiveTime
			ELSE a.FeeOutOfWaiveTime + a.FeeUnderWaiveTime
		END,
		IsApplyMinfeeToDiscount = CASE
			WHEN a.MinFeeAmount < a.FeeAmount AND a.FeeAmount > 0 AND b.FeeType IS NOT NULL THEN 0-- waived
			WHEN p.GroupMinFeeID > 0 THEN 0 -- reach group minfee goal
			ELSE 1 END,
		Minfee = a.MinFeeAmount
	FROM #tmpResult r
	INNER JOIN @partyList p ON r.PartyId=p.PartyId
	INNER JOIN @tmpMinFee a ON a.PartyId = r.PartyId AND a.ProductId=r.ProductID AND a.FeeType = 1 -- minfee setting
	LEFT JOIN @tmpMinFee b ON b.PartyId = r.PartyId AND b.ProductId=r.ProductID AND b.FeeType = 2-- waive setting

	-- 3.3.2 Update licensing fee of primary licensee
	;WITH cte_TotalAmount AS 
	(
		SELECT p.GroupMinFeeId, r.ProductId, SUM(r.LicensingFee) AS TotalAmount
		FROM #tmpResult r
		INNER JOIN @PartyList p ON r.PartyId = p.PartyId
		INNER JOIN @TotalMinFees t ON p.GroupMinFeeId = t.GroupMinFeeId AND r.ProductId = t.ProductId
		WHERE p.GroupMinFeeId > 0
		GROUP BY p.GroupMinFeeId, r.ProductId
	),
	cte_DifferentAmount AS
	(
		SELECT t.GroupMinFeeId , r.ProductId, (t.TotalMinFee - r.TotalAmount) DifferentAmount
		FROM cte_TotalAmount r
		INNER JOIN @TotalMinFees t ON r.GroupMinFeeId = t.GroupMinFeeId
		WHERE r.TotalAmount < t.TotalMinFee
	)
	UPDATE r
	SET r.LicensingFee += d.DifferentAmount
	FROM #tmpResult r
	INNER JOIN LA_GroupMinFeeAssignment a WITH(NOLOCK) ON r.PartyId = a.PartyID
	INNER JOIN cte_DifferentAmount d ON a.GroupMinFeeID = d.GroupMinFeeId AND r.ProductId = d.ProductId
	WHERE a.IsPrimary = 1
END
/*-----------------
 * discount
 *-----------------*/
	DECLARE @Unlimited MONEY = 1000000000000
	DECLARE @tmpDiscountCalculation TABLE(
		CalculationGroup	INT,
		DiscountGroupId		SMALLINT,
		DiscountGroupType	TINYINT,
		CurrencyId			INT,
		Winloss				MONEY,
		Fee 				MONEY
	)
IF @IsShowSettlementDetail = 0
BEGIN
	-- discount by all currency
	INSERT INTO @tmpDiscountCalculation(CalculationGroup,DiscountGroupId,DiscountGroupType,CurrencyId,Winloss,Fee)
	SELECT s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId, SUM(r.Winloss) Winloss,SUM(r.LicensingFee) Fee
	FROM #tmpDiscountSettings s
	INNER JOIN @tmpDiscountCurrency c ON s.PartyId = c.PartyId AND c.DiscountGroupId=s.DiscountGroupId AND c.CurrencyId = 0 -- all currency
	INNER JOIN #tmpResult r ON s.PartyID = r.PartyId AND s.ProductId=r.ProductId
	WHERE s.CalculationType IN (@ToBeCalculated,@CalculateAndDiscount)
	GROUP BY s.DiscountGroupId, s.DiscountGroupType,s.CurrencyId,s.CalculationGroup

	-- discount by currency
	-- only offer this kind of discount for SB & licensing fee
	INSERT INTO @tmpDiscountCalculation(CalculationGroup,DiscountGroupId,DiscountGroupType,CurrencyId,Winloss,Fee)
	SELECT s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId, SUM(r.Winloss) Winloss,SUM(r.AmountToCompany) Fee
	FROM #tmpWinlossData r
	INNER JOIN @tmpDiscountCurrency c ON c.PartyID=r.PartyId AND c.CurrencyId=r.CurrencyId
	INNER JOIN #tmpDiscountSettings s ON s.DiscountGroupId=c.DiscountGroupId AND s.ProductId = r.ProductId AND s.PartyId = c.PartyId
	WHERE s.CalculationType IN (@ToBeCalculated,@CalculateAndDiscount)
		AND s.DiscountGroupType IN (@DiscountIndividualFee, @DiscountByGroupFee)
	GROUP BY s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId

	DECLARE @Rate TABLE(Rate DECIMAL(6,5), CalculationGroup INT, DiscountGroupType INT)
	
	-- get rate
	;WITH cte_Detail AS(
		SELECT c.CalculationGroup, d.DiscountGroupId, d.Rate
			,ISNULL(d.FromAmount,0) * e.Rate AS FromAmount
			,CASE WHEN d.ToAmount > @Unlimited THEN d.ToAmount ELSE (d.ToAmount + 1) * e.Rate END AS ToAmount
		FROM dbo.LA_DiscountGroupDetail d WITH(NOLOCK)
		INNER JOIN @tmpDiscountCalculation c ON d.DiscountGroupId=c.DiscountGroupId
		INNER JOIN #tmpExchange e ON e.ExchangeId = c.CurrencyId AND e.exchangedate=@ToDate
	)
	INSERT INTO @Rate(rate, CalculationGroup,DiscountGroupType)
	SELECT d.Rate, c.CalculationGroup, c.DiscountGroupType
	FROM 
		(SELECT CalculationGroup, DiscountGroupType, SUM(Fee) Fee, SUM(Winloss) Winloss FROM @tmpDiscountCalculation GROUP BY CalculationGroup, DiscountGroupType) c 
	INNER JOIN cte_Detail d ON c.CalculationGroup=d.CalculationGroup
	WHERE (
			c.DiscountGroupType IN (@DiscountByGroupFee, @DiscountIndividualFee) AND
			c.Fee >= d.FromAmount AND c.Fee < d.ToAmount
		) OR (
			c.DiscountGroupType IN (@DiscountByGroupGrosswin, @DiscountIndividualGrosswin) AND
			c.Winloss >= d.FromAmount AND c.Winloss < d.ToAmount
		)

	-- discount by all currencies
	--
	UPDATE r SET Discount = CASE
			WHEN s.DiscountGroupType IN (@DiscountByGroupFee, @DiscountIndividualFee) THEN c.Rate * r.LicensingFee
			WHEN s.DiscountGroupType IN (@DiscountByGroupGrosswin, @DiscountIndividualGrosswin) THEN c.Rate * (CASE WHEN r.Winloss < 0 THEN 0 ELSE r.Winloss END)
		ELSE 0 END
	FROM #tmpResult r
	INNER JOIN #tmpDiscountSettings s ON s.PartyID = r.PartyId AND s.ProductId=r.ProductId
	INNER JOIN @Rate c ON c.CalculationGroup = s.CalculationGroup
	WHERE s.CalculationType IN (@ToBeDiscounted,@CalculateAndDiscount) 
		AND s.IsApplyDiscount = 1

	-- discount by curency
	--
	-- not support gross win
	-- not support multiple products
	-- not discount if fee after discount less than minfee
	;WITH cte_Fee AS
	(
		SELECT r.PartyID, r.ProductID, SUM(r.AmountToCompany) as FeeBase
		FROM #tmpWinlossData r
		INNER JOIN @tmpDiscountCurrency c ON c.PartyID = r.PartyId AND c.CurrencyId = r.CurrencyId
		INNER JOIN #tmpDiscountSettings s ON s.DiscountGroupId = c.DiscountGroupId AND s.ProductId = r.ProductId AND s.PartyId = c.PartyId
		WHERE s.CalculationType IN (@ToBeCalculated,@CalculateAndDiscount)
			AND s.DiscountGroupType IN (@DiscountIndividualFee, @DiscountByGroupFee)
		GROUP BY r.PartyID,  r.ProductID
	),
	cte_DiscountByCurrency AS 
	(
		SELECT t.PartyId, f.ProductId, r.Rate, r.Rate * (CASE WHEN f.FeeBase < 0 THEN 0 ELSE f.FeeBase END) Discount 
		FROM #tmpDiscountSettings t
		INNER JOIN @rate r ON r.CalculationGroup = t.CalculationGroup
		INNER JOIN cte_Fee f ON t.PartyId = f.PartyId
	)
	UPDATE r SET Discount = CASE WHEN (r.LicensingFee - d.Discount) < r.Minfee AND r.IsApplyMinfeeToDiscount = 1 THEN r.LicensingFee - r.Minfee ELSE d.Discount END
	FROM #tmpResult r
	INNER JOIN cte_DiscountByCurrency d on r.PartyID = d.PartyID AND r.ProductID=d.ProductId
	WHERE d.Discount > 0

	-- apply new discount term for licensee have not shared minfee
	-- fee after discount must >= minfee
	DECLARE @ApplyMinfeeToDiscountDate DATE = dbo.LA_f_ApplyDiscountMinfeeDate()
	
	IF (@FromDate >= @ApplyMinfeeToDiscountDate)
	BEGIN
		UPDATE #tmpResult SET Discount = LicensingFee - Minfee WHERE (LicensingFee - Discount) < Minfee AND IsApplyMinfeeToDiscount = 1
	END
	
	UPDATE #tmpResult SET Discount = 0 WHERE Discount <= 0 OR (LicensingFee - Discount) < 0

	-- Region: Adjust Discount of primary licensee to be make sure that (TotalFee - TotalDiscount) >= cte.TotalMinFee  
	;WITH cte_tmpDiscountGroupMinFee AS 
	(
		SELECT p.GroupMinFeeId, r.ProductId, t.TotalMinFee, SUM(r.LicensingFee) AS TotalFee, SUM(r.Discount) AS TotalDiscount
		FROM #tmpResult r
		INNER JOIN @PartyList p ON r.PartyId = p.PartyId
		INNER JOIN @TotalMinFees t ON p.GroupMinFeeId = t.GroupMinFeeId AND r.ProductId = t.ProductId
		WHERE p.GroupMinFeeId > 0
		GROUP BY p.GroupMinFeeId, r.ProductId, t.TotalMinFee
	)
	UPDATE r
	SET r.Discount = cte.TotalFee - (cte.TotalDiscount - r.Discount) - cte.TotalMinFee
	FROM #tmpResult r
	INNER JOIN @PartyList p ON r.PartyId = p.PartyId
	INNER JOIN cte_tmpDiscountGroupMinFee cte ON p.GroupMinFeeId = cte.GroupMinFeeId AND r.ProductId = cte.ProductId
	INNER JOIN LA_GroupMinFeeAssignment a WITH(NOLOCK) ON r.PartyId = a.PartyID
	WHERE a.IsPrimary = 1 AND Discount > 0 AND (cte.TotalFee - cte.TotalDiscount) < cte.TotalMinFee
	-- End-Region: Adjust Discount of primary licensee to be make sure that (TotalFee - TotalDiscount) >= cte.TotalMinFee 

	UPDATE #tmpResult SET Discount = 0 WHERE Discount <= 0 OR (LicensingFee - Discount) < 0

	-- Region: Case 3: One of Licensee in the group has discount. It makes the total licensing fee of the group is less than group min fee.  
	;WITH cte_TotalAmount AS 
	(
		SELECT p.GroupMinFeeId, r.ProductId, SUM(r.LicensingFee - Discount) AS TotalAmount
		FROM #tmpResult r
		INNER JOIN @PartyList p ON r.PartyId = p.PartyId
		INNER JOIN @TotalMinFees t ON p.GroupMinFeeId = t.GroupMinFeeId AND r.ProductId = t.ProductId
		WHERE p.GroupMinFeeId > 0
		GROUP BY p.GroupMinFeeId, r.ProductId
	),
	cte_DifferentAmount AS
	(
		SELECT t.GroupMinFeeId , r.ProductId, (t.TotalMinFee - r.TotalAmount) DifferentAmount
		FROM cte_TotalAmount r
		INNER JOIN @TotalMinFees t ON r.GroupMinFeeId = t.GroupMinFeeId
		WHERE r.TotalAmount < t.TotalMinFee
	)
	UPDATE r
	SET r.LicensingFee += d.DifferentAmount
	FROM #tmpResult r
	INNER JOIN LA_GroupMinFeeAssignment a ON r.PartyId = a.PartyID
	INNER JOIN cte_DifferentAmount d ON a.GroupMinFeeID = d.GroupMinFeeId AND r.ProductId = d.ProductId
	WHERE a.IsPrimary = 1
	-- EndRegion: Case 3: One of Licensee in the group has discount. It makes the total licensing fee of the group is less than group min fee.  
END
/*-----------------
 * Rebate
 *-----------------*/
IF @IsShowSettlementDetail = 0
BEGIN
	-- get rebate settings
	DECLARE @tmpRebateSettings TABLE(PartyId INT, ProductId INT, Rate DECIMAL(7,5), FromDate DATE)
	
	INSERT INTO @tmpRebateSettings(PartyId, ProductId, Rate, FromDate)
	SELECT a.PartyID, p.ProductId, d.Rate, h.FromDate
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
	INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON h.DiscountGroupId = a.DiscountGroupId
	INNER JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON p.DiscountGroupId = h.DiscountGroupId
	INNER JOIN dbo.LA_DiscountGroupDetail d WITH(NOLOCK) ON d.DiscountGroupId = h.DiscountGroupId
	INNER JOIN @PartyList l ON l.PartyId = a.PartyID AND l.IsSelected = 1
	WHERE h.DiscountGroupType=@Rebate
		AND h.FromDate <= @ToDate
		AND h.ToDate >= @FromDate

	-- only 1 rebate per month for product/party
	;WITH cte_Rebate AS (
		SELECT PartyID, ProductId, MAX(FromDate) FromDate
		FROM @tmpRebateSettings
		GROUP BY PartyID, ProductId
		HAVING COUNT(1) > 1
	)
	DELETE r FROM @tmpRebateSettings r INNER JOIN cte_Rebate c ON r.FromDate < c.FromDate
		AND c.PartyID = r.PartyID 
		AND c.ProductId = r.ProductId

	-- calculate rebate
	UPDATE r SET Rebate = (r.LicensingFee - r.Discount) * c.Rate
	FROM #tmpResult r INNER JOIN @tmpRebateSettings c ON r.PartyId = c.PartyID AND r.ProductId = c.ProductId
END
/*-----------------
 * get issued invoice
 *-----------------*/
 IF @IsSyncProductWithInvoice = 1
 BEGIN
	-- invoice header
	--
	SELECT h.PartyId, s.ProductId INTO #productFees
	FROM dbo.LA_InvoiceHeader h WITH(NOLOCK)
	INNER JOIN dbo.LA_InvoiceStatement s WITH(NOLOCK) ON h.InvoiceHeaderId=s.InvoiceHeaderId
	WHERE h.StatusId = 0-- normal invoice
		AND h.Environment = @Environment
		AND h.PartyId IN (SELECT p.PartyId FROM @partyList p WHERE p.IsSelected = 1)
		AND h.FromDate <= @FromDate AND h.ToDate >=@ToDate
		AND s.InvItemTypeId=1 -- software data fee
	GROUP BY h.PartyId, s.ProductId

	-- Sync re-calculated product
	--
	UPDATE r SET 
		 AmountToCompany = (r.AmountToCompany + r.ExtraAmount)
		,ExtraAmount = 0
		,LicensingFee = 0
		,Discount = 0
		,Rebate = 0
	FROM #tmpResult r
	LEFT JOIN #productFees s ON r.PartyID=s.PartyId AND r.ProductID=s.ProductId
	WHERE r.PartyID IN (SELECT p.PartyId FROM #productFees p) AND s.ProductId IS NULL

	DROP TABLE #productFees
END

-- Final Result
BEGIN
	DECLARE @Result TABLE (PartyId INT, LicenseeCode VARCHAR(100), ProductId INT, LicensingFee MONEY, AmountToCompany MONEY, Discount MONEY, Rebate MONEY, Promotion MONEY, ContributionDiscount MONEY)
	INSERT INTO @Result (PartyId, LicenseeCode, ProductId, Discount, Rebate, Promotion, ContributionDiscount, LicensingFee, AmountToCompany)
	SELECT r.PartyId, ISNULL(UPPER(p.LicenseeCode), '') + '|' + CONVERT(VARCHAR(50), p.PartyId), r.ProductId, SUM(r.Discount), SUM(r.Rebate), SUM(r.Promotion)
		,SUM(r.ContributionDiscount)
		,SUM(r.LicensingFee + r.ExtraAmount + Contribution - JackPotPrize - PromotionPrize) AS LicensingFee
		,SUM(r.AmountToCompany + ContributionDiscount + Contribution - JackPotPrize - PromotionPrize) AS AmountToCompany
	FROM #tmpResult r
		INNER JOIN @partyList p ON r.PartyId = p.PartyId
	WHERE p.IsSelected = 1
	GROUP BY r.PartyId, ISNULL(UPPER(p.LicenseeCode), '') + '|' + CONVERT(VARCHAR(50), p.PartyId), r.ProductId

	IF @IsShowSettlementDetail = 1
	BEGIN
		IF @IsGroupByPartyId = 1
			SELECT r.PartyId, p.ProductName, p.ProductId, UPPER(@BaseCurrency) AS CurrencyName, SUM(r.AmountToCompany) AS AmountToCompany
			FROM @Result r
				INNER JOIN #Products p ON r.ProductId = p.ProductId
			GROUP BY p.ProductId, p.ProductName, r.PartyId
		ELSE
			SELECT r.LicenseeCode, p.ProductName, p.ProductId, UPPER(@BaseCurrency) AS CurrencyName, SUM(r.AmountToCompany) AS AmountToCompany
			FROM @Result r
				INNER JOIN #Products p ON r.ProductId = p.ProductId
			GROUP BY r.LicenseeCode, p.ProductId, p.ProductName
			ORDER BY p.ProductId
	END
	ELSE
	BEGIN
		IF @IsGroupByPartyId = 1
			SELECT PartyId
				,UPPER(@BaseCurrency)		AS CurrencyName
				,SUM(AmountToCompany)		AS AmountToCompany
				,SUM(LicensingFee)			AS LicensingFee
				,SUM(Discount)				AS Discount
				,SUM(Rebate)				AS Rebate
				,SUM(Promotion)				AS Promotion
				,SUM(ContributionDiscount)	AS ContributionDiscount
			FROM @Result
			GROUP BY PartyId
		ELSE
			SELECT LicenseeCode
				,UPPER(@BaseCurrency)		AS CurrencyName
				,SUM(AmountToCompany)		AS AmountToCompany
				,SUM(LicensingFee)			AS LicensingFee
				,SUM(Discount)				AS Discount
				,SUM(Rebate)				AS Rebate
				,SUM(Promotion)				AS Promotion
				,SUM(ContributionDiscount)	AS ContributionDiscount
			FROM @Result
			GROUP BY LicenseeCode
	END
END

	DROP TABLE #Products
	DROP TABLE #tmpResult
	DROP TABLE #tmpBettingByProduct
	DROP TABLE #tmpChargeInfo
	DROP TABLE #tmpDiscountSettings
	DROP TABLE #tmpExchange
	DROP TABLE #tmpWinlossData
END
GO