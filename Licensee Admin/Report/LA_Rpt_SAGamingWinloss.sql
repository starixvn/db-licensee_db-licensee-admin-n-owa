/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_SAGamingWinloss]
	  @PartyIds			VARCHAR(4000)
	, @FromDate			DATETIME
	, @ToDate			DATETIME
	, @BaseCurrencyName	VARCHAR(10) = 'EUR'
AS

/*  Created: 20200401@Parsons
	Task : Report - SA Gaming win loss
	DB: DB052.bodb_licensee
	Revisions: 
	    - 20200409@Parsons: Integrate SA Gaming [#129276]
		
	Param's Explanation:
*/
BEGIN
	SET NOCOUNT ON

	-- charge type
	DECLARE @GrossWin				INT = 1
	DECLARE @CreditServiceCharge	INT = 10
	DECLARE @RollingRollingCommType	INT = 11
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
	INSERT INTO #ChargeInfo(PartyId, LicenseeId, ProductId, Rate, IsDeposit, ChargeType, IsPayToSupplier, Fromdate, Todate)
	SELECT DISTINCT CI3rd.PartyID, LicenseeID, CI3rd.ProductID, CI3rd.DI_Rate, 0, CI3rd.ChargeType, 1,
		(CASE WHEN CI3rd.Fromdate < @FromDate THEN @FromDate ELSE CI3rd.Fromdate END),
		(CASE WHEN CI3rd.Todate > @ToDate THEN @ToDate ELSE CI3rd.Todate END)
	FROM #ChargeInfo ci
	INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
	INNER JOIN LA_f_ChargeInfo3rd (@FromDate, @ToDate, 'SAG', 'OA') CI3rd ON p.ParentId = CI3rd.PartyID AND ci.ProductID = CI3rd.ProductID
	WHERE ISNULL(CI3rd.IsDeposit, 0) = 0
	-- Endregion

	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	UPDATE #Exchange SET CurrencyCode = CASE WHEN ExchangeID = 51 THEN 'INH' 
											 WHEN ExchangeID = 92 THEN 'HID' END
	WHERE ExchangeID IN (51,92)

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
		LicensingFeeWithoutTips		MONEY,
		RollingComm	MONEY,
		NetWinLoss		MONEY,
		CompanyTipShare MONEY,
		RoyaltyFee		MONEY,
		BaseCurrency	VARCHAR(10)
	)

	INSERT INTO #Data(PartyId, ReportDate, CurrencyId, IsDeposit, Totaltrans, Turnover, ValidBetAmount, CustomerWL, TipAmount, LicensingFeeWithoutTips, RollingComm, NetWinLoss, CompanyTipShare, RoyaltyFee)
	(
		SELECT  ci.PartyID, b.rptDate, b.currencyID, ci.IsDeposit
			, SUM(CASE WHEN b.Bettype = @SAG_Tips THEN 0 ELSE b.betcount END) AS Totaltrans
			, SUM(b.turnover) AS Turnover
			, SUM(ISNULL(b.ValidBetAmount,0)) AS ValidBetAmount
			, SUM(CASE WHEN b.Bettype = @SAG_Tips THEN 0 ELSE b.MemberWL END) AS CustomerWL
			, SUM(CASE WHEN b.Bettype = @SAG_Tips THEN -b.MemberWL ELSE 0 END) AS TipAmount
			, SUM(CASE WHEN b.Bettype = @SAG_Tips THEN 0 ELSE -b.MemberWL * ISNULL(cr.Rate, ci.Rate) END) AS LicensingFeeWithoutTips
			, SUM(ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) AS RollingComm
			, SUM(CASE WHEN b.Bettype = @SAG_Tips THEN 0 ELSE -b.MemberWL END - ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) AS NetWinLoss
			, SUM(CASE WHEN b.Bettype = @SAG_Tips THEN -b.MemberWL * tipLicensee.Rate ELSE 0 END) AS CompanyTipShare
			, SUM(CASE WHEN b.Bettype = @SAG_Tips THEN 0 ELSE (-b.MemberWL - ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) * ISNULL(s.Rate, 0) END) AS RoyaltyFee
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #ChargeInfo ci ON ( -- licensee charge rate
				b.SiteID = ci.LicenseeID AND b.ProductID = ci.ProductId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate AND
				ci.IsPayToSupplier = 0 AND ci.ChargeType = @GrossWin)
			LEFT JOIN #ChargeInfo r ON ( -- rolling RollingComm rate
				b.SiteID = r.LicenseeID AND b.ProductID = r.ProductId AND b.rptDate BETWEEN r.FromDate AND r.ToDate AND
				r.IsPayToSupplier = 1 AND 
				r.ChargeType = @RollingRollingCommType)
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
			  b.StatusId NOT IN (- 1, 101, 102, 103) AND
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

	;WITH cte_SelectedDepositSettings AS(
		SELECT CASE p.ParentId WHEN @OneWorks THEN @OneWorks ELSE @BopingAndZelianta END AS ParentId,
					d.PartyId
		FROM #Data d
		INNER JOIN @PartyList p ON d.PartyId = p.PartyId
		WHERE ISNULL(d.IsDeposit, 0) = 1 AND ISNULL(p.IsSelected, 0) = 1
	)
	UPDATE d
	SET d.RoyaltyFee = a.ApplyRate * (d.NetWinLoss)
	FROM #Data d
	INNER JOIN cte_SelectedDepositSettings d2 ON d.PartyId = d2.PartyId
	INNER JOIN @ApplyRange a ON d2.ParentId = a.ParentId

	-- Delete list of licensee which is not selected
	DELETE d
	FROM #Data d
	INNER JOIN @PartyList p ON d.PartyId = p.PartyId
	WHERE ISNULL(p.IsSelected, 0) = 0
	--End-Region Update deposit's pay to supplier

	-- Region: Calculate result
	CREATE TABLE #Result (
		PartyId			INT,
		PartyName		VARCHAR(100),
		ParentId		INT,
		ParentName		VARCHAR(100),
		WinLossDate		DATETIME,
		CurrencyId		INT,
		TotalTrans		INT,
		Turnover		MONEY,
		ValidBetAmount	MONEY,
		TipAmount 		MONEY,
		CustomerWinLoss	MONEY,
		LicensingFeeWithoutTips	MONEY,
		RollingComm	MONEY,
		NetWinLoss		MONEY,
		CompanyTipShare MONEY,
		PayToSupplier	MONEY,
		CompanyIncome		MONEY
	)
	
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, ValidBetAmount, TipAmount, CustomerWinLoss, LicensingFeeWithoutTips, RollingComm, NetWinLoss, CompanyTipShare, PayToSupplier, CompanyIncome)
	SELECT d.PartyId, p.PartyName, pa.PartyId, pa.PartyName, d.ReportDate, CurrencyId, TotalTrans, Turnover, ValidBetAmount, TipAmount, CustomerWL, LicensingFeeWithoutTips, RollingComm, NetWinLoss, CompanyTipShare, RoyaltyFee + CompanyTipShare, LicensingFeeWithoutTips - RoyaltyFee
	FROM #Data d
		INNER JOIN @PartyList p ON d.PartyId = p.PartyID
		INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId	
	
	DECLARE @Total TABLE (
		PartyId			INT,
		TotalTrans		INT,
		Turnover		MONEY,
		ValidBetAmount	MONEY,
		TipAmount	MONEY,
		CustomerWinLoss	MONEY,
		LicensingFee	MONEY,
		RollingComm	MONEY,
		NetWinLoss		MONEY,
		CompanyTipShare MONEY,
		PayToSupplier	MONEY,
		CompanyIncome		MONEY,
		Currency		VARCHAR(20)
	)

	DECLARE @GrandTotal TABLE (
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		ValidBetAmount	MONEY,
		TipAmount		MONEY,
		CustomerWinLoss	MONEY,
		LicensingFee	MONEY,
		RollingComm	MONEY,
		NetWinLoss		MONEY,
		CompanyTipShare MONEY,
		PayToSupplier	MONEY,
		CompanyIncome		MONEY
	)

	DECLARE @BaseCurrencies TABLE(CurrencyId	INT, Code	VARCHAR(10))
	INSERT INTO @BaseCurrencies(CurrencyId, Code)
	EXEC LA_SelBaseCurrency

	WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies)
	BEGIN
		DECLARE @Currency VARCHAR(10) = (SELECT TOP 1 Code FROM @BaseCurrencies)
		
		;WITH TotalByParty AS(
			SELECT td.ParentId,
				SUM(td.TotalTrans) TotalTrans,
				SUM(td.Turnover * e.BaseCurrencyRate) Turnover,
				SUM(td.ValidBetAmount * e.BaseCurrencyRate) ValidBetAmount,
				SUM(td.TipAmount * e.BaseCurrencyRate) TipAmount,
				SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss,
				SUM(td.LicensingFeeWithoutTips * e.BaseCurrencyRate) LicensingFeeWithoutTips,
				SUM(td.RollingComm * e.BaseCurrencyRate) RollingComm,
				SUM(td.NetWinLoss * e.BaseCurrencyRate) NetWinLoss,
				SUM(td.CompanyTipShare * e.BaseCurrencyRate) CompanyTipShare,
				SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier
			FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @Currency) e
			ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
			GROUP BY td.ParentId, td.PartyId
		)
		INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,ValidBetAmount,TipAmount,CustomerWinLoss,LicensingFee,RollingComm,NetWinLoss,CompanyTipShare,PayToSupplier,CompanyIncome)
		SELECT @Currency,ParentId,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(ValidBetAmount),
			SUM(TipAmount),
			SUM(CustomerWinLoss),
			SUM(CASE WHEN LicensingFeeWithoutTips < 0 THEN 0 ELSE LicensingFeeWithoutTips END + CompanyTipShare),
			SUM(RollingComm),
			SUM(NetWinLoss),
			SUM(CompanyTipShare),
			SUM(PayToSupplier),
			SUM(CASE WHEN LicensingFeeWithoutTips < 0 THEN 0 ELSE LicensingFeeWithoutTips END + CompanyTipShare - PayToSupplier)
		FROM TotalByParty
		GROUP BY ParentId
		
		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,ValidBetAmount,TipAmount,CustomerWinLoss,LicensingFee,RollingComm,NetWinLoss,CompanyTipShare,PayToSupplier,CompanyIncome)
		SELECT Currency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(ValidBetAmount),
			SUM(TipAmount),
			SUM(CustomerWinLoss),
			SUM(LicensingFee),
			SUM(RollingComm),
			SUM(NetWinLoss),
			SUM(CompanyTipShare),
			SUM(PayToSupplier),
			SUM(LicensingFee - PayToSupplier)
		FROM @Total
		WHERE Currency = @Currency
		GROUP BY Currency

		DELETE @BaseCurrencies WHERE Code = @Currency
	END

	-- Select data by Parties
	SELECT 
		r.PartyId,
		r.PartyName,
		r.ParentId,
		r.ParentName,
		r.WinLossDate,
		e.CurrencyCode AS CurrencyName,
		-- Select by origin currency
		r.TotalTrans,
		r.Turnover AS TurnoverOriginal,
		CAST((r.ValidBetAmount) AS MONEY) AS ValidBetAmountOriginal,
		CAST((r.TipAmount) AS MONEY) AS TipAmountOriginal,
		CAST((r.CustomerWinLoss) AS MONEY) AS CustomerWinLossOriginal,
		CAST((r.LicensingFeeWithoutTips + r.CompanyTipShare) AS MONEY) AS LicensingFeeOriginal,
		CAST((r.RollingComm) AS MONEY) AS RollingCommOriginal,
		CAST((r.NetWinLoss) AS MONEY) AS NetWinLossOriginal,
		CAST((r.CompanyTipShare) AS MONEY) AS CompanyTipShareOriginal,
		CAST((r.PayToSupplier) AS MONEY) AS PayToSupplierOriginal,
		r.LicensingFeeWithoutTips + r.CompanyTipShare - r.PayToSupplier AS CompanyIncomeOriginal,
		-- Select by base currency
		r.Turnover * e.Rate AS Turnover,
		CAST((r.ValidBetAmount * e.Rate) AS MONEY) AS ValidBetAmount,
		CAST((r.TipAmount * e.Rate) AS MONEY) AS TipAmount,
		CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
		CAST(((r.LicensingFeeWithoutTips + r.CompanyTipShare) * e.Rate) AS MONEY) AS LicensingFee,
		CAST((r.RollingComm * e.Rate) AS MONEY) AS RollingComm,
		CAST((r.NetWinLoss * e.Rate) AS MONEY) AS NetWinLoss,
		CAST((r.RollingComm * e.Rate) AS MONEY) AS RollingComm,
		CAST((r.CompanyTipShare * e.Rate) AS MONEY) AS CompanyTipShare,
		CAST((r.PayToSupplier * e.Rate) AS MONEY) AS PayToSupplier,
		CAST((r.LicensingFeeWithoutTips + r.CompanyTipShare - r.PayToSupplier) * e.Rate AS MONEY) AS CompanyIncome
	FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.WinLossDate = e.ExchangeDate
	
	-- Select Grand Total
	SELECT * FROM @GrandTotal
	
	-- Total
	SELECT 
		PartyId,
		TotalTrans,
		Turnover,
		ValidBetAmount,
		TipAmount,
		CustomerWinLoss,
		LicensingFee,
		RollingComm,
		NetWinLoss,
		CompanyTipShare,
		PayToSupplier,
		CompanyIncome
	FROM @Total t
	WHERE Currency = @BaseCurrencyName
	-- End Region

	DROP TABLE #Result
	DROP TABLE #ChargeInfo
	DROP TABLE #Data
	DROP TABLE #Exchange
END
GO