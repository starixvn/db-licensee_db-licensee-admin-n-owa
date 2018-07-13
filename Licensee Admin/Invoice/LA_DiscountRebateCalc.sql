/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="1" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_AmountToCompanySel] (
	@FromDate		DATE,
	@ToDate			DATE,
	@PartyIds		VARCHAR(4000) = '',
	@ProductCodes	VARCHAR(1000) = '',
	@BaseCurrency	VARCHAR(10) = 'EUR'
)
WITH RECOMPILE
AS
/*	Created: 20180703@Bruce
	Task : calculate discount, rebate, licensing fee in one invoice period(one month)
	DB: DB052/bodb_Licensee
	Revisions:
		- 20180703@Bruce: calculate discount,rebate [#94282]
*/

BEGIN
/*--------------------------------------------------------------------------------------------------------------------------------
 * 1. Prepare settings
 *-------------------------------------------------------------------------------------------------------------------------------*/
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
	INNER JOIN @PartyList p ON a.PartyGroupId=p.PartyGroupId
	WHERE p.PartyId != a.PartyId

	-- 1.3 include products that use to calculate discount
	-- discount type
	DECLARE @Rebate INT = 2
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
		INNER JOIN @PartyList b ON a.PartyID=b.PartyId
		WHERE b.IsSelected=1
	)
	SELECT DISTINCT h.DiscountGroupId, h.DiscountGroupType, a.PartyID, p.ProductId, p.CalculationType, a.IsApplyDiscount, h.CurrencyId, a.Remark,h.FromDate
	INTO #DiscountSettings
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
		FROM #DiscountSettings
		GROUP BY DiscountGroupType, PartyID, ProductId
		HAVING COUNT(1) > 1
	)
	DELETE d FROM #DiscountSettings d INNER JOIN cte_Discount c ON d.FromDate < c.FromDate
		AND c.PartyID = d.PartyID 
		AND c.ProductId = d.ProductId
		AND c.DiscountGroupType = d.DiscountGroupType

	-- 1.3.2 add discount calculation party
	INSERT INTO @PartyList(PartyId,PartyGroupId,IsSelected)
	SELECT DISTINCT a.PartyID, -a.PartyID, 0
	FROM #DiscountSettings a
	LEFT JOIN @PartyList b ON a.PartyID = b.PartyId
	WHERE b.PartyId IS NULL AND a.CalculationType IN (@ToBeCalculated, @CalculateAndDiscount)

	-- 1.4 include discount calculation products
	DECLARE @ProductList TABLE (ProductId INT, IsSelected BIT)
	INSERT INTO @ProductList(ProductId,IsSelected)
	SELECT ProductID, 1 FROM dbo.LA_f_Products3rd(@ProductCodes)

	INSERT INTO @ProductList(ProductId,IsSelected)
	SELECT DISTINCT ProductId,0
	FROM #DiscountSettings
	WHERE CalculationType IN (@ToBeCalculated, @CalculateAndDiscount)
		AND ProductId NOT IN (SELECT p.ProductId FROM @ProductList p)

	-- remove unsupported products
	DELETE @ProductList WHERE ProductID IN (1,3,23,13,14,17,31,15,25) -- exclude RB,BA,NG2,bettrade,MGCLC,MGCRNG,BX,CB,CO
	
	-- 1.5 update product code list
	SET @ProductCodes = NULL
	SELECT @ProductCodes = COALESCE((@ProductCodes + ',' + CAST(ProductId AS VARCHAR(10))), CAST(ProductId AS VARCHAR(10)))
	FROM dbo.LA_f_Products3rd('') a
	WHERE a.ProductID IN (SELECT DISTINCT b.ProductId FROM @ProductList b)

	-- 1.6 update party id list
	SET @PartyIds = NULL
	SELECT @PartyIds = COALESCE((@PartyIds + ',' + CAST(PartyId AS VARCHAR(10))), CAST(PartyId AS VARCHAR(10)))
	FROM (SELECT DISTINCT b.PartyId FROM @PartyList b) a
	
	-- 1.7 charge info
	SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, ci.DI_Rate AS Rate, ci.Fromdate, ci.ToDate
	INTO #ChargeInfo
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
	WHERE DI_Rate > 0

	-- 1.7 exchange
	SELECT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate
	INTO #Exchange
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrency)
	WHERE ExchangeDate BETWEEN @FromDate AND @ToDate

	-- 1.8 minfee settings
	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FromDate), 0)
	DECLARE @LastDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FromDate) + 1, 0))

	CREATE TABLE #MinFeeGroup (
		FeeType			TINYINT,
		PartyId			INT,
		ProductId		INT,
		CurrencyId		INT,
		FeeAmount		MONEY,
		FromDate		DATETIME,
		ToDate			DATETIME,
		MinFeeProrate	MONEY,
		WaivedAmount	MONEY,
		TotalAmount		MONEY,
		MinFeeAmount	MONEY,
		AmountToCompany	MONEY,
		DaysOutOfWaiveTime	INT
	)

	-- 1.8.1 minfee
	INSERT INTO #MinFeeGroup(FeeType ,PartyId,ProductId, CurrencyId ,FeeAmount ,FromDate ,ToDate)
	SELECT mf.FeeTypeId,
		mf.PartyId,
		mf.ProductId,
		mf.CurrencyId,
		mf.FeeAmount,
		CASE WHEN @FromDate >= mf.FromDate THEN @FromDate ELSE mf.FromDate END AS FromDate,
		CASE WHEN @ToDate < mf.ToDate THEN @ToDate ELSE mf.ToDate END AS ToDate
	FROM dbo.LA_MinFee mf WITH(NOLOCK)
	INNER JOIN @PartyList p ON mf.PartyId = p.PartyId
	INNER JOIN @ProductList c ON mf.ProductId=c.ProductID
	WHERE mf.FeeTypeId = 1 AND @FromDate <= mf.ToDate AND mf.FromDate <= @ToDate
	
	-- 1.8.2 waive
	INSERT INTO #MinFeeGroup(FeeType ,PartyId,ProductId, CurrencyId ,FeeAmount ,FromDate ,ToDate)
	SELECT a.FeeTypeId,
		a.PartyId,
		a.ProductId,
		a.CurrencyId,
		a.FeeAmount,
		CASE WHEN @FromDate >= a.FromDate THEN @FromDate ELSE a.FromDate END AS FromDate,
		CASE WHEN @ToDate < a.ToDate THEN @ToDate ELSE a.ToDate END AS ToDate
	FROM dbo.LA_MinFee a WITH(NOLOCK)
	INNER JOIN #MinFeeGroup b ON a.PartyId=b.PartyId AND a.ProductId=b.ProductId
	WHERE a.FeeTypeId = 2 AND a.FromDate <= b.ToDate AND b.FromDate <= a.ToDate

	-- 1.8.3 exchange minfee amount to base currency
	UPDATE m SET m.FeeAmount = m.FeeAmount * e.Rate
	FROM #MinFeeGroup m
	INNER JOIN #Exchange e ON m.ToDate = e.ExchangeDate AND m.CurrencyId = e.ExchangeID

