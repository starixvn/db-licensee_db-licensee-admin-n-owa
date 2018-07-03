/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="1" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_DiscountRebateCalc] (
	@FromDate		DATE,
	@ToDate			DATE,
	@PartyIds		VARCHAR(4000) = '',
	@ProductCodes	VARCHAR(1000) = '',
	@BaseCurrency	VARCHAR(10) = 'EUR'
)
--RETURNS @Result TABLE (
--	PartyId	INT,
--	LicensingFee	MONEY,
--	Discount		MONEY,
--	Rebate			MONEY,
--	AmountDueTo		MONEY
--)
AS
/*	Created: 20180703@Bruce
	Task : Get bettype product mapping
	DB: DB052/bodb_Licensee
	Revisions:
		- 20180703@Bruce: calculate discount,rebate [#94282]
*/

BEGIN
/*--------------------------------------------------------------------------------------------------------------------------------
 * Prepare settings
 *-------------------------------------------------------------------------------------------------------------------------------*/
	-- 1. party list
	DECLARE @PartyList TABLE(PartyId INT, PartyName VARCHAR(500), BrandName VARCHAR(500), ParentId INT, IsSelected BIT)
	INSERT INTO @PartyList(PartyId,PartyName,BrandName,ParentId)
	EXEC dbo.LA_PartyListSel

	-- remove parent group
	DELETE @PartyList WHERE ParentId = 0

	-- remove party not selected
	IF ISNULL(@PartyIds,'') != '' DELETE @PartyList WHERE PartyId NOT IN (SELECT val FROM dbo.strSplit(@PartyIds, ','))

	-- mark isselected = true
	UPDATE @PartyList SET IsSelected = 1

	-- to calculate minfee: select all parties in the same group
	INSERT INTO @PartyList(PartyId, IsSelected)
	SELECT DISTINCT p2.PartyGroupId, 0
	FROM dbo.LA_PartyGroupAssignment p1 WITH(NOLOCK)
	INNER JOIN @PartyList p ON p.PartyId = p1.PartyId
	INNER JOIN dbo.LA_PartyGroupAssignment p2 WITH(NOLOCK) ON p1.PartyGroupId = p2.PartyGroupId
	WHERE p2.PartyId NOT IN (SELECT p3.PartyId FROM @PartyList p3)
	-- End region

	-- 2. product list
	-- exclude some unsupported products
	DECLARE @ProductList TABLE(ProductId INT, ProductCode VARCHAR(10))
	INSERT INTO @ProductList(ProductId, ProductCode)
	SELECT ProductID, ProductPrefix
	FROM dbo.LA_f_Products3rd(ISNULL(@ProductCodes,''))
	WHERE ProductID NOT IN (1,3,23,13,14,17,31) -- exclude RB,BA,NG2,bettrade,MGCLC,MGCRNG,BX

	-- 3. charge info
	SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, ci.DI_Rate AS Rate, ci.Fromdate, ci.ToDate,
			CASE WHEN ci.ProductId IN (14,17) THEN ISNULL(sbr.Bettype, ci.Bettype) ELSE -1 END Bettype,
			1 AS TypeId
	INTO #ChargeInfo
	FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
	LEFT JOIN bodb_licensee..Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype AND (
			(ci.ProductId NOT IN (14,17)) OR 
			(ci.ProductID = 14 AND sbr.Bettype BETWEEN 2001 AND 2007) OR
			(ci.ProductID = 17 AND sbr.Bettype BETWEEN 2008 AND 2009)
		)			
	WHERE	DI_Rate > 0 AND ci.ProductID <> 15 -- exclude CB
	
	-- include CB charge info
	IF EXISTS(SELECT TOP 1 1 FROM @ProductList WHERE ProductId=15) -- colossus bet
	BEGIN
		INSERT INTO #ChargeInfo(PartyId, LicenseeId, ProductID, Rate, TypeId, FromDate, ToDate)
		SELECT	ci.FromParty,p.OldRefID,15,ci.Rate,ci.ChargeType,
				CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
				CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END
		FROM dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN @PartyList pl ON p.PartyID=pl.PartyId
			INNER JOIN dbo.OAS_ChargeInfo ci WITH(NOLOCK) ON ci.FromParty = p.PartyID
			LEFT JOIN dbo.OAS_PartyDetail pd WITH(NOLOCK) ON pd.PartyID = p.PartyID
		WHERE ci.ProductID = 15 -- colossus bet
			AND pd.IsDeposit = 1
			AND ChargeType IN (6,7) -- 6 comm, 7 cashin
			AND @FromDate <= ci.ToDate
			AND ci.FromDate <= @ToDate
	END

	-- 4. exchange
	SELECT ExchangeDate, ExchangeId, BaseCurrencyRate AS Rate
	INTO #Exchange
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrency)
	WHERE ExchangeDate BETWEEN @FromDate AND @ToDate

	-- 5. minfee settings
	DECLARE @Month TINYINT = MONTH(@FromDate)
	DECLARE @FirstDate DATETIME = DATEADD(mm, DATEDIFF(mm, 0, @FromDate), 0)
	DECLARE @LastDate DATETIME = DATEADD (dd, -1, DATEADD(mm, DATEDIFF(mm, 0, @FromDate) + 1, 0))
	DECLARE @DaysInMonth INT = DATEDIFF(day, @FirstDate, @LastDate) + 1

	DECLARE @MinFeeGroup TABLE(
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

	INSERT INTO @MinFeeGroup(FeeType ,PartyId,ProductId, CurrencyId ,FeeAmount ,FromDate ,ToDate)
	(
		SELECT	mf.FeeTypeId,
				mf.PartyId,
				mf.ProductId,
				mf.CurrencyId,
				mf.FeeAmount,
				CASE WHEN @FromDate >= mf.FromDate THEN @FromDate ELSE mf.FromDate END AS FromDate,
				CASE WHEN @ToDate < mf.ToDate THEN @ToDate ELSE mf.ToDate END AS ToDate
		FROM	bodb_licensee.dbo.LA_MinFee mf WITH(NOLOCK)
		WHERE	((mf.FeeTypeId = 1)
					OR mf.FeeTypeId = 2 AND EXISTS (SELECT	PartyId
													FROM	bodb_licensee.dbo.LA_MinFee m WITH(NOLOCK)
													WHERE	m.FeeTypeId = 1
															AND m.PartyId = mf.PartyId
															AND m.ProductId = mf.ProductId
															AND ((m.FromDate BETWEEN @FirstDate AND @LastDate)
																OR (m.ToDate BETWEEN @FirstDate AND @LastDate)
																OR (m.FromDate<@FirstDate AND @LastDate < m.ToDate)
															)
													)
				)
				AND mf.ProductId IN (SELECT ProductId FROM @ProductList)
				AND mf.PartyId IN (SELECT p.PartyId FROM @PartyList p)
				AND ((mf.FromDate BETWEEN @FirstDate AND @LastDate) 
					OR (mf.ToDate BETWEEN @FirstDate AND @LastDate) 
					OR (mf.FromDate<@FirstDate AND @LastDate < mf.ToDate)
				)
	)

	UPDATE m SET m.FeeAmount = m.FeeAmount * e.Rate
	FROM @MinFeeGroup m
	INNER JOIN #Exchange e ON m.ToDate = e.ExchangeDate AND m.CurrencyId = e.ExchangeID

/*--------------------------------------------------------------------------------------------------------------------------------
 * winloss data
 *-------------------------------------------------------------------------------------------------------------------------------*/
	-- 6. temp data
	CREATE TABLE #TempData (
		LicenseeId		INT,
		PartyId			INT,
		rptDate			DATETIME,
		CurrencyId		INT,
		WinLoss			DECIMAL(20,5),
		AComm			MONEY,
		ProductId		TINYINT,
		AmountToCompany	DECIMAL(20,5),
		IsApplyMinFee	BIT
	)
	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempData (PartyId, ProductId)

	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,ProductId,WinLoss,AComm,AmountToCompany)
	(
		SELECT	b.SiteID,
				p.PartyId,
				b.rptDate,
				b.CurrencyID,
				p.ProductId,
				SUM(ISNULL(b.MemberWL, 0)) * e.Rate,
				SUM(ISNULL(b.CommissionA, 0)) * e.Rate,
				SUM((-ISNULL(b.MemberWL, 0) * p.Rate) - (CASE WHEN b.ProductId = 3 THEN ISNULL(b.CommissionA, 0) ELSE 0 END)) * e.Rate
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
			INNER JOIN #ChargeInfo p ON b.ProductId = p.ProductID 
					AND p.LicenseeId = b.SiteId
					AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
					AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
		WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
				AND b.ProductId NOT IN (15,25,14,17, 6) -- exclude CO, CB, MGCLC, MGCRNG, CS
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, p.ProductId, e.Rate
	)
