/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_PPLiveCasinoWinLoss]
	@PartyIds			VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20),
	@TimeZone			INT
AS

/*
	Created: 20210506@Percy
	DB: DBLIC-bodb_Licensee
	Task: PP Live Casino Win Loss

	Revisions:
		- 20210506@Percy: Initialize SP [RedmineID: #150971]

	Param's Explanation:
		@TimeZone:	= 1: GMT-4
					= 2: GMT+0
*/

BEGIN
	SET NOCOUNT ON

	DECLARE @FDate DATE = @FromDate
	DECLARE @TDate DATE = @ToDate
	DECLARE @FDateGMT DATE = DATEADD(DAY, -1, @FromDate)
	DECLARE @TDateGMT DATE = DATEADD(DAY, +1, @ToDate)

	-- Get Licensee list
	CREATE TABLE #PartyList (PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT)
	INSERT INTO #PartyList (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	-- Get 3rd Rate
	CREATE TABLE #3rdRate (PartyId INT, FromDate DATE, ToDate DATE, CurrencyId INT, MinAmount MONEY, MaxAmount MONEY, Rate FLOAT)
	INSERT INTO #3rdRate (PartyId, FromDate, ToDate, CurrencyId, MinAmount, MaxAmount, Rate)
	SELECT DISTINCT p.PartyId, r.FromDate, r.ToDate, c.BaseCurrencyId, c.MinAmount - CASE WHEN c.MinAmount = 0 THEN 0 ELSE 1 END, c.MaxAmount, c.Rate
	FROM dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'PPL', 'OA') r
		INNER JOIN #PartyList p ON p.ParentId = r.PartyId
		INNER JOIN dbo.OAS_ChargeInfo c WITH (NOLOCK) ON r.ChargeId = c.ChargeId

	-- Get Charge Rate
	CREATE TABLE #ChargeRate (ChargeId INT, PartyId INT, LicenseeId INT, IsDeposit INT, Rate FLOAT, FromDate DATETIME, ToDate DATETIME)
	INSERT INTO #ChargeRate (ChargeId, PartyId, LicenseeId, IsDeposit, Rate, FromDate, ToDate)
	SELECT DISTINCT c.ChargeId, c.PartyId, c.LicenseeId, c.IsDeposit, c.DI_Rate, c.FromDate, c.ToDate
	FROM dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, 'PPL') c
	WHERE (c.IsDeposit = 0 AND c.DI_Rate = 0) OR (c.IsDeposit = 1 AND c.DI_Rate > 0)

	-- Get Exchange Rate
	CREATE TABLE #Exchange (ExchangeDate DATETIME, ExchangeId INT, CurrencyCode VARCHAR(10), Rate FLOAT)
	INSERT INTO #Exchange (ExchangeDate, ExchangeId, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeId, CASE ExchangeId WHEN 51 THEN 'INH' WHEN 92 THEN 'HID' ELSE Code END, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel (@FromDate, @ToDate, @BaseCurrencyName)

	-- Get Win Loss data
	CREATE TABLE #TempData
	(
		PartyId INT,
		PartyName NVARCHAR(100),
		ParentId INT,
		ParentName NVARCHAR(100),
		WinlostDate DATETIME,
		CurrencyId INT,
		Turnover MONEY,
		TotalTrans INT,
		CustomerWinLoss MONEY,
		LicenseeWinloss MONEY,
		LicensingFee MONEY
	)

	IF @TimeZone = 1 -- GMT-4
	BEGIN
		INSERT INTO #TempData (PartyId, WinlostDate, CurrencyId, Turnover, TotalTrans, CustomerWinLoss, LicenseeWinloss, LicensingFee)
		SELECT ci.PartyId, b.rptDate, b.CurrencyId,
			SUM(b.Turnover)		AS Turnover,
			SUM(b.BetCount)		AS TotalTrans,
			SUM(b.MemberWL)		AS CustomerWinLoss,
			SUM(-b.MemberWL)	AS LicenseeWinloss,
			SUM(-b.MemberWL * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON b.SiteId = ci.LicenseeId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeId = ci.ChargeId AND cr.CurrencyId = b.CurrencyId
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.ProductId = 65
			AND b.StatusId NOT IN (-1, 101, 102, 103)
			AND b.CurrencyId <> 20
			AND b.CustomerCategory NOT IN (27, 28)
		GROUP BY ci.PartyId, b.rptDate, b.CurrencyId
	END
	ELSE -- GMT+0
	BEGIN
		INSERT INTO #TempData (PartyId, WinlostDate, CurrencyId, Turnover, TotalTrans, CustomerWinLoss, LicenseeWinloss, LicensingFee)
		SELECT ci.PartyId, b.RptDate3rd, b.CurrencyId,
			SUM(b.Turnover)		AS Turnover,
			SUM(b.BetCount)		AS TotalTrans,
			SUM(b.Winloss)		AS CustomerWinLoss,
			SUM(-b.Winloss)		AS LicenseeWinloss,
			SUM(-b.Winloss * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee
		FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON b.SiteId = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeId = ci.ChargeId AND cr.CurrencyId = b.CurrencyId
		WHERE b.RptDate BETWEEN @FDateGMT AND @TDateGMT
			AND b.RptDate3rd BETWEEN @FDate AND @TDate
			AND b.BetTypeId BETWEEN 3701 AND 3799
			AND b.StatusId NOT IN (-1, 101, 102, 103)
			AND b.CurrencyId <> 20
		GROUP BY ci.PartyId, b.RptDate3rd, b.CurrencyId
	END

	-- Calculate Result
	CREATE TABLE #Result
	(
		PartyId			INT,
		PartyName		VARCHAR(100),
		ParentId		INT,
		ParentName		VARCHAR(100),
		WinLossDate		DATETIME,
		CurrencyId		INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY
	)
	
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee)
	SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, td.CurrencyId, td.TotalTrans, td.Turnover, td.CustomerWinLoss, td.LicenseeWinloss, td.LicensingFee
	FROM #TempData td
		INNER JOIN #PartyList p ON td.PartyId = p.PartyID
		INNER JOIN #PartyList pa ON p.ParentId = pa.PartyId	

	-- Get all base currencies
	DECLARE @Total TABLE
	(
		PartyId			INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		Currency		VARCHAR(20)
	)

	DECLARE @BaseCurrencies TABLE (ExchangeId INT, BaseCurrencyName VARCHAR(20))
	INSERT INTO @BaseCurrencies(ExchangeId, BaseCurrencyName)
	EXEC bodb_licensee.dbo.LA_SelBaseCurrency

	DECLARE @BaseCurrencyRate TABLE (ExchangeId INT, ExchangeDate DATETIME, BaseCurrencyName VARCHAR(20), Rate FLOAT)
	INSERT INTO @BaseCurrencyRate (ExchangeId, ExchangeDate, BaseCurrencyName, Rate)
	SELECT e.ExchangeId, e.ExchangeDate, bc.BaseCurrencyName, e.BaseCurrencyRate
	FROM @BaseCurrencies bc
		CROSS APPLY bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, bc.BaseCurrencyName) e

	;WITH CTE_SumByParty AS (
		SELECT r.ParentId, e.BaseCurrencyName,
			SUM(r.TotalTrans)				AS TotalTrans,
			SUM(r.Turnover * e.Rate)		AS Turnover,
			SUM(r.CustomerWinLoss * e.Rate) AS CustomerWinLoss,
			SUM(r.LicenseeWinLoss * e.Rate) AS LicenseeWinLoss,
			SUM(r.LicensingFee * e.Rate)	AS LicensingFee
		FROM #Result r
			INNER JOIN @BaseCurrencyRate e ON e.ExchangeId = r.CurrencyId AND e.ExchangeDate = r.WinLossDate
		GROUP BY r.ParentId, r.PartyId, e.BaseCurrencyName
	)
	INSERT INTO @Total (Currency, PartyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee)
	SELECT BaseCurrencyName, ParentId,
		SUM(TotalTrans),
		SUM(Turnover),
		SUM(CustomerWinLoss),
		SUM(LicenseeWinLoss),
		SUM(CASE WHEN LicensingFee < 0 THEN 0 ELSE LicensingFee END)
	FROM CTE_SumByParty
	GROUP BY BaseCurrencyName, ParentId

	-- Update PayToSupplier base on Licensee WL
	DECLARE @CurrencyId INT, @CurrencyName VARCHAR(100)
	SELECT TOP 1 @CurrencyId = CurrencyId FROM #3rdRate
	SELECT @CurrencyName = Currency FROM bodb02.dbo.Exchange WITH (NOLOCK) WHERE ExchangeId = @CurrencyId

	-- Detail
	;WITH CTE_Sum AS (
		SELECT t.PartyId, t.CurrencyId, t.WinlostDate, SUM(t.LicenseeWinloss * e.BaseCurrencyRate) AS LicenseeWinloss
		FROM bodb02.dbo.LA_f_ExchangeDailySel (@FromDate, @ToDate, @CurrencyName) e
			INNER JOIN #TempData t ON t.CurrencyId = e.ExchangeId AND e.ExchangeDate = t.WinlostDate
		GROUP BY t.PartyId, t.CurrencyId, t.WinlostDate
		HAVING SUM(t.LicenseeWinloss) > 0
	), CTE_3rdRate AS (
		SELECT s.PartyId, s.CurrencyId, s.WinlostDate, SUM(CASE WHEN s.LicenseeWinloss <= r.MaxAmount THEN s.LicenseeWinloss - r.MinAmount ELSE r.MaxAmount END * r.Rate) AS PayToSupplier
		FROM CTE_Sum s
			INNER JOIN #3rdRate r ON s.PartyId = r.PartyId AND s.LicenseeWinloss > r.MinAmount
		GROUP BY s.PartyId, s.CurrencyId, s.WinlostDate
	)
	UPDATE t
	SET t.PayToSupplier = ISNULL(r.PayToSupplier, 0)
	FROM #Result t
		LEFT JOIN CTE_3rdRate r ON t.PartyId = r.PartyId AND t.CurrencyId = r.CurrencyId AND t.WinLossDate = r.WinlostDate

	-- Total
	;WITH CTE_Sum AS (
		SELECT t.PartyId, SUM(t.LicenseeWinloss * e.BaseCurrencyRate) AS LicenseeWinloss
		FROM bodb02.dbo.LA_f_ExchangeDailySel (@FromDate, @ToDate, @CurrencyName) e
			INNER JOIN #TempData t ON t.CurrencyId = e.ExchangeId AND e.ExchangeDate = t.WinlostDate
		GROUP BY t.PartyId
		HAVING SUM(t.LicenseeWinloss) > 0
	), CTE_3rdRate AS (
		SELECT s.PartyId, br.BaseCurrencyName, SUM(CASE WHEN s.LicenseeWinloss <= r.MaxAmount THEN s.LicenseeWinloss - r.MinAmount ELSE r.MaxAmount END * r.Rate * br.Rate) AS PayToSupplier
		FROM CTE_Sum s
			INNER JOIN #3rdRate r ON s.PartyId = r.PartyId AND s.LicenseeWinloss > r.MinAmount
			INNER JOIN @BaseCurrencyRate br ON br.ExchangeId = @CurrencyId
		GROUP BY s.PartyId, br.BaseCurrencyName
	)
	UPDATE t
	SET t.PayToSupplier = ISNULL(r.PayToSupplier, 0)
	FROM @Total t
		LEFT JOIN CTE_3rdRate r ON t.PartyId = r.PartyId AND t.Currency = r.BaseCurrencyName

	-- Return data
	BEGIN
		-- Detail by Parties
		SELECT 
			r.PartyId,
			r.PartyName,
			r.ParentId,
			r.ParentName,
			r.WinLossDate,
			e.CurrencyCode AS CurrencyName,
			r.TotalTrans,
			-- Original Currency
			r.Turnover			AS TurnoverOriginal,
			r.CustomerWinLoss	AS CustomerWinLossOriginal,
			r.LicenseeWinLoss	AS LicenseeWinLossOriginal,
			r.LicensingFee		AS LicensingFeeOriginal,
			r.PayToSupplier		AS PayToSupplierOriginal,
			r.LicensingFee - r.PayToSupplier AS CompanyIncomeOriginal,
			-- Base Currency
			CONVERT(MONEY, r.Turnover * e.Rate)			AS Turnover,
			CONVERT(MONEY, r.CustomerWinLoss * e.Rate)	AS CustomerWinLoss,
			CONVERT(MONEY, r.LicenseeWinLoss * e.Rate)	AS LicenseeWinLoss,
			CONVERT(MONEY, r.LicensingFee * e.Rate)		AS LicensingFee,
			CONVERT(MONEY, r.PayToSupplier * e.Rate)	AS PayToSupplier,
			CONVERT(MONEY, (r.LicensingFee - r.PayToSupplier) * e.Rate) AS CompanyIncome
		FROM #Result r
			INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND r.WinLossDate = e.ExchangeDate
	
		-- Grand Total
		SELECT
			Currency				AS CurrencyName
			,SUM(TotalTrans)		AS TotalTrans
			,SUM(Turnover)			AS Turnover
			,SUM(CustomerWinLoss)	AS CustomerWinLoss
			,SUM(LicenseeWinLoss)	AS LicenseeWinLoss
			,SUM(LicensingFee)		AS LicensingFee
			,SUM(PayToSupplier)		AS PayToSupplier
			,SUM(LicensingFee - PayToSupplier) AS CompanyIncome
		FROM @Total
		GROUP BY Currency
	
		-- Total
		SELECT 
			PartyId,
			TotalTrans,
			Turnover,
			CustomerWinLoss,
			LicenseeWinLoss,
			LicensingFee,
			PayToSupplier,
			LicensingFee - PayToSupplier AS CompanyIncome
		FROM @Total t
		WHERE Currency = @BaseCurrencyName
	END

	DROP TABLE #3rdRate
	DROP TABLE #ChargeRate
	DROP TABLE #Exchange
	DROP TABLE #PartyList
	DROP TABLE #Result
	DROP TABLE #TempData
END
GO