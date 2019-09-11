/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_AmountToCompanySel] (
	@FromDate		DATE,
	@ToDate			DATE,
	@PartyIds		VARCHAR(4000) = '',
	@ProductCodes	VARCHAR(1000) = '',
	@BaseCurrency	VARCHAR(10) = 'EUR',
	@CurrencyId		INT = 0,
	@IsApplyDiscountMinfee BIT = 1
)
AS
/*	Created: 20180703@Bruce
	Task : calculate discount, rebate, licensing fee in one invoice period(one month)
	DB: DBLIC.bodb_Licensee
	
	Revisions:
		- 20180703@Bruce: calculate discount,rebate [#94282]
		- 20181114@Bruce: discount by currency [#99694] 
		- 20181127@Parsons: Integrate Bidme games (GD product) [#103695]
		- 20190319@bruce: Apply min fee rule for discount calculation [#109997]
		- 20190410@bruce: calculate discount for terminated licensee[111485]
		- 20190325@Parsons: Integrate-PP-Promotion-Prize [#109014]
		- 20190911@Bruce: Support Exchange product in invoices [#119846]

	Parameters:
		@IsApplyDiscountMinfee: apply minfee term to discount value
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @ApplyMinfeeToDiscountDate DATE = dbo.LA_f_ApplyDiscountMinfeeDate()

/*--------------------------------------------------------------------------------------------------------------------------------
 * 1. Prepare settings
 *-------------------------------------------------------------------------------------------------------------------------------*/
	DECLARE @GD_Tip SMALLINT = 1706, @PromotionPrize SMALLINT = 4300
	
	-- product to be discounted
	DECLARE @ProductList TABLE (ProductId INT, ToBeDiscounted BIT)
	INSERT INTO @ProductList(ProductId,ToBeDiscounted)
	SELECT ProductID, 1 FROM dbo.LA_f_Products3rd(@ProductCodes)

	-- 1.1 party list
	DECLARE @PartyList TABLE(
		PartyId			INT,
		IsSelected		BIT,
		PartyGroupId	INT
	)
	-- set selected = true
	-- put each party to it individual group(indicated by -partyid)
	INSERT INTO @PartyList(PartyId,IsSelected,PartyGroupId)
	SELECT CAST(val AS INT),1,-1 * CAST(val AS INT) FROM dbo.strSplit(@PartyIds, ',')

	-- 1.2 to calculate minfee: need to select all party in same group
	-- 1.2.1 get actual party group id
	UPDATE p
	SET PartyGroupId=a.PartyGroupId
	FROM @PartyList p
	INNER JOIN dbo.LA_PartyGroupAssignment a WITH(NOLOCK) ON p.PartyId = a.PartyId

	-- 1.2.2 get party in same group
	INSERT INTO @PartyList(PartyId,PartyGroupId,IsSelected)
	SELECT DISTINCT a.PartyId, a.PartyGroupId,0
	FROM dbo.LA_PartyGroupAssignment a WITH(NOLOCK)
	WHERE a.PartyId NOT IN (SELECT b.PartyId FROM @PartyList b)
		AND a.PartyGroupId IN (SELECT c.PartyGroupId FROM @PartyList c)

	-- 1.3 include products that use to calculate discount
	-- discount type
	DECLARE @Rebate INT = 2
	DECLARE @DiscountIndividualFee INT = 1
	DECLARE @DiscountIndividualGrosswin INT = 3
	DECLARE @DiscountByGroupFee INT = 11
	DECLARE @DiscountByGroupGrosswin INT = 13

	-- calculation type
	DECLARE @ToBeDiscounted INT = 0
	DECLARE @ToBeCalculated INT = 1
	DECLARE @CalculateAndDiscount INT = 10

	-- 1.3.1 discount settings
	;WITH cte_DiscountGroup AS(
		SELECT DISTINCT a.DiscountGroupId, a.PartyID
		FROM dbo.LA_DiscountGroupAssignment a WITH(NOLOCK)
		INNER JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON p.DiscountGroupId=a.DiscountGroupId
		INNER JOIN @PartyList b ON a.PartyID=b.PartyId
		WHERE b.IsSelected=1
			AND p.ProductId IN (SELECT c.ProductId FROM @ProductList c WHERE c.ToBeDiscounted=1)
			AND p.CalculationType IN (@ToBeDiscounted, @CalculateAndDiscount)
	)
	-- 1.3.2
	-- put parties in discount group to its own group
	-- put parties of individual discount group to new unique virtual group, indicate by discountid & partyid
	SELECT DISTINCT h.DiscountGroupId, h.DiscountGroupType, a.PartyID, p.ProductId, p.CalculationType, a.IsApplyDiscount, h.CurrencyId, a.Remark,h.FromDate,
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

	-- 1.3.3 add discount calculation party
	INSERT INTO @PartyList(PartyId,PartyGroupId,IsSelected)
	SELECT DISTINCT a.PartyID, -a.PartyID, 0
	FROM #tmpDiscountSettings a
	LEFT JOIN @PartyList b ON a.PartyID = b.PartyId
	WHERE b.PartyId IS NULL AND a.CalculationType IN (@ToBeCalculated, @CalculateAndDiscount)

	-- 1.3.4 discount by currency
	DECLARE @tmpDiscountCurrency TABLE(DiscountGroupId SMALLINT, PartyId INT, CurrencyId INT)

	INSERT INTO @tmpDiscountCurrency(DiscountGroupId, PartyId, CurrencyId)
	SELECT c.DiscountGroupId, c.PartyID, c.CurrencyId
	FROM dbo.LA_DiscountGroupCurrency c WITH(NOLOCK)
	WHERE c.DiscountGroupId IN (SELECT DISTINCT d.DiscountGroupId FROM #tmpDiscountSettings d)

	-- 1.3.5 include discount calculation products
	INSERT INTO @ProductList(ProductId,ToBeDiscounted)
	SELECT DISTINCT ProductId,0
	FROM #tmpDiscountSettings
	WHERE CalculationType IN (@ToBeCalculated, @CalculateAndDiscount)
		AND ProductId NOT IN (SELECT p.ProductId FROM @ProductList p)

	-- remove unsupported products
	DELETE @ProductList WHERE ProductID IN (1,3,23,13,14,17,15,25) -- exclude RB,BA,NG2,bettrade,MGCLC,MGCRNG,CB,CO

	IF(NOT EXISTS (SELECT TOP 1 ProductId FROM @ProductList))
	BEGIN
		SELECT	0 AS PartyId
				,0	AS ProductId
				,0	AS Winloss
				,0	AS Fee
				,0	AS NegativeFee
				,0	AS Minfee
				,0	AS IsChargedByMinFee
				,0	AS Discount
				,0	AS DiscountRate
				,N''AS DiscountRemark
				,0	AS Rebate
				,0	AS RebateRate
				,N''AS RebateRemark
		WHERE 1 = 2

		DROP TABLE #tmpDiscountSettings
		RETURN;
	END

	-- 1.5 update product code list
	SET @ProductCodes = NULL
	SELECT @ProductCodes = COALESCE((@ProductCodes + ',' + ProductPrefix), ProductPrefix)
	FROM dbo.LA_f_Products3rd('') a
	WHERE a.ProductID IN (SELECT DISTINCT b.ProductId FROM @ProductList b)

	-- 1.6 update party id list
	SET @PartyIds = NULL
	SELECT @PartyIds = COALESCE((@PartyIds + ',' + CAST(PartyId AS VARCHAR(10))), CAST(PartyId AS VARCHAR(10)))
	FROM (SELECT DISTINCT b.PartyId FROM @PartyList b) a
	
	-- 1.7 charge info
	SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, CAST(ci.DI_Rate AS DECIMAL(6,5)) AS Rate, ci.Fromdate, ci.ToDate 
					,CASE WHEN ProductID=11 AND ChargeType=12 THEN @GD_Tip ELSE -1 END AS Bettype -- GD Tip
	INTO #tmpChargeInfo
	FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
	WHERE DI_Rate > 0

	-- 1.7 exchange
	SELECT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate
	INTO #tmpExchange
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrency)
	WHERE ExchangeDate BETWEEN @FromDate AND @ToDate

	-- 1.8 minfee settings
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

	IF(@CurrencyId = 0)
	BEGIN
		-- 1.8.1 minfee
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
		INNER JOIN @PartyList p ON mf.PartyId = p.PartyId
		INNER JOIN @ProductList c ON mf.ProductId=c.ProductID
		WHERE mf.FeeTypeId = 1 AND @FromDate <= mf.ToDate AND mf.FromDate <= @ToDate

		-- 1.8.2 waive
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

		-- 1.8.3 exchange minfee amount to base currency
		UPDATE m SET m.FeeAmount = m.FeeAmount * e.Rate
		FROM @tmpMinFee m
		INNER JOIN #tmpExchange e ON m.ToDate = e.ExchangeDate AND m.CurrencyId = e.ExchangeID

		-- 1.8.4 calculate minfee amount(exclude waive time)
		-- (days in charged - days in waived) * FeeAmount / days in month
		;WITH waivedDays AS (
			SELECT MinFeeId, SUM(DATEDIFF(DAY, FromDate,ToDate) + 1) WaivedDays
			FROM @tmpMinFee
			WHERE FeeType = 2
			GROUP BY MinFeeId
		)
		UPDATE m SET m.MinFeeAmount = ((DATEDIFF(DAY, m.FromDate,m.ToDate) + 1) - ISNULL(w.WaivedDays,0)) * CAST(m.FeeAmount AS DECIMAL(20,10)) / @DaysInMonth
		FROM @tmpMinFee m
		LEFT JOIN waivedDays w ON m.MinFeeId=w.MinFeeId
		WHERE m.FeeType = 1
	END

