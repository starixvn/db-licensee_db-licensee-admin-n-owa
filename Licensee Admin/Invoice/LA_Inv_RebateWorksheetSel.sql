/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

ALTER PROCEDURE dbo.LA_Inv_RebateWorksheetSel
	@PartyId		INT
	, @FromDate		SMALLDATETIME
	, @ToDate		SMALLDATETIME
AS
/*	Created: 20170417@Bruce
	Task: Rebate worksheet [#76133]
	DB: bodb_licensee

	Revision:
	  - 20170710@bruce: include CO, CB, BA [#79741]
	  - 20171220@Parsons: increase length for variables [#88197]
	  - 20180126@Bruce: Exclude Exchange-BX [#87754]
	  - 20180419@Scofield: update CB for FreePlay [#93907]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @PartyIdTable TABLE (PartyId INT)
	INSERT INTO @PartyIdTable VALUES (@PartyId)

	DECLARE @BaseCurrency VARCHAR(10) = ISNULL((
			SELECT TOP 1 Code 
			FROM bodb02.dbo.Exchange e WITH(NOLOCK)
			INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON e.exchangeid = d.BaseCurrencyId
			WHERE d.PartyID = @PartyId
		),6) -- default is EUR

	-- Party groups
	-- select all parties in the same group
	INSERT INTO @PartyIdTable
	SELECT	PartyId
	FROM	bodb_licensee.dbo.LA_PartyGroupAssignment WITH(NOLOCK)
	WHERE	PartyId <> @PartyId AND PartyGroupId IN (
		SELECT	p1.PartyGroupId
		FROM	bodb_licensee.dbo.LA_PartyGroupAssignment p1 WITH(NOLOCK)
		WHERE	p1.PartyId = @PartyId
	)
	-- End region

	-- products
	DECLARE @Products TABLE (ProductId INT, ProductCode VARCHAR(20))
	INSERT INTO @Products
	SELECT DISTINCT p.ProductID, p.ProductPrefix
	FROM LA_f_Products3rd('') p
	INNER JOIN dbo.OAS_ChargeInfo c WITH(NOLOCK) ON c.ProductID = p.ProductID
	WHERE c.FromParty = @PartyId AND c.ProductId NOT IN (1,23,13,14,17,31 ) --exclude RB,bettrade,NG2, MGCLC,MGCRNG,BX

	-- Region: Party charge info
	DECLARE @CB INT = 15, @CO INT = 25
	DECLARE @PartyIds VARCHAR(4000) = (SELECT CAST(PartyId AS VARCHAR(10)) + ',' FROM @PartyIdTable FOR XML PATH(''))
	DECLARE @ProductCodes VARCHAR(2000) = (SELECT ProductCode + ',' FROM @Products FOR XML PATH(''))
	DECLARE @PartyChargeInfo AS TABLE (
		PartyId		INT,
		LicenseeId	INT,
		ProductID	INT,
		Rate		DECIMAL(9,8),
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME,
		Bettype		INT,
		TypeId		SMALLINT
	)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate, Bettype)
	(
		SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, ci.DI_Rate, ci.Fromdate, ci.ToDate,
				CASE WHEN ci.ProductId IN (14,17) THEN ISNULL(sbr.Bettype, ci.Bettype) ELSE -1 END
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
		LEFT JOIN bodb_licensee..Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype AND (
				(ci.ProductId NOT IN (14,17)) OR 
				(ci.ProductID = 14 AND sbr.Bettype BETWEEN 2001 AND 2007) OR
				(ci.ProductID = 17 AND sbr.Bettype BETWEEN 2008 AND 2009)
			)			
		WHERE	DI_Rate > 0 AND ci.ProductID <> @CB -- exclude CB
	)

	-- include CB	
	DECLARE @CommChargeType INT = 6
	DECLARE @CashInShareChargeType INT = 7

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, TypeId, FromDate, ToDate)
	SELECT	ci.FromParty,
			p.OldRefID,
			@CB,
			ci.Rate,
			ci.ChargeType,
			CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
			CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END
	FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH(NOLOCK) ON ci.FromParty = p.PartyID
		LEFT JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH(NOLOCK) ON pd.PartyID = p.PartyID
	WHERE EXISTS(SELECT TOP 1 1 FROM @Products WHERE ProductId=@CB)
		AND FromParty = @PartyId
		AND ProductID = @CB
		AND pd.IsDeposit = 1
		AND ChargeType IN (@CommChargeType,@CashInShareChargeType) AND (
			@FromDate BETWEEN ci.FromDate AND ci.ToDate OR
			@ToDate BETWEEN ci.FromDate AND ci.ToDate OR
			ci.FromDate BETWEEN @FromDate AND @ToDate OR
			ci.ToDate BETWEEN @FromDate AND @ToDate
		)
	-- End region

	-- keep active products
	DELETE @Products WHERE ProductId NOT IN (SELECT p.ProductId FROM @PartyChargeInfo p WHERE p.PartyId = @PartyId)

	-- Region: MinfeeGroup Date range
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
		DaysOutOfWaiveTime  INT
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
				AND mf.ProductId IN (SELECT ProductId FROM @PartyChargeInfo)
				AND mf.PartyId IN (SELECT p.PartyId FROM @PartyIdTable p)
				AND ((mf.FromDate BETWEEN @FirstDate AND @LastDate) 
					OR (mf.ToDate BETWEEN @FirstDate AND @LastDate) 
					OR (mf.FromDate<@FirstDate AND @LastDate < mf.ToDate)
				)
	)
	-- End region

	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			DECIMAL(9,8)
	)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrency)
	-- End region

	UPDATE m SET m.FeeAmount = m.FeeAmount * e.Rate
	FROM @MinFeeGroup m
	INNER JOIN #Exchange e ON m.ToDate = e.ExchangeDate AND m.CurrencyId = e.ExchangeID

	-- Region: Get Amount by Product
	CREATE	TABLE #TempData (
		LicenseeId		INT,
		PartyId			INT,
		rptDate			DATETIME,
		CurrencyId		INT,
		WinLoss			MONEY,
		AComm			MONEY,
		ProductId		TINYINT,
		AmountToCompany	MONEY,
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
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
													AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
		WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate)
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903,904,911,912,913,914)
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
				AND b.ProductId NOT IN (15,25,14,17) -- exclude CO, CB, MGCLC, MGCRNG
		GROUP BY b.rptdate, b.SiteId, p.PartyId,b.CurrencyID, p.ProductId, e.Rate
	)

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

	-- Rebate
	SELECT h.ToDate,p.ProductId, d.Rate, h.Remark
	INTO #Rebate
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
	INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
	INNER JOIN dbo.LA_DiscountGroupProduct p WITH(NOLOCK) ON p.DiscountGroupId = h.DiscountGroupId
	INNER JOIN dbo.LA_DiscountGroupDetail d WITH(NOLOCK) ON d.DiscountGroupId = h.DiscountGroupId
	WHERE	a.PartyID = @PartyId AND
			@FromDate<= h.ToDate AND
			h.FromDate<=@ToDate AND
			h.DiscountGroupType = 2 AND
			p.ProductId <> 1 --exclude RB

	DELETE  #Rebate WHERE ToDate < (SELECT	MAX(ToDate) FROM #Rebate)
	-- end rebate

	DECLARE @Result TABLE(ProductId INT, AmountToCompany MONEY)
	
	-- products have minfee
	INSERT INTO @Result
	SELECT ProductId, SUM(AmountToCompany)
	FROM @MinFeeGroup
	WHERE PartyId = @PartyId AND FeeType = 1
	GROUP BY ProductId

	-- products don't have minfee
	INSERT INTO @Result
	SELECT td.ProductId, SUM(td.AmountToCompany)
	FROM #TempData td
	WHERE td.PartyId = @PartyId AND td.ProductId NOT IN (SELECT td2.ProductId FROM @MinFeeGroup td2 WHERE td2.PartyId = @PartyId)
	GROUP BY td.ProductId

	-- include no ticket product
	INSERT INTO @Result
	SELECT p.ProductId, 0 FROM @Products p
	WHERE p.ProductId NOT IN (SELECT r.ProductId FROM @Result r)

	;WITH RebateCalculation AS(
		SELECT
			ISNULL(CASE WHEN rs.AmountToCompany < 0 THEN 0 ELSE rs.AmountToCompany END * rb.Rate, 0) Rebate,
			ISNULL(CASE WHEN rs.AmountToCompany < 0 AND rs.ProductId NOT IN (3,15,25) THEN 0 ELSE rs.AmountToCompany END, 0) Amount
		FROM @Result rs
		LEFT JOIN #Rebate rb ON rb.ProductId = rs.ProductId
	)
	SELECT (SELECT TOP 1 Remark FROM #Rebate) Remark,
		@ToDate			AS ReportDate,
		@BaseCurrency	AS CurrencyName,
		SUM(Rebate)		AS TotalRebate,
		SUM(Amount)		AS TotalAmount
	FROM RebateCalculation

	SELECT * FROM @Result

	-- Region: Drop tmp table
	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #Rebate
	DROP TABLE #TempDataCB
	-- End region
END
GO