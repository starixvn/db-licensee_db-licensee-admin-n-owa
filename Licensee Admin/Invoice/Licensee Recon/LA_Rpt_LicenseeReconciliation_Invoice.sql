/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

declare--ALTER PROCEDURE [dbo].LA_Rpt_LicenseeReconciliation
	@PartyIds		VARCHAR(4000),
	@FromDate		DATETIME,
	@ToDate			DATETIME,
	@Environment	VARCHAR(50),
	@BaseCurrency	VARCHAR(5)
--AS
/*	Header:
	Created: 2018.10.04 - Parsons
	Task : Generate amount for software fee
	DB: DBLIC.bodb_Licensee
   
	Revisions: 
		- 20190723@Bruce: Create Sp
*/select @PartyIds='14,15,16',
	@FromDate='20190501',
	@ToDate	 ='20190531',
	@Environment='uat',@BaseCurrency='eur'
BEGIN
	SET NOCOUNT ON
	
	DECLARE @AmountTypeSoftwareFee INT = 1,
		@AmountTypeDiscount INT = 4,
		@AmountTypeRebate INT = 6,
		@DeductAgainstInvoice INT = 24

/*-----------------
 * Settings
 *-----------------*/
	-- get base currency
	--
	DECLARE @baseCurrencyId INT = (SELECT CurrencyId FROM dbo.LA_f_BaseCurrency() WHERE CurrencyName=@BaseCurrency)

	-- supported products
	-- 
	DECLARE @supportedProducts VARCHAR(100) = 'SB,NG,VS,AGC,GD,KN,CS,BA,AB,CO,CB,VS2,PP,VB,FW,LT,BX'
	DECLARE @productList TABLE(ProductId INT, Code VARCHAR(5))
	INSERT INTO @productList
	SELECT ProductID, ProductPrefix FROM dbo.LA_f_Products3rd(@supportedProducts)

	-- get party list
	--
	DECLARE @partyList AS TABLE(
		PartyId			INT,
		PartyName		VARCHAR(50),
		IsSelected		BIT,
		PartyGroupId	INT
	)
	-- set selected = true
	-- put each party to its individual group(indicated by -partyid)
	INSERT INTO @partyList(PartyId,PartyName,IsSelected,PartyGroupId)
	SELECT PartyID,PartyName,1,-PartyID FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyID IN(
		SELECT val FROM dbo.strSplit(@PartyIds, ',')
	)

	-- to calculate minfee: need to select all party in same group
	-- get actual party group id
	UPDATE p
	SET PartyGroupId=a.PartyGroupId
	FROM @partyList p
	INNER JOIN dbo.LA_PartyGroupAssignment a WITH(NOLOCK) ON p.PartyId = a.PartyId

	-- include party in same group for minfee calculation
	INSERT INTO @partyList(PartyId,PartyGroupId,IsSelected)
	SELECT DISTINCT a.PartyId, a.PartyGroupId,0
	FROM dbo.LA_PartyGroupAssignment a WITH(NOLOCK)
	WHERE a.PartyId NOT IN (SELECT b.PartyId FROM @partyList b)
		AND a.PartyGroupId IN (SELECT c.PartyGroupId FROM @partyList c)

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
			WHERE b.IsSelected=1
				AND p.ProductId IN (SELECT c.ProductId FROM @productList c)
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
		INSERT INTO @partyList(PartyId,PartyGroupId,IsSelected)
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
	SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, CAST(ci.DI_Rate AS DECIMAL(6,5)) AS Rate, ci.Fromdate, ci.ToDate,ci.ChargeType
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
		INSERT INTO @tmpMinFee(FeeType ,PartyId,ProductId, CurrencyId ,FeeAmount ,FromDate ,ToDate, MinFeeId)
		SELECT mf.FeeTypeId,
			mf.PartyId,
			mf.ProductId,
			mf.CurrencyId,
			mf.FeeAmount,
			CASE WHEN @FromDate >= mf.FromDate THEN @FromDate ELSE mf.FromDate END AS FromDate,
			CASE WHEN @ToDate < mf.ToDate THEN @ToDate ELSE mf.ToDate END AS ToDate,
			mf.MinFeeId
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
	DECLARE @GDTip_ChargeType			SMALLINT = 12
		,@CommissionShare_ChargeType	SMALLINT = 6
		,@CashinShare_ChargeType		SMALLINT = 7
		,@CashoutComm_ChargeType		SMALLINT = 5
		,@PromotionPrize_Bettype	SMALLINT = 4300
		,@GDTip_Bettype				SMALLINT = 1706  
		,@BA	SMALLINT = 3
		,@GD	SMALLINT = 11
		,@CB	SMALLINT = 15
		,@CO	SMALLINT = 25
		,@PP	SMALLINT = 32

	BEGIN
		SELECT b.SiteID,b.rptDate,b.ProductId,b.CurrencyId,b.Bettype,b.MemberWL,b.CommissionA
			,b.WinPrizeAmount,b.CashOutAmount,b.BuyBackAmount,b.Turnover
			,CASE WHEN ISNULL(b.TicketType, 0) = 0 THEN b.Turnover ELSE b.ExtraAmount END TurnoverForCommision
		INTO #tmpBettingByProduct
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		WHERE (b.rptDate BETWEEN @FromDate AND @ToDate)
			AND b.SiteID IN (SELECT DISTINCT c.LicenseeID FROM #tmpChargeInfo c)
			AND b.ProductID IN (SELECT p.ProductId FROM @productList p)
			AND b.customercategory NOT IN (27, 28)
			AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund

		CREATE INDEX IX_tmpBettingByProduct ON #tmpBettingByProduct(SiteId, ProductId)

		-- calculate amount to company
		-- excludes: golddeluxe bidme tip, pragmatic promotion prize, colossus bet
		--  
		SELECT p.PartyID,b.rptDate,p.ProductId,b.CurrencyId,
			CAST(0 AS MONEY) AS ExtraAmount,
			SUM(ISNULL(b.MemberWL, 0) * e.Rate) AS Winloss,
			SUM((
				ISNULL(-b.MemberWL, 0) * p.Rate - (CASE WHEN b.ProductID=@BA THEN ISNULL(b.CommissionA,0) ELSE 0 END)
			) * e.Rate) AS AmountToCompany
		INTO #tmpWinlossData
		FROM #tmpBettingByProduct b
		INNER JOIN #tmpChargeInfo p ON b.ProductId = p.ProductID AND p.LicenseeId = b.SiteId AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
		INNER JOIN #tmpExchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
		WHERE p.ChargeType NOT IN (
				@CashoutComm_ChargeType,
				@CommissionShare_ChargeType,
				@CashinShare_ChargeType,
				@GDTip_ChargeType
			)
			AND b.Bettype NOT IN (
				@GDTip_Bettype,
				@PromotionPrize_Bettype
			)
		GROUP BY p.PartyID,b.rptdate,p.ProductId,b.CurrencyId

		-- includes extra values: gdtip, promotion prize
		--
		INSERT INTO #tmpWinlossData(PartyID,rptDate,ProductID,CurrencyId, Winloss,AmountToCompany,ExtraAmount)
		SELECT p.PartyID,b.rptDate,p.ProductId,b.CurrencyId,0,0,
			SUM(CASE
				WHEN b.Bettype = @GDTip_Bettype THEN -ISNULL(b.MemberWL, 0) * p.Rate * e.Rate
				WHEN b.Bettype = @PromotionPrize_Bettype THEN -ISNULL(b.MemberWL, 0) * e.Rate
				ELSE 0 END)
		FROM #tmpBettingByProduct b  
		INNER JOIN #tmpChargeInfo p ON b.ProductId = p.ProductID AND p.LicenseeId = b.SiteId AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)  
		INNER JOIN #tmpExchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID  
		WHERE b.Bettype IN (@GDTip_Bettype,@PromotionPrize_Bettype)  
			AND (p.ProductID = @PP OR p.ChargeType = @GDTip_ChargeType)  
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
			JOIN #tmpChargeInfo AS cm ON cm.ProductID = @CB AND cm.ChargeType = @CommissionShare_ChargeType AND (td.rptDate BETWEEN cm.FromDate AND cm.ToDate)  
			JOIN #tmpChargeInfo AS ci ON cm.ProductID = @CB AND ci.ChargeType = @CashinShare_ChargeType AND (td.rptDate BETWEEN ci.FromDate AND ci.ToDate)  

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
			,SUM(ISNULL(a.AmountToCompany,0)) AmountToCompany
			,SUM(ISNULL(a.ExtraAmount,0)) ExtraAmount
			,SUM(ISNULL(a.Winloss,0)) Winloss
			,CAST(0 AS MONEY) LicensingFee
			,CAST(0 AS MONEY) Discount
			,CAST(0 AS MONEY) MinFee
			,CAST(0 AS BIT) IsApplyMinfeeToDiscount
		INTO #tmpResult
		FROM #tmpWinlossData a  
		GROUP BY a.PartyID, a.ProductId  

		-- treat negative as 0  
		-- excepts: BA,CB,CO
		UPDATE #tmpResult SET LicensingFee = CASE WHEN ProductID NOT IN (@BA,@CB,@CO) AND AmountToCompany < 0 THEN 0 ELSE AmountToCompany END  
	END
/*-----------------
 * minfee
 *-----------------*/
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
		DECLARE @totalMinFees TABLE(
			PartyGroupId	INT,
			ProductId		INT,
			TotalMinFee		MONEY,
			TotalAmount		MONEY
		)
		INSERT INTO @totalMinFees(PartyGroupId,ProductId, TotalMinFee, TotalAmount)
		SELECT p.PartyGroupId, mf.ProductId, SUM(mf.MinFeeAmount), SUM(mf.FeeOutOfWaiveTime)
		FROM @tmpMinFee mf
		INNER JOIN @partyList p ON mf.PartyId = p.PartyId
		WHERE mf.FeeType = 1
		GROUP BY p.PartyGroupId, mf.ProductId

		-- apply minfee if amount to company do not reach the goal
		--
		UPDATE r SET LicensingFee = CASE
				WHEN t.TotalAmount < t.TotalMinFee AND a.FeeOutOfWaiveTime < a.MinFeeAmount
					THEN a.MinFeeAmount + a.FeeUnderWaiveTime
				ELSE a.FeeOutOfWaiveTime + a.FeeUnderWaiveTime
			END,
			--IsChargedByMinFee = CASE
			--	WHEN t.TotalAmount < t.TotalMinFee AND a.FeeOutOfWaiveTime < a.MinFeeAmount
			--		THEN 1
			--	ELSE 0
			--END,
			IsApplyMinfeeToDiscount = CASE
				WHEN a.MinFeeAmount < a.FeeAmount AND a.FeeAmount > 0 AND b.FeeType IS NOT NULL THEN 0-- waived
				WHEN t.TotalAmount >= t.TotalMinFee AND p.PartyGroupId > 0 THEN 0 -- reach group minfee goal
				ELSE 1 END,
			Minfee = a.MinFeeAmount
		FROM #tmpResult r
		INNER JOIN @partyList p ON r.PartyId=p.PartyId
		INNER JOIN @tmpMinFee a ON a.PartyId = r.PartyId AND a.ProductId=r.ProductID AND a.FeeType = 1 -- minfee setting
		INNER JOIN @totalMinFees t ON a.ProductId = t.ProductId AND t.PartyGroupId=p.PartyGroupId
		LEFT JOIN @tmpMinFee b ON b.PartyId = r.PartyId AND b.ProductId=r.ProductID AND b.FeeType = 2-- waive setting
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
		Fee 				MONEY,
		IsDiscountByCurrency BIT
	)

	BEGIN
		-- discount by all currency
		INSERT INTO @tmpDiscountCalculation(CalculationGroup,DiscountGroupId,DiscountGroupType,CurrencyId,Winloss,Fee,IsDiscountByCurrency)
		SELECT s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId, SUM(r.Winloss) Winloss,SUM(r.LicensingFee) Fee,0
		FROM #tmpDiscountSettings s
		INNER JOIN @tmpDiscountCurrency c ON s.PartyId = c.PartyId AND c.DiscountGroupId=s.DiscountGroupId AND c.CurrencyId = 0 -- all currency
		INNER JOIN #tmpResult r ON s.PartyID = r.PartyId AND s.ProductId=r.ProductId
		WHERE s.CalculationType IN (@ToBeCalculated,@CalculateAndDiscount)
		GROUP BY s.DiscountGroupId, s.DiscountGroupType,s.CurrencyId,s.CalculationGroup

		-- discount by currency
		-- only offer this kind of discount for SB & licensing fee
		INSERT INTO @tmpDiscountCalculation(CalculationGroup,DiscountGroupId,DiscountGroupType,CurrencyId,Winloss,Fee,IsDiscountByCurrency)
		SELECT s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId, SUM(r.Winloss) Winloss,SUM(r.AmountToCompany) Fee,1
		FROM #tmpWinlossData r
		INNER JOIN @tmpDiscountCurrency c ON c.PartyID=r.PartyId AND c.CurrencyId=r.CurrencyId
		INNER JOIN #tmpDiscountSettings s ON s.DiscountGroupId=c.DiscountGroupId AND s.ProductId = r.ProductId AND s.PartyId = c.PartyId
		WHERE s.CalculationType IN (@ToBeCalculated,@CalculateAndDiscount)
			AND s.DiscountGroupType IN (@DiscountIndividualFee, @DiscountByGroupFee)
		GROUP BY s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId

		DECLARE @Rate TABLE(Rate DECIMAL(6,5), CalculationGroup INT, IsDiscountByCurrency BIT)
	
		-- get rate
		;WITH cte_Detail AS(
			SELECT c.CalculationGroup, d.DiscountGroupId, d.Rate
				,ISNULL(d.FromAmount,0) * e.Rate AS FromAmount
				,CASE WHEN d.ToAmount > @Unlimited THEN d.ToAmount ELSE (d.ToAmount + 1) * e.Rate END AS ToAmount
			FROM dbo.LA_DiscountGroupDetail d
			INNER JOIN @tmpDiscountCalculation c ON d.DiscountGroupId=c.DiscountGroupId
			INNER JOIN #tmpExchange e ON e.ExchangeId = c.CurrencyId AND e.exchangedate=@ToDate
		)
		INSERT INTO @Rate(rate, CalculationGroup,IsDiscountByCurrency)
		SELECT d.Rate, c.CalculationGroup, c.IsDiscountByCurrency
		FROM @tmpDiscountCalculation c INNER JOIN cte_Detail d ON c.CalculationGroup=d.CalculationGroup
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
			AND c.IsDiscountByCurrency = 0

		-- discount by curency
		--
		-- not support gross win
		-- not support multiple products
		-- not discount if fee after discount less than minfee
		;WITH cte_DiscountByCurrency AS(
			SELECT c.CalculationGroup, c.Rate, c.Rate * (CASE WHEN s.Fee <0 THEN 0 ELSE s.Fee END) Discount
			FROM @tmpDiscountCalculation s
			INNER JOIN @rate c ON c.CalculationGroup = s.CalculationGroup
			WHERE c.IsDiscountByCurrency = 1
		)
		UPDATE t SET Discount = CASE WHEN (t.LicensingFee - d.Discount) < t.Minfee AND t.IsApplyMinfeeToDiscount=1 THEN t.LicensingFee - t.Minfee ELSE d.Discount END
		FROM #tmpResult t
		INNER JOIN #tmpDiscountSettings s ON t.PartyID = s.PartyID AND t.ProductID=s.ProductId
		INNER JOIN cte_DiscountByCurrency d on d.CalculationGroup=s.CalculationGroup
		WHERE d.Discount > 0

		-- apply new discount term for licensee have not shared minfee
		-- fee after discount must >= minfee
		DECLARE @ApplyMinfeeToDiscountDate DATE = dbo.LA_f_ApplyDiscountMinfeeDate()
	
		IF (@FromDate >= @ApplyMinfeeToDiscountDate)
		BEGIN
			UPDATE #tmpResult SET Discount = LicensingFee - Minfee WHERE (LicensingFee - Discount) < Minfee AND IsApplyMinfeeToDiscount = 1
		END

		UPDATE #tmpResult SET Discount = 0 WHERE Discount <= 0
	END
