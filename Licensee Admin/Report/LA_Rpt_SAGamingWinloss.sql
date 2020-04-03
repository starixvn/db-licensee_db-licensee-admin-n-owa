/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

--ALTER PROCEDURE [dbo].[LA_Rpt_SAGamingWinloss]
declare	  @PartyIds			VARCHAR(4000)
	, @FromDate			DATETIME
	, @ToDate			DATETIME
	, @BaseCurrencyName	VARCHAR(10) = 'EUR'
--AS
select @BaseCurrencyName='EUR',@ToDate='2019-05-31 00:00:00',@PartyIds='14,34,30',@FromDate='2019-05-01 00:00:00'

/*  Created: 20200401@Parsons
	Task : Report - SA Gaming win loss
	DB: DB052.bodb_licensee
	Revisions:
		
	Param's Explanation:
*/
BEGIN
	SET NOCOUNT ON

	-- charge type
	DECLARE @GrossWin				INT = 1
	DECLARE @CreditServiceCharge	INT = 10
	DECLARE @RollingCommissionType	INT = 11
	DECLARE @TipChargeType			INT = 12

	-- Tips
	DECLARE @SAG_Tips INT = 3007

	-- Get partylist and parent group
	DECLARE @PartyList AS TABLE (PartyId INT, PartyName	VARCHAR(100), BranchName VARCHAR(100), ParentId	INT, ParentName VARCHAR(100), IsSelected BIT)

	INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC LA_PartyListSel

	UPDATE p1
	SET IsSelected = 1
	FROM @PartyList p1
	INNER JOIN bodb02.dbo.strSplit(@PartyIds, ',') p2 ON p1.PartyId = p2.val

	SET @PartyIds = '';
	SELECT @PartyIds = COALESCE(@PartyIds + ', ', '') + CAST(PartyId AS VARCHAR(4)) 
	FROM @PartyList
	WHERE ParentId <> 0
	
	SELECT @PartyIds

	CREATE TABLE #ChargeInfo(
		ChargeId				INT
		,PartyId				INT
		, LicenseeId			INT
		, IsDeposit				INT
		, ProductId				INT
		, Rate					FLOAT
		, IsPayToSupplier		BIT
		, FromDate				SMALLDATETIME
		, ToDate				SMALLDATETIME
		, ChargeType			INT
	)
	
	-- get licenseeFee's charge rate
	-- credit licensee display licensee fee as 0 -> set rate to 0
	INSERT INTO #ChargeInfo(ChargeId, PartyId, LicenseeId, ProductId, Rate, IsDeposit, Fromdate, Todate, IsPayToSupplier, ChargeType)
	(
		SELECT DISTINCT ChargeId, PartyID, LicenseeId, ProductId, CASE WHEN IsDeposit=1 THEN DI_Rate ELSE 0 END, IsDeposit, Fromdate, Todate, 0, ChargeType
		FROM dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, 'SAG')
	)

	-- Region: Insert Rate3rd for Credit's charge rate
	INSERT INTO #ChargeInfo(ChargeId, PartyId, LicenseeId, ProductId, Rate, IsDeposit, ChargeType, IsPayToSupplier, Fromdate, Todate)
	SELECT CI3rd.ChargeId, CI3rd.PartyID, LicenseeID, CI3rd.ProductID, Rate, 0, CI3rd.ChargeType, 1,
		(CASE WHEN CI3rd.Fromdate < @FromDate THEN @FromDate ELSE CI3rd.Fromdate END),
		(CASE WHEN CI3rd.Todate > @ToDate THEN @ToDate ELSE CI3rd.Todate END)
	FROM #ChargeInfo ci
	INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
	INNER JOIN LA_f_ChargeInfo3rd (@FromDate, @ToDate, 'SAG', 'OA') CI3rd ON p.ParentId = CI3rd.PartyID AND ci.ProductID = CI3rd.ProductID
	WHERE ISNULL(CI3rd.IsDeposit, 0) = 0
	-- Endregion

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
		RoyaltyFee		MONEY,
		BaseCurrency	VARCHAR(10)
	)

	INSERT INTO #Data(PartyId, ReportDate, CurrencyId, IsDeposit, Totaltrans, Turnover, ValidBetAmount, CustomerWL, TipAmount, LicenseeFee, Commission, NetWinLoss, CompanyTipShare, RoyaltyFee)
	(
		SELECT  ci.PartyID, b.rptDate, b.currencyID, ci.IsDeposit
			, SUM(CASE WHEN b.Bettype = @SAG_Tips THEN 0 ELSE b.betcount END) AS Totaltrans
			, SUM(b.turnover) AS Turnover
			, SUM(ISNULL(b.ValidBetAmount,0)) AS ValidBetAmount
			, SUM(CASE WHEN b.Bettype = @SAG_Tips THEN 0 ELSE b.MemberWL END) AS CustomerWL
			, SUM(CASE WHEN b.Bettype = @SAG_Tips THEN -b.MemberWL ELSE 0 END) AS TipAmount
			, SUM(CASE WHEN b.Bettype = @SAG_Tips THEN 0 ELSE -b.MemberWL * ISNULL(cr.Rate, ci.Rate) END) AS LicenseeFee
			, SUM(ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) AS Commission
			, SUM(CASE WHEN b.Bettype = @SAG_Tips THEN 0 ELSE -b.MemberWL END - ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) AS NetWinLoss
			, SUM(CASE WHEN b.Bettype = @SAG_Tips THEN -b.MemberWL * tipLicensee.Rate ELSE 0 END) AS CompanyTipShare
			, SUM(CASE WHEN b.Bettype = @SAG_Tips THEN 0 ELSE (-b.MemberWL - ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) * ISNULL(s.Rate, 0) END) AS RoyaltyFee
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #ChargeInfo ci ON ( -- licensee charge rate
				b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate AND
				ci.IsPayToSupplier = 0 AND
				(ci.IsDeposit = 0 OR (ci.IsDeposit = 1 AND ci.ChargeType = @GrossWin)))
			LEFT JOIN #ChargeInfo r ON ( -- rolling commission rate
				b.SiteID = r.LicenseeID AND b.ProductID = r.ProductId AND b.rptDate BETWEEN r.FromDate AND r.ToDate AND
				r.IsPayToSupplier = 1 AND 
				r.ChargeType = @RollingCommissionType)
			LEFT JOIN #ChargeInfo s ON ( -- service charge rate
				b.SiteID = s.LicenseeID AND b.ProductID = s.ProductId AND b.rptDate BETWEEN s.FromDate AND s.ToDate AND
				s.IsPayToSupplier = 1 AND
				s.ChargeType = @CreditServiceCharge)
			LEFT JOIN #ChargeInfo tipLicensee ON(
				b.SiteID = tipLicensee.LicenseeID AND b.ProductID = tipLicensee.ProductId AND b.rptDate BETWEEN tipLicensee.FromDate AND tipLicensee.ToDate AND
				tipLicensee.IsPayToSupplier = 0 AND
				tipLicensee.ChargeType = @TipChargeType)
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeId = ci.ChargeId AND cr.CurrencyID = b.CurrencyId
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
			  b.StatusId NOT IN (- 1, 101, 102) AND
			  b.customercategory NOT IN (27,28)
		GROUP BY b.rptDate, ci.PartyID, b.CurrencyID, ci.IsDeposit
	)

	--Region Update deposit's pay to supplier
	/*  To specific, 5% If Σ OneWorks Licensee Gross WL >= 10M CNY
		To specific, 5% If Σ [Boping & Zelianta] Licensee Gross WL >= 10M CNY */

	DECLARE @OneWorks INT = 1, @Boping INT = 11, @Zelianta INT = 98, @BopingAndZelianta INT = 99
	DECLARE @ApplyRange TABLE (ParentId INT, SumApplyValue MONEY, ApplyRate MONEY)
	
	INSERT INTO @ApplyRange (ParentId, SumApplyValue)
	SELECT CASE p.ParentId WHEN @OneWorks THEN @OneWorks ELSE @BopingAndZelianta END, SUM(-d.CustomerWL * ec.BaseCurrencyRate)
	FROM #Data d
	INNER JOIN @PartyList p ON d.PartyId = p.PartyId
	INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'CNY') ec ON d.CurrencyId = ec.ExchangeID AND ec.ExchangeDate = d.ReportDate
	WHERE ISNULL(d.IsDeposit, 0) = 1
	GROUP BY CASE p.ParentId WHEN @OneWorks THEN @OneWorks ELSE @BopingAndZelianta END

	UPDATE @ApplyRange
	SET ApplyRate = CASE WHEN (ParentId = @OneWorks AND SumApplyValue >= 10000000)
								OR (ParentId = @BopingAndZelianta AND SumApplyValue >= 10000000)
								THEN 0.05
								ELSE 0.06 
					END

	;WITH cte_DepositData AS(
		SELECT CASE p.ParentId WHEN @OneWorks THEN @OneWorks ELSE @BopingAndZelianta END AS ParentId,
					d.PartyId, -d.CustomerWL AS LicenseeWL
		FROM #Data d
		INNER JOIN @PartyList p ON d.PartyId = p.PartyId
		WHERE ISNULL(d.IsDeposit, 0) = 1 AND ISNULL(p.IsSelected, 0) = 1
	)
	UPDATE d
	SET d.RoyaltyFee = a.ApplyRate * (d2.LicenseeWL * a.ApplyRate)
	FROM #Data d
	INNER JOIN cte_DepositData d2 ON d.PartyId = d2.PartyId
	INNER JOIN @ApplyRange a ON d2.ParentId = a.ParentId

	-- Delete list of licensee which is not selected
	DELETE d
	FROM #Data d
	INNER JOIN @PartyList p ON d.PartyId = p.PartyId
	WHERE ISNULL(p.IsSelected, 0) = 0

	--End-Region Update deposit's pay to supplier

	DECLARE @BaseCurrencies TABLE(CurrencyId	INT, Code	VARCHAR(10))
	INSERT INTO @BaseCurrencies(CurrencyId, Code)
	EXEC LA_SelBaseCurrency

	WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies)
	BEGIN
		DECLARE @Currency VARCHAR(10) = (SELECT TOP 1 Code FROM @BaseCurrencies)

		-- 1. INSERT INTO @Total
		SELECT d.PartyId, d.IsDeposit, d.ReportDate, CASE WHEN ExchangeId = 92 THEN 'HID' WHEN ExchangeId = 51 THEN 'INH' ELSE Code END, d.Totaltrans, @Currency,
			d.Turnover * e.BaseCurrencyRate,
			d.CustomerWL * e.BaseCurrencyRate,
			d.TipAmount * e.BaseCurrencyRate,
			d.LicenseeFee * e.BaseCurrencyRate,
			d.Commission * e.BaseCurrencyRate,
			d.NetWinLoss * e.BaseCurrencyRate,
			d.CompanyTipShare * e.BaseCurrencyRate,
			d.RoyaltyFee * e.BaseCurrencyRate,	
			d.ValidBetAmount * e.BaseCurrencyRate
		FROM #Data d
		INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @Currency) e ON e.ExchangeId = d.CurrencyId AND e.exchangedate = d.ReportDate

		-- 2. INSERT INTO @GrandTotal

		DELETE @BaseCurrencies WHERE Code = @Currency
	END

	SELECT * FROM #ChargeInfo
	SELECT * FROM #Data

	DROP TABLE #ChargeInfo
	DROP TABLE #Data
END
GO