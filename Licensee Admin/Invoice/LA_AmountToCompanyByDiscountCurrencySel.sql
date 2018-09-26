/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_AmountToCompanyByDiscountCurrencySel] (
	@FromDate		DATE,
	@ToDate			DATE,
	@PartyIds		VARCHAR(4000) = '',
	@ProductCodes	VARCHAR(1000) = '',
	@BaseCurrencyName VARCHAR(10) = 'EUR',
	@CurrencyId		INT = 0
)
AS
/*	Created: 20180924@Parsons
	Task : select amount to company by discount currency
	DB: DB052/bodb_Licensee
	Revisions:
		- 20180924@Parsons: LA - LPID report - Apply one discount rate across all base currencies [#100046]
*/
BEGIN
/*--------------------------------------------------------------------------------------------------------------------------------
 * 1. Prepare settings
 *-------------------------------------------------------------------------------------------------------------------------------*/
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

	-- 1.4 include discount calculation products
	INSERT INTO @ProductList(ProductId,ToBeDiscounted)
	SELECT DISTINCT ProductId,0
	FROM #tmpDiscountSettings
	WHERE CalculationType IN (@ToBeCalculated, @CalculateAndDiscount)
		AND ProductId NOT IN (SELECT p.ProductId FROM @ProductList p)

	-- remove unsupported products
	DELETE @ProductList WHERE ProductID IN (1,3,23,13,14,17,31,15,25) -- exclude RB,BA,NG2,bettrade,MGCLC,MGCRNG,BX,CB,CO
	
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
	SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, ci.DI_Rate AS Rate, ci.Fromdate, ci.ToDate
	INTO #tmpChargeInfo
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
	WHERE DI_Rate > 0

	-- 1.7 exchange
	DECLARE @tempCurrencyName VARCHAR(10), @tempCurrencyId INT
	DECLARE @BaseCurrencies TABLE(Id INT, Name VARCHAR(20), IsApply BIT )

	CREATE TABLE #tmpExchange (
		ExchangeDate		DATETIME,
		ExchangeId			INT,
		Rate				FLOAT,
		CurrencyId		INT,
		CurrencyName	VARCHAR(10),
		IsBaseCurrency		BIT
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	SELECT DISTINCT ds.CurrencyId, e.Code 
	FROM #tmpDiscountSettings ds
	INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON e.exchangeid = ds.CurrencyId

	WHILE EXISTS (SELECT 1 FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SELECT @tempCurrencyId = Id, @tempCurrencyName = Name FROM @BaseCurrencies WHERE IsApply IS NULL

		INSERT INTO #tmpExchange(ExchangeDate, ExchangeId, Rate, CurrencyId, CurrencyName, IsBaseCurrency)
		SELECT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate, @tempCurrencyId, @tempCurrencyName, 0
		FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrencyName)
		WHERE ExchangeDate BETWEEN @FromDate AND @ToDate

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrencyName 
	END
	IF(NOT EXISTS(SELECT 1 FROM #tmpExchange WHERE CurrencyName = @BaseCurrencyName))
	BEGIN
		DECLARE @BaseCurrencyId INT
		SELECT TOP 1 @BaseCurrencyId = exchangeID FROM bodb02.dbo.Exchange WITH (NOLOCK) WHERE Code = @BaseCurrencyName
		INSERT INTO #tmpExchange(ExchangeDate, ExchangeId, Rate, CurrencyId, CurrencyName, IsBaseCurrency)
		SELECT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate, @BaseCurrencyId, @BaseCurrencyName, 1
		FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
		WHERE ExchangeDate BETWEEN @FromDate AND @ToDate
	END
	ELSE
	BEGIN
		UPDATE #tmpExchange
		SET IsBaseCurrency = 1
		WHERE CurrencyName = @BaseCurrencyName
	END
	
	-- 1.8 minfee settings
	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FromDate), 0)
	DECLARE @LastDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FromDate) + 1, 0))
	DECLARE @Month TINYINT = MONTH(@FromDate)
	DECLARE @DaysInMonth INT = DATEDIFF(DAY, @FirstDate, @LastDate) + 1

	CREATE TABLE #tmpMinFee (
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
		MinFeeId		INT,
		IsBaseCurrency	BIT 
	)

	IF(@CurrencyId = 0)
	BEGIN
		-- 1.8.1 minfee
		INSERT INTO #tmpMinFee(FeeType ,PartyId,ProductId, CurrencyId ,FeeAmount ,FromDate ,ToDate, MinFeeId, IsBaseCurrency)
		SELECT mf.FeeTypeId,
			mf.PartyId,
			mf.ProductId,
			mf.CurrencyId,
			mf.FeeAmount,
			CASE WHEN @FromDate >= mf.FromDate THEN @FromDate ELSE mf.FromDate END AS FromDate,
			CASE WHEN @ToDate < mf.ToDate THEN @ToDate ELSE mf.ToDate END AS ToDate,
			mf.MinFeeId,
			0 AS IsBaseCurrency
		FROM dbo.LA_MinFee mf WITH(NOLOCK)
		INNER JOIN @PartyList p ON mf.PartyId = p.PartyId
		INNER JOIN @ProductList c ON mf.ProductId=c.ProductID
		WHERE mf.FeeTypeId = 1 AND @FromDate <= mf.ToDate AND mf.FromDate <= @ToDate

		-- 1.8.2 waive
		INSERT INTO #tmpMinFee(FeeType ,PartyId,ProductId, FromDate ,ToDate, MinFeeId, IsBaseCurrency)
		SELECT w.FeeTypeId,
			w.PartyId,
			w.ProductId,
			CASE WHEN w.FromDate < m.FromDate THEN m.FromDate ELSE w.FromDate END,
			CASE WHEN w.ToDate > m.ToDate THEN m.ToDate ELSE w.ToDate END,
			m.MinFeeId,
			0 AS IsBaseCurrency
		FROM dbo.LA_MinFee w WITH(NOLOCK)
		INNER JOIN #tmpMinFee m ON w.PartyId=m.PartyId AND w.ProductId=m.ProductId
		WHERE w.FeeTypeId = 2 AND w.FromDate <= m.ToDate AND m.FromDate <= w.ToDate

		-- 1.8.3 clone #tmpMinFee out to base currency version.
		INSERT INTO #tmpMinFee(FeeType,PartyId,ProductId,CurrencyId,FeeAmount,FromDate,ToDate,MinFeeId,IsBaseCurrency)
		SELECT FeeType,PartyId,ProductId,CurrencyId,FeeAmount,FromDate,ToDate,MinFeeId,1 
		FROM #tmpMinFee

		-- 1.8.4 exchange minfee amount to currency accordingly
			--1.8.4.1 discount currency	
		UPDATE m SET m.FeeAmount = m.FeeAmount * e.Rate
		FROM #tmpMinFee m
		INNER JOIN #tmpExchange e ON m.ToDate = e.ExchangeDate AND m.CurrencyId = e.ExchangeID
		INNER JOIN #tmpDiscountSettings ds ON e.CurrencyId = ds.CurrencyId AND ds.PartyId = m.PartyID
		WHERE m.IsBaseCurrency = 0
			--1.8.4.2 base currency	
		UPDATE m SET m.FeeAmount = m.FeeAmount * e.Rate
		FROM #tmpMinFee m
		INNER JOIN #tmpExchange e ON m.ToDate = e.ExchangeDate AND m.CurrencyId = e.ExchangeID
		WHERE m.IsBaseCurrency = 1 AND e.IsBaseCurrency = 1

		-- 1.8.5 calculate minfee amount(exclude waive time)
		-- (days in charged - days in waived) * FeeAmount / days in month
		;WITH waivedDays AS (
			SELECT MinFeeId, SUM(DATEDIFF(DAY, FromDate,ToDate) + 1) WaivedDays
			FROM #tmpMinFee
			WHERE FeeType = 2
			GROUP BY MinFeeId
		)
		UPDATE m SET m.MinFeeAmount = ((DATEDIFF(DAY, m.FromDate,m.ToDate) + 1) - ISNULL(w.WaivedDays,0)) * CAST(m.FeeAmount AS DECIMAL(20,10)) / @DaysInMonth
		FROM #tmpMinFee m
		LEFT JOIN waivedDays w ON m.MinFeeId=w.MinFeeId
		WHERE m.FeeType = 1
	END