/*--------------------------------------------------------------------------------------------------------------------------------
 * 2. winloss data
 *-------------------------------------------------------------------------------------------------------------------------------*/
	CREATE TABLE #TempData (
		PartyId			INT,
		WinlossDate		DATE,
		ProductId		TINYINT,
		AmountToCompany	DECIMAL(20,5),
		Winloss			DECIMAL(20,5),
		IsApplyMinFee	BIT
	)
	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempData (PartyId, ProductId)
	
	-- 2.1 include general products
	INSERT INTO #TempData (PartyId,WinlossDate,ProductId,Winloss,AmountToCompany)
	(
		SELECT	p.PartyId,
				b.rptDate,
				p.ProductId,
				SUM(-ISNULL(b.MemberWL * e.Rate, 0)),
				SUM(-ISNULL(b.MemberWL * p.Rate * e.Rate, 0))
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
			INNER JOIN #ChargeInfo p ON b.ProductId = p.ProductID 
					AND p.LicenseeId = b.SiteId
					AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
		WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
				AND b.ProductId NOT IN (6) -- exclude CS
		GROUP BY b.rptdate, b.SiteId, p.PartyId, p.ProductId
	)
	
	-- 2.2 include CS winloss
	INSERT INTO #TempData (PartyId,WinlossDate,ProductId,Winloss,AmountToCompany)
	SELECT p.PartyID,b.rptDate, 6 -- CS
	, SUM((
		CASE WHEN b.bettype IN (2199, 2399, 2999) THEN 0 ELSE -MemberWL END + -- exclude jackpot tickets
		CASE WHEN b.bettype IN (2198, 2398, 2998) THEN GrossWL ELSE 0 END -- exclude contrinution tickets ( grosswl = -awinloss = -contribution)
	) * e.Rate)
	, SUM((
		CASE WHEN b.bettype IN (2199, 2399, 2999) THEN 0 ELSE -MemberWL END +
		CASE WHEN b.bettype IN (2198, 2398, 2998) THEN GrossWL ELSE 0 END
	) * p.Rate * e.Rate)
	FROM bodb_licenseereport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
	INNER JOIN #ChargeInfo p ON b.SiteID = p.LicenseeId AND b.ProductID = p.ProductID AND b.rptDate BETWEEN p.FromDate AND p.ToDate
	INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND CurrencyID = e.ExchangeID
	WHERE b.ProductID = 6 -- RNG casino
		AND (b.CurrencyID <> 20)
		AND b.StatusId NOT IN (-1, 101, 102, 103)
		AND b.customercategory NOT IN (27, 28)
	GROUP BY b.SiteID, b.rptdate, p.PartyID
	
	-- 2.3 insert zero tickets: to fix no data when join
	INSERT INTO #TempData(PartyId,WinlossDate,ProductId,Winloss,AmountToCompany)
	SELECT DISTINCT PartyId,@ToDate,ProductId, 0, 0
	FROM @PartyList INNER JOIN @ProductList ON 1=1
	
	-- 2.4 create result
	SELECT a.PartyId,a.ProductId
		,SUM(a.Winloss) AS Winloss
		,SUM(a.AmountToCompany) AS Fee
		,CAST(0 AS MONEY) AS Discount
		,CAST(0 AS MONEY) AS Rebate
		,CAST(0 AS MONEY) AS DiscountRate
		,CAST(0 AS MONEY) AS RebateRate
		,CAST('' AS NVARCHAR(4000)) AS DiscountRemark
		,CAST('' AS NVARCHAR(4000)) AS RebateRemark
		,CAST(0 AS MONEY)			AS Minfee
		,CAST(0 AS BIT)				AS IsChargedByMinFee
	INTO #Result
	FROM #TempData a
	GROUP BY PartyId, ProductId

