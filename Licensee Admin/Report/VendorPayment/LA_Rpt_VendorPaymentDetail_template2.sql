/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Rpt_VendorPaymentDetail_template2]
	@PartyIds			VARCHAR(MAX)
	,@ProductID			INT
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@BaseCurrencyName	VARCHAR(20)
	,@TimeZoneId		INT
	,@PlatformId		TINYINT = 0
AS
/*
 * Created by : [20220418@Danny]
 * Task  : Vendor Payment Detail (template2 - Template for Number Game product, including some specific info such as: House TO, Extra PT info)
 * Revisions
	- 20220418@Danny: Initialize SP [#168387]
	- 20220927@Danny: Remove DBLink [#176986] 
	- 20221003@Malcolm: Add platform filter [RedmineID: #165707]
	- 20220227@Danny: Incorporate USDTJP currency [RedmineID: #183461]
	- 20240924@Danny: exclude BTS currency [RedmineID: #210422]
	- 20241016@Danny: Extend parameter data length [RemineID: #212252]
 */

BEGIN

SET NOCOUNT ON
	
	DECLARE @ProductCode VARCHAR(50)
	SELECT @ProductCode = ProductPrefix FROM dbo.Product3rd WITH(NOLOCK) WHERE Productid = @ProductID

	DECLARE @IsConvertNegativeFeeToZero BIT, @IsConvertNegativePaytoSupplierToZero BIT
	SELECT @IsConvertNegativeFeeToZero = IsConvertNegativeFeeToZero, @IsConvertNegativePaytoSupplierToZero = IsConvertNegativePaytoSupplierToZero  FROM dbo.LA_VendorPaymentSetting WITH(NOLOCK) WHERE ProductId = @ProductID

	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
		    INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END

	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT, IsKeepNegativeAmount BIT DEFAULT 0)
	INSERT INTO #PartyList (PartyId, PartyName, BrandName, ParentId) EXEC LA_PartyListSel

	UPDATE #PartyList SET PartyName = REPLACE(PartyName,' Licensees','') WHERE ParentId = 0

	UPDATE t 
	SET t.IsKeepNegativeAmount = CASE WHEN u.PartyId IS NULL THEN 0 ELSE 1 END 
	FROM #PartyList t 
	LEFT JOIN bodb_Licensee.dbo.LA_f_JVPartyListSel() u ON u.PartyId = t.PartyId

	CREATE TABLE #ChargeRate (
		ChargeId		INT
		,PartyID		INT
		,LicenseeID		INT
		,isDeposit		INT
		,ProductID		INT
		,Rate			MONEY
		,Rate3rd		MONEY
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
	)
	-- ​Pay to Supplier: equals 40%(0.4) of [Licensing Fee]
	-- Except CN88 = 1.5%
	INSERT INTO #ChargeRate(ChargeID, PartyID, LicenseeID, isDeposit, ProductID, Rate, Rate3rd, Fromdate, Todate)
	SELECT c.ChargeID, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate, 0.4, c.Fromdate, c.Todate
	FROM LA_f_ChargeInfoWithCredit(@PartyIDs, @FromDate, @ToDate, @ProductCode) c

	-- From 01 Dec 2019, pay to supplier = 50%
	BEGIN
		DECLARE @EffectiveDateForNewRate DATE = '20191201'

		INSERT INTO #ChargeRate(ChargeID, PartyID, LicenseeID, isDeposit, ProductID, Rate, Rate3rd, Fromdate, Todate)
		SELECT c.ChargeId, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.Rate, c.Rate3rd, c.Fromdate, DATEADD(DAY,-1,@EffectiveDateForNewRate)
		FROM #ChargeRate c
		WHERE Fromdate < @EffectiveDateForNewRate AND @EffectiveDateForNewRate <= ToDate

		UPDATE #ChargeRate SET
			Fromdate = (CASE WHEN Fromdate < @EffectiveDateForNewRate THEN @EffectiveDateForNewRate ELSE Fromdate END),
			Rate3rd = 0.5
		WHERE @EffectiveDateForNewRate <= Todate
	END

	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(65),
		Rate			FLOAT
	)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate, CurrencyCode)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate, CASE WHEN ExchangeID = 51 THEN 'INH' 
															WHEN ExchangeID = 92 THEN 'HID' 
															ELSE Code END
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	-- Region: TempData
	CREATE TABLE #TempData (
		PartyID			INT,
		PartyName		NVARCHAR(100),
		ParentId		INT,
		ParentName		NVARCHAR(100),
		Winlostdate		DATETIME,
		CurrencyId		INT,
		Turnover		MONEY,
		HouseTurnover	MONEY,
		TotalTrans		INT,
		CustomerWinLoss MONEY,
		LicenseeWinloss MONEY,
		LicensingFee	MONEY,
		ExtraPT 		MONEY,
		PayToSupplier	MONEY,
		IsKeepNegativeAmount BIT
		)

	INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,ExtraPT,Turnover,HouseTurnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier)
	SELECT ci.PartyId,
		b.rptDate as Winlostdate,
		b.CurrencyId,
		0,
		SUM(b.Turnover) AS Turnover,
		SUM(b.ExtraAmount) AS HouseTurnover,
		SUM(b.BetCount) AS TotalTrans,
		SUM(b.MemberWL) AS CustomerWinLoss,
		SUM(-b.MemberWL) AS LicenseeWinloss,
		SUM(-b.MemberWL * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
		SUM(-b.MemberWL * ISNULL(cr.Rate, ci.Rate) * ci.Rate3rd) AS PayToSupplier
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.ProductID = ci.ProductID AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON ci.ChargeId = cr.ChargeId AND cr.CurrencyId = b.CurrencyId
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
		b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
		AND b.CustomerCategory NOT IN (27,28)
		AND ci.isDeposit = 1
	GROUP BY b.rptDate, ci.PartyId, b.CurrencyId
	
	-- Calculate for credit
	;WITH cte_CreditData AS 
	(
		SELECT b.SiteID, b.rptDate as Winlostdate, b.CurrencyId,
		SUM(ISNULL(b.WinLossE, 0) +  ISNULL(b.CommissionE, 0)) AS ExtraPT,
		SUM(b.Turnover)		AS Turnover,
		SUM(b.ExtraAmount)	AS HouseTurnover,
		SUM(b.BetCount)		AS TotalTrans,
		SUM(b.WinLoss)		AS CustomerWinLoss,
		SUM(-b.WinLoss)		AS LicenseeWinloss,
		- SUM(b.WinLoss + b.WinLossA + WinLossM + WinLossS + b.CommissionS)		AS LicensingFee
		FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH (NOLOCK)
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
			b.Status NOT IN (-1, 101, 102, 103) AND b.CurrencyId NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
			AND b.CustomerCategory NOT IN (27,28)
			AND b.Bettype in (Select Bettype FROM LA_f_BettypeProductMapping(0,@ProductCode))
		GROUP BY b.SiteID, b.rptDate, b.CurrencyId
	)
	INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,ExtraPT,Turnover,HouseTurnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier)
	SELECT ci.PartyID, r.Winlostdate, r.CurrencyID,
			SUM(r.ExtraPT),
			SUM(r.Turnover), 
			SUM(r.HouseTurnover), 
			SUM(r.TotalTrans), 
			SUM(r.CustomerWinLoss), 
			SUM(r.LicenseeWinloss), 
			SUM(r.LicensingFee),
			SUM((r.LicensingFee - CASE
									WHEN r.SiteID IN (1487/*IBCIndo*/, 1547/*76666b*/) THEN ExtraPT
									ELSE 0
								  END) * ci.Rate3rd) AS PayToSupplier
	FROM cte_CreditData r
	INNER JOIN #ChargeRate ci ON r.SiteID = ci.LicenseeId AND r.Winlostdate BETWEEN ci.FromDate AND ci.ToDate
	WHERE ci.isDeposit = 0
	GROUP BY ci.PartyID, r.Winlostdate, r.CurrencyId

	-- EndRegion
	
	UPDATE td SET
		PartyName = p.PartyName,
		ParentId = pa.PartyId,
		ParentName = pa.PartyName,
		IsKeepNegativeAmount = p.IsKeepNegativeAmount
	FROM #TempData td
		INNER JOIN #PartyList p ON td.PartyID = p.PartyId
		INNER JOIN #PartyList pa ON P.ParentId = pa.PartyId
		
	--Region Update PayToSupplier = 0.015 * Licensee WL for CN88
	UPDATE td SET
		td.PayToSupplier = td.LicenseeWinloss * 0.015
	FROM #TempData td 
	WHERE PartyID IN (SELECT p.PartyID FROM OAS_Party p WITH(NOLOCK) WHERE p.PartyName = 'CN88')
	
	DECLARE @Total TABLE (
		PartyId		INT,
		TotalTrans		INT,
		Turnover		MONEY,
		HouseTurnover	MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		ExtraPT 		MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY,
		Currency		VARCHAR(20)
	)

	-- Region: Calculate Grand Total
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(Id INT, [Name] VARCHAR(20))
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

	DECLARE @GrandTotal TABLE (
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		HouseTurnover	MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		ExtraPT 		MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)
	
	WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies)

		;WITH t AS
		(
			SELECT 
				CASE WHEN  td.PartyID = 14 THEN 14 ELSE  td.ParentId END ParentId,
				td.PartyId,
				td.IsKeepNegativeAmount,
				@tempCurrency AS Currency,
				SUM(td.TotalTrans) AS TotalTrans,
				SUM(td.Turnover * e.BaseCurrencyRate) Turnover,
				SUM(td.HouseTurnover * e.BaseCurrencyRate) HouseTurnover,
				SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss,
				SUM(td.LicenseeWinLoss * e.BaseCurrencyRate) LicenseeWinLoss, 
				SUM(td.LicensingFee * e.BaseCurrencyRate) LicensingFee,
				SUM(td.ExtraPT * e.BaseCurrencyRate) ExtraPT,
				SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier,
				SUM((LicensingFee - ExtraPT - PayToSupplier) * e.BaseCurrencyRate) AS CompanyIncome
			FROM #TempData td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e
			ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.Winlostdate
			GROUP BY CASE WHEN  td.PartyId = 14 THEN 14 ELSE td.ParentId END, td.PartyId, td.IsKeepNegativeAmount
		)
		INSERT INTO @Total (PartyId, Currency,TotalTrans,Turnover,HouseTurnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,ExtraPT,PayToSupplier,CompanyIncome)
		SELECT	ParentId, @tempCurrency, 
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(HouseTurnover),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinLoss),
				SUM(CASE WHEN LicensingFee < 0 AND  @IsConvertNegativeFeeToZero = 1 AND  IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END),
				SUM(ExtraPT),
				SUM(CASE WHEN PayToSupplier < 0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END),
				SUM(CASE WHEN LicensingFee < 0 AND  @IsConvertNegativeFeeToZero = 1 AND  IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END - ExtraPT - CASE WHEN PayToSupplier < 0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END)
		FROM t	
		GROUP BY ParentId

		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,HouseTurnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,ExtraPT,PayToSupplier,CompanyIncome)
		SELECT Currency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(HouseTurnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(LicensingFee),
			SUM(ExtraPT),
			SUM(PayToSupplier),
			SUM(CompanyIncome)
		FROM @Total
		WHERE Currency = @tempCurrency
		GROUP BY Currency

		DELETE @BaseCurrencies WHERE [Name] = @tempCurrency
	END
	
	-- Select data by Parties
	SELECT 
		r.PartyId,
		r.PartyName,
		CASE WHEN r.PartyId = 14 THEN 14 ELSE r.ParentId END ParentId,
		CASE WHEN r.PartyId = 14 THEN '12Bet' ELSE r.ParentName END ParentName,
		r.Winlostdate				AS WinLossDate,
		e.CurrencyCode				AS CurrencyName,
		-- Select by origin currency
		r.TotalTrans,
		r.Turnover					AS TurnoverOriginal,
		r.HouseTurnover				AS HouseTurnoverOriginal,
		CAST((r.CustomerWinLoss) AS MONEY)	AS CustomerWinLossOriginal,
		CAST((r.LicenseeWinLoss) AS MONEY)	AS LicenseeWinLossOriginal,
		CAST((r.LicensingFee) AS MONEY)		AS LicensingFeeOriginal,
		CAST((r.ExtraPT) AS MONEY)			AS ExtraPTOriginal,
		CAST((r.PayToSupplier) AS MONEY)	AS PayToSupplierOriginal,
		r.LicensingFee - ExtraPT - r.PayToSupplier	AS CompanyIncomeOriginal,
		-- Select by base currency
		r.Turnover * e.Rate AS Turnover,
		r.HouseTurnover * e.Rate AS HouseTurnover,
		CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
		CAST((r.LicenseeWinLoss * e.Rate) AS MONEY) AS LicenseeWinLoss,
		CAST((r.LicensingFee * e.Rate) AS MONEY)	AS LicensingFee,
		CAST((r.ExtraPT * e.Rate) AS MONEY)			AS ExtraPT,
		CAST((r.PayToSupplier * e.Rate)AS MONEY) AS PayToSupplier,
		CAST((r.LicensingFee - ExtraPT - r.PayToSupplier) * e.Rate AS MONEY) AS CompanyIncome
	FROM #TempData r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.Winlostdate = e.ExchangeDate
	
	;WITH totalByParty AS
		(
		SELECT r.PartyId, r.PartyName, r.ParentId,
			SUM(r.TotalTrans) AS TotalTrans,
			SUM(r.Turnover * e.Rate) Turnover,
			SUM(r.HouseTurnover * e.Rate) HouseTurnover,
			SUM(r.CustomerWinLoss * e.Rate) CustomerWinLoss,
			SUM(r.LicenseeWinLoss * e.Rate) LicenseeWinLoss,
			SUM(r.LicensingFee * e.Rate) LicensingFee,
			SUM(r.ExtraPT * e.Rate) ExtraPT,
			SUM(r.PayToSupplier * e.Rate) PayToSupplier,
			r.IsKeepNegativeAmount
		FROM #TempData r
			INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND r.WinLostDate = e.ExchangeDate
		GROUP BY r.PartyId, r.PartyName, r.ParentId, r.IsKeepNegativeAmount
		)
		SELECT	PartyId, 
				PartyName, 
				CASE WHEN PartyId = 14 THEN 14 ELSE ParentId END ParentId, 
				TotalTrans, 
				Turnover, 
				HouseTurnover,
				CustomerWinLoss, 
				LicenseeWinLoss, 
				CASE WHEN LicensingFee < 0 AND IsKeepNegativeAmount = 0 AND @IsConvertNegativeFeeToZero = 1 THEN 0 ELSE  LicensingFee END LicensingFee, 
				ExtraPT,
				CASE WHEN PayToSupplier <0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END PayToSupplier, 
				CASE WHEN LicensingFee < 0 AND IsKeepNegativeAmount = 0 AND @IsConvertNegativeFeeToZero = 1 THEN 0 ELSE  LicensingFee END - ExtraPT - CASE WHEN PayToSupplier <0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END  AS CompanyIncome
		FROM totalByParty

	-- Select Grand Total
	SELECT 	CurrencyName	,
			TotalTrans		,
			Turnover		,
			HouseTurnover	,
			CustomerWinLoss	,
			LicenseeWinLoss	,
			LicensingFee	,
			ExtraPT 		,
			PayToSupplier	,
			CompanyIncome	 
	FROM @GrandTotal
	
	-- Total
	SELECT	PartyId			,
			TotalTrans		,
			Turnover		,
			HouseTurnover	,
			CustomerWinLoss	,
			LicenseeWinLoss	,
			LicensingFee	,
			ExtraPT 		,
			PayToSupplier	,
			CompanyIncome	,
			Currency		
		FROM @Total WHERE Currency = @BaseCurrencyName
	
	-- End Region
	
	DROP TABLE	#PartyList
	DROP TABLE	#Exchange
	DROP TABLE	#ChargeRate
	DROP TABLE  #TempData	
END
GO