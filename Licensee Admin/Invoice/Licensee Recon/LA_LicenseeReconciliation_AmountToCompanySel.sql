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
		,@BA	SMALLINT = 3
		,@GD	SMALLINT = 11
		,@CB	SMALLINT = 15
		,@CO	SMALLINT = 25
		,@BX	SMALLINT = 31
		,@PP	SMALLINT = 32
		,@CC	SMALLINT = 34
		,@SPR	SMALLINT = 37
		,@SBC	SMALLINT = 42

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
	-- 
	DECLARE @supportedProducts VARCHAR(500) = 'SB,NG,VS,AGC,GD,KN,CS,BA,AB,CO,CB,VS2,PP,VB,FW,LT,BX,CC,SG,VRG,SAG,I4D,TG,SBC,SXG,PGS,JK,WM,VS3,GDG,BGG,MXG'
	DECLARE @productList TABLE(ProductId INT, Code VARCHAR(10), Name VARCHAR(100))
	INSERT INTO @productList(ProductId,Code,Name)
	SELECT ProductID, ProductPrefix,ProductName FROM dbo.LA_f_Products3rd(@supportedProducts)

	-- get party list
	--
	DECLARE @partyList TABLE(PartyId INT, PartyName	VARCHAR(50), LicenseeCode VARCHAR(50), IsSelected BIT, GroupMinFeeId INT)
	-- set selected = true
	-- put each party to its individual group(indicated by -partyid)
	INSERT INTO @partyList(PartyId, PartyName, IsSelected, GroupMinFeeId, LicenseeCode)
	SELECT p.PartyID, p.PartyName
		, 1 AS IsSelected
		, -p.PartyID AS PartyGroupId
		, CASE WHEN ISNULL(d.LicenseeCode,'') = '' THEN CAST(p.PartyID AS VARCHAR(10)) ELSE d.LicenseeCode END
	FROM dbo.OAS_Party p WITH(NOLOCK)
	INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON p.PartyID=d.PartyID
	WHERE p.PartyID IN(SELECT val FROM dbo.strSplit(@PartyIds, ',')) AND d.LicenseeCode IS NOT NULL

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
			WHERE p.ProductId IN (SELECT c.ProductId FROM @productList c)
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
	FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @supportedProducts, 'OA', 1) ci
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
		INNER JOIN @productList c ON mf.ProductId=c.ProductID
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
		SELECT b.SiteID,b.rptDate,b.ProductId,b.CurrencyId,b.CommissionA,b.CommissionP
			,b.WinPrizeAmount,b.CashOutAmount,b.BuyBackAmount,b.Turnover,b.TicketType
			,ISNULL(-b.MemberWL, 0) LicWinloss
			,CASE WHEN b.Bettype IN (@PPContribution_Bettype, @SB_AdjustedOdds_Bettype) THEN ISNULL(-b.GrossWL, 0) ELSE 0 END GrossWL
			,CASE WHEN b.ProductID = @SPR THEN @SabaPromotion_Bettype ELSE b.Bettype END			Bettype
			,CASE WHEN ISNULL(b.TicketType, 0) = 0 THEN b.Turnover ELSE b.ExtraAmount END			TurnoverForCommision
		INTO #tmpBettingByProduct
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		WHERE (b.rptDate BETWEEN @FromDate AND @ToDate)
			AND b.SiteID IN (SELECT DISTINCT c.LicenseeID FROM #tmpChargeInfo c)
			AND (b.ProductID = @SPR OR b.ProductID IN (SELECT p.ProductId FROM @productList p))
			AND b.customercategory NOT IN (27, 28)
			AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund

		CREATE INDEX IX_tmpBettingByProduct ON #tmpBettingByProduct(SiteId, ProductId)

		-- calculate amount to company
		-- excludes: golddeluxe bidme tip, PP JP & Prize, colossus bet
		-- 
		SELECT p.PartyID,b.rptDate,p.ProductId,b.CurrencyId,
			CAST(0 AS MONEY) AS Promotion,
			CAST(0 AS MONEY) AS ExtraAmount,
			CAST(0 AS MONEY) AS Contribution,
			CAST(0 AS MONEY) AS JackPotPrize,
			CAST(0 AS MONEY) AS PromotionPrize,
			SUM((b.LicWinloss + (CASE WHEN b.ProductID = @BX THEN b.CommissionA ELSE 0 END)) * e.Rate) AS Winloss,
			SUM((((b.LicWinloss - CASE WHEN b.ProductID = @PP THEN GrossWL ELSE 0 END) * ISNULL(cr.Rate, p.Rate) - 
				(CASE
					WHEN b.ProductID = @BA THEN ISNULL(b.CommissionA,0)
					WHEN b.ProductID = @BX THEN (b.CommissionA + b.CommissionP)
					ELSE 0
				END)
				) + CASE WHEN b.ProductID = 0 THEN GrossWL ELSE 0 END) * e.Rate) AS AmountToCompany
		INTO #tmpWinlossData
		FROM #tmpBettingByProduct b
		INNER JOIN #tmpChargeInfo p ON b.ProductId = p.ProductID AND p.LicenseeId = b.SiteId AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
		INNER JOIN #tmpExchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
		LEFT JOIN LA_ChargeRateByCurrency cr WITH (NOLOCK) ON p.ChargeId = cr.ChargeId AND b.CurrencyId = cr.CurrencyId
		LEFT JOIN LA_f_ExcludedBettypeListSel('11,32,34,39', '4297') eb ON b.Bettype = eb.BettypeID
		WHERE p.ChargeType NOT IN (
				@CashoutComm_ChargeType,
				@CommissionShare_ChargeType,
				@CashinShare_ChargeType,
				@GDTip_ChargeType
			)
			AND eb.BettypeID IS NULL
			AND	ISNULL(b.TicketType, 0) <> 2 -- Free_Bets_TicketType 
		GROUP BY p.PartyID,b.rptdate,p.ProductId,b.CurrencyId
		-- includes extra values: gdtip, PP JP & Prize
		--
		INSERT INTO #tmpWinlossData(PartyID,rptDate,ProductID,CurrencyId,Winloss,AmountToCompany,ExtraAmount,Promotion,Contribution,JackPotPrize,PromotionPrize)
		SELECT p.PartyID,b.rptDate,p.ProductId,b.CurrencyId,0,0,
			SUM(CASE WHEN b.Bettype IN(@GDTip_Bettype, @SAGTip_Bettype) THEN b.LicWinloss * p.Rate * e.Rate ELSE 0 END) ExtraAmount,
			SUM(CASE WHEN b.Bettype = @SabaPromotion_Bettype THEN -b.LicWinloss * e.Rate ELSE 0 END) Promotion,
			SUM(GrossWL * e.Rate) Contribution,
			SUM(CASE WHEN b.Bettype = @PPJackpotPrize_Bettype THEN -b.LicWinloss * e.Rate ELSE 0 END) JackPotPrize,
			SUM(CASE WHEN ISNULL(b.TicketType, 0) = 2 OR b.Bettype IN (@PPTournament_Bettype, @PromotionPrize_Bettype, @CC_ArcadiaBonus_Bettype) THEN -b.LicWinloss * e.Rate ELSE 0 END) PromotionPrize
		FROM #tmpBettingByProduct b
		INNER JOIN #tmpChargeInfo p ON p.LicenseeId = b.SiteId AND b.ProductId = (CASE WHEN p.ProductID = 0 THEN @SPR ELSE p.ProductID END)
		INNER JOIN #tmpExchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
		LEFT JOIN LA_f_ExcludedBettypeListSel('11,32,34,39', '') eb ON b.Bettype = eb.BettypeID
		WHERE b.rptDate BETWEEN p.FromDate AND p.ToDate
			AND (p.ProductID IN(0, @PP, @CC, @SBC) OR p.ChargeType = @GDTip_ChargeType)
			AND (b.Bettype = @SabaPromotion_Bettype OR eb.BettypeID IS NOT NULL OR ISNULL(b.TicketType, 0) = 2)
		GROUP BY p.PartyID,b.rptdate,p.ProductId,b.CurrencyId

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
			INNER JOIN @productList pd ON 1=1  
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

		-- treat negative as 0  
		-- excepts: BA, CB, CO, BX
				--  9wickets-316, 9Wsports-459
		UPDATE #tmpResult SET LicensingFee = CASE WHEN AmountToCompany < 0 AND ProductID NOT IN (@BA,@CB,@CO,@BX) AND PartyId NOT IN (316, 459) THEN 0 ELSE AmountToCompany END
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
		AND h.InvoiceDate BETWEEN @FromDate AND @ToDate
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
/*-----------------
 * aggregate
 *-----------------*/
	IF @IsShowSettlementDetail = 1
	BEGIN
		IF @IsGroupByPartyId = 1
		BEGIN	
			SELECT p.PartyId
				, pl.Name AS ProductName
				, pl.ProductId
				, UPPER(@BaseCurrency) AS CurrencyName
				, SUM(CASE WHEN r.ProductID = 32 THEN 
										        (CASE WHEN r.AmountToCompany < 0 THEN 0 ELSE r.AmountToCompany END) + Contribution - JackPotPrize - PromotionPrize
					  ELSE r.AmountToCompany + r.ExtraAmount - PromotionPrize END) AmountToCompany
			FROM #tmpResult r
			INNER JOIN @partyList p ON r.PartyID=p.PartyId
			INNER JOIN @productList pl ON r.ProductID = pl.ProductId
			WHERE p.IsSelected=1
			GROUP BY pl.ProductId, p.PartyId, pl.Name
		END
		ELSE
		BEGIN
			SELECT p.LicenseeCode
				, pl.Name AS ProductName
				, UPPER(@BaseCurrency) AS CurrencyName
				, SUM(CASE WHEN r.ProductID = 32 THEN 
										        (CASE WHEN r.AmountToCompany < 0 THEN 0 ELSE r.AmountToCompany END) + Contribution - JackPotPrize - PromotionPrize
					  ELSE r.AmountToCompany + r.ExtraAmount - PromotionPrize END) AmountToCompany
			FROM #tmpResult r
			INNER JOIN @partyList p ON r.PartyID=p.PartyId
			INNER JOIN @productList pl ON r.ProductID = pl.ProductId
			WHERE p.IsSelected=1
			GROUP BY pl.ProductId, p.LicenseeCode, pl.Name
			ORDER BY pl.ProductId
		END
	END
	ELSE
	BEGIN
		IF @IsGroupByPartyId = 1
		BEGIN
			SELECT p.PartyId
				,UPPER(@BaseCurrency) AS CurrencyName
				,SUM(CASE WHEN r.ProductID = 32 THEN 
										        (CASE WHEN r.AmountToCompany < 0 THEN 0 ELSE r.AmountToCompany END) + Contribution - JackPotPrize - PromotionPrize
					 ELSE r.AmountToCompany + r.ExtraAmount - PromotionPrize END) AmountToCompany
				,SUM(r.LicensingFee + r.ExtraAmount + Contribution - JackPotPrize - PromotionPrize) LicensingFee
				,SUM(r.Discount) Discount
				,SUM(r.Rebate) Rebate
				,SUM(r.Promotion) Promotion
			FROM #tmpResult r
			INNER JOIN @partyList p ON p.PartyId = r.PartyID
			WHERE p.IsSelected = 1
			GROUP BY p.PartyId
		END
		ELSE
		BEGIN
			SELECT UPPER(p.LicenseeCode) AS LicenseeCode
				,UPPER(@BaseCurrency) AS CurrencyName 
				, SUM(CASE WHEN r.ProductID = 32 THEN 
										        (CASE WHEN r.AmountToCompany < 0 THEN 0 ELSE r.AmountToCompany END) + Contribution - JackPotPrize - PromotionPrize
					  ELSE r.AmountToCompany + r.ExtraAmount - PromotionPrize END) AmountToCompany
				,SUM(r.LicensingFee + r.ExtraAmount + Contribution - JackPotPrize - PromotionPrize) LicensingFee
				,SUM(r.Discount) Discount
				,SUM(r.Rebate) Rebate
				,SUM(r.Promotion) Promotion
			FROM #tmpResult r
			INNER JOIN @partyList p ON p.PartyId = r.PartyID
			WHERE p.IsSelected = 1
			GROUP BY p.LicenseeCode
		END
	END

	DROP TABLE #tmpResult
	DROP TABLE #tmpBettingByProduct
	DROP TABLE #tmpChargeInfo
	DROP TABLE #tmpDiscountSettings
	DROP TABLE #tmpExchange
	DROP TABLE #tmpWinlossData
END
GO