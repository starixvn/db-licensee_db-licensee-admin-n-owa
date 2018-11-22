/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_GoldDeluxeWinloss]
	  @PartyIds			VARCHAR(4000)
	, @FromDate			DATETIME
	, @ToDate			DATETIME
	, @BaseCurrencyName	VARCHAR(10) = 'EUR'
AS
/*  Created: 20161118@bruce.bui
	Task : Report - Gold Deluxe win loss
	DB: DB052.bodb_licensee
	Revisions:
		- 20170622@bruce: show original value [#78398]
		- 20171219@Bruce: increase length for variables [#88197]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20180628@Scofield: Update calculation formula for AG& GD report [#94283]
		- 20181119@Scofield: Integrate Bidme games  [#103695]
		
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
	DECLARE @BidMeTipChargeType	INT = 12

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
		SELECT DISTINCT PartyID, LicenseeId, ProductId, CASE WHEN IsDeposit=1 THEN DI_Rate ELSE 0 END, IsDeposit, Fromdate, Todate, 0, ChargeType
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
		WHERE ci.ChargeType = @GrossWin
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
		TipAmount 		MONEY,
		LicenseeFee		MONEY,
		Commission		MONEY,
		NetWinLoss		MONEY,
		CompanyTipShare MONEY,
		PayToSupplier	MONEY,
		BaseCurrency	VARCHAR(10),
		RowId			UNIQUEIDENTIFIER
	)

	INSERT INTO #Data(PartyId, ReportDate, CurrencyId, IsDeposit, Totaltrans, Turnover, ValidBetAmount, CustomerWL, TipAmount, LicenseeFee, Commission, NetWinLoss, CompanyTipShare, PayToSupplier, RowId)
	(
		SELECT  ci.PartyID, b.rptDate, b.currencyID, ci.IsDeposit
			, SUM(b.betcount) AS Totaltrans
			, SUM(b.turnover) AS Turnover
			, SUM(ISNULL(b.ValidBetAmount,0)) AS ValidBetAmount
			, SUM(CASE WHEN b.Bettype = 1706 THEN 0 ELSE b.MemberWL END) AS CustomerWL
			, SUM(CASE WHEN b.Bettype = 1706 THEN -b.MemberWL ELSE 0 END) AS TipAmount
			, SUM(CASE WHEN b.Bettype = 1706 THEN -b.MemberWL * tipLicensee.Rate ELSE -b.MemberWL * ci.Rate END) AS LicenseeFee
			, SUM(ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) AS Commission
			, SUM(-b.MemberWL - ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) AS NetWinLoss
			, SUM(CASE WHEN b.Bettype = 1706 THEN -b.MemberWL * (1 - tipSupplier.Rate) ELSE 0 END) AS CompanyTipShare
			, SUM(CASE WHEN b.Bettype = 1706 THEN -b.MemberWL * tipSupplier.Rate ELSE (-b.MemberWL - ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) * ISNULL(s.Rate, 0) END) AS PayToSupplier
			, NEWID()
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #ChargeInfo ci ON ( -- licensee charge rate
				b.SiteID = ci.LicenseeID AND
				b.ProductID = ci.ProductId AND
				b.rptDate BETWEEN ci.FromDate AND ci.ToDate AND
				ci.IsPayToSupplier = 0 AND
				ci.ChargeType = @GrossWin)
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
				s.ChargeType IN (@GrossWin, @CreditServiceCharge, @DepositServiceCharge)) -- @GrossWin for old setting 
			LEFT JOIN #ChargeInfo tipLicensee ON(
				b.ProductID = tipLicensee.ProductId AND
				b.rptDate BETWEEN tipLicensee.FromDate AND tipLicensee.ToDate AND
				tipLicensee.IsPayToSupplier = 0 AND
				tipLicensee.ChargeType = @BidMeTipChargeType)
			LEFT JOIN #ChargeInfo tipSupplier ON(
				b.ProductID = tipSupplier.ProductId AND
				b.rptDate BETWEEN tipSupplier.FromDate AND tipSupplier.ToDate AND
				tipSupplier.IsPayToSupplier = 1 AND
				tipSupplier.ChargeType = @BidMeTipChargeType)
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
			  b.StatusId NOT IN (- 1, 101, 102) AND
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

		INSERT INTO #Data(PartyId, IsDeposit, ReportDate, CurrencyName, Totaltrans, BaseCurrency, Turnover, CustomerWL, TipAmount, LicenseeFee, Commission, NetWinLoss, CompanyTipShare, PayToSupplier, ValidBetAmount, RowId)
		SELECT d.PartyId, d.IsDeposit, d.ReportDate, e.Code, d.Totaltrans, @Currency,
			d.Turnover * e.BaseCurrencyRate,
			d.CustomerWL * e.BaseCurrencyRate,
			d.TipAmount * e.BaseCurrencyRate,
			d.LicenseeFee * e.BaseCurrencyRate,
			d.Commission * e.BaseCurrencyRate,
			d.NetWinLoss * e.BaseCurrencyRate,
			d.CompanyTipShare * e.BaseCurrencyRate,
			d.PayToSupplier * e.BaseCurrencyRate,
			d.ValidBetAmount * e.BaseCurrencyRate,
			d.RowId
		FROM #Data d
		INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @Currency) e ON e.ExchangeId = d.CurrencyId AND e.exchangedate = d.ReportDate

		UPDATE @BaseCurrencies SET IsApplied = 1 WHERE Code = @Currency
	END

	SELECT p2.PartyName AS GroupName,
		p1.PartyId,
		p1.PartyName,
		d.IsDeposit,
		d.ReportDate,
		CASE WHEN d.CurrencyName='VND' THEN 'INH' ELSE d.CurrencyName END CurrencyName,
		d.Totaltrans,
		d.Turnover,
		o.Turnover			AS TurnoverOriginal,
		d.CustomerWL		AS CustomerWinLoss,
		o.CustomerWL		AS CustomerWinLossOriginal,
		d.TipAmount 		AS TipAmount,
		o.TipAmount 		AS TipAmountOriginal,
		d.ValidBetAmount,
		o.ValidBetAmount	AS ValidBetAmountOriginal,
		d.LicenseeFee,
		o.LicenseeFee		AS LicenseeFeeOriginal,
		d.Commission,
		o.Commission			AS CommissionOriginal,
		d.NetWinLoss,
		o.NetWinLoss		AS NetWinLossOriginal,
		d.CompanyTipShare	AS CompanyTipShare,
		o.CompanyTipShare	AS CompanyTipShareOriginal,
		d.PayToSupplier,
		o.PayToSupplier		AS PayToSupplierOriginal
	FROM #Data d
	INNER JOIN #Data o ON o.RowId = d.RowId AND o.BaseCurrency IS NULL
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
		TipAmount 		MONEY,
		LicenseeFee		MONEY,		
		Commission		MONEY,
		NetWinLoss		MONEY,
		CompanyTipShare MONEY,
		PayToSupplier	MONEY,
		ValidBetAmount	MONEY,
		Step			TINYINT
	)

	INSERT INTO @GrandTotals
	SELECT d.BaseCurrency, d.PartyId, p2.PartyName,
		SUM(d.Totaltrans),
		SUM(d.Turnover),
		SUM(d.CustomerWL),
		SUM(d.TipAmount),
		SUM(d.LicenseeFee),
		SUM(d.Commission),
		SUM(d.NetWinLoss),
		SUM(d.CompanyTipShare),
		SUM(d.PayToSupplier),
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
		SUM(TipAmount),
		SUM(CASE WHEN LicenseeFee < 0 THEN 0 ELSE LicenseeFee END), -- negative amount = 0		
		SUM(Commission),
		SUM(NetWinLoss),
		SUM(CompanyTipShare),
		SUM(CASE WHEN PayToSupplier < 0 THEN 0 ELSE PayToSupplier END), -- negative amount = 0		
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
		SUM(TipAmount) AS TipAmount,
		SUM(LicenseeFee) AS LicenseeFee,
		SUM(Commission) AS Commission,
		SUM(NetWinLoss) AS NetWinLoss,
		SUM(CompanyTipShare) AS CompanyTipShare,
		SUM(PayToSupplier) AS PaytoSupplier 
	FROM @GrandTotals
	WHERE Step = 2
	GROUP BY CurrencyName

	DROP TABLE #PartyList
	DROP TABLE #ChargeInfo
	DROP TABLE #Data
END
GO
