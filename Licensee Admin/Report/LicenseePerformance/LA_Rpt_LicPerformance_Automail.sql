/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicPerformance_Automail] 
	@ProductCodes VARCHAR(500)
	, @FromDate		SMALLDATETIME
	, @ToDate		SMALLDATETIME 
AS
/*	Created: 20171122@Parsons
	Task: LicenseeAdmin - Get Licensee Performance Report
	DB: DB052.bodb_licensee

	Revisions:
	 - 20180712@Bruce: Enhance Manage Discount group [#94282]
	 - 20180716@bruce: add new group TEST for credit [#98126]
	 - 20180607@Parsons: Integrate Pragmatic [#94108]

	Example:
	USE bodb_licensee
	DECLARE @ProductCodes		VARCHAR(500)	= 'NG,BA,LC,VS,CS,KN,AGC,GD,VG,BT,MGCLC,MGCRNG,AB,VB,NG2,FW,VS2,LT' 
	DECLARE @FromDate	DATETIME	= '2017-5-01'
	DECLARE @ToDate	DATETIME	= '2017-5-31'

	EXEC [LA_Rpt_LicPerformance_Automail] @ProductCodes, @FromDate, @ToDate	
*/

BEGIN
	SET NOCOUNT ON

	DECLARE 
		@PartyIDs VARCHAR(1000),
		@BaseCurrencyName VARCHAR(10) = 'EUR'
	
	-- get ALL partyIDs exclude 'FDL', 'PIH', '18bb', 'IBC'
	DECLARE @PartyRoot table (PartyId int, PartyName varchar(100), BrandName varchar(100), ParentID int)
	INSERT INTO @PartyRoot
	EXEC LA_PartyListSel 

	DELETE @PartyRoot
	WHERE ParentID IN (0,999)

	SET @PartyIDs = (SELECT CAST(PartyId AS VARCHAR(10)) + ',' 
	FROM @PartyRoot FOR XML PATH(''))

	-- ************************************************************************
	--  select all parties in the same group	
	-- ************************************************************************
	DECLARE @PartyGroup AS TABLE (PartyGroupId INT, PartyId INT)
	INSERT	INTO @PartyGroup(PartyGroupId, PartyId)
	(
		SELECT	PartyGroupId, PartyId
		FROM	bodb_licensee.dbo.LA_PartyGroupAssignment WITH(NOLOCK)
		WHERE	PartyGroupId IN (	SELECT	p1.PartyGroupId
									FROM	bodb_licensee.dbo.LA_PartyGroupAssignment p1 WITH(NOLOCK)
									WHERE	p1.PartyId IN (SELECT p2.PartyId FROM @PartyRoot p2))
	)

	-- Region: Party charge info
	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			Rate		MONEY,
			TypeId		INT,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME,
			Bettype		INT)

	-- ***********************************************************************************************
	-- *** Get ChargeInfo for @PartyIDs 
	-- ***********************************************************************************************
	-- select bettype to avoid duplicated data of MGC

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, TypeId, Fromdate, Todate, Bettype)
	(
		SELECT DISTINCT ci.PartyID, ci.LicenseeID, ci.ProductID, 
				CASE WHEN ISNULL(ci.isDeposit, 0) = 1 THEN ci.DI_Rate ELSE 0 END,
				ci2.ChargeType, 
				ci.Fromdate, 
				ci.ToDate,	
				CASE WHEN ci.ProductId IN (14,17) THEN ISNULL(sbr.Bettype, ci.Bettype) ELSE -1 END
		FROM	bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCodes, 'OA', 1) ci
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci2 WITH(NOLOCK) ON ci.ChargeID = ci2.ChargeID
		LEFT JOIN bodb_licensee..Sport_Bettype_Reference sbr WITH(NOLOCK) ON sbr.BettypeRef = ci.Bettype
	)
	-- End region

	-- *************************************************************************************************************
	-- *** Get minfee, waive 
	-- *** - minfee: FeeType = 1, waive: FeeType = 2
	-- *** - conditions: Product is in (PartyChargeInfo)
	-- *** - waive: select only waive which has corresponding minfee config
	-- *************************************************************************************************************
	--  Minimum fee is calculated for all currencies that licensee offer. There is no minimum fee when data display individual currency.

	-- Region: MinfeeGroup Date range
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
				AmountToCompany	MONEY)
		
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
					AND ((mf.FromDate BETWEEN @FirstDate AND @LastDate) 
						OR (mf.ToDate BETWEEN @FirstDate AND @LastDate) 
						OR (mf.FromDate<@FirstDate AND @LastDate < mf.ToDate)
					)
		)

		DELETE	FROM @MinFeeGroup
		WHERE	(FeeType = 2 AND FromDate > ToDate) OR
				(PartyId NOT IN (SELECT g.PartyId FROM @PartyGroup g) AND
					PartyId NOT IN (SELECT p.PartyId FROM @PartyRoot p))
	-- End region


	-- **********************************************************************************************
	-- *** Get Exchange info for @BaseCurrencyName
	-- **********************************************************************************************
	-- Region: Get exchange rate info
	CREATE	TABLE #Exchange (
			ExchangeDate	DATE,
			ExchangeID		INT,
			CurrencyCode	VARCHAR(10),
			Rate			FLOAT)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	-- End region

	UPDATE m SET m.FeeAmount = m.FeeAmount * e.Rate
	FROM @MinFeeGroup m
	INNER JOIN #Exchange e ON m.ToDate = e.ExchangeDate AND m.CurrencyId = e.ExchangeID

	-- Region: Get Amount by Product
	CREATE	TABLE #TempData (
			PartyId			INT,
			ProductId		INT,
			rptDate			DATETIME,
			Turnover		MONEY,
			WinLoss			MONEY,
			AmountToCompany MONEY,
			IsApplyMinFee	BIT)
	CREATE NONCLUSTERED INDEX Idx_InvoiceData ON #TempData (PartyId)
	INSERT INTO #TempData (PartyId,rptDate,Turnover,WinLoss,AmountToCompany,ProductId)
	(
		SELECT	p.PartyId,
				b.rptDate,
				SUM(ISNULL(b.Turnover, 0)) * e.Rate,
				SUM(ISNULL(b.MemberWL, 0)) * e.Rate,
				SUM((-ISNULL(b.MemberWL, 0) * p.Rate) - (CASE WHEN b.ProductId = 3 THEN ISNULL(b.CommissionA, 0) ELSE 0 END)) * e.Rate,
				p.ProductId
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #Exchange e ON b.rptDate = e.ExchangeDate AND b.CurrencyId = e.ExchangeID
				INNER JOIN @PartyChargeInfo p ON	b.ProductId = p.ProductID 
													AND p.LicenseeId = b.SiteId
													AND (b.rptDate BETWEEN p.FromDate AND p.ToDate)
													AND (p.Bettype = -1 OR p.Bettype = b.Bettype)
		WHERE	(b.rptDate BETWEEN @FromDate AND @ToDate)
				AND b.CurrencyID <> 20
				AND b.customercategory NOT IN (27, 28)
				AND b.StatusId NOT IN (-1, 101, 102, 103) -- Exclude Reject , Void, Refund
		GROUP BY b.rptdate, p.PartyId, p.ProductId, e.Rate
	)