/*-----------------
 * prepayment
 *-----------------*/
	-- define AMF, AG and prepayment
	--
	DECLARE @SB INT = 0, @AG INT = 10
	DECLARE @InvoiceItemTypes TABLE([Key] VARCHAR(5), [Value] INT)

	INSERT INTO @InvoiceItemTypes ([Key], [Value])
	SELECT 'AMF', val FROM dbo.strSplit('3,5,7,21',',')

	INSERT INTO @InvoiceItemTypes ([Key], [Value])
	SELECT 'PRE', val FROM dbo.strSplit('22,23,24',',')

	INSERT INTO @InvoiceItemTypes ([Key], [Value])
	SELECT 'AGP', val FROM  dbo.strSplit('25,26,27',',')

	INSERT INTO @InvoiceItemTypes ([Key], [Value])
	SELECT 'OTHER', val FROM  dbo.strSplit('11,12,13,14,17',',')

	-- get statement
	DECLARE @statementQuery VARCHAR(4000) = 
		'select s.Income,s.Expense,InvItemTypeId,h.Environment,s.RefPartyId '+
		'from bodb_Licensee.dbo.LA_InvoiceStatement s with(nolock) '+
		'inner join bodb_Licensee.dbo.LA_InvoiceHeader h with(nolock) on s.InvoiceHeaderId=h.InvoiceHeaderId '+
		'where s.RefPartyId in ('+@PartyIds+') and isnull(h.StatusId, 0) = 0'
	DECLARE @openQuery VARCHAR(1000) = 'SELECT * FROM OPENQUERY(DBCUST,'''+@statementQuery+''')'

	DECLARE @statement TABLE(Income MONEY,Expense MONEY,InvItemTypeId SMALLINT,Environment VARCHAR(10),PartyId INT)
	INSERT INTO @statement(Income,Expense,InvItemTypeId,Environment,PartyId)
	EXEC (@openQuery)

	DECLARE @credit TABLE(Amount MONEY,Remaining MONEY,FeeAfterDiscount MONEY,[Key] VARCHAR(50),PartyId INT)
	INSERT INTO @credit(Remaining, [Key], PartyId,Amount,FeeAfterDiscount)
	SELECT SUM(ISNULL(s.Income,0) - ISNULL(s.Expense,0)), i.[Key], s.PartyId,0,0
	FROM @statement s INNER JOIN @InvoiceItemTypes i ON s.InvItemTypeId = i.Value
	WHERE s.Environment = @Environment
		AND s.PartyId IN (SELECT p.PartyId FROM @partyList p WHERE p.IsSelected=1)
	GROUP BY i.[Key],s.PartyId

	UPDATE @credit SET Remaining = 0 WHERE Remaining<0 AND [Key] IN ('AMF', 'AGP', 'PRE')

	-- calculate AMF, AG-Prepayment
	--
	UPDATE c SET 
		FeeAfterDiscount = r.LicensingFee - Discount,
		Amount = CASE 
			WHEN r.ProductID = @SB THEN (CASE WHEN c.Remaining < r.MinFee THEN c.Remaining ELSE r.MinFee END)
			ELSE c.Remaining END
	FROM @credit c INNER JOIN #tmpResult r ON r.PartyID=c.PartyId
	WHERE r.ProductID IN (@SB, @AG) AND c.[Key] IN ('AMF', 'AGP')

	UPDATE c SET Amount = (CASE WHEN c.Amount < c.FeeAfterDiscount THEN c.Amount ELSE c.FeeAfterDiscount END) FROM @credit c

	-- calculate deduction against invoice - prepayment
	--
	;WITH cte_FeeAfterDiscount AS (
		SELECT r.PartyId, SUM(r.LicensingFee - r.Discount) Amount FROM #tmpResult r GROUP BY r.PartyID
	), cte_Deduction AS(
		SELECT c.PartyId, SUM(c.Amount) Amount FROM @credit c WHERE [Key] IN ('AMF', 'AGP') GROUP BY c.PartyId
	)
	UPDATE c SET c.Amount = CASE WHEN c.Remaining < (a.Amount - b.Amount) THEN c.Remaining ELSE (a.Amount - b.Amount) END
	FROM @credit c
	INNER JOIN cte_FeeAfterDiscount a ON a.PartyID=c.PartyId AND c.[Key]='PRE'
	INNER JOIN cte_Deduction b ON a.PartyID=b.PartyId
/*-----------------
 * aggregate
 *-----------------*/
	;WITH a AS (
		SELECT r.PartyID
			, SUM(r.AmountToCompany + r.ExtraAmount) AmountToCompany
			, SUM(r.LicensingFee + r.ExtraAmount) LicensingFee
			, SUM(r.Discount) Discount
			, SUM(r.MinFee) MinFee
		FROM #tmpResult r
		INNER JOIN @partyList p ON r.PartyID=p.PartyId
		WHERE p.PartyId IN (SELECT p.PartyId FROM @partyList p WHERE p.IsSelected=1)
		GROUP BY r.PartyId
	), b AS (
		SELECT c.PartyId,
			SUM(CASE WHEN c.[Key] IN ('AMF', 'AGP', 'PRE') THEN Amount ELSE 0 END) Prepayment,
			SUM(CASE WHEN c.[Key] = 'OTHER' THEN Amount ELSE 0 END) Others
		FROM @credit c
		GROUP BY c.PartyId
	)
	SELECT p.PartyId, p.PartyName, a.AmountToCompany,a.LicensingFee,a.MinFee,a.Discount,b.Prepayment,b.Others
	FROM a LEFT JOIN b ON a.PartyID=b.PartyId
	INNER JOIN @partyList p ON p.PartyId = a.PartyID
	WHERE p.IsSelected = 1

	DROP TABLE #tmpResult
	DROP TABLE #tmpBettingByProduct
	DROP TABLE #tmpChargeInfo
	DROP TABLE #tmpDiscountSettings
	DROP TABLE #tmpExchange
	DROP TABLE #tmpWinlossData
END
GO