/*--------------------------------------------------------------------------------------------------------------------------------
 * minfee settings
 *-------------------------------------------------------------------------------------------------------------------------------*/

	DROP TABLE #Exchange
	DROP TABLE #ChargeInfo
END
GO

/*
SET NOCOUNT ON

	DECLARE @LicenseeID INT
	DECLARE @PartyIdTable TABLE (PartyId INT)
	INSERT INTO @PartyIdTable VALUES (@PartyId)

	DECLARE @BaseCurrencyId INT = (SELECT TOP 1 BaseCurrencyId FROM dbo.OAS_PartyDetail WITH(NOLOCK) WHERE PartyID = @PartyId)
	DECLARE @BaseCurrency VARCHAR(10) = (SELECT TOP 1 Code FROM bodb02.dbo.Exchange e WITH(NOLOCK) WHERE e.exchangeid = @BaseCurrencyId)


	-- Region: MinfeeGroup Date range
	
	-- End region



	

	-- Region: include CB
	SELECT	rptDate,
			b.SiteID,
			cb.PartyId,
			b.ProductId,
			CurrencyId,
			SUM(Turnover) Turnover,
			SUM(CASE WHEN ISNULL(b.TicketType, 0) = 0 THEN b.Turnover ELSE b.ExtraAmount END) TurnoverForCommision,
			SUM(ISNULL(WinPrizeAmount,0)) WinningPrize,
			SUM(ISNULL(CashOutAmount,0)) CashOut,
			SUM(ISNULL(BuyBackAmount,0)) CashInAmount,
			CAST(0 AS MONEY) CommisionShare,
			CAST(0 AS MONEY) CashInShare
	INTO #TempDataCB
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
	JOIN @PartyChargeInfo cb ON b.SiteID = cb.LicenseeId AND b.ProductId = cb.ProductID AND b.rptDate BETWEEN cb.FromDate AND cb.ToDate
	WHERE b.ProductId = @CB
		AND b.StatusId NOT IN (-1, 101, 102, 103)
		AND CustomerCategory NOT IN (27, 28)
		AND CurrencyId <> 20
		AND cb.TypeId = @CommChargeType -- to remove duplicate we use one of (6,7)
	GROUP BY rptdate, CurrencyId, b.SiteID, cb.PartyId, b.ProductId
	
	UPDATE #TempDataCB SET
		CommisionShare = td.TurnoverForCommision * cm.Rate,
		CashInShare = td.CashInAmount * ci.Rate
	FROM #TempDataCB td
	JOIN @PartyChargeInfo AS cm ON cm.ProductID = @CB AND cm.TypeId = @CommChargeType AND (td.rptDate BETWEEN cm.FromDate AND cm.ToDate)
	JOIN @PartyChargeInfo AS ci ON cm.ProductID = @CB AND ci.TypeId = @CashInShareChargeType AND (td.rptDate BETWEEN ci.FromDate AND ci.ToDate)

	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,ProductId, AmountToCompany)
	SELECT SiteID, PartyId, rptDate, CurrencyId, ProductId, (Turnover - WinningPrize - Cashout - CommisionShare - CashInShare) * e.Rate
	FROM #TempDataCB tcb
	INNER JOIN #Exchange e ON tcb.rptDate = e.ExchangeDate AND tcb.CurrencyId = e.ExchangeID
	-- End region: include CB

	-- Region: include CO
	;WITH CO AS (
		SELECT p.LicenseeId, p.PartyId, b.Winlostdate, b.Currency,
			SUM(b.BuyBackAmt) AS BuyBackAmountSB,
			SUM(b.BABuyBackAmt) AS BuyBackAmountBA,
			SUM(b.TicketPayout) AS TicketsPayout,
			SUM(b.BuyBackAmt * p.Rate) AS CashoutCommission
		FROM bodb_licenseereport.dbo.rptLicCashoutSummary b WITH (NOLOCK)
		INNER JOIN @PartyChargeInfo p ON b.SiteId = p.LicenseeId AND b.ProductId = p.ProductID AND b.Winlostdate BETWEEN p.FromDate AND p.ToDate
		WHERE b.Winlostdate BETWEEN p.FromDate AND p.ToDate
			AND b.ProductID = @CO
			AND b.Currency <> 20
			AND b.RoleID = 1 -- Member Level
		GROUP BY p.LicenseeId, p.PartyId, b.Winlostdate, b.Currency
	)
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,ProductId, AmountToCompany)
	SELECT CO.LicenseeId, CO.PartyId, CO.Winlostdate, CO.Currency, @CO, (TicketsPayout - BuyBackAmountSB - BuyBackAmountBA - CashoutCommission) * e.Rate
	FROM CO INNER JOIN #Exchange e ON CO.Winlostdate = e.ExchangeDate AND CO.Currency = e.ExchangeID
	-- End region: include CO

	-- Region: include MGCLC, MGCRNG
	;WITH MGC AS (
		SELECT p.LicenseeId, p.PartyId, b.RptDate, b.CurrencyID, p.ProductID
			, SUM((-ISNULL(b.winloss, 0) - ISNULL(b.ProgressiveContribution, 0)) * p.Rate - ISNULL(b.AComm, 0)) Amount
		FROM bodb_licenseereport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
		INNER JOIN @PartyChargeInfo p ON p.LicenseeId=b.SiteId AND p.Bettype=b.BetTypeId AND b.RptDate BETWEEN p.FromDate AND p.ToDate
		WHERE b.RptDate BETWEEN p.FromDate AND p.ToDate
			AND (b.CurrencyID <> 20)
			AND b.StatusId NOT IN (-1, 101, 102, 103)
		GROUP BY p.LicenseeId, p.PartyId, b.rptDate, b.CurrencyID, p.ProductID
	)
	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,ProductId, AmountToCompany)
	SELECT MGC.LicenseeId,MGC.PartyId,MGC.RptDate,MGC.CurrencyId,MGC.ProductID, MGC.Amount * e.Rate
	FROM MGC INNER JOIN #Exchange e ON MGC.RptDate = e.ExchangeDate AND MGC.CurrencyId = e.ExchangeID
	-- End region: include MGCLC, MGCRNG

	-- Region: Get Amount By Product CS	
	;WITH cte_RNGReport(LicenseeId, rptDate, CurrencyID, Winloss, ProgressiveContribution, WinningPrize) AS
	(
		SELECT b.SiteID, b.rptDate, b.CurrencyID
		, SUM(MemberWL) AS Winloss
		, SUM(CASE WHEN b.bettype IN (2198, 2398, 2998) THEN -GrossWL ELSE 0 END) AS ProgressiveContribution
		, SUM(CASE WHEN b.bettype IN (2199, 2399, 2999) THEN MemberWL ELSE 0 END) AS WinningPrize
		FROM bodb_licenseereport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		WHERE b.ProductID = @CSProductId
			AND b.rptDate BETWEEN @FromDate AND @ToDate
			AND (b.CurrencyID <> 20)
			AND b.StatusId NOT IN (-1, 101, 102, 103)
			AND b.customercategory NOT IN (27, 28)
			AND b.SiteID = @LicenseeID
		GROUP BY b.SiteID, b.rptdate, b.CurrencyID
	)

	INSERT INTO #TempData (LicenseeId,PartyId,rptDate,CurrencyId,ProductId,AmountToCompany)
	SELECT d.LicenseeId
		,p.PartyId
		,rptDate
		,CurrencyID
		,@CSProductId
		,SUM((-Winloss + WinningPrize - ProgressiveContribution) * p.Rate * e.Rate) AS AmountToCompany
	FROM cte_RNGReport AS d
	INNER JOIN @PartyChargeInfo p ON d.LicenseeId = p.LicenseeId AND @CSProductId = p.ProductID AND d.rptDate BETWEEN p.FromDate AND p.ToDate
	INNER JOIN #Exchange e ON d.rptDate = e.ExchangeDate AND CurrencyID = e.ExchangeID	
	WHERE d.rptDate BETWEEN p.Fromdate AND p.Todate
	GROUP BY d.LicenseeId, p.PartyId, rptDate, CurrencyID
	-- End region: Get Amount By Product CS

	UPDATE  t SET t.IsApplyMinFee = 0
	FROM #TempData t
	INNER JOIN @MinFeeGroup m ON t.ProductId = m.ProductId
		AND (t.PartyId = m.PartyId )
		AND (t.rptDate BETWEEN m.FromDate AND m.ToDate)
	WHERE m.FeeType=2
	-- End region

	-- Region: Check min fee group
	-- calculate minfee amount under waive time
	UPDATE amf
	SET MinFeeProrate = (DATEDIFF(DAY, FromDate, ToDate) + 1) * ((
			SELECT TOP 1 mfg.FeeAmount
			FROM @MinFeeGroup mfg
			WHERE mfg.FeeType = 1 AND mfg.PartyId = amf.PartyId AND mfg.ProductId = amf.ProductId
		) / @DaysInMonth)
	FROM @MinFeeGroup amf
	WHERE FeeType = 2

	-- calculate amount to company under waived time
	UPDATE amf SET amf.WaivedAmount = ISNULL((
			SELECT SUM(td.AmountToCompany)
			FROM #TempData td 
			WHERE	amf.PartyId = td.PartyId AND
					amf.ProductId = td.ProductId AND
					td.rptDate BETWEEN amf.FromDate AND amf.ToDate
		), 0)
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 2

	--- calculate min fee prorate (min fee amount in month - minfee amount under waive time
	UPDATE amf SET
		amf.DaysOutOfWaiveTime = @DaysInMonth - ISNULL((SELECT  (DATEDIFF(DAY, ff.FromDate, ff.ToDate) + 1)
                                        FROM	@MinFeeGroup ff
                                        WHERE	ff.FeeType = 2
                                                AND amf.PartyId = ff.PartyId
                                                AND amf.ProductId = ff.ProductId),0),
		amf.MinFeeProrate = ROUND((amf.FeeAmount / @DaysInMonth) * (DATEDIFF(DAY, FromDate, ToDate) + 1) -
								ISNULL((SELECT	SUM(f.MinFeeProrate)
										FROM	@MinFeeGroup f
										WHERE	f.FeeType = 2
												AND amf.PartyId = f.PartyId
												AND amf.ProductId = f.ProductId), 0)
							, 2),
		amf.WaivedAmount =  ISNULL((SELECT	SUM(f.WaivedAmount)
									FROM	@MinFeeGroup f
									WHERE	f.FeeType = 2 AND amf.PartyId = f.PartyId AND amf.ProductId = f.ProductId), 0),
		amf.MinFeeAmount =  ISNULL((SELECT	SUM(td.AmountToCompany)
									FROM	#TempData td
									WHERE	amf.PartyId = td.PartyId
											AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate
											AND td.IsApplyMinFee IS NULL
											AND amf.ProductId = td.ProductId), 0)
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 1

	UPDATE @MinFeeGroup SET WaivedAmount = 0 
	WHERE FeeType = 1 AND WaivedAmount < 0 AND DaysOutOfWaiveTime > 0

	-- calculate total amount to company = amount under waive time + amount out of waive range
	UPDATE	amf
	SET		amf.TotalAmount =  amf.MinFeeAmount + amf.WaivedAmount
	FROM	@MinFeeGroup amf
	WHERE	amf.FeeType = 1
	
	DECLARE @TotalMinFees TABLE(
		ProductId					INT,
		TotalMinFee					MONEY,
		TotalAmountUnderMinfeeTime	MONEY
	)
	INSERT	INTO @TotalMinFees(ProductId, TotalMinFee, TotalAmountUnderMinfeeTime)
	SELECT	mf.ProductId,
			SUM(mf.MinFeeProrate),-- actual min fee in given time range
			SUM(CASE WHEN mf.MinFeeAmount < 0 THEN 0 ELSE mf.MinFeeAmount END) -- total amount to company under minfee time(exclude waive range)
	FROM @MinFeeGroup mf
	INNER JOIN @PartyIdTable p ON mf.PartyId = p.PartyId
	WHERE	mf.FeeType = 1
	GROUP BY mf.ProductId

	-- update minfee group
	UPDATE amf
	SET amf.AmountToCompany = CASE
			WHEN t.TotalAmountUnderMinfeeTime < t.TotalMinFee AND amf.MinFeeAmount < amf.MinFeeProrate 
				THEN amf.MinFeeProrate + amf.WaivedAmount
			ELSE amf.TotalAmount
		END
	FROM @MinFeeGroup amf
	INNER JOIN @TotalMinFees t ON amf.ProductId = t.ProductId
	WHERE amf.FeeType = 1

	-- get discount settings
	DECLARE @RebateType INT = 2, @DiscountByFee INT = 1, @DiscountByWinloss INT = 3

	SELECT h.ToDate,p.ProductId, d.Rate, h.Remark,h.CurrencyId,h.FromDate,d.FromAmount,d.ToAmount, h.DiscountGroupType, h.DiscountGroupId
	INTO #DiscountRebate
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
	INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
	INNER JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON p.DiscountGroupId = h.DiscountGroupId
	INNER JOIN dbo.LA_DiscountGroupDetail d WITH(NOLOCK) ON d.DiscountGroupId = h.DiscountGroupId
	WHERE	a.PartyID = @PartyId AND
			@FromDate<= h.ToDate AND
			h.FromDate<=@ToDate AND
			p.ProductId <> 1 --exclude RB

	-- only one discount/rebate for a product at time
	DELETE d
	FROM #DiscountRebate d
	INNER JOIN (SELECT dr.ProductId, dr.DiscountGroupType, MAX(dr.ToDate) ToDate
		FROM #DiscountRebate dr
		GROUP BY dr.ProductId,dr.DiscountGroupType
	) t ON t.ProductId = d.ProductId AND t.DiscountGroupType = d.DiscountGroupType
	WHERE d.ToDate < t.ToDate

	-- discount currency must the same with party's base currency
	DELETE #DiscountRebate WHERE CurrencyId <> @BaseCurrencyId AND DiscountGroupType <> @RebateType
	-- end

	DECLARE @Result TABLE(ProductId INT, AmountToCompany MONEY, Discount MONEY)
	
	-- products have minfee
	INSERT INTO @Result(ProductId, AmountToCompany)
	SELECT ProductId, SUM(AmountToCompany)
	FROM @MinFeeGroup
	WHERE PartyId = @PartyId AND FeeType = 1
	GROUP BY ProductId

	-- products don't have minfee
	INSERT INTO @Result(ProductId, AmountToCompany)
	SELECT td.ProductId, SUM(td.AmountToCompany)
	FROM #TempData td
	WHERE td.PartyId = @PartyId AND td.ProductId NOT IN (SELECT td2.ProductId FROM @MinFeeGroup td2 WHERE td2.PartyId = @PartyId)
	GROUP BY td.ProductId

	-- include no ticket product
	INSERT INTO @Result(ProductId, AmountToCompany)
	SELECT p.ProductId, 0 FROM @Products p
	WHERE p.ProductId NOT IN (SELECT r.ProductId FROM @Result r)

	-- calculate discount by winloss
	;WITH wl AS (SELECT - SUM(WinLoss) Amount, ProductId FROM #TempData WHERE PartyId = @PartyId GROUP BY ProductId)
	UPDATE r SET Discount = (CASE WHEN wl.Amount<0 THEN 0 ELSE wl.Amount * dr.Rate END)
	FROM @Result r
	INNER JOIN #DiscountRebate dr ON r.ProductId = dr.ProductId AND dr.DiscountGroupType = @DiscountByWinloss
	INNER JOIN wl ON wl.ProductId = dr.ProductId AND wl.Amount > dr.FromAmount AND wl.Amount <= dr.ToAmount

	-- calculate discount by fee
	;WITH f AS (
		SELECT dr.DiscountGroupId, SUM(CASE WHEN r.AmountToCompany<0 THEN 0 ELSE r.AmountToCompany END) AS Amount
		FROM @Result r
		INNER JOIN (SELECT DISTINCT DiscountGroupId,ProductId 
			FROM #DiscountRebate d 
			WHERE d.DiscountGroupType = @DiscountByFee) dr ON r.ProductId = dr.ProductId
		GROUP BY dr.DiscountGroupId
	)
	UPDATE r SET Discount = (CASE WHEN r.AmountToCompany<0 THEN 0 ELSE r.AmountToCompany * dr.Rate END) + ISNULL(Discount,0)
	FROM @Result r
	INNER JOIN #DiscountRebate dr ON r.ProductId = dr.ProductId
	INNER JOIN f ON f.DiscountGroupId = dr.DiscountGroupId
			AND f.Amount > dr.FromAmount
			AND f.Amount <= dr.ToAmount
	 
	 UPDATE @Result SET AmountToCompany = CASE 
			WHEN AmountToCompany < 0 THEN AmountToCompany
			WHEN AmountToCompany > ISNULL(Discount,0) THEN AmountToCompany - ISNULL(Discount,0)
			ELSE 0
		END
	-- end

	-- calculate rebate
	;WITH RebateCalculation AS(
		SELECT
			ISNULL(CASE WHEN rs.AmountToCompany < 0 THEN 0 ELSE rs.AmountToCompany END * rb.Rate, 0) Rebate,
			ISNULL(CASE WHEN rs.AmountToCompany < 0 AND rs.ProductId NOT IN (3,15,25,6) THEN 0 ELSE rs.AmountToCompany END, 0) Amount
		FROM @Result rs
		LEFT JOIN #DiscountRebate rb ON rb.ProductId = rs.ProductId AND rb.DiscountGroupType=@RebateType
	)
	SELECT (SELECT TOP 1 Remark FROM #DiscountRebate WHERE DiscountGroupType = @RebateType) Remark,
		@ToDate			AS ReportDate,
		@BaseCurrency	AS CurrencyName,
		SUM(Rebate)		AS TotalRebate,
		SUM(Amount)		AS TotalAmount
	FROM RebateCalculation

	SELECT ProductId, AmountToCompany FROM @Result

	-- Region: Drop tmp table
	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #DiscountRebate
	DROP TABLE #TempDataCB
	-- End region

*/