/*--------------------------------------------------------------------------------------------------------------------------------
 * 3. minfee calculation
 *-------------------------------------------------------------------------------------------------------------------------------*/
	DECLARE @Month TINYINT = MONTH(@FromDate)
	DECLARE @DaysInMonth INT = DATEDIFF(day, @FirstDate, @LastDate) + 1

	-- 3.1 mark data to be applied minfee under waive time
	UPDATE t SET t.IsApplyMinFee = 0
	FROM #TempData t
	INNER JOIN #MinFeeGroup m ON t.ProductId = m.ProductId
		AND (t.PartyId = m.PartyId )
		AND (t.WinlossDate BETWEEN m.FromDate AND m.ToDate)
	WHERE m.FeeType=2

	-- 3.2 calculate minfee amount(minfee prograte) under waive time
	UPDATE amf
	SET MinFeeProrate = (DATEDIFF(DAY, FromDate, ToDate) + 1) * ((
			SELECT TOP 1 mfg.FeeAmount
			FROM #MinFeeGroup mfg
			WHERE mfg.FeeType = 1 AND mfg.PartyId = amf.PartyId AND mfg.ProductId = amf.ProductId
		) / @DaysInMonth)
	FROM #MinFeeGroup amf
	WHERE FeeType = 2

	-- 3.3 calculate licensing fee under waive time
	UPDATE amf SET amf.WaivedAmount = ISNULL((
			SELECT SUM(td.AmountToCompany)
			FROM #TempData td
			WHERE amf.PartyId = td.PartyId AND amf.ProductId = td.ProductId AND td.WinlossDate BETWEEN amf.FromDate AND amf.ToDate
		), 0)
	FROM #MinFeeGroup amf
	WHERE amf.FeeType = 2

	--- 3.4 calculate waived values
	;WITH cte_Waive AS(
		SELECT PartyId,ProductId
			, SUM(DATEDIFF(DAY, FromDate, ToDate) + 1) WaivedDays
			, SUM(WaivedAmount) WaivedAmount
			, SUM(MinFeeProrate) MinFeeProrate
		FROM #MinFeeGroup
		WHERE FeeType = 2
		GROUP BY PartyId,ProductId
	)
	UPDATE a SET
		-- number of days not in waive time
		DaysOutOfWaiveTime = @DaysInMonth - ISNULL(WaivedDays,0)
		-- Minfee = Minfee(setting) - minfee under waive time(calculate by single day)
		,MinFeeProrate = ROUND(((a.FeeAmount / @DaysInMonth) * (DATEDIFF(DAY, a.FromDate, a.ToDate) + 1) - ISNULL(c.MinFeeProrate,0)),2)
		-- total licensing fee under waive time
		,WaivedAmount = ISNULL(c.WaivedAmount,0)
	FROM #MinFeeGroup a LEFT JOIN cte_Waive c ON a.PartyId=c.PartyId AND a.ProductId=c.ProductId
	WHERE a.FeeType=1

	-- 3.5 total licensing fee not in waive time
	;WITH fee AS(
		SELECT a.PartyId,a.ProductId,SUM(ISNULL(t.AmountToCompany,0)) AS MinFeeAmount
		FROM #MinFeeGroup a 
		LEFT JOIN #TempData t ON a.PartyId=t.PartyId AND a.ProductId = t.ProductId
		WHERE a.FeeType = 1 
			AND t.IsApplyMinFee IS NULL
			AND t.WinlossDate BETWEEN a.FromDate AND a.ToDate
		GROUP BY a.PartyId,a.ProductId
	)
	UPDATE a SET MinFeeAmount = fee.MinFeeAmount
	FROM #MinFeeGroup a INNER JOIN fee ON a.PartyId=fee.PartyId AND a.ProductId=a.ProductId

	-- 3.6 Set zero when WaivedAmount < 0 or no days under waive time
	UPDATE #MinFeeGroup SET WaivedAmount = 0 
	WHERE FeeType = 1 AND WaivedAmount < 0 AND DaysOutOfWaiveTime > 0

	-- 3.7 calculate total amount to company = amount under waive time + amount out of waive range
	UPDATE amf
	SET amf.TotalAmount =  amf.MinFeeAmount + amf.WaivedAmount
	FROM #MinFeeGroup amf
	WHERE amf.FeeType = 1
	
	--3.8 calculate total minfee by group
	DECLARE @TotalMinFees TABLE(
		PartyGroupId				INT,
		ProductId					INT,
		TotalMinFee					MONEY,
		TotalAmountUnderMinfeeTime	MONEY
	)
	INSERT INTO @TotalMinFees(PartyGroupId,ProductId, TotalMinFee, TotalAmountUnderMinfeeTime)
	SELECT p.PartyGroupId,mf.ProductId,
			SUM(mf.MinFeeProrate),-- actual min fee in given time range
			SUM(CASE WHEN mf.MinFeeAmount < 0 THEN 0 ELSE ISNULL(mf.MinFeeAmount,0) END) -- total amount to company under minfee time(exclude waive range)
	FROM #MinFeeGroup mf
	INNER JOIN @PartyList p ON mf.PartyId = p.PartyId
	WHERE mf.FeeType = 1
	GROUP BY p.PartyGroupId, mf.ProductId

	-- 3.9 calculate actual licensing fee
	UPDATE r SET Fee = CASE
			WHEN t.TotalAmountUnderMinfeeTime < t.TotalMinFee AND a.MinFeeAmount < a.MinFeeProrate
				THEN a.MinFeeProrate + ISNULL(a.WaivedAmount,0)
			ELSE ISNULL(a.TotalAmount,0)
		END,
		IsChargedByMinFee = CASE
			WHEN t.TotalAmountUnderMinfeeTime < t.TotalMinFee AND a.MinFeeAmount < a.MinFeeProrate
				THEN 1
			ELSE 0
		END,
		Minfee = a.MinFeeProrate
	FROM #Result r
	INNER JOIN @PartyList p ON r.PartyId=p.PartyId
	INNER JOIN #MinFeeGroup a ON a.PartyId = r.PartyId AND a.ProductId=r.ProductID AND a.FeeType = 1
	INNER JOIN @TotalMinFees t ON a.ProductId = t.ProductId AND t.PartyGroupId=p.PartyGroupId