/*--------------------------------------------------------------------------------------------------------------------------------
 * 2. winloss data
 *-------------------------------------------------------------------------------------------------------------------------------*/
	DECLARE @BX INT = 31 -- exchange

	-- 2.1 include general products
	SELECT p.PartyId,
		b.rptDate	AS WinlossDate,
		p.ProductId,
		b.CurrencyId,
		SUM(CASE WHEN b.Bettype = @GD_Tip OR b.Bettype = @PromotionPrize THEN 0 ELSE ISNULL(-b.MemberWL, 0) * e.Rate END) AS Winloss,
		SUM(CASE WHEN b.Bettype = @GD_Tip OR b.Bettype = @PromotionPrize THEN 0 ELSE ISNULL(-b.MemberWL, 0) * p.Rate * e.Rate END) AS AmountToCompany,
		SUM(CASE 
			WHEN b.Bettype = @GD_Tip THEN ISNULL(-b.MemberWL, 0) * p.Rate * e.Rate
			WHEN b.ProductID = @BX THEN -(b.CommissionA + b.CommissionP) * e.Rate
			ELSE 0 END) AS ExtraAmount, 
		SUM(CASE WHEN b.Bettype = @PromotionPrize THEN ISNULL(b.MemberWL, 0) * e.Rate ELSE 0 END) AS WinningPrize 
	INTO #tmpWinlossData
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
	INNER JOIN #tmpExchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
	INNER JOIN #tmpChargeInfo p ON b.ProductId = p.ProductID 
		AND p.LicenseeId = b.SiteId
		AND (b.rptDate BETWEEN p.FromDate AND p.ToDate) 
		AND (p.ProductID <> 11 OR b.Bettype = p.Bettype)
	WHERE (b.rptDate BETWEEN @FromDate AND @ToDate)
			AND b.customercategory NOT IN (27, 28)
			AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
			AND (@CurrencyId = 0 OR b.CurrencyId = @CurrencyId)
	GROUP BY p.PartyId,b.rptdate,p.ProductId,b.CurrencyId

	-- 2.2 insert product don't have any ticket
	INSERT INTO #tmpWinlossData (PartyId,WinlossDate,ProductId,CurrencyId,Winloss,AmountToCompany,ExtraAmount,WinningPrize)
	SELECT DISTINCT PartyId,@ToDate,c.ProductId,6, 0, 0, 0, 0-- default eur = 6
	FROM @PartyList p 
	INNER JOIN @ProductList pd ON 1=1
	INNER JOIN dbo.OAS_ChargeInfo c WITH(NOLOCK) ON c.ProductID = pd.ProductID AND p.PartyId = c.FromParty
	WHERE c.ToDate >= @FromDate

	-- 2.3 create result
	SELECT a.PartyId,a.ProductId
		,CAST(SUM(a.Winloss) AS MONEY) AS Winloss
		,CAST(SUM(a.AmountToCompany) AS MONEY) AS AmountToCompany 
		,CAST(SUM(a.ExtraAmount) AS MONEY) AS ExtraAmount
		,CAST(SUM(a.WinningPrize) AS MONEY) AS WinningPrize
		,CAST(0 AS MONEY) AS Fee
		,CAST(0 AS MONEY) AS Discount
		,CAST(0 AS MONEY) AS Rebate
		,CAST(0 AS MONEY) AS DiscountRate
		,CAST(0 AS MONEY) AS RebateRate
		,CAST('' AS NVARCHAR(4000)) AS DiscountRemark
		,CAST('' AS NVARCHAR(4000)) AS RebateRemark
		,CAST(0 AS MONEY)			AS Minfee
		,CAST(0 AS BIT)				AS IsChargedByMinFee
		,CAST(0 AS BIT)				AS IsApplyMinfeeToDiscount
	INTO #tmpResult
	FROM #tmpWinlossData a
	GROUP BY PartyId, ProductId

	-- 2.4 treat negative as 0
	UPDATE #tmpResult SET Fee = CASE WHEN AmountToCompany < 0 AND ProductID NOT IN (@BX) THEN 0 ELSE AmountToCompany END

