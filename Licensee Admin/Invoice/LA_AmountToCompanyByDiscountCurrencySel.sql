/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_AmountToCompanyByDiscountCurrencySel] (
	@FromDate			DATE,
	@ToDate				DATE,
	@PartyIds			VARCHAR(4000) = '',
	@ProductCodes		VARCHAR(1000) = '',
	@BaseCurrencyName	VARCHAR(10) = 'EUR',
	@BaseCurrencyId		INT = 6,
	@CurrencyId			INT = 0
)
AS
/*	Created: 20180924@Parsons
	Task : select amount to company by discount currency
	DB: DBLIC.bodb_Licensee
	
	Revisions:
		- 20180924@Parsons: LA - LPID report - Apply one discount rate across all base currencies [#100046]
		- 20181114@Bruce: discount by currency [#99694] 
		- 20181127@Parsons: Integrate Bidme games (GD product) [#103695]
		- 20190319@bruce: Apply min fee rule for discount calculation [#109997]
		- 20190410@bruce: calculate discount for terminated licensee[111485]
		- 20190417@Parsons: Integrate-PP-Promotion-Prize [#109014]
		- 20191125@Mason: Setup billing terms by Currency  [#120005]
		- 20191206@Parsons: PP tournament [#123958]
	    - 20200409@Parsons: Integrate SA Gaming [#129276]
		- 20200512@Parsons: Special handling for INH market [#128570]
*/
BEGIN
	SET NOCOUNT ON
	DECLARE @ApplyMinfeeToDiscountDate DATE = dbo.LA_f_ApplyDiscountMinfeeDate()
	