/*--------------------------------------------------------------------------------------------------------------------------------
 * 2. winloss data
 *-------------------------------------------------------------------------------------------------------------------------------*/
	CREATE TABLE #tmpWinlossData (
		PartyId			INT,
		ProductId		TINYINT,
		WinlossDate		DATE,
		Winloss			DECIMAL(20,5),
		AmountToCompany	DECIMAL(20,5),
		IsApplyMinFee	BIT,
		IsBaseCurrency	BIT
	)

	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #tmpWinlossData (PartyId, ProductId)

	-- 2.1 include general products
		-- 2.1.1 discount currency
	INSERT INTO #tmpWinlossData (PartyId,WinlossDate,ProductId,IsBaseCurrency,Winloss,AmountToCompany)
	(
		SELECT	p.PartyId,
				b.rptDate,
				p.ProductId,
				0 AS IsBaseCurrency,
				SUM(-ISNULL(b.MemberWL * e.Rate, 0)),
				SUM(-ISNULL(b.MemberWL * p.Rate * e.Rate, 0))
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #tmpExchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
			INNER JOIN #tmpChargeInfo p ON b.ProductId = p.ProductID 
					AND p.LicenseeId = b.SiteId
					AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
			INNER JOIN #tmpDiscountSettings ds ON e.CurrencyId = ds.CurrencyId AND ds.PartyId = p.PartyID
		WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
				AND (@CurrencyId = 0 OR b.CurrencyId = @CurrencyId)
		GROUP BY b.rptdate, b.SiteId, p.PartyId, p.ProductId
	)

		-- 2.1.2 base currency
	INSERT INTO #tmpWinlossData (PartyId,WinlossDate,ProductId,IsBaseCurrency,Winloss,AmountToCompany)
	(
		SELECT	p.PartyId,
				b.rptDate,
				p.ProductId,
				1 AS IsBaseCurrency,
				SUM(-ISNULL(b.MemberWL * e.Rate, 0)),
				SUM(-ISNULL(b.MemberWL * p.Rate * e.Rate, 0))
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #tmpExchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
			INNER JOIN #tmpChargeInfo p ON b.ProductId = p.ProductID 
					AND p.LicenseeId = b.SiteId
					AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
		WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
				AND (@CurrencyId = 0 OR b.CurrencyId = @CurrencyId)
				AND e.IsBaseCurrency = 1
		GROUP BY b.rptdate, b.SiteId, p.PartyId, p.ProductId
	)

	-- 2.2 insert product don't have any ticket
	INSERT INTO #tmpWinlossData (PartyId,WinlossDate,ProductId,Winloss,AmountToCompany,IsBaseCurrency)
	SELECT DISTINCT PartyId,@ToDate,c.ProductId, 0, 0, 1
	FROM @PartyList p 
	INNER JOIN @ProductList pd ON 1=1
	INNER JOIN dbo.OAS_ChargeInfo c WITH(NOLOCK) ON c.ProductID = pd.ProductID AND p.PartyId = c.FromParty
	WHERE c.ToDate >= @FromDate  
	
	-- 2.3 create result
	SELECT a.PartyId,a.ProductId, a.IsBaseCurrency
		,CAST(SUM(a.Winloss) AS MONEY) AS Winloss
		,CAST(SUM(a.AmountToCompany) AS MONEY) AS AmountToCompany
		,CAST(0 AS MONEY) AS Fee
		,CAST(0 AS DECIMAL(7, 5)) AS DiscountRate
		,CAST(0 AS DECIMAL(7, 5)) AS RebateRate
		,CAST(0 AS BIT)				AS IsChargedByMinFee
	INTO #tmpResult
	FROM #tmpWinlossData a
	GROUP BY PartyId, ProductId, a.IsBaseCurrency

	-- 2.4 treat negative as 0
	UPDATE #tmpResult SET Fee = CASE WHEN AmountToCompany < 0 THEN 0 ELSE AmountToCompany END