/*--------------------------------------------------------------------------------------------------------------------------------
 * 3. minfee calculation
 *-------------------------------------------------------------------------------------------------------------------------------*/
	-- 3.1 sum data to 2 parts
	-- under waive time
	-- out of waive time
	;WITH Fee AS(
		SELECT m.MinFeeId
			, SUM(CASE WHEN w.ProductId IS NULL THEN 0 ELSE t.AmountToCompany END) FeeUnderWaiveTime
			, SUM(CASE WHEN w.ProductId IS NULL THEN t.AmountToCompany ELSE 0 END) FeeOutOfWaiveTime
		FROM #tmpWinlossData t
		INNER JOIN @tmpMinFee m ON t.ProductId = m.ProductId AND t.PartyId = m.PartyId AND t.WinlossDate BETWEEN m.FromDate AND m.ToDate
		LEFT JOIN @tmpMinFee w ON w.FeeType=2 AND w.MinFeeId=m.MinFeeId AND t.WinlossDate BETWEEN w.FromDate AND w.ToDate
		WHERE m.FeeType=1
		GROUP BY  m.MinFeeId
	)
	UPDATE mf SET
		FeeUnderWaiveTime = CASE WHEN f.FeeUnderWaiveTime < 0 THEN 0 ELSE f.FeeUnderWaiveTime END,
		FeeOutOfWaiveTime = CASE WHEN f.FeeOutOfWaiveTime < 0 THEN 0 ELSE f.FeeOutOfWaiveTime END
	FROM @tmpMinFee mf INNER JOIN Fee f ON mf.MinFeeId=f.MinFeeId
	WHERE mf.FeeType=1

	--3.2 calculate total minfee by group
	DECLARE @TotalMinFees TABLE(
		PartyGroupId	INT,
		ProductId		INT,
		TotalMinFee		MONEY,
		TotalAmount		MONEY
	)
	INSERT INTO @TotalMinFees(PartyGroupId,ProductId, TotalMinFee, TotalAmount)
	SELECT p.PartyGroupId, mf.ProductId, SUM(mf.MinFeeAmount), SUM(mf.FeeOutOfWaiveTime)
	FROM @tmpMinFee mf
	INNER JOIN @PartyList p ON mf.PartyId = p.PartyId
	WHERE mf.FeeType = 1
	GROUP BY p.PartyGroupId, mf.ProductId

	-- 3.3 calculate actual licensing fee
	UPDATE r SET Fee = CASE
			WHEN t.TotalAmount < t.TotalMinFee AND a.FeeOutOfWaiveTime < a.MinFeeAmount
				THEN a.MinFeeAmount + a.FeeUnderWaiveTime
			ELSE a.FeeOutOfWaiveTime + a.FeeUnderWaiveTime
		END,
		IsChargedByMinFee = CASE
			WHEN t.TotalAmount < t.TotalMinFee AND a.FeeOutOfWaiveTime < a.MinFeeAmount
				THEN 1
			ELSE 0
		END,
		IsApplyMinfeeToDiscount = CASE
			WHEN a.MinFeeAmount < a.FeeAmount AND a.FeeAmount > 0 AND b.FeeType IS NOT NULL THEN 0-- waived
			WHEN t.TotalAmount >= t.TotalMinFee AND p.PartyGroupId > 0 THEN 0 -- reach group minfee goal
			ELSE 1 END,
		Minfee = a.MinFeeAmount
	FROM #tmpResult r
	INNER JOIN @PartyList p ON r.PartyId=p.PartyId
	INNER JOIN @tmpMinFee a ON a.PartyId = r.PartyId AND a.ProductId=r.ProductID AND a.FeeType = 1 -- minfee setting
	INNER JOIN @TotalMinFees t ON a.ProductId = t.ProductId AND t.PartyGroupId=p.PartyGroupId
	LEFT JOIN @tmpMinFee b ON b.PartyId = r.PartyId AND b.ProductId=r.ProductID AND b.FeeType = 2-- waive setting