/*--------------------------------------------------------------------------------------------------------------------------------
 * 1. Prepare settings
 *-------------------------------------------------------------------------------------------------------------------------------*/
	DECLARE @GD_Tip SMALLINT = 1706,
			@SAG_Tip SMALLINT = 3007,
			@PPTournament SMALLINT = 4299,
			@PromotionPrize SMALLINT = 4300

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
	DELETE @ProductList WHERE ProductID IN (1,3,23,13,14,17,31,15,25) -- exclude RB,BA,NG2,bettrade,MGCLC,MGCRNG,BX,CB,CO
	
	IF(NOT EXISTS (SELECT TOP 1 ProductId FROM @ProductList))
	BEGIN
		SELECT 0 AS PartyId
				,0	AS ProductId
				,0	AS Fee
				,0	AS Discount
				,0	AS Rebate
				,0	AS IsChargedByMinFee
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
	SELECT DISTINCT ci.ChargeID, ci.PartyID, ci.LicenseeID, ci.ProductID, CAST(ci.DI_Rate AS DECIMAL(6,5)) AS Rate, ci.Fromdate, ci.ToDate 
					,CASE 
						WHEN ProductID=11 AND ChargeType=12 THEN @GD_Tip
						WHEN ProductID=39 AND ChargeType=12 THEN @SAG_Tip
						ELSE -1 
					END AS Bettype -- Tips
	INTO #tmpChargeInfo
	FROM dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
	WHERE DI_Rate > 0

	-- 1.7 exchange
	DECLARE @tempCurrencyName VARCHAR(10), @tempCurrencyId INT
	DECLARE @BaseCurrencies TABLE(Id INT, [Name] VARCHAR(10))

	CREATE TABLE #tmpExchange (
		ExchangeDate		DATETIME,
		ExchangeId			INT,
		Rate				FLOAT,
		BaseCurrencyId		INT
	)
	CREATE NONCLUSTERED INDEX Idx_tmpExchange ON #tmpExchange (BaseCurrencyId, ExchangeDate, ExchangeId)

	INSERT INTO @BaseCurrencies(Id)
	SELECT DISTINCT ds.CurrencyId FROM #tmpDiscountSettings ds

	IF NOT EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies WHERE Id = @BaseCurrencyId)
	BEGIN
		INSERT INTO @BaseCurrencies(Id) VALUES(@BaseCurrencyId)
	END

	WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies)
	BEGIN
		SELECT TOP 1 @tempCurrencyId = Id, @tempCurrencyName = e.Code
		FROM @BaseCurrencies b
		INNER JOIN bodb02.dbo.Exchange e WITH (NOLOCK) ON e.exchangeid = b.Id

		INSERT INTO #tmpExchange(ExchangeDate, ExchangeId, Rate, BaseCurrencyId)
		SELECT ExchangeDate, ExchangeId, BaseCurrencyRate, @tempCurrencyId
		FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrencyName)

		DELETE @BaseCurrencies WHERE Id = @tempCurrencyId 
	END

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
		FeeAmountByDiscountBaseCurrency	MONEY,
		FeeAmountByBaseCurrency		MONEY,
		FromDate		DATETIME,
		ToDate			DATETIME,
		FeeUnderWaiveTimeByDiscountBaseCurrency	MONEY,
		FeeUnderWaiveTimeByBaseCurrency		MONEY,
		FeeOutOfWaiveTimeByDiscountBaseCurrency	MONEY,
		FeeOutOfWaiveTimeByBaseCurrency		MONEY,
		MinFeeAmountByDiscountBaseCurrency			MONEY,
		MinFeeAmountByBaseCurrency				MONEY,
		MinFeeId					INT
	)

	IF(@CurrencyId = 0)
	BEGIN
		-- 1.8.1 minfee
		INSERT INTO @tmpMinFee(FeeType,PartyId,ProductId,CurrencyId,FeeAmountByDiscountBaseCurrency,FeeAmountByBaseCurrency,FromDate,ToDate,MinFeeId,FeeUnderWaiveTimeByDiscountBaseCurrency,FeeUnderWaiveTimeByBaseCurrency,FeeOutOfWaiveTimeByDiscountBaseCurrency,FeeOutOfWaiveTimeByBaseCurrency)
		SELECT mf.FeeTypeId,
			mf.PartyId,
			mf.ProductId,
			mf.CurrencyId,
			mf.FeeAmount,
			mf.FeeAmount,
			CASE WHEN @FromDate >= mf.FromDate THEN @FromDate ELSE mf.FromDate END AS FromDate,
			CASE WHEN @ToDate < mf.ToDate THEN @ToDate ELSE mf.ToDate END AS ToDate,
			mf.MinFeeId,
			0,0,0,0
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

		-- 1.8.3 exchange minfee amount to currency accordingly
		UPDATE m 
			SET m.FeeAmountByDiscountBaseCurrency = m.FeeAmountByDiscountBaseCurrency * ISNULL(ed.Rate, eb.Rate),
				m.FeeAmountByBaseCurrency = m.FeeAmountByBaseCurrency * eb.Rate
		FROM @tmpMinFee m
		INNER JOIN #tmpExchange eb ON m.ToDate = eb.ExchangeDate AND m.CurrencyId = eb.ExchangeID AND eb.BaseCurrencyId = @BaseCurrencyId
		LEFT JOIN #tmpDiscountSettings ds ON ds.PartyId = m.PartyID AND m.ProductId = ds.ProductID 
		LEFT JOIN #tmpExchange ed ON m.ToDate = ed.ExchangeDate AND m.CurrencyId = ed.ExchangeID AND ed.BaseCurrencyId = ds.CurrencyId

		-- 1.8.4 calculate minfee amount(exclude waive time)
		-- (days in charged - days in waived) * FeeAmount / days in month
		;WITH waivedDays AS (
			SELECT MinFeeId, SUM(DATEDIFF(DAY, FromDate,ToDate) + 1) WaivedDays
			FROM @tmpMinFee
			WHERE FeeType = 2
			GROUP BY MinFeeId
		)
		UPDATE m 
			SET m.MinFeeAmountByDiscountBaseCurrency = ((DATEDIFF(DAY, m.FromDate,m.ToDate) + 1) - ISNULL(w.WaivedDays,0)) * CAST(m.FeeAmountByDiscountBaseCurrency AS DECIMAL(20,10)) / @DaysInMonth,
				m.MinFeeAmountByBaseCurrency = ((DATEDIFF(DAY, m.FromDate,m.ToDate) + 1) - ISNULL(w.WaivedDays,0)) * CAST(m.FeeAmountByBaseCurrency AS DECIMAL(20,10)) / @DaysInMonth
		FROM @tmpMinFee m
		LEFT JOIN waivedDays w ON m.MinFeeId=w.MinFeeId
		WHERE m.FeeType = 1
	END