/*--------------------------------------------------------------------------------------------------------------------------------
 * 4. discount calculation
 *-------------------------------------------------------------------------------------------------------------------------------*/
	DECLARE @DiscountIndividualFee INT = 1
	DECLARE @DiscountIndividualGrosswin INT = 3
	DECLARE @Unlimited MONEY = 1000000000000

	;WITH cte_Calculation AS(
		SELECT s.DiscountGroupId,s.DiscountGroupType,s.CurrencyId, SUM(r.Winloss) Winloss,SUM(r.Fee) Fee
		FROM #DiscountSettings s
		INNER JOIN #Result r ON s.PartyID = r.PartyId AND s.ProductId=r.ProductId
		WHERE s.CalculationType IN (@ToBeCalculated,@CalculateAndDiscount)
		GROUP BY s.DiscountGroupId, s.DiscountGroupType,s.CurrencyId
	), cte_Detail AS(
		SELECT d.DiscountGroupId, d.Rate
			,d.FromAmount * e.Rate AS FromAmount
			,CASE WHEN d.ToAmount > @Unlimited THEN d.ToAmount ELSE (d.ToAmount + 1) * e.Rate END AS ToAmount
		FROM dbo.LA_DiscountGroupDetail d
		INNER JOIN cte_Calculation c ON d.DiscountGroupId=c.DiscountGroupId
		INNER JOIN #Exchange e ON e.ExchangeId = c.CurrencyId AND e.exchangedate=@ToDate
	), cte_Rate AS (
		SELECT c.DiscountGroupId, d.Rate
		FROM cte_Calculation c INNER JOIN cte_Detail d ON c.DiscountGroupId=d.DiscountGroupId
		WHERE (
				c.DiscountGroupType IN (@DiscountByGroupFee, @DiscountIndividualFee) AND
				c.Fee >= d.FromAmount AND c.Fee < d.ToAmount
			) OR (
				c.DiscountGroupType IN (@DiscountByGroupGrosswin, @DiscountIndividualGrosswin) AND
				c.Winloss >= d.FromAmount AND c.Winloss < d.ToAmount
			)
	)
	UPDATE r SET DiscountRemark = s.Remark, DiscountRate = c.Rate
		,Discount = CASE
			WHEN s.DiscountGroupType IN (@DiscountByGroupFee, @DiscountIndividualFee) THEN c.Rate * r.Fee
			WHEN s.DiscountGroupType IN (@DiscountByGroupGrosswin, @DiscountIndividualGrosswin) THEN c.Rate * r.Winloss
		ELSE 0 END
	FROM #Result r
	INNER JOIN #DiscountSettings s ON s.PartyID = r.PartyId AND s.ProductId=r.ProductId
	INNER JOIN cte_Rate c ON s.DiscountGroupId=c.DiscountGroupId
	WHERE s.CalculationType IN (@ToBeDiscounted,@CalculateAndDiscount) AND s.IsApplyDiscount = 1

