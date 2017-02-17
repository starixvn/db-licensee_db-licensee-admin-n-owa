USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Rpt_AllBetWinloss]
	 @PartyIDs			VARCHAR(5500)
	,@FromDate			SMALLDATETIME
	,@ToDate			SMALLDATETIME
	,@BaseCurrencyName	VARCHAR(3) = 'GBP'
	,@IsGroupByLicensee BIT = 0
AS
/*
 Created by	: [20160907@Bruce]
 Task		: Get Allbet Winloss
 DB			: DB052.bodb_licensee

 Revisions:
	- 20170113@bruce: checking launchDate to exclude trial data
	- 20170217@bruce: change deposit service charge to 9

 Param's Explanation:
	- @FromDate			: From date
	- @ToDate			: To date
	- @BaseCurrencyName	: base currency
	- @IsGroupByLicensee: if group by curreny then all curreny will be converted to base currency
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @Allbet INT = (SELECT PartyID FROM dbo.OAS_Party WITH(NOLOCK) WHERE PartyName='Allbet' AND PartyType=3)
	DECLARE @RebateCommissionType INT = 11
	DECLARE @DepositServiceCharge INT = 9

	-- ChargeRate
	DECLARE @ChargeRate TABLE(
		PartyId				INT,
		LicenseeId			INT,
		Rate				DECIMAL(10,8),
		RebateCommission	DECIMAL(10,8),
		FromDate			DATETIME,
		ToDate				DATETIME
	)

	INSERT INTO @ChargeRate(PartyId, LicenseeId, FromDate,ToDate, Rate, RebateCommission)
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
		dc.ChargeType = @DepositServiceCharge
	LEFT JOIN dbo.OAS_ChargeInfo cc WITH(NOLOCK) ON
		cc.FromParty = ci.PartyID AND
		cc.ProductID = ci.ProductID AND
		cc.ToDate >= ci.FromDate AND
		cc.FromDate <= ci.Todate AND
		cc.ChargeType = 11

	-- Party group List
	BEGIN
		DECLARE @PartyGroupList AS TABLE (
			PartyId		INT,
			PartyName	VARCHAR(100),
			BranchName	VARCHAR(100),
			ParentId	INT
		)

		INSERT INTO @PartyGroupList (PartyId, PartyName, BranchName, ParentId)
		EXEC dbo.LA_PartyListSel

		UPDATE @PartyGroupList SET PartyName=REPLACE(PartyName,' Licensees','') WHERE ParentId=0
	END

	-- Play currency settings
	BEGIN
		DECLARE @PlayCurrencySettings TABLE(
			SiteId			INT,
			MemberCurrency	INT,
			PlayCurrency	INT,
			FromDate		DATETIME,
			ToDate			DATETIME
		)
		INSERT INTO @PlayCurrencySettings
		SELECT SiteId, MemberCurrency,PlayCurrency,FromDate,ToDate
		FROM OPENQUERY(DB06,'SELECT SiteId, MemberCurrency,PlayCurrency,FromDate,ToDate FROM bodb02.dbo.PlayCurrencySetting WITH(NOLOCK) WHERE SportType=211')
	END

	-- Base currencies
	BEGIN	
		DECLARE @BaseCurrencies TABLE(
			CurrencyId	INT,
			Code		VARCHAR(10),
			IsApply		BIT
		)
		INSERT INTO @BaseCurrencies(CurrencyId, Code)
		EXEC bodb_Licensee.dbo.LA_SelBaseCurrency
		
		-- include HKD
		INSERT INTO @BaseCurrencies(CurrencyId, Code) VALUES (5, 'HKD')
	END

	-- Exchange
	CREATE TABLE #Exchange(
		ExchangeDate	DATETIME,
		ExchangeId		INT,
		Code			VARCHAR(10),
		Rate			FLOAT
	)

	-- Get Winloss data to #TempData
	SELECT	ci.PartyId,
			b.RptDate3rd AS rptDate,
			b.CurrencyID,
			ISNULL(pc.PlayCurrency, b.CurrencyID) AS PlayCurrency,
			SUM(ISNULL(b.BetCount, 0)) AS TotalTrans,
			SUM(ISNULL(b.Turnover, 0)) AS Turnover,
			SUM(ISNULL(b.Winloss, 0)) AS CustomerWinLoss,
			SUM(ISNULL(b.ValidBetAmount, 0)) AS ValidBetAmount,
			SUM(ISNULL(-b.Winloss, 0) * ci.Rate) AS ServiceChargeOriginal,
			SUM(ISNULL(b.ValidBetAmount, 0) * ci.RebateCommission) AS RebateCommissionOriginal
	INTO #TempData
	FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
		INNER JOIN @ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
		INNER JOIN dbo.view_site_list s WITH(NOLOCK) ON b.SiteId = s.SiteID
		LEFT JOIN @PlayCurrencySettings pc ON
		(
			s.IbcSiteID = pc.SiteId AND
			b.CurrencyId = pc.MemberCurrency AND
			b.rptDate BETWEEN pc.FromDate AND pc.ToDate
		)
	WHERE	(b.RptDate3rd BETWEEN @FromDate AND @ToDate) AND
			(b.CurrencyID <> 20) AND
			(b.BetTypeId BETWEEN 2401 AND 2499) AND
			(b.StatusId NOT IN (-1, 101, 102, 103))
	GROUP BY b.RptDate3rd, ci.PartyId, b.CurrencyID, ISNULL(pc.PlayCurrency, b.CurrencyID)

	-- Report result
	CREATE TABLE #Result(
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
		PayToSupplierVariance		MONEY
	)
	
	DECLARE @GrandTotals AS TABLE(
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
		PayToSupplierVariance		MONEY
	)

	DECLARE @TempCurrency VARCHAR(10)
	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @TempCurrency = (SELECT TOP 1 Code FROM @BaseCurrencies WHERE IsApply IS NULL)
		
		INSERT INTO #Exchange(ExchangeDate, ExchangeId,Code,Rate)
		SELECT exchangedate, ExchangeId,Code, BaseCurrencyRate
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
					t.RebateCommissionOriginal * re.Rate AS RebateCommissionRegistered
			FROM #TempData t
			INNER JOIN #Exchange oe ON oe.exchangedate=t.rptDate AND oe.ExchangeId=t.CurrencyId
			INNER JOIN #Exchange re ON re.exchangedate=t.rptDate AND re.ExchangeId=t.PlayCurrency
		)
		INSERT INTO #Result
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
				ServiceChargeOriginal - RebateCommissionOriginal,
				ServiceChargeBased - RebateCommissionBased,
				ServiceChargeRegistered - RebateCommissionRegistered,
				(ServiceChargeBased - RebateCommissionBased) - (ServiceChargeRegistered - RebateCommissionRegistered)
		FROM StagingData

		IF @BaseCurrencyName=@TempCurrency
		BEGIN
			IF @IsGroupByLicensee=1 BEGIN
				SELECT	g.PartyName AS GroupName,
						p.PartyName,
						r.PartyId,
						@FromDate AS ReportDate, -- dummy data,
						CASE WHEN r.OriginalCurrency='VND' THEN 'INH' ELSE r.OriginalCurrency END OriginalCurrency,
						CASE WHEN r.RegisteredCurrency='VND' THEN 'INH' ELSE r.RegisteredCurrency END RegisteredCurrency,
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
						SUM(r.PayToSupplierVariance) AS PayToSupplierVariance
				FROM #Result r
				INNER JOIN @PartyGroupList p ON r.PartyId = p.PartyId AND p.ParentId > 0
				INNER JOIN @PartyGroupList g ON p.ParentId= g.PartyId AND g.ParentId = 0
				GROUP BY g.PartyName, p.PartyName, r.PartyId, r.OriginalCurrency, r.RegisteredCurrency
			END ELSE BEGIN
				SELECT	'' AS GroupName,	-- dummy data
						'' AS PartyName,	-- dummy data
						0 AS PartyId,		-- dummy data
						r.ReportDate,
						CASE WHEN r.OriginalCurrency='VND' THEN 'INH' ELSE r.OriginalCurrency END OriginalCurrency,
						CASE WHEN r.RegisteredCurrency='VND' THEN 'INH' ELSE r.RegisteredCurrency END RegisteredCurrency,
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
						SUM(r.PayToSupplierVariance) AS PayToSupplierVariance
				FROM #Result r
				INNER JOIN @PartyGroupList p ON r.PartyId = p.PartyId AND p.ParentId > 0
				INNER JOIN @PartyGroupList g ON p.ParentId= g.PartyId AND g.ParentId = 0
				GROUP BY r.ReportDate, r.OriginalCurrency, r.RegisteredCurrency
			END
		END

		INSERT INTO @GrandTotals
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
				SUM(PayToSupplierVariance)
		FROM #Result

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Code = @TempCurrency
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
		ISNULL(PayToSupplierVariance,0)			AS PayToSupplierVariance
	FROM @GrandTotals

	DROP TABLE #Result
	DROP TABLE #TempData
	DROP TABLE #Exchange
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_AllBetWinloss] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_Rpt_AllBetWinloss] TO bodbAdminNet