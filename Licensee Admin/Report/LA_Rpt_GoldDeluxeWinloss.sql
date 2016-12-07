USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_GoldDeluxeWinloss] 
	  @PartyIds			VARCHAR(1000)
	, @FromDate			DATETIME
	, @ToDate			DATETIME
	, @BaseCurrencyName	VARCHAR(3) = 'EUR'
AS
/*  Created: 20161118@bruce.bui
	Task : Report - Gold Deluxe win loss
	DB: DB052.bodb_licensee
	Revisions:

	Param's Explanation:
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @3rdPartyId INT = (SELECT PartyId FROM dbo.OAS_Party WHERE PartyName = 'GD' AND PartyType = 3)	
	DECLARE @NoExchange VARCHAR(3) = '---'

	-- charge type
	DECLARE @RollingCommissionType	INT = 11
	DECLARE @CreditServiceCharge	INT = 10
	DECLARE @DepositServiceCharge	INT = 9
	DECLARE @GrossWin				INT = 1

	-- get partylist and parent group
	CREATE TABLE #PartyList(
		PartyId		INT,
		PartyName	VARCHAR(100),
		BrandName	VARCHAR(100),
		ParentId	INT
	)
	INSERT INTO #PartyList EXEC dbo.LA_PartyListSel
	UPDATE #PartyList SET PartyName = REPLACE(PartyName,' Licensees', '') WHERE ParentId = 0

	CREATE TABLE #ChargeInfo(
		PartyId					INT
		, LicenseeId			INT
		, IsDeposit				INT
		, ProductId				INT
		, Rate					FLOAT
		, FromDate				SMALLDATETIME
		, ToDate				SMALLDATETIME
		, IsPayToSupplier		BIT
		, ChargeType			INT
	)

	-- get licenseeFee's charge rate
	-- credit licensee display licensee fee as 0 -> set rate to 0
	INSERT INTO #ChargeInfo(PartyId, LicenseeId, ProductId, Rate, IsDeposit, Fromdate, Todate, IsPayToSupplier, ChargeType)
	(
		SELECT PartyID, LicenseeId, ProductId, CASE WHEN IsDeposit=1 THEN DI_Rate ELSE 0 END, IsDeposit, Fromdate, Todate, 0, 1
		FROM dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'GD', 'OA', 1)
	)
	
	-- get payToSupplier's charge rate
	;WITH CI AS (
		SELECT ci.PartyId, ci.LicenseeId, ci.ProductId, ci.IsDeposit,
			ISNULL(c1.Rate, c2.Rate) AS Rate,
			ISNULL(c1.FromDate, c2.FromDate) AS FromDate,
			ISNULL(c1.ToDate, c2.ToDate) AS ToDate,
			ISNULL(c1.ChargeType, c2.ChargeType) AS ChargeType
		FROM #ChargeInfo ci
		JOIN #PartyList pl ON pl.PartyId = ci.PartyID
		LEFT JOIN dbo.OAS_ChargeInfo c1 WITH(NOLOCK) ON c1.FromParty = ci.PartyID AND c1.ToParty = @3rdPartyId AND (
			c1.FromDate BETWEEN @FromDate AND @ToDate OR @FromDate BETWEEN c1.FromDate AND c1.ToDate
		) -- individual charge rate
		LEFT JOIN dbo.OAS_ChargeInfo c2 WITH(NOLOCK) ON c2.FromParty = pl.ParentId AND c2.ToParty = @3rdPartyId AND (
			c2.FromDate BETWEEN @FromDate AND @ToDate OR @FromDate BETWEEN c2.FromDate AND c2.ToDate
		) -- inherit from parent group
	)
	INSERT INTO #ChargeInfo(PartyId, LicenseeId, ProductId, Rate, IsDeposit, ChargeType, IsPayToSupplier, Fromdate, Todate)
	SELECT PartyID, LicenseeID, ProductID, Rate, isDeposit, ChargeType, 1,
		(CASE WHEN Fromdate < @FromDate THEN @FromDate ELSE Fromdate END),
		(CASE WHEN Todate > @ToDate THEN @ToDate ELSE Todate END)
	FROM CI

	CREATE TABLE #Data (
		PartyId			INT,
		IsDeposit		BIT,
		ReportDate		DATETIME,
		CurrencyId		INT,
		CurrencyName	VARCHAR(10),
		Totaltrans		INT,
		Turnover		MONEY,
		ValidBetAmount	MONEY,
		CustomerWL		MONEY,
		LicenseeFee		MONEY,
		ServiceCharge	MONEY,
		Rebate			MONEY,
		BaseCurrency	VARCHAR(10)
	)

	INSERT INTO #Data(PartyId, ReportDate, CurrencyId, IsDeposit, Totaltrans, Turnover, ValidBetAmount, CustomerWL, LicenseeFee, ServiceCharge, Rebate)
	(
		SELECT  ci.PartyID, b.rptDate, b.currencyID, ci.IsDeposit
			, SUM(b.betcount) AS Totaltrans
			, SUM(b.turnover) AS Turnover
			, SUM(ISNULL(b.ValidBetAmount,0)) AS ValidBetAmount
			, SUM(b.MemberWL) AS CustomerWL
			, SUM(-b.MemberWL * ci.Rate) AS LicenseeFee
			, SUM(-b.MemberWL *  ISNULL(s.Rate, 0)) AS ServiceCharge
			, SUM(ISNULL(b.ValidBetAmount,0) * ISNULL(r.Rate, 0) * ISNULL(s.Rate, 0)) AS Rebate
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #ChargeInfo ci ON ( -- licensee charge rate
				b.SiteID = ci.LicenseeID AND
				b.ProductID = ci.ProductId AND
				b.rptDate BETWEEN ci.FromDate AND ci.ToDate AND
				ci.IsPayToSupplier = 0)
			LEFT JOIN #ChargeInfo r ON ( -- rolling commission rate
				b.SiteID = r.LicenseeID AND
				b.ProductID = r.ProductId AND
				b.rptDate BETWEEN r.FromDate AND r.ToDate AND
				r.IsPayToSupplier = 1 AND
				r.ChargeType = @RollingCommissionType)
			LEFT JOIN #ChargeInfo s ON ( -- service charge rate
				b.SiteID = s.LicenseeID AND
				b.ProductID = s.ProductId AND
				b.rptDate BETWEEN s.FromDate AND s.ToDate AND
				s.IsPayToSupplier = 1 AND
				s.ChargeType IN (@GrossWin, @CreditServiceCharge, @DepositServiceCharge))
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
			  b.StatusId NOT IN (- 1, 101, 102, 103) AND
			  b.CurrencyId <> 20 AND
			  b.customercategory NOT IN (27,28)
		GROUP BY b.rptDate, ci.PartyID, b.CurrencyID, ci.IsDeposit
	)

	DECLARE @BaseCurrencies TABLE(
		CurrencyId	INT,
		Code		VARCHAR(10),
		IsApplied	BIT
	)
	INSERT INTO @BaseCurrencies(CurrencyId, Code)
	EXEC LA_SelBaseCurrency

	IF ISNULL(@BaseCurrencyName,'')=''
	BEGIN
		SET @BaseCurrencyName = @NoExchange
		INSERT INTO @BaseCurrencies(CurrencyId, Code) VALUES (0, @BaseCurrencyName)
	END

	WHILE EXISTS (SELECT TOP 1 Code FROM @BaseCurrencies WHERE IsApplied IS NULL)
	BEGIN
		DECLARE @Currency VARCHAR(10) = (SELECT TOP 1 Code FROM @BaseCurrencies WHERE IsApplied IS NULL)

		INSERT INTO #Data(PartyId, IsDeposit, ReportDate, CurrencyName, Totaltrans, BaseCurrency, Turnover, CustomerWL, LicenseeFee, ServiceCharge, Rebate, ValidBetAmount)
		SELECT d.PartyId, d.IsDeposit, d.ReportDate, e.Code, d.Totaltrans, @Currency,
			d.Turnover * e.BaseCurrencyRate,
			d.CustomerWL * e.BaseCurrencyRate,
			d.LicenseeFee * e.BaseCurrencyRate,
			d.ServiceCharge * e.BaseCurrencyRate,
			d.Rebate * e.BaseCurrencyRate,
			d.ValidBetAmount * e.BaseCurrencyRate
		FROM #Data d
		INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @Currency) e ON e.ExchangeId = d.CurrencyId AND e.exchangedate = d.ReportDate

		UPDATE @BaseCurrencies SET IsApplied = 1 WHERE Code = @Currency
	END

	SELECT p2.PartyName AS GroupName,
		p1.PartyId,
		p1.PartyName,
		d.IsDeposit,
		d.ReportDate,
		d.CurrencyName,
		d.Totaltrans,
		d.Turnover,
		d.CustomerWL AS CustomerWinLoss,
		d.ValidBetAmount,
		d.LicenseeFee,
		d.ServiceCharge,
		d.Rebate,
		(d.ServiceCharge - d.Rebate) AS PayToSupplier
	FROM #Data d
	INNER JOIN #PartyList p1 ON d.PartyId = p1.PartyId
	INNER JOIN #PartyList p2 ON p1.ParentId = p2.PartyId
	WHERE d.BaseCurrency = @BaseCurrencyName

	DECLARE @GrandTotals TABLE (
		CurrencyName	VARCHAR(10),
		PartyId			INT,
		GroupName		VARCHAR(100),
		Totaltrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeFee		MONEY,
		ServiceCharge	MONEY,
		Rebate			MONEY,
		ValidBetAmount	MONEY,
		Step			TINYINT
	)

	INSERT INTO @GrandTotals
	SELECT d.BaseCurrency, d.PartyId, p2.PartyName,
		SUM(d.Totaltrans),
		SUM(d.Turnover),
		SUM(d.CustomerWL),
		SUM(d.LicenseeFee),
		SUM(d.ServiceCharge),
		SUM(d.Rebate),
		SUM(d.ValidBetAmount),
		1 -- step 1
	FROM #Data d
	INNER JOIN #PartyList p1 ON d.PartyId = p1.PartyId
	INNER JOIN #PartyList p2 ON p2.PartyId = p1.ParentId
	WHERE d.BaseCurrency IS NOT NULL AND d.BaseCurrency <> @NoExchange
	GROUP BY d.BaseCurrency, d.PartyId, p2.PartyName

	INSERT INTO @GrandTotals
	SELECT CurrencyName, 0, GroupName,
		SUM(Totaltrans),
		SUM(Turnover),
		SUM(CustomerWinLoss),
		SUM(CASE WHEN LicenseeFee < 0 THEN 0 ELSE LicenseeFee END), -- negative amount = 0
		SUM(ServiceCharge),
		SUM(Rebate),
		SUM(ValidBetAmount),
		2 -- step 2
	FROM @GrandTotals
	WHERE Step = 1
	GROUP BY CurrencyName, GroupName

	SELECT CurrencyName,
		SUM(Totaltrans) AS Totaltrans,
		SUM(Turnover) AS Turnover,
		SUM(ValidBetAmount) AS ValidBetAmount,
		SUM(CustomerWinLoss) AS CustomerWinLoss,
		SUM(LicenseeFee) AS LicenseeFee,
		SUM(ServiceCharge) AS ServiceCharge,
		SUM(Rebate) AS Rebate,
		SUM(CASE WHEN (ServiceCharge - Rebate) < 0 THEN 0 ELSE (ServiceCharge - Rebate) END) AS PaytoSupplier -- negative amount = 0
	FROM @GrandTotals
	WHERE Step = 2
	GROUP BY CurrencyName

	DROP TABLE #PartyList
	DROP TABLE #ChargeInfo
	DROP TABLE #Data
END
GO

GRANT EXECUTE ON [dbo].[LA_Rpt_GoldDeluxeWinloss] TO [bodbAdminNet] AS [dbo]
GO

GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_GoldDeluxeWinloss] TO [vnteam] AS [dbo]
GO