/*--------------------------------------------------------------------------------------------------------------------------------
 * 4. rebate calculation
 *-------------------------------------------------------------------------------------------------------------------------------*/
	-- 4.1 get rebate settings
	SELECT a.PartyID, p.ProductId, d.Rate, h.Remark,h.FromDate
	INTO #RebateSettings
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
		FROM #RebateSettings
		GROUP BY PartyID, ProductId
		HAVING COUNT(1) > 1
	)
	DELETE r FROM #RebateSettings r INNER JOIN cte_Rebate c ON r.FromDate < c.FromDate
		AND c.PartyID = r.PartyID 
		AND c.ProductId = r.ProductId

	-- 4.3 calculate rebate
	UPDATE r SET 
		Rebate = (r.Fee - r.Discount) * c.Rate,
		RebateRemark = c.Remark,
		RebateRate = c.Rate
	FROM #Result r INNER JOIN #RebateSettings c ON r.PartyId = c.PartyID AND r.ProductId = c.ProductId

	-- result
	SELECT PartyId
		,ProductId
		,Winloss
		,Fee
		,Discount
		,DiscountRate
		,DiscountRemark
		,Rebate
		,RebateRate
		,RebateRemark
		,(Fee - Discount - Rebate)	AS AmountToCompany
		,Minfee
		,IsChargedByMinFee
	FROM #Result
	WHERE PartyId IN (SELECT a.PartyId FROM @PartyList a WHERE a.IsSelected = 1)
		AND ProductId IN (SELECT b.ProductId FROM @ProductList b WHERE b.IsSelected = 1)

	DROP TABLE #Exchange
	DROP TABLE #ChargeInfo
	DROP TABLE #TempData
	DROP TABLE #DiscountSettings
	DROP TABLE #Result
	DROP TABLE #MinFeeGroup
	DROP TABLE #RebateSettings
END
GO