/*--------------------------------------------------------------------------------------------------------------------------------
 * 3. minfee calculation
 *-------------------------------------------------------------------------------------------------------------------------------*/
	-- 3.1 sum data to 2 parts
	-- under waive time
	-- out of waive time
	;WITH Fee AS(
		SELECT m.MinFeeId, t.IsBaseCurrency
			, SUM(CASE WHEN w.ProductId IS NULL THEN 0 ELSE t.AmountToCompany END) FeeUnderWaiveTime
			, SUM(CASE WHEN w.ProductId IS NULL THEN t.AmountToCompany ELSE 0 END) FeeOutOfWaiveTime
		FROM #tmpWinlossData t
		INNER JOIN #tmpMinFee m ON t.ProductId = m.ProductId AND t.PartyId = m.PartyId AND t.WinlossDate BETWEEN m.FromDate AND m.ToDate
		LEFT JOIN #tmpMinFee w ON w.FeeType=2 AND w.MinFeeId=m.MinFeeId AND t.WinlossDate BETWEEN w.FromDate AND w.ToDate
		WHERE m.FeeType=1
		GROUP BY  m.MinFeeId, t.IsBaseCurrency
	)
	UPDATE mf SET
		FeeUnderWaiveTime = CASE WHEN f.FeeUnderWaiveTime < 0 THEN 0 ELSE f.FeeUnderWaiveTime END,
		FeeOutOfWaiveTime = CASE WHEN f.FeeOutOfWaiveTime < 0 THEN 0 ELSE f.FeeOutOfWaiveTime END
	FROM #tmpMinFee mf INNER JOIN Fee f ON mf.MinFeeId=f.MinFeeId AND mf.IsBaseCurrency=f.IsBaseCurrency
	WHERE mf.FeeType=1
	
	--3.2 calculate total minfee by group
	DECLARE @TotalMinFees TABLE(
		PartyGroupId	INT,
		ProductId		INT,
		TotalMinFee		MONEY,
		TotalAmount		MONEY,
		IsBaseCurrency	BIT
	)
	INSERT INTO @TotalMinFees(PartyGroupId,ProductId,IsBaseCurrency,TotalMinFee,TotalAmount)
	SELECT p.PartyGroupId, mf.ProductId, IsBaseCurrency, SUM(mf.MinFeeAmount), SUM(mf.FeeOutOfWaiveTime)
	FROM #tmpMinFee mf
	INNER JOIN @PartyList p ON mf.PartyId = p.PartyId
	WHERE mf.FeeType = 1
	GROUP BY p.PartyGroupId, mf.ProductId, IsBaseCurrency

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
		END
	FROM #tmpResult r
	INNER JOIN @PartyList p ON r.PartyId=p.PartyId
	INNER JOIN #tmpMinFee a ON a.PartyId = r.PartyId AND a.ProductId=r.ProductID AND a.FeeType = 1
	INNER JOIN @TotalMinFees t ON a.ProductId = t.ProductId AND t.PartyGroupId=p.PartyGroupId AND r.IsBaseCurrency = t.IsBaseCurrency
	