--  Minimum fee is calculated for all currencies that licensee offer. There is no minimum fee when data display individual currency.
	BEGIN
		UPDATE  t
		SET		t.IsApplyMinFee = 0
		FROM	#TempData t INNER JOIN @MinFeeGroup m ON (t.rptDate BETWEEN m.FromDate AND m.ToDate)
				AND t.ProductId = m.ProductId
				AND t.PartyId = m.PartyId
		WHERE	m.FeeType=2
		-- End region

		-- Region: Check min fee group
		--- calculate waived prorate (*)
		UPDATE	amf
		SET		MinFeeProrate = ((	SELECT	TOP 1 mfg.FeeAmount
									FROM	@MinFeeGroup mfg
									WHERE	mfg.FeeType = 1
											AND mfg.PartyId = amf.PartyId
											AND mfg.ProductId = amf.ProductId)
								/ (@DaysInMonth ) * (DATEDIFF(DAY, FromDate, ToDate) + 1) )
		FROM	@MinFeeGroup amf
		WHERE	FeeType = 2

		--- sum amount under waived
		UPDATE	amf
		SET		amf.WaivedAmount = ISNULL((	SELECT	SUM(td.AmountToCompany)
											FROM	#TempData td 
											WHERE	amf.PartyId = td.PartyId
													AND amf.ProductId = td.ProductId
													AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate), 0)
		FROM	@MinFeeGroup amf
		WHERE	amf.FeeType = 2

		--- calculate min fee prorate (fee amount in month - waived amount (*)
		UPDATE	amf
		SET		amf.MinFeeProrate = ROUND((	amf.FeeAmount / ( @DaysInMonth)) * (DATEDIFF(DAY, FromDate, ToDate) + 1) -
											ISNULL((SELECT	SUM(f.MinFeeProrate)
													FROM	@MinFeeGroup f
													WHERE	f.FeeType = 2
															AND amf.PartyId = f.PartyId
															AND amf.ProductId = f.ProductId), 0), 2),
				amf.WaivedAmount =  ISNULL((SELECT	CASE WHEN SUM(f.WaivedAmount) < 0 THEN 0 ELSE SUM(f.WaivedAmount) END
											FROM	@MinFeeGroup f
											WHERE	f.FeeType = 2
													AND amf.PartyId = f.PartyId
													AND amf.ProductId = f.ProductId), 0),
				amf.MinFeeAmount =  ISNULL((SELECT	SUM(td.AmountToCompany)
											FROM	#TempData td 
											WHERE	amf.PartyId = td.PartyId
													AND td.rptDate BETWEEN amf.FromDate AND amf.ToDate
													AND td.IsApplyMinFee IS NULL
													AND amf.ProductId = td.ProductId), 0)
		FROM	@MinFeeGroup amf
		WHERE	amf.FeeType = 1
		--- sum min fee amount
		UPDATE	amf
		SET		amf.TotalAmount =  amf.MinFeeAmount + amf.WaivedAmount
		FROM	@MinFeeGroup amf
		WHERE	amf.FeeType = 1
	
		DECLARE @TotalMinFees TABLE(
			PartyGroupId		INT,
			ProductId			INT,
			TotalMinFee			MONEY,
			TotalMinFeeAmount	MONEY
		)
		INSERT	INTO @TotalMinFees(PartyGroupId, ProductId, TotalMinFee, TotalMinFeeAmount)
		SELECT	pg.PartyGroupId, mf.ProductId,
				SUM(mf.MinFeeProrate),
				SUM(CASE WHEN mf.MinFeeAmount < 0 THEN 0 ELSE mf.MinFeeAmount END)
		FROM	@MinFeeGroup mf
		INNER JOIN @PartyGroup pg ON mf.PartyId = pg.PartyId
		WHERE	mf.FeeType = 1
		GROUP BY pg.PartyGroupId,mf.ProductId

		-- update minfee group
		UPDATE	amf
		SET		amf.AmountToCompany =	CASE
											WHEN t.TotalMinFeeAmount < t.TotalMinFee AND amf.MinFeeAmount < amf.MinFeeProrate 
												THEN amf.MinFeeProrate + amf.WaivedAmount
											ELSE amf.TotalAmount
										END
		FROM	@MinFeeGroup amf
		INNER JOIN @PartyGroup pg ON pg.PartyId = amf.PartyId
		INNER JOIN @TotalMinFees t ON amf.ProductId = t.ProductId AND t.PartyGroupId = pg.PartyGroupId
		WHERE	amf.FeeType = 1
		
		-- update minfee non-group
		UPDATE	amf
		SET		amf.AmountToCompany =	CASE WHEN amf.MinFeeAmount < amf.MinFeeProrate
												THEN amf.MinFeeProrate + amf.WaivedAmount
											ELSE amf.TotalAmount
										END
		FROM	@MinFeeGroup amf
		WHERE	amf.FeeType = 1 AND amf.AmountToCompany IS NULL
	END

	-- ********************************************************************************************
	-- *** Get Discount and Rebate Headers
	-- *** Conditions: FromDate-ToDate intersect with @FromDate-@ToDate
	-- ********************************************************************************************
	-- Region: Discount & Rebate Settings
	BEGIN
	DECLARE @DiscountGroupHeader AS TABLE (
			DiscountGroupId		INT,
			DiscountGroupType	TINYINT,
			PartyId				INT,
			CurrencyId			INT,
			FromDate			DATETIME,
			ToDate				DATETIME
			)
	
	INSERT INTO @DiscountGroupHeader(DiscountGroupId,DiscountGroupType,PartyId,CurrencyId,FromDate,ToDate)
	(
		SELECT	dg.DiscountGroupId,dg.DiscountGroupType,dga.PartyId, dg.CurrencyId, dg.FromDate, dg.ToDate
		FROM	bodb_Licensee.dbo.LA_DiscountGroupHeader dg WITH(NOLOCK)
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupAssignment dga WITH(NOLOCK) ON dga.DiscountGroupId = dg.DiscountGroupId
		WHERE	@FromDate<= ToDate AND FromDate<=@ToDate
	)

	-- ********************************************
	-- *** Get the lastest discount/rebate headers
	-- ********************************************
	DECLARE @DiscountGroupType INT = 1
	WHILE @DiscountGroupType <= 2
	BEGIN
		DELETE	d FROM @DiscountGroupHeader d
		WHERE	d.ToDate < (SELECT	MAX(g.ToDate)
					FROM	@DiscountGroupHeader g
					WHERE	g.DiscountGroupType = @DiscountGroupType AND d.PartyId = g.PartyId)
			AND d.DiscountGroupType = @DiscountGroupType
		
	   SET @DiscountGroupType = @DiscountGroupType + 1
	END

	-- **********************************************
	-- *** Get Discount/Rebate Settings Infos
	-- *** Conditions: ProductId in (PartyChargeInfo)
	-- **********************************************
	DECLARE @DiscountGroup AS TABLE(
			DiscountGroupId		SMALLINT,
			DiscountGroupType	TINYINT,
			FromAmount			MONEY,
			ToAmount			MONEY,
			Rate				MONEY,
			PartyId				INT,
			ProductId			TINYINT,
			BaseCurrency		INT)

	INSERT INTO @DiscountGroup (DiscountGroupId, DiscountGroupType, FromAmount, ToAmount, Rate, PartyId, ProductId , BaseCurrency)	
	(
		SELECT	dg.DiscountGroupId,
				dg.DiscountGroupType,
				dgd.FromAmount,
				dgd.ToAmount,
				dgd.Rate,
				dg.PartyID,
				dgp.ProductId,
				dg.CurrencyId
		FROM	@DiscountGroupHeader dg 
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupDetail dgd WITH(NOLOCK) ON dg.DiscountGroupId = dgd.DiscountGroupId
				INNER JOIN bodb_Licensee.dbo.LA_DiscountGroupProduct dgp WITH(NOLOCK) ON dg.DiscountGroupId = dgp.DiscountGroupId
		WHERE	dgp.ProductId IN ( SELECT DISTINCT ProductId FROM @PartyChargeInfo)
	)

	-- ***************************************************************
	-- *** Convert Discount FromAmount, ToAmount to @BaseCurrencyName
	-- *** Notes: Rebate does not have FromAmount, ToAmount
	-- ***************************************************************
	-- convert discount amount to base currency
	UPDATE d SET
		d.FromAmount = d.FromAmount * e.Rate,
		d.ToAmount = d.ToAmount * e.Rate
	FROM @DiscountGroup d
	INNER JOIN #Exchange e ON
		e.ExchangeDate =(@ToDate) AND
		d.BaseCurrency = e.ExchangeID AND
		d.DiscountGroupType = 1 -- discount = 1
	END
	-- End Region

	-- Sum products
	BEGIN
		DECLARE @SumByProducts TABLE(
			PartyId			INT,
			Turnover		MONEY,
			WinLoss			MONEY,
			AmountToCompany	MONEY,
			ProductId		INT
		)
		-- sum by product
		INSERT INTO @SumByProducts (PartyId,ProductId,Turnover,WinLoss,AmountToCompany)
		SELECT	PartyId
				,ProductId
				,SUM(Turnover) Turnover
				,SUM(WinLoss) WinLoss
				,SUM(AmountToCompany) AmountToCompany
		FROM #TempData
		GROUP BY PartyId, ProductId

		-- merge to minfee group
		UPDATE s SET AmountToCompany = m.AmountToCompany
		FROM @SumByProducts s
		INNER JOIN @MinFeeGroup m ON m.PartyId = s.PartyId AND m.ProductId = s.ProductId
		WHERE m.FeeType = 1 -- min fee
		
		-- insert data for party-product which has min fee but doesn't has bet ticket
		INSERT INTO @SumByProducts(PartyId, ProductId, AmountToCompany, Turnover, WinLoss)
		SELECT m.PartyId, m.ProductId, m.AmountToCompany, 0, 0
		FROM @MinFeeGroup m
		LEFT JOIN @SumByProducts s ON m.PartyId = s.PartyId AND m.ProductId = s.ProductId
		WHERE m.FeeType = 1 AND s.PartyId IS NULL

		-- filter discount
		;WITH t AS(
			SELECT SUM(s.AmountToCompany) Total, s.PartyId,d.DiscountGroupId
			FROM @SumByProducts s
			INNER JOIN (SELECT DISTINCT DiscountGroupId,PartyId,ProductId FROM @DiscountGroup WHERE DiscountGroupType = 1) AS d
				ON s.PartyId=d.PartyId AND s.ProductId=d.ProductId 
			GROUP BY s.PartyId, d.DiscountGroupId
		)
		DELETE d
		FROM @DiscountGroup d
		INNER JOIN t ON t.DiscountGroupId = d.DiscountGroupId AND t.PartyId = d.PartyId
		WHERE d.DiscountGroupType = 1 AND t.Total NOT BETWEEN d.FromAmount AND d.ToAmount
	END

	-- Region: Result
	CREATE TABLE #Result (
		PartyId			INT,
		ProductId		INT,
		LicenseeName	VARCHAR(100),
		Turnover		MONEY,
		WinLoss			MONEY,
		AmountToBA		MONEY,
		LicensingFee	MONEY,
		Discount		MONEY,
		Rebate			MONEY
	)

	INSERT INTO #Result (PartyId, ProductId, LicenseeName, LicensingFee, Turnover, WinLoss,AmountToBA, Discount)
	SELECT	p.PartyId,
			s.ProductId,
			op.PartyName,
			SUM(CASE WHEN s.ProductId = 3 THEN 0 ELSE s.AmountToCompany END),
			SUM(s.Turnover),
			SUM(s.WinLoss),
			SUM(CASE WHEN s.ProductId = 3 THEN s.AmountToCompany ELSE 0 END),
			SUM((CASE WHEN -s.WinLoss < 0 THEN 0 ELSE -s.WinLoss * ISNULL(d3.Rate, 0) END) + (CASE WHEN s.AmountToCompany < 0 THEN 0 ELSE s.AmountToCompany * ISNULL(d1.Rate, 0) END))
	FROM	@PartyRoot p
			INNER JOIN bodb_licensee.dbo.OAS_Party (NOLOCK) op ON p.PartyId = op.PartyID
			INNER JOIN @SumByProducts s ON p.PartyId = s.PartyId
			LEFT JOIN @DiscountGroup d1 ON s.PartyId = d1.PartyId AND d1.ProductId = s.ProductId AND d1.DiscountGroupType = 1 -- discount = 1
			LEFT JOIN @DiscountGroup d3 ON s.PartyId = d3.PartyId AND d3.ProductId = s.ProductId AND d3.DiscountGroupType = 3 -- discount = 3 
	GROUP BY p.PartyId, s.ProductId, op.PartyName

	-- calculate licensing fee
	UPDATE #Result SET LicensingFee = 0 WHERE LicensingFee < 0

	-- calculate rebate
	UPDATE res SET Rebate = CASE WHEN res.LicensingFee = 0 THEN 0 ELSE (res.LicensingFee - res.Discount) * ISNULL(r.Rate, 0) END
	FROM #Result res
	LEFT JOIN @DiscountGroup r ON res.PartyId = r.PartyId AND r.ProductId = res.ProductId AND r.DiscountGroupType = 2 -- rebate = 2

	-- Region: Select Data	
	;WITH r AS 
	(
		SELECT LicenseeName, 
			SUM(Turnover)	AS Turnover,
			SUM(WinLoss)	AS WinLoss,
			SUM(LicensingFee - Discount - Rebate + AmountToBA) AS LicensingFee
		FROM #Result
		GROUP BY LicenseeName
	)
	SELECT r.LicenseeName, r.Turnover,r.WinLoss,
		CASE WHEN r.WinLoss = 0 THEN 0 ELSE
			ABS((r.LicensingFee/CAST(-r.WinLoss AS DECIMAL(18,5))) * r.Turnover)
		END	AS TurnoverOneworks,
		r.LicensingFee
	FROM r
	-- End region

	-- Region: Drop tmp table
	DROP TABLE #Exchange
	DROP TABLE #TempData
	DROP TABLE #Result
	-- End region
END
GO

