/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[LA_Rpt_VendorPaymentDetail_template17]
	@PartyIds			VARCHAR(MAX)
	,@ProductID			INT
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@BaseCurrencyName	VARCHAR(20)
	,@TimeZoneId		INT
	,@PlatformId		TINYINT = 0
AS
/*
 * Created by : [20220409@Danny]
 * Task  : Vendor Payment Detail (template17 - Template for Inhouse Product)
 * Revisions
	- 20240409@Danny: Initialize SP [#200955]
	
 */
 BEGIN
	SET NOCOUNT ON

	DECLARE @IsConvertNegativeFeeToZero BIT, @IsConvertNegativePaytoSupplierToZero BIT
	SELECT @IsConvertNegativeFeeToZero = IsConvertNegativeFeeToZero, @IsConvertNegativePaytoSupplierToZero = IsConvertNegativePaytoSupplierToZero  FROM dbo.LA_VendorPaymentSetting WITH(NOLOCK) WHERE ProductId = @ProductID

	DECLARE @ProductCode VARCHAR(50), @3rdProductCode VARCHAR(50)
	DECLARE @BettypeIdList TABLE (BetTypeId INT)
	DECLARE @3rdRate TABLE(PartyID INT, ProductID INT, DI_Rate MONEY, IsDeposit INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME, MinAmount MONEY DEFAULT 0, MaxAmount MONEY DEFAULT 0, CurrencyId INT)
	
	--Get @PartyIds by platform
	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
		    INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END

	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT, IsKeepNegativeAmount BIT DEFAULT 0)
	
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
	)

	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(65),
		Rate			FLOAT
	)

	CREATE TABLE #TempData (
		PartyID			INT,
		PartyName		NVARCHAR(100),
		ParentId		INT,
		ParentName		NVARCHAR(100),
		Winlostdate		DATETIME,
		CurrencyId		INT,
		Turnover		MONEY	DEFAULT 0,
		TotalTrans		INT		DEFAULT 0,
		CustomerWinLoss MONEY	DEFAULT 0,
		LicenseeWinloss MONEY	DEFAULT 0,
		HouseTurnover   MONEY	DEFAULT 0,
		JackpotPrize	MONEY	DEFAULT 0,
		LicenseeContribution	MONEY DEFAULT 0,
		LicenseeChargeRate	MONEY DEFAULT 0,
		LicensingFee	MONEY	DEFAULT 0,
		PayToSupplier	MONEY	DEFAULT 0,
		isDeposit		BIT,
		Promotion		MONEY	DEFAULT 0
	)

	 -- Exchange
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, CASE WHEN ExchangeID = 51 THEN 'INH' 
										  WHEN ExchangeID = 92 THEN 'HID'  
										  ELSE Code END, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	-- ProductCode
	SELECT @ProductCode = GroupProductCode, @3rdProductCode = ProductCode 
	FROM   dbo.LA_f_GroupProduct('',@FromDate,@ToDate) WHERE ProductId = @ProductID

	-- Party list
	INSERT INTO #PartyList (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	UPDATE #PartyList SET PartyName = REPLACE(PartyName,' Licensees','') WHERE ParentId = 0
	
	UPDATE t 
	SET t.IsKeepNegativeAmount = CASE WHEN u.PartyId IS NULL THEN 0 ELSE 1 END 
	FROM #PartyList t 
	LEFT JOIN bodb_Licensee.dbo.LA_f_JVPartyListSel() u ON u.PartyId = t.PartyId

	-- Bettype List
	INSERT INTO @BettypeIdList (BetTypeId)
	SELECT	DISTINCT bettype
	FROM	bodb_licensee.dbo.LA_f_BettypeProductMapping(0,@3rdProductCode) la

	-- Handle chargeRate
	BEGIN
		-- ​#ChargeRate
		INSERT INTO #ChargeRate (ChargeID, PartyID, LicenseeID, isDeposit, ProductID, Rate, Rate3rd, Fromdate, Todate)
		SELECT DISTINCT c.ChargeID, 
						c.PartyID, 
						c.LicenseeID, 
						c.isDeposit, 
						c.ProductID, 
						CASE WHEN c.IsDeposit = 0 THEN 0 ELSE c.DI_Rate END AS Rate, 
						-- Rate3rd
						0 AS Rate3rd, 
						c.Fromdate, 
						c.Todate
						
		FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate,@ProductCode) c
		LEFT JOIN @3rdRate r ON r.PartyID = c.PartyID AND (r.ProductID = c.ProductID OR @ProductCode <> @3rdProductCode)
		WHERE (c.isDeposit = 0 AND (c.DI_Rate = 0 OR c.ProductID IN (24,0))) OR (c.DI_Rate > 0 and c.isDeposit = 1)
	END
	
	-- Region: TempData 
	IF @TimeZoneId = 1 --GMT -4
	BEGIN
		;WITH cte_detail AS
			(
			SELECT
				b.RptDate as Winlostdate,
				b.CurrencyId,
				b.SiteId,
				SUM(CASE WHEN lf.Bettype IS NOT NULL THEN 0 ELSE b.Turnover END) AS Turnover,
				SUM(CASE WHEN lf.Bettype IS NOT NULL THEN 0 ELSE b.BetCount END) AS TotalTrans,
				SUM(CASE WHEN lf.Bettype IS NOT NULL THEN 0 ELSE b.MemberWL END) AS CustomerWinLoss,
				- SUM(CASE WHEN lf.Bettype IS NOT NULL THEN 0 ELSE b.MemberWL END) AS LicenseeWinloss,
				SUM(CASE WHEN lf.TypeId = 2 THEN -b.GrossWL ELSE 0 END) AS LicenseeContribution,
				SUM(CASE WHEN lf.TypeId = 3 THEN b.MemberWL ELSE 0 END) AS JackpotPrize,
				SUM(CASE WHEN lf.TypeId IN (4,8) THEN b.MemberWL ELSE 0 END) AS Promotion,
				SUM(ExtraAmount) AS HouseTurnover
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.RptDate BETWEEN ci.FromDate AND ci.ToDate
				LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
				LEFT JOIN dbo.LA_f_GroupBettype() lf ON b.BetType = lf.Bettype
			WHERE b.RptDate BETWEEN @FromDate AND @ToDate 
				AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20
				AND b.ProductID = @ProductID
			GROUP BY b.RptDate, b.CurrencyId, b.SiteId
			)
			INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,LicenseeContribution,JackpotPrize,LicenseeChargeRate,IsDeposit,Promotion,HouseTurnover)
			SELECT	ci.PartyID,
					b.Winlostdate,
					b.CurrencyId,
					SUM(Turnover),
					SUM(TotalTrans),
					SUM(CustomerWinLoss),
					SUM(LicenseeWinloss),
					SUM( CASE WHEN  IsDeposit = 0 THEN 0  ELSE (LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate) + LicenseeContribution - JackpotPrize - Promotion END) AS LicensingFee,
					0,
					SUM(LicenseeContribution),
					SUM(JackpotPrize),
					SUM((LicenseeWinloss - LicenseeContribution) * ISNULL(cr.Rate, ci.Rate)) AS LicenseeChargeRate,
					ci.IsDeposit,
					SUM(Promotion),
					SUM(HouseTurnover)
			FROM	cte_detail b
			INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
			GROUP BY b.Winlostdate, b.CurrencyId, ci.PartyID, ci.isDeposit
	
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
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		HouseTurnover   MONEY,
		JackpotPrize	MONEY,
		LicenseeContribution MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		IsKeepNegativeAmount BIT,
		LicenseeChargeRate	MONEY ,
		Promotion		MONEY,
		IsDeposit		BIT
	)
	
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, IsKeepNegativeAmount, LicenseeChargeRate, Promotion, JackpotPrize, LicenseeContribution, HouseTurnover, IsDeposit)
	SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, td.CurrencyId, td.TotalTrans, td.Turnover, td.CustomerWinLoss, td.LicenseeWinloss, td.LicensingFee, td.PayToSupplier, p.IsKeepNegativeAmount, td.LicenseeChargeRate, td.Promotion, td.JackpotPrize, td.LicenseeContribution, td.HouseTurnover, td.isDeposit
	FROM #TempData td
		INNER JOIN #PartyList p ON td.PartyId = p.PartyID
		INNER JOIN #PartyList pa ON p.ParentId = pa.PartyId	

	DECLARE @Total TABLE (
		PartyId			INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		HouseTurnover   MONEY,
		JackpotPrize	MONEY,
		LicenseeContribution MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY,
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
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		HouseTurnover   MONEY,
		JackpotPrize	MONEY,
		LicenseeContribution MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)
	
	BEGIN
		WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies)
		BEGIN
			SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies)

			;WITH TotalByParty AS(
				SELECT  CASE WHEN  td.PartyId = 14 THEN 14 ELSE td.ParentId END ParentId, 
						td.PartyId, 
						td.IsKeepNegativeAmount,
						SUM(td.TotalTrans) TotalTrans,
						SUM(td.Turnover * e.BaseCurrencyRate) Turnover,
						SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss,
						SUM(td.LicenseeWinLoss * e.BaseCurrencyRate) LicenseeWinLoss,
						SUM(td.LicensingFee * e.BaseCurrencyRate) LicensingFee,
						SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier,
						SUM(td.LicenseeChargeRate * e.BaseCurrencyRate) LicenseeChargeRate,
						SUM(td.LicenseeContribution * e.BaseCurrencyRate) LicenseeContribution,
						SUM(td.JackpotPrize * e.BaseCurrencyRate) JackpotPrize,
						SUM(td.Promotion * e.BaseCurrencyRate) Promotion,
						SUM(td.HouseTurnover * e.BaseCurrencyRate) HouseTurnover,
						td.IsDeposit
				FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e
				ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
				GROUP BY CASE WHEN  td.PartyId = 14 THEN 14 ELSE td.ParentId END, td.PartyId, td.IsKeepNegativeAmount, td.IsDeposit
			)
			INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome, LicenseeContribution, JackpotPrize, HouseTurnover)
			SELECT @tempCurrency,ParentId,
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinLoss),
				SUM(CASE WHEN  IsDeposit = 0 THEN 0 
					 ELSE CASE WHEN LicenseeChargeRate < 0 AND  @IsConvertNegativeFeeToZero = 1 AND  IsKeepNegativeAmount = 0 THEN 0 ELSE LicenseeChargeRate END + LicenseeContribution - JackpotPrize - Promotion END),
				0,
				SUM(CASE WHEN  IsDeposit = 0 THEN 0 
					ELSE CASE WHEN LicenseeChargeRate < 0 AND  @IsConvertNegativeFeeToZero = 1 AND  IsKeepNegativeAmount = 0 THEN 0 ELSE LicenseeChargeRate END + LicenseeContribution - JackpotPrize - Promotion END),
				SUM(LicenseeContribution),
				SUM(JackpotPrize),
				SUM(HouseTurnover)
			FROM TotalByParty
			GROUP BY ParentId

			INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee, PayToSupplier, CompanyIncome, LicenseeContribution, JackpotPrize, HouseTurnover)
			SELECT Currency,
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinLoss),
				SUM(LicensingFee),
				SUM(PayToSupplier),
				SUM(LicensingFee - PayToSupplier),
				SUM(LicenseeContribution),
				SUM(JackpotPrize),
				SUM(HouseTurnover)
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
			r.WinLossDate,
			e.CurrencyCode AS CurrencyName,
			-- Select by origin currency
			r.TotalTrans,
			r.Turnover AS TurnoverOriginal,
			CAST((r.CustomerWinLoss) AS MONEY) AS CustomerWinLossOriginal,
			CAST((r.LicenseeWinLoss) AS MONEY) AS LicenseeWinLossOriginal,
			CAST((r.HouseTurnover) AS MONEY) AS HouseTurnoverOriginal,
			CAST((r.JackpotPrize) AS MONEY) AS JackpotPrizeOriginal,
			CAST((r.LicenseeContribution) AS MONEY) AS LicenseeContributionOriginal,
			CAST((r.LicensingFee) AS MONEY) AS LicensingFeeOriginal,
			CAST((r.PayToSupplier) AS MONEY) AS PayToSupplierOriginal,
			r.LicensingFee - r.PayToSupplier AS CompanyIncomeOriginal,
			-- Select by base currency
			r.Turnover * e.Rate AS Turnover,
			CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
			CAST((r.LicenseeWinLoss * e.Rate) AS MONEY) AS LicenseeWinLoss,
			CAST((r.HouseTurnover * e.Rate) AS MONEY) AS HouseTurnover,
			CAST((r.JackpotPrize * e.Rate) AS MONEY) AS JackpotPrize,
			CAST((r.LicenseeContribution * e.Rate) AS MONEY) AS LicenseeContribution,
			CAST((r.LicensingFee * e.Rate) AS MONEY) AS LicensingFee,
			CAST((r.PayToSupplier * e.Rate)AS MONEY) AS PayToSupplier,
			CAST(((r.LicensingFee - r.PayToSupplier) * e.Rate)AS MONEY)  AS CompanyIncome
		FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.WinLossDate = e.ExchangeDate

		;WITH totalByParty AS
		(
		SELECT r.PartyId, r.PartyName, r.ParentId,
			SUM(r.TotalTrans) AS TotalTrans,
			SUM(r.Turnover * e.Rate) Turnover,
			SUM(r.CustomerWinLoss * e.Rate) CustomerWinLoss,
			SUM(r.LicenseeWinLoss * e.Rate) LicenseeWinLoss,
			SUM(r.HouseTurnover * e.Rate) HouseTurnover,
			SUM(r.JackpotPrize * e.Rate) JackpotPrize,
			SUM(r.LicenseeContribution * e.Rate) LicenseeContribution,
			SUM(r.LicensingFee * e.Rate) LicensingFee,
			SUM(r.PayToSupplier * e.Rate) PayToSupplier,
			SUM(r.LicenseeChargeRate * e.Rate) LicenseeChargeRate,
			SUM(r.Promotion * e.Rate) Promotion,
			r.IsKeepNegativeAmount,
			r.IsDeposit
		FROM #Result r
			INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND r.WinLossDate = e.ExchangeDate
		GROUP BY r.PartyId, r.PartyName, r.ParentId, r.IsKeepNegativeAmount, r.IsDeposit
		)
		SELECT	PartyId, 
				PartyName, 
				CASE WHEN PartyId = 14 THEN 14 ELSE ParentId END ParentId, 
				TotalTrans, 
				Turnover, 
				CustomerWinLoss, 
				LicenseeWinLoss, 
				HouseTurnover,
				JackpotPrize,
				LicenseeContribution,
				CASE WHEN  IsDeposit = 0 THEN 0  ELSE CASE WHEN LicenseeChargeRate < 0 AND IsKeepNegativeAmount = 0 AND @IsConvertNegativeFeeToZero = 1 THEN 0 ELSE  LicenseeChargeRate  END + LicenseeContribution - JackpotPrize - Promotion END AS  LicensingFee, 
				0 PayToSupplier, 
				CASE WHEN  IsDeposit = 0 THEN 0  ELSE  CASE WHEN LicenseeChargeRate < 0 AND IsKeepNegativeAmount = 0 AND @IsConvertNegativeFeeToZero = 1 THEN 0 ELSE  LicenseeChargeRate  END + LicenseeContribution - JackpotPrize - Promotion END  AS CompanyIncome
		FROM totalByParty
	
		-- Select Grand Total
		SELECT 	CurrencyName,
				TotalTrans		,
				Turnover		,
				CustomerWinLoss	,
				LicenseeWinLoss	,
				HouseTurnover,
				JackpotPrize,
				LicenseeContribution,
				LicensingFee	,
				PayToSupplier	,
				CompanyIncome	 
		FROM @GrandTotal
	
		-- Total
		SELECT 
			PartyId,
			TotalTrans,
			Turnover,
			CustomerWinLoss,
			LicenseeWinLoss,
			HouseTurnover,
			JackpotPrize,
			LicenseeContribution,
			LicensingFee,
			PayToSupplier,
			CompanyIncome
		FROM @Total t
		WHERE Currency = @BaseCurrencyName
	-- End Region
	END


	DROP TABLE	#PartyList
	DROP TABLE	#Exchange
	DROP TABLE	#ChargeRate
	DROP TABLE  #TempData	
	DROP TABLE  #Result
END
GO