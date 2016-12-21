USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_FishingWorldWinloss]
	@PartyIDs			VARCHAR(5500),
	@FromDate			SMALLDATETIME,
	@ToDate				SMALLDATETIME,
	@BaseCurrencyName	VARCHAR(3) = 'EUR'
AS

/*
 * Created by : [20161220@Scofield.Huynh]
 * Task  : Get Fishing World Winloss
 * DB   : DB052.bodb_licensee
 */
BEGIN
	SET NOCOUNT ON

	DECLARE @NoBaseCurrency VARCHAR(3) = '---'

	-- Party List
	CREATE TABLE #PartyList(
		PartyId 	INT, 
		PartyName 	VARCHAR(100), 
		BrandName 	VARCHAR(100), 
		ParentId 	INT)
	
	INSERT INTO #PartyList
	EXEC bodb_licensee.dbo.LA_PartyListSel
	
	UPDATE #PartyList SET PartyName = REPLACE(PartyName,' Licensees','') WHERE ParentId = 0
	
	-- ChargeRate
	DECLARE @ChargeRate AS TABLE (
		PartyId		INT,
		PartyName	VARCHAR(100),
		GroupName	VARCHAR(100),
		LicenseeId	INT,
		ProductID	INT,
		Rate		MONEY,
		Rate3rd		MONEY,
		FromDate	DATETIME,
		ToDate		DATETIME)	

	INSERT INTO @ChargeRate(PartyId, PartyName, GroupName, LicenseeId, ProductID, Rate, Rate3rd, Fromdate, Todate)
	(
		SELECT a.PartyID, p.PartyName, g.PartyName, LicenseeID, a.ProductID, 
			CASE WHEN a.isDeposit = 0 THEN 0 ELSE DI_Rate END, 
			CASE WHEN a.isDeposit = 0 THEN a.DI_Rate ELSE b.Rate END AS Rate3rd, 
			a.Fromdate, a.Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'FW', 'OA', 1) a
			LEFT JOIN #PartyList p ON a.PartyID = p.PartyId
			LEFT JOIN #PartyList g ON p.ParentID = g.PartyID
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo b WITH (NOLOCK) ON p.ParentId = b.FromParty AND a.ProductID = b.ProductID 
				AND (a.Fromdate BETWEEN b.FromDate AND b.ToDate OR a.Todate BETWEEN b.FromDate AND b.ToDate )		
	)	
	
	-- Base currencies
	DECLARE @BaseCurrencies TABLE(
		CurrencyId	INT,
		Code		VARCHAR(10),
		IsApply		BIT)
	
	INSERT INTO @BaseCurrencies(CurrencyId, Code)
	EXEC bodb_Licensee.dbo.LA_SelBaseCurrency

	IF (ISNULL(@BaseCurrencyName, '') = '')
	BEGIN
		SET @BaseCurrencyName = @NoBaseCurrency
		INSERT INTO @BaseCurrencies(CurrencyId, Code) VALUES(0, @BaseCurrencyName)
	END

	-- Get Data
	CREATE TABLE #TempData (
		PartyId			INT,
		PartyName		VARCHAR(100),
		GroupName		VARCHAR(100),
		RptDate			DATETIME,
		CurrencyId		INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY)
		
	INSERT INTO #TempData (PartyId, PartyName, GroupName, RptDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, CompanyIncome)
	SELECT r.PartyId, r.PartyName, r.GroupName, b.rptDate, b.CurrencyId, b.BetCount, b.Turnover, b.MemberWL, -b.MemberWL, 
		(-b.MemberWL) * r.Rate, 
		(-b.MemberWL) * r.Rate3rd, 
		((-b.MemberWL) * r.Rate) - ((-b.MemberWL) * r.Rate3rd)
	FROM bodb_licenseereport.dbo.rpt_BettingByProduct b WITH (NOLOCK) 
	INNER JOIN @ChargeRate r ON b.SiteID = r.LicenseeId AND b.ProductId = r.ProductID AND b.rptDate BETWEEN r.FromDate AND r.ToDate
	WHERE b.StatusId NOT IN (-1, 101, 102, 103)
		AND b.CustomerCategory NOT IN (27, 28)
		AND b.CurrencyId <> 20
		AND b.rptDate BETWEEN @FromDate AND @ToDate
		
	-- Calculate result
	CREATE TABLE #TempResult (
		PartyId			INT,
		PartyName		VARCHAR(100),
		GroupName		VARCHAR(100),
		ReportDate		DATETIME,
		CurrencyName	VARCHAR(10),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY,
		BaseCurrency	VARCHAR(10)
	)

	CREATE TABLE #GrandTotals (
		 CurrencyName		VARCHAR(10),
		 TotalTrans			INT,
		 Turnover			MONEY,
		 CustomerWinLoss	MONEY,
		 LicenseeWinLoss	MONEY,
		 LicensingFee		MONEY,
		 PayToSupplier		MONEY)

	DECLARE @TempCurrency VARCHAR(10)

	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @TempCurrency = (SELECT TOP 1 Code FROM @BaseCurrencies WHERE IsApply IS NULL)

		INSERT INTO #TempResult(PartyId, PartyName, GroupName, ReportDate, CurrencyName, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, CompanyIncome, BaseCurrency)
		SELECT t.PartyId,
			t.PartyName,
			t.GroupName,
			t.RptDate,
			CASE WHEN e.Code='VND' THEN 'INH' ELSE e.Code END,
			t.TotalTrans,
			t.Turnover * e.BaseCurrencyRate,
			t.CustomerWinLoss * e.BaseCurrencyRate,
			t.LicenseeWinLoss * e.BaseCurrencyRate,
			t.LicensingFee * e.BaseCurrencyRate,
			t.PayToSupplier * e.BaseCurrencyRate,
			t.CompanyIncome * e.BaseCurrencyRate,
			@TempCurrency
		FROM #TempData t
		INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @TempCurrency) e ON e.ExchangeDate = t.RptDate AND e.ExchangeId = t.CurrencyId		

		;WITH TempResultGroupByParty AS(
			SELECT t.PartyId,t.GroupName,
				SUM(TotalTrans) AS TotalTrans,
				SUM(Turnover) AS Turnover,
				SUM(CustomerWinLoss) AS CustomerWinLoss,
				SUM(LicenseeWinLoss) AS LicenseeWinLoss,
				SUM(LicensingFee) AS LicensingFee,
				SUM(PayToSupplier) AS PayToSupplier
			FROM #TempResult t
			WHERE BaseCurrency = @TempCurrency
			GROUP BY t.PartyId, t.GroupName
		)
		INSERT INTO #GrandTotals (CurrencyName, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier)
		SELECT @TempCurrency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(CASE WHEN LicensingFee < 0 THEN 0 ELSE LicensingFee END),
			SUM(PayToSupplier)
		FROM TempResultGroupByParty
		GROUP BY GroupName
		
		--UPDATE #GrandTotals SET CompanyIncome = LicensingFee - PayToSupplier
		--WHERE CurrencyName = @TempCurrency

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Code = @TempCurrency
	END

	SELECT * from #TempResult WHERE BaseCurrency = @BaseCurrencyName

	;WITH TempGrandTotals AS(
		SELECT CurrencyName,
			SUM(TotalTrans) AS TotalTrans,
			SUM(Turnover) AS Turnover,
			SUM(CustomerWinLoss) AS CustomerWinLoss,
			SUM(LicenseeWinLoss) AS LicenseeWinLoss,
			SUM(LicensingFee) AS LicensingFee,
			SUM(CASE WHEN PayToSupplier < 0 THEN 0 ELSE PayToSupplier END) AS PayToSupplier
		FROM #GrandTotals
		WHERE CurrencyName <> @NoBaseCurrency
		GROUP BY CurrencyName
	)
	SELECT CurrencyName,
		TotalTrans,
		Turnover,
		CustomerWinLoss,
		LicenseeWinLoss,
		LicensingFee,
		PayToSupplier,
		(LicensingFee-PayToSupplier) AS CompanyIncome
	FROM TempGrandTotals
	
	-- Drop temp tables
	DROP TABLE #TempResult
	DROP TABLE #TempData
	DROP TABLE #GrandTotals	
	DROP TABLE #PartyList
END    

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_FishingWorldWinloss] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_Rpt_FishingWorldWinloss] TO bodbAdminNet