/*--------------------------------------------------------------------------------------------------------------------------------
 * 4. discount calculation
 *-------------------------------------------------------------------------------------------------------------------------------*/
	DECLARE @Unlimited MONEY = 1000000000000

	;WITH cte_Calculation AS(
		SELECT s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId, SUM(r.Winloss) Winloss,SUM(r.Fee) Fee
		FROM #tmpDiscountSettings s
		INNER JOIN #tmpResult r ON s.PartyID = r.PartyId AND s.ProductId=r.ProductId
		WHERE s.CalculationType IN (@ToBeCalculated,@CalculateAndDiscount) AND r.IsBaseCurrency = 0
		GROUP BY s.DiscountGroupId, s.DiscountGroupType,s.CurrencyId,s.CalculationGroup
	), cte_Detail AS(
		SELECT c.CalculationGroup, d.DiscountGroupId, d.Rate
			,ISNULL(d.FromAmount,0) AS FromAmount
			,CASE WHEN d.ToAmount > @Unlimited THEN d.ToAmount ELSE (d.ToAmount + 1) END AS ToAmount
		FROM dbo.LA_DiscountGroupDetail d
		INNER JOIN cte_Calculation c ON d.DiscountGroupId=c.DiscountGroupId
	), cte_Rate AS (
		SELECT c.DiscountGroupId, d.Rate, c.CalculationGroup
		FROM cte_Calculation c INNER JOIN cte_Detail d ON c.CalculationGroup=d.CalculationGroup
		WHERE (
				c.DiscountGroupType IN (@DiscountByGroupFee, @DiscountIndividualFee) AND
				c.Fee >= d.FromAmount AND c.Fee < d.ToAmount
			) OR (
				c.DiscountGroupType IN (@DiscountByGroupGrosswin, @DiscountIndividualGrosswin) AND
				c.Winloss >= d.FromAmount AND c.Winloss < d.ToAmount
			)
	)
	UPDATE r SET DiscountRate = c.Rate
	FROM #tmpResult r
	INNER JOIN #tmpDiscountSettings s ON s.PartyID = r.PartyId AND s.ProductId=r.ProductId
	INNER JOIN cte_Rate c ON c.CalculationGroup = s.CalculationGroup
	WHERE s.CalculationType IN (@ToBeDiscounted,@CalculateAndDiscount) AND s.IsApplyDiscount = 1 AND r.IsBaseCurrency = 0
