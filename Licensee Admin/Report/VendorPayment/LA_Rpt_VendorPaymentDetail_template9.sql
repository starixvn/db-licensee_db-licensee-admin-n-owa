/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Rpt_VendorPaymentDetail_template9]
	@PartyIds			VARCHAR(4000)
	,@ProductID			INT
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@BaseCurrencyName	VARCHAR(20)
	,@TimeZoneId		INT
	,@GroupByLicensee	BIT = 0
	,@PlatformId		TINYINT = 0
AS
/*
 * Created by : [20220405@Danny]
 * Task  : Vendor Payment Detail (template9 - Template for Allbet product, including some specific info such as: Promotion, Valid Bet Amount, Play Currency, Comm...)
 * Revisions
	- 20220426@Danny: Initialize SP [#168387]
	- 20221003@Malcolm: Add platform filter [RedmineID: #165707]
 */

BEGIN
	SET NOCOUNT ON

	DECLARE @ProductCode VARCHAR(50)
	DECLARE @BettypeIdList TABLE (BetTypeId INT)
	DECLARE @3rdRate TABLE(PartyID INT, ProductID INT, DI_Rate MONEY, IsDeposit INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME, MinAmount MONEY DEFAULT 0, MaxAmount MONEY DEFAULT 0, CurrencyId INT)
	
	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT, IsKeepNegativeAmount BIT DEFAULT 0)
	
	CREATE TABLE #ChargeRate (
		ChargeID		INT
		,PartyID		INT
		,LicenseeID		INT
		,isDeposit		INT
		,ProductID		INT
		,Rate				DECIMAL(10,8)	DEFAULT 0
		,Rate3rd			MONEY	DEFAULT 0
		,RebateCommission	DECIMAL(10,8)	DEFAULT 0
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
	)

	CREATE TABLE #Exchange (
		ExchangeDate	DATETIME,
		ExchangeId		INT,
		Code			VARCHAR(10),
		Rate			FLOAT
	)

	CREATE TABLE #TempData (
		PartyID			INT,
		PartyName		NVARCHAR(100),
		ParentId		INT,
		ParentName		NVARCHAR(100),
		rptDate			DATETIME,
		CurrencyId		INT,
		PlayCurrency	INT,
		Turnover		MONEY	DEFAULT 0,
		TotalTrans		INT		DEFAULT 0,
		CustomerWinLoss MONEY	DEFAULT 0,
		LicenseeWinloss MONEY	DEFAULT 0,
		LicensingFee	MONEY	DEFAULT 0,
		PayToSupplier	MONEY	DEFAULT 0,
		isDeposit		BIT,
		ValidBetAmount	MONEY	DEFAULT 0, 
		ServiceChargeOriginal DECIMAL(20,12)	DEFAULT 0, 
		RebateCommissionOriginal DECIMAL(20,12)	DEFAULT 0, 
		PromotionOriginal MONEY	DEFAULT 0
	)


	-- ProductCode
	SELECT  @ProductCode =  ProductPrefix 
	FROM dbo.Product3rd WITH(NOLOCK) WHERE Productid = @ProductID

	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = p.PartyName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END
	-- Party list
	INSERT INTO #PartyList (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	UPDATE #PartyList SET PartyName = REPLACE(PartyName,' Licensees','') WHERE ParentId = 0
	
	UPDATE t 
	SET t.IsKeepNegativeAmount = CASE WHEN u.PartyId IS NULL THEN 0 ELSE 1 END 
	FROM #PartyList t 
	LEFT JOIN bodb_Licensee.dbo.LA_f_JVPartyListSel() u ON u.PartyId = t.PartyId

	-- Bettype List
	INSERT INTO @BettypeIdList (BetTypeId)
	SELECT	DISTINCT bettype
	FROM	bodb_licensee.dbo.LA_f_BettypeProductMapping(0,@ProductCode) la

	-- Handle chargeRate
	IF @ProductID = 21
	BEGIN
		DECLARE @Allbet INT 
		SELECT @Allbet = PartyID FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyName='Allbet' AND PartyType=3

		DECLARE @PlayCurrencySettings TABLE(
			SiteId			INT,
			MemberCurrency	INT,
			PlayCurrency	INT,
			FromDate		DATETIME,
			ToDate			DATETIME
		)
		INSERT INTO @PlayCurrencySettings
		SELECT SiteId, MemberCurrency,PlayCurrency,FromDate,ToDate
		FROM OPENQUERY(DBACC,'SELECT SiteId, MemberCurrency,PlayCurrency,FromDate,ToDate FROM bodb02.dbo.PlayCurrencySetting WITH(NOLOCK) WHERE SportType=211')

		INSERT INTO #ChargeRate(PartyId, LicenseeId, FromDate,ToDate, Rate, RebateCommission)
		SELECT ci.PartyId, ci.LicenseeID,
			CASE WHEN ci.isDeposit=1 AND ci.FromDate <= dc.FromDate THEN dc.FromDate
				 WHEN ci.isDeposit=0 AND ci.FromDate <= cc.FromDate THEN cc.FromDate
				 ELSE ci.FromDate END,
			CASE WHEN ci.isDeposit=1 AND ci.Todate >= dc.ToDate THEN dc.ToDate
				 WHEN ci.isDeposit=0 AND ci.Todate >= cc.ToDate THEN cc.ToDate
				 ELSE ci.ToDate END,
			ISNULL(CASE WHEN ci.isDeposit=1 THEN dc.Rate ELSE ci.DI_Rate END,0),
			ISNULL(ci.DI_Rate * cc.Rate, 0)
		FROM dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate,@ToDate,'AB','OA',1) ci
		LEFT JOIN dbo.OAS_ChargeInfo dc WITH(NOLOCK) ON
			dc.FromParty = 1 AND
			dc.ToParty = @Allbet AND
			dc.ProductID = ci.ProductID AND
			dc.ToDate >= ci.FromDate AND
			dc.FromDate <= ci.Todate AND
			dc.ChargeType = 9
		LEFT JOIN dbo.OAS_ChargeInfo cc WITH(NOLOCK) ON
			cc.FromParty = ci.PartyID AND
			cc.ProductID = ci.ProductID AND
			cc.ToDate >= ci.FromDate AND
			cc.FromDate <= ci.Todate AND
			cc.ChargeType = 11
	END
	ELSE 
	BEGIN
		-- Get 3rd Rate
		INSERT INTO @3rdRate (PartyID, ProductID, DI_Rate, IsDeposit, Fromdate, Todate)
		SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.IsDeposit, r.Fromdate, r.Todate 
		FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, @ProductCode, 'OA') r 
		INNER JOIN #PartyList p on p.ParentId = r.PartyID
	
		-- ​#ChargeRate
		INSERT INTO #ChargeRate (ChargeID, PartyID, LicenseeID, isDeposit, ProductID, Rate, Rate3rd, Fromdate, Todate)
		SELECT DISTINCT c.ChargeID, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate AS Rate, r.DI_Rate AS Rate3rd, c.Fromdate, c.Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, @ProductCode) c
		INNER JOIN @3rdRate r ON r.PartyID = c.PartyID and CASE WHEN r.ProductID = 69 THEN 0 ELSE  r.ProductID END = c.ProductID
		WHERE (c.DI_Rate = 0 AND c.isDeposit = 0) OR (c.DI_Rate > 0 and c.isDeposit = 1)
	END

	-- Region: TempData 
	IF @TimeZoneId = 1 --GMT -4
	BEGIN
			INSERT INTO #TempData (PartyID, rptDate, CurrencyId, PlayCurrency, TotalTrans, Turnover, CustomerWinLoss, ValidBetAmount, ServiceChargeOriginal, RebateCommissionOriginal, PromotionOriginal)
			SELECT	ci.PartyId,
				b.RptDate AS rptDate,
				b.CurrencyID,
				ISNULL(pc.PlayCurrency, b.CurrencyID) AS PlayCurrency,
				SUM(ISNULL(CASE WHEN p.Bettype IS NOT NULL THEN 0 ELSE b.BetCount END, 0)) AS TotalTrans,
				SUM(ISNULL(CASE WHEN p.Bettype IS NOT NULL THEN 0 ELSE b.Turnover END, 0)) AS Turnover,
				SUM(ISNULL(CASE WHEN p.Bettype IS NOT NULL THEN 0 ELSE b.MemberWL END, 0)) AS CustomerWinLoss,
				SUM(ISNULL(b.ValidBetAmount, 0)) AS ValidBetAmount,
				SUM(ISNULL(CASE WHEN p.Bettype IS NOT NULL THEN 0 ELSE -b.MemberWL END, 0) * ci.Rate) AS ServiceChargeOriginal,
				SUM(ISNULL(b.ValidBetAmount, 0) * ci.RebateCommission) AS RebateCommissionOriginal,
				SUM(CASE WHEN p.Bettype IS NOT NULL THEN b.MemberWL ELSE 0 END) AS PromotionOriginal
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.RptDate BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN dbo.view_site_list s WITH(NOLOCK) ON b.SiteId = s.SiteID
			LEFT JOIN @PlayCurrencySettings pc ON
			(
				s.IbcSiteID = pc.SiteId AND
				b.CurrencyId = pc.MemberCurrency AND
				b.rptDate BETWEEN pc.FromDate AND pc.ToDate
			)
			LEFT JOIN bodb_licensee.dbo.LA_f_GroupBettype() p ON p.Bettype = b.Bettype AND p.ProductId = @ProductID AND p.TypeId = 8 -- Promotion 
		WHERE	b.RptDate BETWEEN @FromDate AND @ToDate 
				AND b.CurrencyID <> 20 
				AND b.ProductID = @ProductID
				AND	b.StatusId NOT IN (-1, 101, 102, 103)
		GROUP BY b.RptDate, ci.PartyId, b.CurrencyID, ISNULL(pc.PlayCurrency, b.CurrencyID)
	END
	ELSE -- Another timezone
	BEGIN
		INSERT INTO #TempData (PartyID, rptDate, CurrencyId, PlayCurrency, TotalTrans, Turnover, CustomerWinLoss, ValidBetAmount, ServiceChargeOriginal, RebateCommissionOriginal, PromotionOriginal)
		SELECT	ci.PartyId,
				b.RptDate3rd AS rptDate,
				b.CurrencyID,
				ISNULL(pc.PlayCurrency, b.CurrencyID) AS PlayCurrency,
				SUM(ISNULL(CASE WHEN p.Bettype IS NOT NULL THEN 0 ELSE b.BetCount END, 0)) AS TotalTrans,
				SUM(ISNULL(CASE WHEN p.Bettype IS NOT NULL THEN 0 ELSE b.Turnover END, 0)) AS Turnover,
				SUM(ISNULL(CASE WHEN p.Bettype IS NOT NULL THEN 0 ELSE b.Winloss END, 0)) AS CustomerWinLoss,
				SUM(ISNULL(b.ValidBetAmount, 0)) AS ValidBetAmount,
				SUM(ISNULL(CASE WHEN p.Bettype IS NOT NULL THEN 0 ELSE -b.Winloss END, 0) * ci.Rate) AS ServiceChargeOriginal,
				SUM(ISNULL(b.ValidBetAmount, 0) * ci.RebateCommission) AS RebateCommissionOriginal,
				SUM(CASE WHEN p.Bettype IS NOT NULL THEN b.Winloss ELSE 0 END) AS PromotionOriginal
		FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN dbo.view_site_list s WITH(NOLOCK) ON b.SiteId = s.SiteID
			LEFT JOIN @PlayCurrencySettings pc ON
			(
				s.IbcSiteID = pc.SiteId AND
				b.CurrencyId = pc.MemberCurrency AND
				b.rptDate BETWEEN pc.FromDate AND pc.ToDate
			)
			LEFT JOIN bodb_licensee.dbo.LA_f_GroupBettype() p ON p.Bettype = b.BetTypeId AND p.ProductId = @ProductID AND p.TypeId = 8 -- Promotion 
		WHERE	b.RptDate BETWEEN DATEADD(DAY, -1, @FromDate) AND DATEADD(DAY, 1, @ToDate)
				AND b.RptDate3rd BETWEEN @FromDate AND @ToDate 
				AND b.CurrencyID <> 20 
				AND b.BetTypeId IN (SELECT x.bettypeID FROM @BettypeIdList x)
				AND	b.StatusId NOT IN (-1, 101, 102, 103)
		GROUP BY b.RptDate3rd, ci.PartyId, b.CurrencyID, ISNULL(pc.PlayCurrency, b.CurrencyID)
	END

	-- Region: Calculate result
	CREATE TABLE #Result (
		PartyId						INT,
		ReportDate					DATETIME,
		OriginalCurrency			VARCHAR(10),
		RegisteredCurrency			VARCHAR(10),
		TotalTrans					INT,
		Turnover					MONEY,
		TurnoverBased				MONEY,
		ValidBetAmount				MONEY,
		ValidBetAmountBased			MONEY,
		CustomerWinLoss				MONEY,
		CustomerWinLossBased		MONEY,
		ServiceChargeOriginal		MONEY,
		ServiceChargeBased			MONEY,
		ServiceChargeRegistered		MONEY,
		ServiceChargeVariance		MONEY,
		RebateCommissionOriginal	MONEY,
		RebateCommissionBased		MONEY,
		RebateCommissionRegistered	MONEY,
		RebateCommissionVariance	MONEY,
		PayToSupplierOriginal		MONEY,
		PayToSupplierBase			MONEY,
		PayToSupplierRegistered		MONEY,
		PayToSupplierVariance		MONEY,
		PromotionOriginal			MONEY,
		PromotionBased				MONEY,
		PromotionRegistered			MONEY,
		PromotionVariance			MONEY
	)

	DECLARE @Total TABLE (
		PartyId			INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY,
		Currency		VARCHAR(20)
	)

	-- Region: Calculate Grand Total
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id		INT,
		Name	VARCHAR(20),
		IsApply	BIT
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC bodb_licensee.dbo.LA_SelBaseCurrency
	-- include HKD
	INSERT INTO @BaseCurrencies(ID, Name) VALUES (5, 'HKD')

	DECLARE @GrandTotal TABLE (
		RegisteredCurrency			VARCHAR(10),
		TotalTrans					INT,
		Turnover					MONEY,
		ValidBetAmount				MONEY,
		CustomerWinLoss				MONEY,
		ServiceChargeBased			MONEY,
		ServiceChargeRegistered		MONEY,
		ServiceChargeVariance		MONEY,
		RebateCommissionBased		MONEY,
		RebateCommissionRegistered	MONEY,
		RebateCommissionVariance	MONEY,
		PayToSupplierBase			MONEY,
		PayToSupplierRegistered		MONEY,
		PayToSupplierVariance		MONEY,
		PromotionBased				MONEY,
		PromotionRegistered			MONEY,
		PromotionVariance			MONEY
	)
	
	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @TempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
		
		INSERT INTO #Exchange(ExchangeDate, ExchangeId, Rate, Code)
		SELECT exchangedate, ExchangeId, BaseCurrencyRate, CASE WHEN ExchangeId = 92 THEN 'HID' 
																WHEN ExchangeId = 51 THEN 'INH' 
																ELSE Code END
		FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @TempCurrency)

		;WITH StagingData AS (
			SELECT	t.PartyId,
					t.rptDate,
					oe.Code AS OriginalCurrency,
					re.Code AS RegisteredCurrency,
					t.TotalTrans,
					t.Turnover,
					t.Turnover * oe.Rate AS TurnoverBased,
					t.ValidBetAmount,
					t.ValidBetAmount * oe.Rate AS ValidBetAmountBased,
					t.CustomerWinLoss,
					t.CustomerWinLoss * oe.Rate AS CustomerWinLossBased,
					t.ServiceChargeOriginal,
					t.ServiceChargeOriginal * oe.Rate AS ServiceChargeBased,
					t.ServiceChargeOriginal * re.Rate AS ServiceChargeRegistered,
					t.RebateCommissionOriginal ,
					t.RebateCommissionOriginal * oe.Rate AS RebateCommissionBased,
					t.RebateCommissionOriginal * re.Rate AS RebateCommissionRegistered,
					t.PromotionOriginal,
					t.PromotionOriginal * oe.Rate AS PromotionBased,
					t.PromotionOriginal * re.Rate AS PromotionRegistered
			FROM #TempData t
			INNER JOIN #Exchange oe ON oe.exchangedate=t.rptDate AND oe.ExchangeId=t.CurrencyId
			INNER JOIN #Exchange re ON re.exchangedate=t.rptDate AND re.ExchangeId=t.PlayCurrency
		)
		INSERT INTO #Result (	
				PartyId						,
				ReportDate					,
				OriginalCurrency			,
				RegisteredCurrency			,
				TotalTrans					,
				Turnover					,
				TurnoverBased				,
				ValidBetAmount				,
				ValidBetAmountBased			,
				CustomerWinLoss				,
				CustomerWinLossBased		,
				ServiceChargeOriginal		,
				ServiceChargeBased			,
				ServiceChargeRegistered		,
				ServiceChargeVariance		,
				RebateCommissionOriginal	,
				RebateCommissionBased		,
				RebateCommissionRegistered	,
				RebateCommissionVariance	,
				PayToSupplierOriginal		,
				PayToSupplierBase			,
				PayToSupplierRegistered		,
				PayToSupplierVariance		,
				PromotionOriginal			,
				PromotionBased				,
				PromotionRegistered			,
				PromotionVariance			
			)
		SELECT	PartyId,
				rptDate,
				OriginalCurrency,
				RegisteredCurrency,
				TotalTrans,
				Turnover,
				TurnoverBased,
				ValidBetAmount,
				ValidBetAmountBased,
				CustomerWinLoss,
				CustomerWinLossBased,
				ServiceChargeOriginal,
				ServiceChargeBased,
				ServiceChargeRegistered,
				ServiceChargeBased - ServiceChargeRegistered,
				RebateCommissionOriginal,
				RebateCommissionBased,
				RebateCommissionRegistered,
				RebateCommissionBased - RebateCommissionRegistered,
				ServiceChargeOriginal - RebateCommissionOriginal - PromotionOriginal,
				ServiceChargeBased - RebateCommissionBased - PromotionBased,
				ServiceChargeRegistered - RebateCommissionRegistered - PromotionRegistered,
				(ServiceChargeBased - RebateCommissionBased - PromotionBased) - (ServiceChargeRegistered - RebateCommissionRegistered - PromotionRegistered),
				PromotionOriginal,
				PromotionBased,
				PromotionRegistered	,
				PromotionBased - PromotionRegistered			
		FROM StagingData

		IF @BaseCurrencyName=@TempCurrency
		BEGIN
			IF @GroupByLicensee=1 BEGIN
				SELECT	CASE WHEN r.PartyId = 14 THEN '12Bet' ELSE g.PartyName END AS GroupName,
						p.PartyName,
						r.PartyId,
						@FromDate AS ReportDate, -- dummy data,
						r.OriginalCurrency AS OriginalCurrency,
						r.RegisteredCurrency AS RegisteredCurrency,
						SUM(r.TotalTrans) AS TotalTrans,
						SUM(r.TurnoverBased) AS Turnover,
						SUM(r.ValidBetAmountBased) AS ValidBetAmount,
						SUM(r.CustomerWinLossBased) AS CustomerWinLoss,
						SUM(r.ServiceChargeOriginal) AS ServiceChargeOriginal,
						SUM(r.ServiceChargeBased) AS ServiceChargeBased,
						SUM(r.ServiceChargeRegistered) AS ServiceChargeRegistered,
						SUM(r.ServiceChargeVariance) AS ServiceChargeVariance,
						SUM(r.RebateCommissionOriginal) AS RebateCommissionOriginal,
						SUM(r.RebateCommissionBased) AS RebateCommissionBased,
						SUM(r.RebateCommissionRegistered) AS RebateCommissionRegistered,
						SUM(r.RebateCommissionVariance) AS RebateCommissionVariance,
						SUM(r.PayToSupplierOriginal) AS PayToSupplierOriginal,
						SUM(r.PayToSupplierBase) AS PayToSupplierBase,
						SUM(r.PayToSupplierRegistered) AS PayToSupplierRegistered,
						SUM(r.PayToSupplierVariance) AS PayToSupplierVariance,
						SUM(r.PromotionOriginal) AS PromotionOriginal,
						SUM(r.PromotionBased) AS PromotionBased,
						SUM(r.PromotionRegistered) AS PromotionRegistered,
						SUM(r.PromotionVariance) AS PromotionVariance
				FROM #Result r
				INNER JOIN #PartyList p ON r.PartyId = p.PartyId AND p.ParentId > 0
				INNER JOIN #PartyList g ON p.ParentId= g.PartyId AND g.ParentId = 0
				GROUP BY CASE WHEN r.PartyId = 14 THEN '12Bet' ELSE g.PartyName END, p.PartyName, r.PartyId, r.OriginalCurrency, r.RegisteredCurrency
			END ELSE BEGIN
				SELECT	'' AS GroupName,	-- dummy data
						'' AS PartyName,	-- dummy data
						0 AS PartyId,		-- dummy data
						r.ReportDate,
						r.OriginalCurrency AS OriginalCurrency,
						r.RegisteredCurrency AS RegisteredCurrency,
						SUM(r.TotalTrans) AS TotalTrans,
						SUM(r.Turnover) AS Turnover,
						SUM(r.ValidBetAmount) AS ValidBetAmount,
						SUM(r.CustomerWinLoss) AS CustomerWinLoss,
						SUM(r.ServiceChargeOriginal) AS ServiceChargeOriginal,
						SUM(r.ServiceChargeBased) AS ServiceChargeBased,
						SUM(r.ServiceChargeRegistered) AS ServiceChargeRegistered,
						SUM(r.ServiceChargeVariance) AS ServiceChargeVariance,
						SUM(r.RebateCommissionOriginal) AS RebateCommissionOriginal,
						SUM(r.RebateCommissionBased) AS RebateCommissionBased,
						SUM(r.RebateCommissionRegistered) AS RebateCommissionRegistered,
						SUM(r.RebateCommissionVariance) AS RebateCommissionVariance,
						SUM(r.PayToSupplierOriginal) AS PayToSupplierOriginal,
						SUM(r.PayToSupplierBase) AS PayToSupplierBase,
						SUM(r.PayToSupplierRegistered) AS PayToSupplierRegistered,
						SUM(r.PayToSupplierVariance) AS PayToSupplierVariance,
						SUM(r.PromotionOriginal) AS PromotionOriginal,
						SUM(r.PromotionBased) AS PromotionBased,
						SUM(r.PromotionRegistered) AS PromotionRegistered,
						SUM(r.PromotionVariance) AS PromotionVariance
				FROM #Result r
				INNER JOIN #PartyList p ON r.PartyId = p.PartyId AND p.ParentId > 0
				INNER JOIN #PartyList g ON p.ParentId= g.PartyId AND g.ParentId = 0
				GROUP BY r.ReportDate, r.OriginalCurrency, r.RegisteredCurrency
			END
		END

		INSERT INTO @GrandTotal (
				RegisteredCurrency			,
				TotalTrans					,
				Turnover					,
				ValidBetAmount				,
				CustomerWinLoss				,
				ServiceChargeBased			,
				ServiceChargeRegistered		,
				ServiceChargeVariance		,
				RebateCommissionBased		,
				RebateCommissionRegistered	,
				RebateCommissionVariance	,
				PayToSupplierBase			,
				PayToSupplierRegistered		,
				PayToSupplierVariance		,
				PromotionBased				,
				PromotionRegistered			,
				PromotionVariance			
		)
		SELECT	@TempCurrency,
				SUM(TotalTrans),
				SUM(TurnoverBased),
				SUM(ValidBetAmountBased),
				SUM(CustomerWinLossBased),
				SUM(ServiceChargeBased),
				SUM(ServiceChargeRegistered),
				SUM(ServiceChargeVariance),
				SUM(RebateCommissionBased),
				SUM(RebateCommissionRegistered),
				SUM(RebateCommissionVariance),
				SUM(PayToSupplierBase),
				SUM(PayToSupplierRegistered),
				SUM(PayToSupplierVariance),
				SUM(PromotionBased),
				SUM(PromotionRegistered),
				SUM(PromotionVariance)
		FROM #Result

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @TempCurrency
		DELETE #Exchange
		DELETE #Result
	END

	SELECT RegisteredCurrency,
		ISNULL(TotalTrans,0)					AS TotalTrans,
		ISNULL(Turnover,0)						AS Turnover,
		ISNULL(ValidBetAmount,0)				AS ValidBetAmount,
		ISNULL(CustomerWinLoss,0)				AS CustomerWinLoss,
		ISNULL(ServiceChargeBased,0)			AS ServiceChargeBased,
		ISNULL(ServiceChargeRegistered,0)		AS ServiceChargeRegistered,
		ISNULL(ServiceChargeVariance,0)			AS ServiceChargeVariance,
		ISNULL(RebateCommissionBased,0)			AS RebateCommissionBased,
		ISNULL(RebateCommissionRegistered,0)	AS RebateCommissionRegistered,
		ISNULL(RebateCommissionVariance,0)		AS RebateCommissionVariance,
		ISNULL(PayToSupplierBase,0)				AS PayToSupplierBase,
		ISNULL(PayToSupplierRegistered,0)		AS PayToSupplierRegistered,
		ISNULL(PayToSupplierVariance,0)			AS PayToSupplierVariance,
		ISNULL(PromotionBased,0)				AS PromotionBased,
		ISNULL(PromotionRegistered,0)			AS PromotionRegistered,
		ISNULL(PromotionVariance,0)				AS PromotionVariance
	FROM @GrandTotal

	DROP TABLE #Result
	DROP TABLE #TempData
	DROP TABLE #Exchange
END
GO