/*--------------------------------------------------------------------------------------------------------------------------------
 * 2. winloss data
 *-------------------------------------------------------------------------------------------------------------------------------*/
	-- 2.1 include general products
	SELECT	p.PartyId,
			b.rptDate AS WinlossDate,
			p.ProductId,
			b.CurrencyId, 
			CASE WHEN b.Bettype IN (@GD_Tip, @SAG_Tip) THEN 0 ELSE ISNULL(b.MemberWL, 0) END AS MemberWL,
			CASE WHEN b.Bettype IN (@GD_Tip, @SAG_Tip) THEN 0 ELSE ISNULL(b.MemberWL, 0) * ISNULL(cr.Rate, p.Rate) END AS Amount,
			CASE WHEN b.Bettype IN (@GD_Tip, @SAG_Tip) THEN ISNULL(b.MemberWL, 0) * ISNULL(cr.Rate, p.Rate) ELSE 0 END AS ExtraAmount
	INTO #temData
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN #tmpChargeInfo p ON p.LicenseeId = b.SiteId 
				AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
				AND b.ProductId = p.ProductID   
				AND (p.ProductID NOT IN (11,39) OR b.Bettype = p.Bettype)
				AND (b.Bettype NOT IN (@PPTournament, @PromotionPrize))
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON p.ChargeID = cr.ChargeID AND b.CurrencyId = cr.CurrencyID
	WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate)
			AND b.customercategory NOT IN (27, 28)
			AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
			AND (@CurrencyId = 0 OR b.CurrencyId = @CurrencyId)

	-- 2.2 convert to base
	SELECT	t.WinlossDate,
			t.PartyId,
			t.ProductId,
			SUM(-t.MemberWL * eb.Rate) AS WinlossByBaseCurrency,
			SUM(-t.Amount * eb.Rate) AS AmountToCompanyByBaseCurrency, 
			SUM(-t.ExtraAmount * eb.Rate)	AS ExtraAmount,
			CAST(0 AS MONEY) WinlossByDiscountBaseCurrency,
			CAST(0 AS MONEY) AmountToCompanyByDiscountBaseCurrency,
			t.CurrencyId
		INTO #tmpWinlossData
	FROM #temData t
		INNER JOIN #tmpExchange eb ON eb.ExchangeDate = t.WinlossDate AND eb.BaseCurrencyId = @BaseCurrencyId AND eb.ExchangeID = t.CurrencyId
	GROUP BY t.WinlossDate, t.PartyId, t.ProductId, t.CurrencyId

	-- 2.3 convert to discount base
	;WITH cte_winlossByDiscountBaseCurrency AS (
		SELECT	t.WinlossDate,
				t.PartyId,
				t.ProductId,
				t.CurrencyId,
				SUM(-ISNULL(t.MemberWL * ed.Rate, 0)) AS WinlossByDiscountBaseCurrency,
				SUM(-ISNULL(t.Amount * ed.Rate, 0)) AS AmountToCompanyByDiscountBaseCurrency
		FROM #temData t
			INNER JOIN #tmpDiscountSettings ds ON ds.PartyId = t.PartyID AND t.ProductId = ds.ProductID 
			INNER JOIN #tmpExchange ed ON t.WinlossDate = ed.ExchangeDate AND t.CurrencyId = ed.ExchangeID AND ed.BaseCurrencyId = ds.CurrencyId
		GROUP BY t.WinlossDate, t.PartyId, t.ProductId, t.CurrencyId
	)
	UPDATE t
	SET WinlossByDiscountBaseCurrency = ISNULL(c.WinlossByDiscountBaseCurrency, t.WinlossByBaseCurrency),
		AmountToCompanyByDiscountBaseCurrency = ISNULL(c.AmountToCompanyByDiscountBaseCurrency, t.AmountToCompanyByBaseCurrency)
	FROM #tmpWinlossData t
	LEFT JOIN cte_winlossByDiscountBaseCurrency c ON t.PartyId = c.PartyID AND t.WinlossDate = c.WinlossDate AND t.ProductId = c.ProductID AND t.CurrencyId = c.CurrencyId

	-- 2.4 insert product don't have any ticket
	INSERT INTO #tmpWinlossData (PartyId,WinlossDate,ProductId,WinlossByDiscountBaseCurrency,WinlossByBaseCurrency,AmountToCompanyByDiscountBaseCurrency,AmountToCompanyByBaseCurrency,ExtraAmount,CurrencyId)
	SELECT DISTINCT PartyId,@ToDate,c.ProductId,0,0,0,0,0,6--EUR = 6
	FROM @PartyList p 
	INNER JOIN @ProductList pd ON 1=1
	INNER JOIN dbo.OAS_ChargeInfo c WITH(NOLOCK) ON c.ProductID = pd.ProductID AND p.PartyId = c.FromParty
	WHERE c.ToDate >= @FromDate  

	-- 2.5 create result
	DECLARE @FinalResult TABLE(PartyId INT, ProductId INT, WinlossByDiscountBaseCurrency MONEY, WinlossByBaseCurrency MONEY, AmountToCompanyByDiscountBaseCurrency MONEY, AmountToCompanyByBaseCurrency MONEY, ExtraAmount MONEY, FeeByDiscountBaseCurrency MONEY, FeeByBaseCurrency MONEY, Discount MONEY, Rebate MONEY, IsChargedByMinFee BIT, IsApplyMinfeeToDiscount BIT, MinFee MONEY)

	INSERT INTO @FinalResult
	SELECT a.PartyId,a.ProductId
		,SUM(a.WinlossByDiscountBaseCurrency)
		,SUM(a.WinlossByBaseCurrency)
		,SUM(a.AmountToCompanyByDiscountBaseCurrency)
		,SUM(a.AmountToCompanyByBaseCurrency)
		,SUM(a.ExtraAmount)
		,0,0,0,0,0,0,0
	FROM #tmpWinlossData a
	GROUP BY PartyId, ProductId

	-- 2.6 treat negative as 0
	UPDATE @FinalResult 
			SET FeeByDiscountBaseCurrency = CASE WHEN AmountToCompanyByDiscountBaseCurrency < 0 THEN 0 ELSE AmountToCompanyByDiscountBaseCurrency END,
				FeeByBaseCurrency = CASE WHEN AmountToCompanyByBaseCurrency < 0 THEN 0 ELSE AmountToCompanyByBaseCurrency END