/*--------------------------------------------------------------------------------------------------------------------------------
 * 4. rebate calculation
 *-------------------------------------------------------------------------------------------------------------------------------*/
	-- 4.1 get rebate settings
	SELECT a.PartyID, p.ProductId, d.Rate, h.Remark,h.FromDate
	INTO #tmpRebateSettings
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
	INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON h.DiscountGroupId=a.DiscountGroupId
	INNER JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON p.DiscountGroupId=h.DiscountGroupId
	INNER JOIN dbo.LA_DiscountGroupDetail d WITH(NOLOCK) ON d.DiscountGroupId=h.DiscountGroupId
	INNER JOIN @PartyList l ON l.PartyId=a.PartyID AND l.IsSelected=1
	WHERE h.DiscountGroupType=@Rebate
		AND h.FromDate <= @ToDate
		AND h.ToDate >= @FromDate

	-- 4.2 only 1 rebate per month for product/party
	;WITH cte_Rebate AS (
		SELECT PartyID, ProductId, MAX(FromDate) FromDate
		FROM #tmpRebateSettings
		GROUP BY PartyID, ProductId
		HAVING COUNT(1) > 1
	)
	DELETE r FROM #tmpRebateSettings r INNER JOIN cte_Rebate c ON r.FromDate < c.FromDate
		AND c.PartyID = r.PartyID 
		AND c.ProductId = r.ProductId

	-- 4.3 calculate rebate
	UPDATE r SET RebateRate = c.Rate
	FROM #tmpResult r INNER JOIN #tmpRebateSettings c ON r.PartyId = c.PartyID AND r.ProductId = c.ProductId
	WHERE r.IsBaseCurrency = 0

	-- result
	;WITH cte_ResultByDiscountCurrency AS (
		SELECT PartyId, ProductId, DiscountRate, RebateRate, IsChargedByMinFee
		FROM #tmpResult
		WHERE IsBaseCurrency = 0
	)
	SELECT b.PartyId, b.ProductId, b.Fee,
			CASE
				WHEN s.DiscountGroupType IN (@DiscountByGroupFee, @DiscountIndividualFee) THEN ISNULL(d.DiscountRate, 0) * b.Fee
				WHEN s.DiscountGroupType IN (@DiscountByGroupGrosswin, @DiscountIndividualGrosswin) THEN ISNULL(d.DiscountRate, 0) * (CASE WHEN b.Winloss < 0 THEN 0 ELSE b.Winloss END)
				ELSE 0
			END AS Discount,
			(b.Fee - (CASE
						WHEN s.DiscountGroupType IN (@DiscountByGroupFee, @DiscountIndividualFee) THEN ISNULL(d.DiscountRate, 0) * b.Fee
						WHEN s.DiscountGroupType IN (@DiscountByGroupGrosswin, @DiscountIndividualGrosswin) THEN ISNULL(d.DiscountRate, 0) * (CASE WHEN b.Winloss < 0 THEN 0 ELSE b.Winloss END)
						ELSE 0
					  END)) * b.RebateRate AS Rebate,
			ISNULL(d.IsChargedByMinFee, 0 ) AS IsChargedByMinFee
	FROM #tmpResult b
	LEFT JOIN cte_ResultByDiscountCurrency d ON b.PartyId = d.PartyId AND b.ProductId = d.ProductId
	LEFT JOIN #tmpDiscountSettings s ON s.PartyID = b.PartyId AND s.ProductId=b.ProductId
	WHERE IsBaseCurrency = 1
		AND b.PartyId IN (SELECT a.PartyId FROM @PartyList a WHERE a.IsSelected = 1)
		AND b.ProductId IN (SELECT p.ProductId FROM @ProductList p WHERE p.ToBeDiscounted = 1)

	DROP TABLE #tmpExchange
	DROP TABLE #tmpChargeInfo
	DROP TABLE #tmpWinlossData
	DROP TABLE #tmpDiscountSettings
	DROP TABLE #tmpResult
	DROP TABLE #tmpMinFee
	DROP TABLE #tmpRebateSettings
END
GO