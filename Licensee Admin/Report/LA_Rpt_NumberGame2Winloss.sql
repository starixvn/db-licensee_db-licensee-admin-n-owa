USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_NumberGame2Winloss]
	 @PartyIDs				VARCHAR(5500)
	, @FromDate				SMALLDATETIME
	, @ToDate				SMALLDATETIME
	, @BaseCurrencyName		VARCHAR(3) = 'EUR'
AS

/*
 * Created by : [20161214@Scofield.Huynh]
 * Task  : Get Number Game 2 Winloss
 * DB   : DB052.bodb_licensee
 */
BEGIN
	SET NOCOUNT ON

	DECLARE @NoBaseCurrency VARCHAR(3) = '---'

	-- ChargeRate
	BEGIN
		DECLARE @ChargeRate TABLE(
			PartyId		INT,
			Rate3rd		MONEY,
			ProductId	INT,
			LicenseeId	INT,
			FromDate	DATETIME,
			ToDate		DATETIME)

		INSERT INTO @ChargeRate (PartyId, LicenseeId, Rate3rd, ProductId, FromDate, ToDate)
		(
			SELECT PartyID, LicenseeID, DI_Rate, ProductID, Fromdate, Todate
			FROM dbo.LA_f_ChargeInfo(@PartyIDs,@FromDate,@ToDate,'NG2','OA',1)
		)
	END
	
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

	-- Base currencies
	DECLARE @BaseCurrencies TABLE(
		CurrencyId	INT,
		Code		VARCHAR(10),
		IsApply		BIT
	)
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
		RptDate			DATETIME,
		CurrencyId		INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)

	;WITH CalculateLicenseeWinLoss AS (
		SELECT r.PartyId,
			b.rptDate,
			b.CurrencyId,
			b.BetCount,
			b.Turnover,
			b.WinLoss,
			-(b.WinLoss + b.WinLossS + b.WinLossM + b.WinLossA + b.CommissionS) LicenseeWl,
			r.Rate3rd
		FROM bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK) 
		INNER JOIN @ChargeRate r ON b.SiteID = r.LicenseeId AND b.rptDate BETWEEN r.FromDate AND r.ToDate
		WHERE b.Status NOT IN (-1, 101, 102, 103)
			AND b.Bettype BETWEEN 2501 AND 2699
			AND b.CustomerCategory NOT IN (27, 28)
			AND b.CurrencyId <> 20
			AND b.rptDate BETWEEN @FromDate AND @ToDate
	)
	INSERT INTO #TempData (PartyId, RptDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, CompanyIncome)
	SELECT PartyId,rptDate, CurrencyID, BetCount, Turnover, WinLoss, LicenseeWl , 0, LicenseeWl * Rate3rd, LicenseeWl - (LicenseeWl * Rate3rd)
	FROM CalculateLicenseeWinLoss

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
		 PayToSupplier		MONEY,
		 CompanyIncome		MONEY)

	DECLARE @TempCurrency VARCHAR(10)

	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @TempCurrency = (SELECT TOP 1 Code FROM @BaseCurrencies WHERE IsApply IS NULL)

		INSERT INTO #TempResult(PartyId, PartyName, GroupName, ReportDate, CurrencyName, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, CompanyIncome, BaseCurrency)
		SELECT t.PartyId,
			p.PartyName,
			g.PartyName,
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
		INNER JOIN @PartyGroupList p ON t.PartyId = p.PartyId AND p.ParentId > 0
		INNER JOIN @PartyGroupList g ON p.ParentId= g.PartyId AND g.ParentId = 0

		INSERT INTO #GrandTotals (CurrencyName, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, CompanyIncome)
		SELECT @TempCurrency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(LicensingFee),
			SUM(PayToSupplier),
			SUM(CompanyIncome)
		FROM #TempResult
		WHERE BaseCurrency = @TempCurrency

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Code = @TempCurrency
	END

	SELECT * from #TempResult WHERE BaseCurrency = @BaseCurrencyName
	SELECT * FROM #GrandTotals WHERE CurrencyName <> @NoBaseCurrency

	-- Drop temp tables
	DROP TABLE #TempResult
	DROP TABLE #TempData
	DROP TABLE #GrandTotals
END    

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_NumberGame2Winloss] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_Rpt_NumberGame2Winloss] TO bodbAdminNet