/*--------------------------------------------------------------------------------------------------------------------------------
 * 4. discount calculation
 *-------------------------------------------------------------------------------------------------------------------------------*/
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

	-- 4.1 discount by all currency
	INSERT INTO @tmpDiscountCalculation(CalculationGroup,DiscountGroupId,DiscountGroupType,CurrencyId,Winloss,Fee,IsDiscountByCurrency)
	SELECT s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId, SUM(r.Winloss) Winloss,SUM(r.Fee) Fee,0
	FROM #tmpDiscountSettings s
	INNER JOIN @tmpDiscountCurrency c ON s.PartyId = c.PartyId AND c.DiscountGroupId=s.DiscountGroupId AND c.CurrencyId = 0 -- all currency
	INNER JOIN #tmpResult r ON s.PartyID = r.PartyId AND s.ProductId=r.ProductId
	WHERE s.CalculationType IN (@ToBeCalculated,@CalculateAndDiscount)
	GROUP BY s.DiscountGroupId, s.DiscountGroupType,s.CurrencyId,s.CalculationGroup

	-- 4.2 discount by currency
	-- only offer discount for licensing fee
	INSERT INTO @tmpDiscountCalculation(CalculationGroup,DiscountGroupId,DiscountGroupType,CurrencyId,Winloss,Fee,IsDiscountByCurrency)
	SELECT s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId, SUM(r.Winloss) Winloss,SUM(r.AmountToCompany) Fee,1
	FROM #tmpWinlossData r
	INNER JOIN @tmpDiscountCurrency c ON c.PartyID=r.PartyId AND c.CurrencyId=r.CurrencyId
	INNER JOIN #tmpDiscountSettings s ON s.DiscountGroupId=c.DiscountGroupId AND s.ProductId = r.ProductId AND s.PartyId = c.PartyId
	WHERE s.CalculationType IN (@ToBeCalculated,@CalculateAndDiscount)
		AND s.DiscountGroupType IN (@DiscountIndividualFee, @DiscountByGroupFee)
	GROUP BY s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId

	DECLARE @Rate TABLE(Rate DECIMAL(6,5), CalculationGroup INT, IsDiscountByCurrency BIT)
	
	-- 4.3 get rate
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

	-- 4.4 discount by all currencies
	UPDATE r SET DiscountRemark = s.Remark, DiscountRate = c.Rate
		,Discount = CASE
			WHEN s.DiscountGroupType IN (@DiscountByGroupFee, @DiscountIndividualFee) THEN c.Rate * r.Fee
			WHEN s.DiscountGroupType IN (@DiscountByGroupGrosswin, @DiscountIndividualGrosswin) THEN c.Rate * (CASE WHEN r.Winloss < 0 THEN 0 ELSE r.Winloss END)
		ELSE 0 END
	FROM #tmpResult r
	INNER JOIN #tmpDiscountSettings s ON s.PartyID = r.PartyId AND s.ProductId=r.ProductId
	INNER JOIN @Rate c ON c.CalculationGroup = s.CalculationGroup
	WHERE s.CalculationType IN (@ToBeDiscounted,@CalculateAndDiscount) 
		AND s.IsApplyDiscount = 1
		AND c.IsDiscountByCurrency = 0

	-- 4.5 discount by curency
	-- not support gross win
	-- not support multiple products
	-- not discount if fee after discount less than minfee
	;WITH cte_DiscountByCurrency AS(
		SELECT c.CalculationGroup, c.Rate, c.Rate * (CASE WHEN s.Fee <0 THEN 0 ELSE s.Fee END) Discount
		FROM @tmpDiscountCalculation s
		INNER JOIN @rate c ON c.CalculationGroup = s.CalculationGroup
		WHERE c.IsDiscountByCurrency = 1
	)
	UPDATE t SET
		DiscountRemark = s.Remark
		, DiscountRate = d.Rate
		, Discount = CASE WHEN (t.Fee - d.Discount) < t.Minfee AND t.IsApplyMinfeeToDiscount=1 THEN t.Fee - t.Minfee ELSE d.Discount END
	FROM #tmpResult t
	INNER JOIN #tmpDiscountSettings s ON t.PartyID = s.PartyID AND t.ProductID=s.ProductId
	INNER JOIN cte_DiscountByCurrency d on d.CalculationGroup=s.CalculationGroup
	WHERE d.Discount > 0

	-- 4.6 apply new discount term for licensee have not shared minfee
	-- fee after discount must >= minfee
	IF (@FromDate >= @ApplyMinfeeToDiscountDate AND @IsApplyDiscountMinfee = 1)
	BEGIN
		UPDATE #tmpResult SET Discount = Fee - Minfee WHERE (Fee - Discount) < Minfee AND IsApplyMinfeeToDiscount = 1
	END

	UPDATE #tmpResult SET DiscountRate=0, DiscountRemark='', Discount = 0 WHERE Discount <= 0

