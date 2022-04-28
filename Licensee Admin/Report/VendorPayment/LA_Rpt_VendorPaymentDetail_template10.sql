/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Rpt_VendorPaymentDetail_template10]
	@PartyIds			VARCHAR(4000),
	@ProductID			INT,
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20),
	@TimeZoneId			INT
AS
/*
 * Created by : [20220405@Danny]
 * Task  : Vendor Payment Detail (template10 - Template for SA Gaming product, including some specific info such as: Valid Bet Amount, Tip Sharing, Rolling Comm...)
 * Revisions
	- 20220426@Danny: Initialize SP [#168387]
 */

BEGIN
	SET NOCOUNT ON
	-- charge type
	DECLARE @GrossWin				INT = 1,
			@CreditServiceCharge	INT = 10,
			@RollingRollingCommType INT = 11,
			@TipChargeType			INT = 12, 
			@ProductCode			VARCHAR(50)

	DECLARE @BettypeIdList TABLE (BetTypeId INT)
	DECLARE @3rdRate TABLE(PartyID INT, ProductID INT, DI_Rate MONEY, IsDeposit INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME, MinAmount MONEY DEFAULT 0, MaxAmount MONEY DEFAULT 0, CurrencyId INT)
	
	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT, IsKeepNegativeAmount BIT DEFAULT 0, IsSelected BIT)
	
	CREATE TABLE #ChargeRate (
		ChargeID		INT
		,PartyID		INT
		,LicenseeID		INT
		,isDeposit		INT
		,ProductID		INT
		,Rate			MONEY	DEFAULT 0
		,Rate3rd		MONEY	DEFAULT 0
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
		,IsPayToSupplier	BIT
		,ChargeType		SMALLINT
	)

	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)

	CREATE TABLE #TempData (
		PartyId					INT,
		IsDeposit				BIT,
		ReportDate				DATETIME,
		CurrencyId				INT,
		CurrencyName			VARCHAR(10),
		Totaltrans				INT,
		Turnover				MONEY,
		ValidBetAmount			MONEY,
		CustomerWL				MONEY,
		TipAmount 				MONEY,
		LicensingFeeWithoutTips	MONEY,
		RollingComm				MONEY,
		NetWinLoss				MONEY,
		CompanyTipShare			MONEY,
		RoyaltyFee				MONEY,
		BaseCurrency			VARCHAR(10)
	)

	 -- Exchange
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT	ExchangeDate, 
			ExchangeID,  
			CASE WHEN ExchangeID = 51 THEN 'INH' 
				 WHEN ExchangeID = 92 THEN 'HID'
				 ELSE Code END Code, 
			BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	


	-- ProductCode
	SELECT @ProductCode = ProductPrefix FROM dbo.Product3rd WITH(NOLOCK) WHERE Productid = @ProductID

	-- Party list
	INSERT INTO #PartyList (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	UPDATE #PartyList SET PartyName = REPLACE(PartyName,' Licensees','') WHERE ParentId = 0
	
	UPDATE t 
	SET t.IsKeepNegativeAmount = CASE WHEN u.PartyId IS NULL THEN 0 ELSE 1 END 
	FROM #PartyList t 
	LEFT JOIN bodb_Licensee.dbo.LA_f_JVPartyListSel() u ON u.PartyId = t.PartyId

	UPDATE p1
	SET IsSelected = 1
	FROM #PartyList p1
	INNER JOIN bodb02.dbo.strSplit(@PartyIds, ',') p2 ON p1.PartyId = p2.val

	SET @PartyIds = '';
	SELECT @PartyIds = COALESCE(@PartyIds + ', ', '') + CAST(PartyId AS VARCHAR(4)) 
	FROM #PartyList
	WHERE ParentId <> 0

	-- Bettype List
	INSERT INTO @BettypeIdList (BetTypeId)
	SELECT	DISTINCT bettype
	FROM	bodb_licensee.dbo.LA_f_BettypeProductMapping(0,@ProductCode) la

	-- Handle chargeRate
	BEGIN
		IF @ProductID = 39 --SAG
		BEGIN
			INSERT INTO #ChargeRate(ChargeId, PartyId, LicenseeId, ProductId, Rate, IsDeposit, Fromdate, Todate, IsPayToSupplier, ChargeType)
			(
				SELECT DISTINCT ChargeId, PartyID, LicenseeId, ProductId, CASE WHEN IsDeposit=1 THEN DI_Rate ELSE 0 END, IsDeposit, Fromdate, Todate, 0, ChargeType
				FROM dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, 'SAG')
			)

			UPDATE p
			SET p.ParentId = ci.ToParty
			FROM #PartyList p
			INNER JOIN #ChargeRate c ON p.PartyId = c.PartyId
			INNER JOIN OAS_ChargeInfo ci WITH(NOLOCK) ON c.ChargeId = ci.ChargeID
			WHERE p.ParentId IN (1,9,11,98)

			INSERT INTO #ChargeRate(PartyId, LicenseeId, ProductId, Rate, IsDeposit, ChargeType, IsPayToSupplier, Fromdate, Todate)
			SELECT DISTINCT CI3rd.PartyID, LicenseeID, CI3rd.ProductID, CI3rd.DI_Rate, 0, CI3rd.ChargeType, 1,
				(CASE WHEN CI3rd.Fromdate < @FromDate THEN @FromDate ELSE CI3rd.Fromdate END),
				(CASE WHEN CI3rd.Todate > @ToDate THEN @ToDate ELSE CI3rd.Todate END)
			FROM #ChargeRate ci
			INNER JOIN #PartyList p ON ci.PartyId = p.PartyId 
			INNER JOIN LA_f_ChargeInfo3rd (@FromDate, @ToDate, 'SAG', 'OA') CI3rd ON p.ParentId = CI3rd.PartyID AND ci.ProductID = CI3rd.ProductID
			WHERE ISNULL(CI3rd.IsDeposit, 0) = 0
		END
		ELSE
		BEGIN
			-- Get 3rd Rate
			INSERT INTO @3rdRate (PartyID, ProductID, DI_Rate, IsDeposit, Fromdate, Todate)
			SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.IsDeposit, r.Fromdate, r.Todate 
			FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, @ProductCode, 'OA') r 
			INNER JOIN #PartyList p on p.ParentId = r.PartyID
	
			-- ​#ChargeRate
			INSERT INTO #ChargeRate (ChargeID, PartyID, LicenseeID, isDeposit, ProductID, Rate, Rate3rd, Fromdate, Todate)
			SELECT DISTINCT c.ChargeID, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate AS Rate, r.DI_Rate AS Rate3rd, c.Fromdate, c.Todate
			FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate,@ProductCode) c
			INNER JOIN @3rdRate r ON r.PartyID = c.PartyID and CASE WHEN r.ProductID = 69 THEN 0 ELSE  r.ProductID END = c.ProductID
			WHERE (c.DI_Rate = 0 AND c.isDeposit = 0) OR (c.DI_Rate > 0 and c.isDeposit = 1)
		END
	END
	
	-- Region: TempData 
	IF @TimeZoneId = 1 --GMT -4
	BEGIN
		INSERT INTO #TempData(PartyId, ReportDate, CurrencyId, IsDeposit, Totaltrans, Turnover, ValidBetAmount, CustomerWL, TipAmount, LicensingFeeWithoutTips, RollingComm, NetWinLoss, CompanyTipShare, RoyaltyFee)
		SELECT  ci.PartyID, b.RptDate, b.currencyID, ci.IsDeposit
			, SUM(CASE WHEN tip.Bettype IS NOT NULL THEN 0 ELSE b.betcount END) AS Totaltrans
			, SUM(b.turnover) AS Turnover
			, SUM(ISNULL(b.ValidBetAmount,0)) AS ValidBetAmount
			, SUM(CASE WHEN tip.Bettype IS NOT NULL THEN 0 ELSE b.MemberWL END) AS CustomerWL
			, SUM(CASE WHEN tip.Bettype IS NOT NULL THEN -b.MemberWL ELSE 0 END) AS TipAmount
			, SUM(CASE WHEN tip.Bettype IS NOT NULL THEN 0 ELSE -b.MemberWL * ISNULL(cr.Rate, ci.Rate) END) AS LicensingFeeWithoutTips
			, SUM(ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) AS RollingComm
			, SUM(CASE WHEN tip.Bettype IS NOT NULL THEN 0 ELSE -b.MemberWL END - ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) AS NetWinLoss
			, SUM(CASE WHEN tip.Bettype IS NOT NULL THEN -b.MemberWL * tipLicensee.Rate ELSE 0 END) AS CompanyTipShare
			, SUM(CASE WHEN tip.Bettype IS NOT NULL THEN 0 ELSE (-b.MemberWL - ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) * ISNULL(s.Rate, 0) END) AS RoyaltyFee
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON ( -- licensee charge rate
				b.SiteID = ci.LicenseeID AND b.RptDate BETWEEN ci.FromDate AND ci.ToDate AND
				ci.IsPayToSupplier = 0 AND ci.ChargeType = @GrossWin)
			LEFT JOIN #ChargeRate r ON ( -- rolling RollingComm rate
				b.SiteID = r.LicenseeID AND b.RptDate BETWEEN r.FromDate AND r.ToDate AND
				r.IsPayToSupplier = 1 AND 
				r.ChargeType = @RollingRollingCommType)
			LEFT JOIN #ChargeRate s ON ( -- service charge rate
				b.SiteID = s.LicenseeID AND b.RptDate BETWEEN s.FromDate AND s.ToDate AND
				s.IsPayToSupplier = 1 AND
				s.ChargeType = @CreditServiceCharge)
			LEFT JOIN #ChargeRate tipLicensee ON(
				b.SiteID = tipLicensee.LicenseeID AND b.RptDate BETWEEN tipLicensee.FromDate AND tipLicensee.ToDate AND
				tipLicensee.IsPayToSupplier = 0 AND
				tipLicensee.ChargeType = @TipChargeType)
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeId = ci.ChargeId AND cr.CurrencyID = b.CurrencyId
			LEFT JOIN dbo.LA_f_GroupBettype() tip ON tip.Bettype = b.Bettype AND tip.ProductId = @ProductID AND tip.TypeId = 1
		WHERE 
			  b.RptDate BETWEEN @FromDate AND @ToDate AND
			  b.StatusId NOT IN (- 1, 101, 102, 103) AND
			  b.ProductID = @ProductID AND
			  b.CurrencyId <> 20 -- UUS - Currency testing
		GROUP BY b.RptDate, ci.PartyID, b.CurrencyID, ci.IsDeposit
	END
	ELSE -- Another timezone
	BEGIN
		INSERT INTO #TempData(PartyId, ReportDate, CurrencyId, IsDeposit, Totaltrans, Turnover, ValidBetAmount, CustomerWL, TipAmount, LicensingFeeWithoutTips, RollingComm, NetWinLoss, CompanyTipShare, RoyaltyFee)
		SELECT  ci.PartyID, b.RptDate3rd, b.currencyID, ci.IsDeposit
			, SUM(CASE WHEN tip.Bettype IS NOT NULL THEN 0 ELSE b.betcount END) AS Totaltrans
			, SUM(b.turnover) AS Turnover
			, SUM(ISNULL(b.ValidBetAmount,0)) AS ValidBetAmount
			, SUM(CASE WHEN tip.Bettype IS NOT NULL THEN 0 ELSE b.Winloss END) AS CustomerWL
			, SUM(CASE WHEN tip.Bettype IS NOT NULL THEN -b.Winloss ELSE 0 END) AS TipAmount
			, SUM(CASE WHEN tip.Bettype IS NOT NULL THEN 0 ELSE -b.Winloss * ISNULL(cr.Rate, ci.Rate) END) AS LicensingFeeWithoutTips
			, SUM(ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) AS RollingComm
			, SUM(CASE WHEN tip.Bettype IS NOT NULL THEN 0 ELSE -b.Winloss END - ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) AS NetWinLoss
			, SUM(CASE WHEN tip.Bettype IS NOT NULL THEN -b.Winloss * tipLicensee.Rate ELSE 0 END) AS CompanyTipShare
			, SUM(CASE WHEN tip.Bettype IS NOT NULL THEN 0 ELSE (-b.Winloss - ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) * ISNULL(s.Rate, 0) END) AS RoyaltyFee
		FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON ( -- licensee charge rate
				b.SiteID = ci.LicenseeID AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate AND
				ci.IsPayToSupplier = 0 AND ci.ChargeType = @GrossWin)
			LEFT JOIN #ChargeRate r ON ( -- rolling RollingComm rate
				b.SiteID = r.LicenseeID AND b.RptDate3rd BETWEEN r.FromDate AND r.ToDate AND
				r.IsPayToSupplier = 1 AND 
				r.ChargeType = @RollingRollingCommType)
			LEFT JOIN #ChargeRate s ON ( -- service charge rate
				b.SiteID = s.LicenseeID AND b.RptDate3rd BETWEEN s.FromDate AND s.ToDate AND
				s.IsPayToSupplier = 1 AND
				s.ChargeType = @CreditServiceCharge)
			LEFT JOIN #ChargeRate tipLicensee ON(
				b.SiteID = tipLicensee.LicenseeID AND b.RptDate3rd BETWEEN tipLicensee.FromDate AND tipLicensee.ToDate AND
				tipLicensee.IsPayToSupplier = 0 AND
				tipLicensee.ChargeType = @TipChargeType)
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeId = ci.ChargeId AND cr.CurrencyID = b.CurrencyId
			LEFT JOIN dbo.LA_f_GroupBettype() tip ON tip.Bettype = b.BetTypeId AND tip.ProductId = @ProductID AND tip.TypeId = 1
		WHERE b.RptDate BETWEEN DATEADD(DAY, -1, @FromDate) AND DATEADD(DAY, 1, @ToDate) AND
			  b.RptDate3rd BETWEEN @FromDate AND @ToDate AND
			  b.StatusId NOT IN (- 1, 101, 102, 103) AND
			  b.BetTypeId IN (SELECT x.BetTypeId FROM @BettypeIdList x) AND
			  b.CurrencyId <> 20 -- UUS - Currency testing
		GROUP BY b.RptDate3rd, ci.PartyID, b.CurrencyID, ci.IsDeposit
	END

	IF @ProductID = 39
	BEGIN
		--Region Update deposit's pay to supplier
		/*  To specific, 5% If Σ OneWorks Licensee Gross WL >= 10M CNY
			To specific, 5% If Σ [Boping & Zelianta] Licensee Gross WL >= 10M CNY */
		DECLARE @OneWorks INT = 1, @Boping INT = 11, @Zelianta INT = 98, @BopingAndZelianta INT = 99
		DECLARE @ApplyRange TABLE (ParentId INT, SumApplyValue MONEY, ApplyRate MONEY)
	
		INSERT INTO @ApplyRange (ParentId, SumApplyValue)
		SELECT CASE p.ParentId WHEN @OneWorks THEN @OneWorks ELSE @BopingAndZelianta END, SUM(-d.CustomerWL * ec.BaseCurrencyRate)
		FROM #TempData d
		INNER JOIN #PartyList p ON d.PartyId = p.PartyId
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
			FROM #TempData d
			INNER JOIN #PartyList p ON d.PartyId = p.PartyId
			WHERE ISNULL(d.IsDeposit, 0) = 1 AND ISNULL(p.IsSelected, 0) = 1
		)
		UPDATE d
		SET d.RoyaltyFee = a.ApplyRate * (d.NetWinLoss)
		FROM #TempData d
		INNER JOIN cte_SelectedDepositSettings d2 ON d.PartyId = d2.PartyId
		INNER JOIN @ApplyRange a ON d2.ParentId = a.ParentId

		-- Delete list of licensee which is not selected
		DELETE d
		FROM #TempData d
		INNER JOIN #PartyList p ON d.PartyId = p.PartyId
		WHERE ISNULL(p.IsSelected, 0) = 0
		--End-Region Update deposit's pay to supplier
	END

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
		RollingComm		MONEY,
		NetWinLoss		MONEY,
		CompanyTipShare MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)
	
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, ValidBetAmount, TipAmount, CustomerWinLoss, LicensingFeeWithoutTips, RollingComm, NetWinLoss, CompanyTipShare, PayToSupplier, CompanyIncome)
	SELECT d.PartyId, p.PartyName, pa.PartyId, pa.PartyName, d.ReportDate, CurrencyId, TotalTrans, Turnover, ValidBetAmount, TipAmount, CustomerWL, LicensingFeeWithoutTips, RollingComm, NetWinLoss, CompanyTipShare, RoyaltyFee + CompanyTipShare, LicensingFeeWithoutTips - RoyaltyFee
	FROM #TempData d
		INNER JOIN #PartyList p ON d.PartyId = p.PartyID
		INNER JOIN #PartyList pa ON p.ParentId = pa.PartyId	
	

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

	-- Region: Calculate Grand Total
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20)
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC bodb_licensee.dbo.LA_SelBaseCurrency

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
		CompanyIncome	MONEY
	)
	
	WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies)
	BEGIN
		DECLARE @Currency VARCHAR(10) = (SELECT TOP 1 Name FROM @BaseCurrencies)
		
		;WITH TotalByParty AS(
			SELECT CASE WHEN td.PartyId = 14 THEN 14 ELSE td.ParentId END ParentId,
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
			GROUP BY CASE WHEN td.PartyId = 14 THEN 14 ELSE td.ParentId END, td.PartyId
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

		DELETE @BaseCurrencies WHERE Name = @Currency
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
	DROP TABLE #ChargeRate
	DROP TABLE #TempData
	DROP TABLE #Exchange
END
GO