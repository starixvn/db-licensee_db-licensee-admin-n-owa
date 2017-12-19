USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_MacauWinloss]
	  @PartyIds				VARCHAR(4000)
	, @FromDate				DATETIME
	, @ToDate				DATETIME
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'
WITH RECOMPILE
AS
/*  Created: 20160329@Bruce
	Task : Support settlement for Macau
	DB: DBEXT/bodb02
	Revisions:
		- 20160329@Bruce: Create SP
		- 20171219@Bruce: increase length for variables [#88197]
	Param's Explanation:
*/
BEGIN
	SET NOCOUNT ON

	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)

	-- Charge Info
	BEGIN
		DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			LicenseeId	INT,
			ProductID	INT,
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME
		)

		INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
		(
			SELECT	PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
			FROM	dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'VG', 'OA', 1)
			WHERE	DI_Rate > 0

			UNION ALL

			SELECT	ci.FromParty, 0, ci.ProductID, Rate,
					CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
					CASE WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END
			FROM	dbo.OAS_ChargeInfo ci WITH(NOLOCK)
			WHERE	FromParty = 1 AND ProductID = 12 AND (@FromDate BETWEEN ci.FromDate AND ci.ToDate OR
														  @ToDate BETWEEN ci.FromDate AND ci.ToDate OR
														  ci.FromDate BETWEEN @FromDate AND @ToDate OR
														  ci.ToDate BETWEEN @FromDate AND @ToDate)
		)
	END

	-- Party List
	BEGIN
		DECLARE @PartyList AS TABLE (
			PartyId		INT,
			PartyName	VARCHAR(100),
			BranchName	VARCHAR(100),
			ParentId	INT
		)

		INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
		EXEC LA_PartyListSel
	END

	-- Get Winloss data
	BEGIN
		CREATE TABLE #TempData (
			LicenseeId		INT,
			PartyId			INT,
			rptDate			DATETIME,
			CurrencyId		INT,
			TotalTrans		INT,
			Turnover		MONEY,
			MemberWL		MONEY,
			LicensingFee	MONEY,
			PayToSupplier	MONEY
		)

		INSERT INTO #TempData (
				LicenseeId,
				PartyId,
				rptDate,
				CurrencyId,
				TotalTrans,
				Turnover,
				MemberWL,
				LicensingFee,
				PayToSupplier)
		SELECT	p.LicenseeId,
				p.PartyId,
				b.Winlostdate,
				b.Currency,
				SUM(ISNULL(b.BetCount, 0)) TotalTrans,
				SUM(ISNULL(b.Turnover, 0)) Turnover,
				SUM(ISNULL(b.Winlost, 0)) MemberWL,
				SUM(ISNULL(-b.Winlost, 0) * p.Rate) LicensingFee,
				SUM(ISNULL(-b.Winlost, 0) * f.Rate) PayToSupplier
		FROM	bodb_LicenseeReport.dbo.rptDepWinlost_ThirdParty b WITH (NOLOCK)
			INNER JOIN bodb02.dbo.Custinfo co WITH (NOLOCK) ON b.CustID = co.CustID
			INNER JOIN bodb_Licensee.dbo.f_SelLicenseeCust(0) lc ON lc.CustID = co.recommend AND co.currency = lc.Currency
			INNER JOIN @PartyChargeInfo p ON b.ProductID = p.ProductID
				AND lc.LicenseeID = p.LicenseeId
				AND b.Winlostdate BETWEEN p.FromDate AND p.ToDate
			INNER JOIN @PartyChargeInfo f ON b.ProductID = f.ProductID
				AND f.LicenseeId = 0
				AND b.Winlostdate BETWEEN p.FromDate AND p.ToDate
		WHERE	b.Winlostdate BETWEEN @FromDate AND @ToDate AND (b.Currency <> 20)
		GROUP BY b.Winlostdate, p.LicenseeId, p.PartyId, b.Currency
	END

	-- Result data
	BEGIN
		CREATE TABLE #Result (
			PartyId			INT,
			PartyName		VARCHAR(100),
			ParentId		INT,
			ParentName		VARCHAR(100),
			WinLossDate		DATETIME,
			CurrencyName	VARCHAR(20),
			TotalTrans		INT,
			Turnover		MONEY,
			CustomerWL		MONEY,
			LicensingFee	MONEY,
			PayToSupplier	MONEY
		)

	-- Convert base currency
		IF @BaseCurrencyName = ''
		BEGIN
			INSERT INTO #Result (
					PartyId,
					PartyName,
					ParentId,
					ParentName,
					WinLossDate,
					CurrencyName,
					TotalTrans,
					Turnover,
					CustomerWL,
					LicensingFee,
					PayToSupplier)
			SELECT	p.PartyId,
					p.PartyName,
					g.PartyId,
					g.PartyName,
					td.rptDate,
					e.Code,
					td.TotalTrans,
					td.Turnover,
					td.MemberWL,
					td.LicensingFee,
					td.PayToSupplier
			FROM #TempData td
				INNER JOIN bodb02.dbo.Exchange e ON td.CurrencyId = e.ExchangeID
				INNER JOIN @PartyList p ON td.PartyId = p.PartyID
				INNER JOIN @PartyList g ON p.ParentId = g.PartyId
		END
		ELSE
		BEGIN
			INSERT INTO #Result (
					PartyId,
					PartyName,
					ParentId,
					ParentName,
					WinLossDate,
					CurrencyName,
					TotalTrans,
					Turnover,
					CustomerWL,
					LicensingFee,
					PayToSupplier)
			SELECT	p.PartyId,
					p.PartyName,
					g.PartyId,
					g.PartyName,
					td.rptDate,
					e.Code,
					td.TotalTrans,
					td.Turnover * e.BaseCurrencyRate,
					td.MemberWL * e.BaseCurrencyRate,
					td.LicensingFee * e.BaseCurrencyRate,
					td.PayToSupplier * e.BaseCurrencyRate
			FROM #TempData td
				INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName) e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate
				INNER JOIN @PartyList p ON td.PartyId = p.PartyID
				INNER JOIN @PartyList g ON p.ParentId = g.PartyId
		END
	END

	-- Region: Grand total data
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20),
		IsApply BIT
	)

	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

	DECLARE @GrandTotal AS TABLE(
		CurrencyName	VARCHAR(3),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWL		MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY
	)

	WHILE EXISTS (SELECT TOP 1 * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)

		INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
		SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
		FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency)

		;WITH SumByParty AS (
			SELECT	SUM(td.TotalTrans) TotalTrans,
					SUM(td.Turnover*e.Rate) Turnover,
					SUM(td.MemberWL*e.Rate) CustomerWL,
					SUM(td.LicensingFee*e.Rate) LicensingFee,
					SUM(td.PayToSupplier*e.Rate) PayToSupplier
			FROM #TempData td
			INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate
			GROUP BY td.PartyId
		)
		INSERT INTO @GrandTotal(CurrencyName, TotalTrans, Turnover, CustomerWL, LicensingFee, PayToSupplier)
		SELECT	@tempCurrency,
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(CustomerWL),
				SUM(CASE WHEN (-CustomerWL) < 0 THEN 0 ELSE LicensingFee END),
				SUM(PayToSupplier)
		FROM SumByParty

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
		DELETE FROM #Exchange
	END
	--EndRegion Grand total data

	SELECT	PartyId,
			PartyName,
			ParentId,
			ParentName,
			WinLossDate,
			(CASE WHEN CurrencyName='VND' THEN 'INH' ELSE CurrencyName END) AS CurrencyName,
			TotalTrans,
			Turnover,
			CustomerWL,
			-CustomerWL AS LicenseeWL,
			LicensingFee,
			PayToSupplier
	FROM #Result

	SELECT	CurrencyName,
			TotalTrans,
			Turnover,
			CustomerWL,
			-CustomerWL AS LicenseeWL,
			LicensingFee,
			(CASE WHEN (-CustomerWL) < 0 THEN 0 ELSE PayToSupplier END) PayToSupplier,
			(LicensingFee - (CASE WHEN (-CustomerWL) < 0 THEN 0 ELSE PayToSupplier END)) CompanyIncome
	FROM @GrandTotal

	DROP TABLE #TempData
	DROP TABLE #Result
	DROP TABLE #Exchange
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_MacauWinloss] TO [vnteam]
GRANT EXECUTE ON [dbo].[LA_Rpt_MacauWinloss] TO bodbAdminNet