/*--------------------------------------------------------------------------------------------------------------------------------
 * 5. rebate calculation
 *-------------------------------------------------------------------------------------------------------------------------------*/
	-- 5.1 get rebate settings
	DECLARE @tmpRebateSettings TABLE(PartyId INT, ProductId INT, Rate DECIMAL(7,5), Remark NVARCHAR(4000), FromDate DATE)
	
	INSERT INTO @tmpRebateSettings(PartyId, ProductId, Rate, Remark, FromDate)
	SELECT a.PartyID, p.ProductId, d.Rate, h.Remark,h.FromDate
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
	INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON h.DiscountGroupId=a.DiscountGroupId
	INNER JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON p.DiscountGroupId=h.DiscountGroupId
	INNER JOIN dbo.LA_DiscountGroupDetail d WITH(NOLOCK) ON d.DiscountGroupId=h.DiscountGroupId
	INNER JOIN @PartyList l ON l.PartyId=a.PartyID AND l.IsSelected=1
	WHERE h.DiscountGroupType=@Rebate
		AND h.FromDate <= @ToDate
		AND h.ToDate >= @FromDate

	-- 5.2 only 1 rebate per month for product/party
	;WITH cte_Rebate AS (
		SELECT PartyID, ProductId, MAX(FromDate) FromDate
		FROM @tmpRebateSettings
		GROUP BY PartyID, ProductId
		HAVING COUNT(1) > 1
	)
	DELETE r FROM @tmpRebateSettings r INNER JOIN cte_Rebate c ON r.FromDate < c.FromDate
		AND c.PartyID = r.PartyID 
		AND c.ProductId = r.ProductId

	-- 5.3 calculate rebate
	UPDATE r SET 
		Rebate = (r.Fee - r.Discount) * c.Rate,
		RebateRemark = c.Remark,
		RebateRate = c.Rate
	FROM #tmpResult r INNER JOIN @tmpRebateSettings c ON r.PartyId = c.PartyID AND r.ProductId = c.ProductId

	-- result
	SELECT PartyId
		,ProductId
		,Winloss + WinningPrize AS Winloss 
		,Fee + ExtraAmount - WinningPrize AS Fee
		,CASE WHEN IsChargedByMinFee = 1 AND Fee > 0 THEN Fee ELSE AmountToCompany END NegativeFee
		,Minfee
		,IsChargedByMinFee
		,Discount
		,DiscountRate
		,DiscountRemark
		,Rebate
		,RebateRate
		,RebateRemark
	FROM #tmpResult
	WHERE PartyId IN (SELECT a.PartyId FROM @PartyList a WHERE a.IsSelected = 1)
		AND ProductId IN (SELECT b.ProductId FROM @ProductList b WHERE b.ToBeDiscounted = 1)

	DROP TABLE #tmpExchange
	DROP TABLE #tmpChargeInfo
	DROP TABLE #tmpWinlossData
	DROP TABLE #tmpDiscountSettings
	DROP TABLE #tmpResult
END
GO