/*--------------------------------------------------------------------------------------------------------------------------------
 * 3. minfee calculation
 *-------------------------------------------------------------------------------------------------------------------------------*/
	-- 3.1 sum data to 2 parts
	-- under waive time
	-- out of waive time
	;WITH Fee AS(
		SELECT m.MinFeeId
			, SUM(CASE WHEN w.ProductId IS NULL THEN 0 ELSE t.AmountToCompanyByDiscountBaseCurrency END) FeeUnderWaiveTimeByDiscountBaseCurrency
			, SUM(CASE WHEN w.ProductId IS NULL THEN 0 ELSE t.AmountToCompanyByBaseCurrency END) FeeUnderWaiveTimeByBaseCurrency
			, SUM(CASE WHEN w.ProductId IS NULL THEN t.AmountToCompanyByDiscountBaseCurrency ELSE 0 END) FeeOutOfWaiveTimeByDiscountBaseCurrency
			, SUM(CASE WHEN w.ProductId IS NULL THEN t.AmountToCompanyByBaseCurrency ELSE 0 END) FeeOutOfWaiveTimeByBaseCurrency
		FROM #tmpWinlossData t
		INNER JOIN @tmpMinFee m ON t.ProductId = m.ProductId AND t.PartyId = m.PartyId AND t.WinlossDate BETWEEN m.FromDate AND m.ToDate
		LEFT JOIN @tmpMinFee w ON w.FeeType=2 AND w.MinFeeId=m.MinFeeId AND t.WinlossDate BETWEEN w.FromDate AND w.ToDate
		WHERE m.FeeType=1
		GROUP BY  m.MinFeeId
	)
	UPDATE mf SET
		FeeUnderWaiveTimeByDiscountBaseCurrency = CASE WHEN f.FeeUnderWaiveTimeByDiscountBaseCurrency < 0 THEN 0 ELSE f.FeeUnderWaiveTimeByDiscountBaseCurrency END,
		FeeUnderWaiveTimeByBaseCurrency = CASE WHEN f.FeeUnderWaiveTimeByBaseCurrency < 0 THEN 0 ELSE f.FeeUnderWaiveTimeByBaseCurrency END,
		FeeOutOfWaiveTimeByDiscountBaseCurrency = CASE WHEN f.FeeOutOfWaiveTimeByDiscountBaseCurrency < 0 THEN 0 ELSE f.FeeOutOfWaiveTimeByDiscountBaseCurrency END,
		FeeOutOfWaiveTimeByBaseCurrency = CASE WHEN f.FeeOutOfWaiveTimeByBaseCurrency < 0 THEN 0 ELSE f.FeeOutOfWaiveTimeByBaseCurrency END
	FROM @tmpMinFee mf INNER JOIN Fee f ON mf.MinFeeId=f.MinFeeId
	WHERE mf.FeeType=1
	
	--3.2 calculate total minfee by group
	DECLARE @TotalMinFees TABLE(
		PartyGroupId	INT,
		ProductId		INT,
		TotalMinFeeByDiscountBaseCurrency	MONEY,
		TotalMinFeeByBaseCurrency		MONEY,
		TotalAmountByDiscountBaseCurrency		MONEY,
		TotalAmountByBaseCurrency			MONEY
	)
	INSERT INTO @TotalMinFees(PartyGroupId,ProductId,TotalMinFeeByDiscountBaseCurrency,TotalMinFeeByBaseCurrency,TotalAmountByDiscountBaseCurrency,TotalAmountByBaseCurrency)
	SELECT p.PartyGroupId, mf.ProductId, SUM(mf.MinFeeAmountByDiscountBaseCurrency), SUM(mf.MinFeeAmountByBaseCurrency), SUM(mf.FeeOutOfWaiveTimeByDiscountBaseCurrency), SUM(mf.FeeOutOfWaiveTimeByBaseCurrency)
	FROM @tmpMinFee mf
	INNER JOIN @PartyList p ON mf.PartyId = p.PartyId
	WHERE mf.FeeType = 1
	GROUP BY p.PartyGroupId, mf.ProductId

	-- 3.3 calculate actual licensing fee
	UPDATE r SET FeeByDiscountBaseCurrency = CASE
				WHEN t.TotalAmountByDiscountBaseCurrency < t.TotalMinFeeByDiscountBaseCurrency AND a.FeeOutOfWaiveTimeByDiscountBaseCurrency < a.MinFeeAmountByDiscountBaseCurrency
					THEN a.MinFeeAmountByDiscountBaseCurrency + a.FeeUnderWaiveTimeByDiscountBaseCurrency
				ELSE a.FeeOutOfWaiveTimeByDiscountBaseCurrency + a.FeeUnderWaiveTimeByDiscountBaseCurrency
			END,
		FeeByBaseCurrency = CASE
				WHEN t.TotalAmountByBaseCurrency < t.TotalMinFeeByBaseCurrency AND a.FeeOutOfWaiveTimeByBaseCurrency < a.MinFeeAmountByBaseCurrency
					THEN a.MinFeeAmountByBaseCurrency + a.FeeUnderWaiveTimeByBaseCurrency
				ELSE a.FeeOutOfWaiveTimeByBaseCurrency + a.FeeUnderWaiveTimeByBaseCurrency
			END,
		IsChargedByMinFee = CASE
				WHEN t.TotalAmountByDiscountBaseCurrency < t.TotalMinFeeByDiscountBaseCurrency AND a.FeeOutOfWaiveTimeByDiscountBaseCurrency < a.MinFeeAmountByDiscountBaseCurrency
					THEN 1
				ELSE 0
			END,
		IsApplyMinfeeToDiscount = CASE
			WHEN a.MinFeeAmountByBaseCurrency < a.FeeAmountByBaseCurrency AND a.FeeAmountByBaseCurrency > 0 AND b.FeeType IS NOT NULL THEN 0-- waived
			WHEN t.TotalAmountByDiscountBaseCurrency >= t.TotalMinFeeByDiscountBaseCurrency AND p.PartyGroupId >0 THEN 0 -- reach group minfee goal
			ELSE 1 END,
		MinFee = a.MinFeeAmountByBaseCurrency
	FROM @FinalResult r
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
		FeeBase 				MONEY
	)

	-- 4.1 discount by all currency
	INSERT INTO @tmpDiscountCalculation(CalculationGroup,DiscountGroupId,DiscountGroupType,CurrencyId,Winloss,Fee)
	SELECT s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId, SUM(r.WinlossByDiscountBaseCurrency),SUM(r.FeeByDiscountBaseCurrency)
	FROM #tmpDiscountSettings s
	INNER JOIN @tmpDiscountCurrency c ON s.PartyId = c.PartyId AND c.DiscountGroupId=s.DiscountGroupId AND c.CurrencyId = 0 -- all currency
	INNER JOIN @FinalResult r ON s.PartyID = r.PartyId AND s.ProductId=r.ProductId
	WHERE s.CalculationType IN (@ToBeCalculated,@CalculateAndDiscount)
	GROUP BY s.DiscountGroupId, s.DiscountGroupType,s.CurrencyId,s.CalculationGroup

	-- 4.2 discount by currency
	-- only offer discount for licensing fee
	INSERT INTO @tmpDiscountCalculation(CalculationGroup,DiscountGroupId,DiscountGroupType,CurrencyId,Winloss,Fee,FeeBase)
	SELECT s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId,
		SUM(r.WinlossByDiscountBaseCurrency),
		SUM(r.AmountToCompanyByDiscountBaseCurrency),
		SUM(r.AmountToCompanyByBaseCurrency)
	FROM #tmpWinlossData r
	INNER JOIN @tmpDiscountCurrency c ON c.PartyID=r.PartyId AND c.CurrencyId=r.CurrencyId
	INNER JOIN #tmpDiscountSettings s ON s.DiscountGroupId=c.DiscountGroupId AND s.ProductId=r.ProductId AND s.PartyId = c.PartyId
	WHERE s.CalculationType IN (@ToBeCalculated,@CalculateAndDiscount)
		AND s.DiscountGroupType IN (@DiscountIndividualFee, @DiscountByGroupFee)
	GROUP BY s.CalculationGroup,s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId


	DECLARE @Rate TABLE(Rate DECIMAL(6,5), CalculationGroup INT, DiscountGroupType INT)
	-- 4.3 get rate
	;WITH cte_Detail AS(
		SELECT c.CalculationGroup, d.DiscountGroupId, d.Rate
			,ISNULL(d.FromAmount,0) AS FromAmount
			,CASE WHEN d.ToAmount > @Unlimited THEN d.ToAmount ELSE (d.ToAmount + 1) END AS ToAmount
		FROM dbo.LA_DiscountGroupDetail d WITH(NOLOCK)
		INNER JOIN @tmpDiscountCalculation c ON d.DiscountGroupId=c.DiscountGroupId
	)
	INSERT INTO @Rate(rate, CalculationGroup, DiscountGroupType)
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

	-- 4.4 discount by all currencies
	UPDATE r SET Discount = CASE
			WHEN s.DiscountGroupType IN (@DiscountByGroupFee, @DiscountIndividualFee) THEN c.Rate * r.FeeByBaseCurrency
			WHEN s.DiscountGroupType IN (@DiscountByGroupGrosswin, @DiscountIndividualGrosswin) THEN c.Rate * (CASE WHEN r.WinlossByBaseCurrency < 0 THEN 0 ELSE r.WinlossByBaseCurrency END)
		ELSE 0 END
	FROM @FinalResult r
	INNER JOIN #tmpDiscountSettings s ON s.PartyID = r.PartyId AND s.ProductId=r.ProductId
	INNER JOIN @Rate c ON c.CalculationGroup = s.CalculationGroup
	WHERE s.CalculationType IN (@ToBeDiscounted,@CalculateAndDiscount) 
		AND s.IsApplyDiscount = 1

	-- 4.5 discount by curency
	-- not support gross win
	-- not support multiple products
	-- not discount if fee after discount less than minfee(in case minfee is not shared)
	;WITH cte_Fee AS
	(
		SELECT r.PartyID, r.ProductID, SUM(r.AmountToCompanyByBaseCurrency) as FeeBase
		FROM #tmpWinlossData r
		INNER JOIN @tmpDiscountCurrency c ON c.PartyID = r.PartyId AND c.CurrencyId = r.CurrencyId
		INNER JOIN #tmpDiscountSettings s ON s.DiscountGroupId = c.DiscountGroupId AND s.ProductId = r.ProductId AND s.PartyId = c.PartyId
		WHERE s.CalculationType IN (@ToBeCalculated,@CalculateAndDiscount)
			AND s.DiscountGroupType IN (@DiscountIndividualFee, @DiscountByGroupFee)
		GROUP BY r.PartyID,  r.ProductID
	),
	cte_DiscountByCurrency AS 
	(
		SELECT t.PartyId, f.ProductId, r.Rate * (CASE WHEN f.FeeBase < 0 THEN 0 ELSE f.FeeBase END) Discount 
		FROM #tmpDiscountSettings t
		INNER JOIN @rate r ON r.CalculationGroup = t.CalculationGroup
		INNER JOIN cte_Fee f ON t.PartyId = f.PartyId
	)
	UPDATE t SET Discount = CASE WHEN (t.FeeByBaseCurrency - d.Discount) < t.Minfee AND t.IsApplyMinfeeToDiscount = 1 THEN t.FeeByBaseCurrency - t.Minfee ELSE d.Discount END
	FROM @FinalResult t
	INNER JOIN cte_DiscountByCurrency d on t.PartyID = d.PartyID AND t.ProductID = d.ProductId
	WHERE d.Discount > 0

	-- 4.6 apply new discount term for licensee have not shared minfee
	-- fee after discount must >= minfee
	IF (@FromDate >= @ApplyMinfeeToDiscountDate)
	BEGIN
		UPDATE @FinalResult SET Discount = FeeByBaseCurrency - Minfee WHERE (FeeByBaseCurrency - Discount) < Minfee AND IsApplyMinfeeToDiscount = 1
	END

	UPDATE @FinalResult 
	SET Discount = 0 
	WHERE Discount < 0 OR (FeeByBaseCurrency - Discount) < 0
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
		Rebate = (r.FeeByBaseCurrency - r.Discount) * c.Rate
	FROM @FinalResult r INNER JOIN @tmpRebateSettings c ON r.PartyId = c.PartyID AND r.ProductId = c.ProductId

	-- 5. return result
	SELECT PartyId
		,ProductId 
		,FeeByBaseCurrency + ExtraAmount AS Fee
		,Discount
		,Rebate
		,IsChargedByMinFee
	FROM @FinalResult
	WHERE PartyId IN (SELECT a.PartyId FROM @PartyList a WHERE a.IsSelected = 1)
		AND ProductId IN (SELECT b.ProductId FROM @ProductList b WHERE b.ToBeDiscounted = 1)

	DROP TABLE #tmpExchange
	DROP TABLE #tmpChargeInfo
	DROP TABLE #temData
	DROP TABLE #tmpWinlossData
	DROP TABLE #tmpDiscountSettings
END
GO