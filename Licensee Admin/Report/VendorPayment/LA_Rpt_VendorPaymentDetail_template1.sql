/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
ALTER PROCEDURE [dbo].[LA_Rpt_VendorPaymentDetail_template1]
	@PartyIds			VARCHAR(4000),
	@ProductID			INT,
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20),
	@TimeZoneId			INT
AS
/*
 * Created by : [20220405@Danny]
 * Task  : Vendor Payment Detail (template1 - normal)
 * Revisions
	- 20210615@Danny: Initialize SP [#168387]
	- 20220927@Danny: Remove DBLink [#176986] 
 */

BEGIN
	SET NOCOUNT ON

	DECLARE @IsConvertNegativeFeeToZero BIT, @IsConvertNegativePaytoSupplierToZero BIT
	SELECT @IsConvertNegativeFeeToZero = IsConvertNegativeFeeToZero, @IsConvertNegativePaytoSupplierToZero = IsConvertNegativePaytoSupplierToZero  FROM dbo.LA_VendorPaymentSetting WITH(NOLOCK) WHERE ProductId = @ProductID

	DECLARE @ProductCode VARCHAR(50), @3rdProductCode VARCHAR(50)
	DECLARE @BettypeIdList TABLE (BetTypeId INT)
	DECLARE @3rdRate TABLE(PartyID INT, ProductID INT, DI_Rate MONEY, IsDeposit INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME, MinAmount MONEY DEFAULT 0, MaxAmount MONEY DEFAULT 0, CurrencyId INT)
	
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
		--BTC only
		,Fromdate3rd		SMALLDATETIME
		,Todate3rd			SMALLDATETIME
	)

	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
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
		LicensingFee	MONEY	DEFAULT 0,
		PayToSupplier	MONEY	DEFAULT 0,
		isDeposit		BIT,
		-- AGC
		ApplyValue		MONEY	DEFAULT 0
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
		DECLARE	@CN88PartyId	INT = (SELECT a.PartyID FROM dbo.OAS_Party a WITH(NOLOCK) WHERE a.PartyName='CN88'),
				@TianboPartyId	INT = 432,
				@BobbetPartyId	INT = 346
		-- Get 3rd Rate
		INSERT INTO @3rdRate (PartyID, ProductID, DI_Rate, IsDeposit, Fromdate, Todate)
		SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.IsDeposit, r.Fromdate, r.Todate 
		FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, @3rdProductCode, 'OA') r 
		INNER JOIN #PartyList p on p.ParentId = r.PartyID
	
		-- ​#ChargeRate
		INSERT INTO #ChargeRate (ChargeID, PartyID, LicenseeID, isDeposit, ProductID, Rate, Rate3rd, Fromdate, Todate, Fromdate3rd, Todate3rd)
		SELECT DISTINCT c.ChargeID, 
						c.PartyID, 
						c.LicenseeID, 
						c.isDeposit, 
						c.ProductID, 
						CASE WHEN c.IsDeposit = 0 THEN 0 ELSE c.DI_Rate END AS Rate, 
						-- Rate3rd
						CASE WHEN c.ProductID = 27 AND c.isDeposit = 0 THEN 0.01
							 WHEN c.ProductID = 40 THEN CASE WHEN @FromDate >= CAST('2020-07-01' AS DATETIME) THEN  CASE WHEN c.PartyID IN (@TianboPartyId, @BobbetPartyId) THEN 0.02 ELSE 0.036  END ELSE ISNULL(r.DI_Rate,0) END
							 WHEN c.ProductID = 8 THEN CASE 
															WHEN c.PartyId = @CN88PartyId THEN 0.015
															WHEN c.PartyId IN (@TianboPartyId, @BobbetPartyId) THEN 0.02
															WHEN @FromDate >= CAST('2020-07-01' AS DATETIME) THEN 0.036
															WHEN c.PartyId = 14 OR  c.isDeposit = 0 OR @FromDate >= CAST('2018-8-1' AS DATETIME) THEN 0.03 
															ELSE 0.05 END 		
						     WHEN c.ProductID = 28 THEN CASE WHEN c.isDeposit = 1 THEN 
																					 CASE WHEN @FromDate >= CAST('2020-07-01' AS DATETIME) THEN  CASE WHEN c.PartyID IN (@TianboPartyId, @BobbetPartyId) THEN 0.02 ELSE 0.036  END 
																						  WHEN c.PartyId = 14 OR @FromDate >= CAST('2018-8-1' AS DATETIME) THEN 0.03 
																					 ELSE 0.05 END
															WHEN c.isDeposit = 0 THEN  CASE WHEN c.PartyId = @CN88PartyId THEN 0.015
																							WHEN @FromDate >= CAST('2020-07-01' AS DATETIME) THEN 0.036 ELSE 0.03 END
															END		
							ELSE ISNULL(r.DI_Rate,0) END AS Rate3rd, 
						c.Fromdate, 
						c.Todate,
						CASE WHEN r.ProductID = 69 THEN r.Fromdate END,
						CASE WHEN r.ProductID = 69 THEN r.ToDate END
		FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate,@ProductCode) c
		LEFT JOIN @3rdRate r ON r.PartyID = c.PartyID AND (r.ProductID = c.ProductID OR @ProductCode <> @3rdProductCode)
		WHERE (c.isDeposit = 0 AND (c.DI_Rate = 0 OR c.ProductID IN (24,0))) OR (c.DI_Rate > 0 and c.isDeposit = 1)

	END
	
	-- Region: TempData 
	IF @TimeZoneId = 1 --GMT -4
	BEGIN
		INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,isDeposit)
		SELECT ci.PartyId,
			b.rptDate		  AS Winlostdate,
			b.CurrencyId,
			SUM(b.Turnover)   AS Turnover,
			SUM(b.BetCount)	  AS TotalTrans,
			SUM(b.MemberWL)	  AS CustomerWinLoss,
			SUM(-b.MemberWL)  AS LicenseeWinloss,
			SUM(-b.MemberWL * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
			SUM(-b.MemberWL * CASE WHEN ci.ProductID = 0 THEN ISNULL(ci_3rd.Rate3rd, 0) ELSE  ISNULL(ci.Rate3rd, 0) END) AS PayToSupplier,
			ci.isDeposit
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN #ChargeRate ci_3rd ON b.SiteID = ci_3rd.LicenseeId AND b.rptDate BETWEEN ci_3rd.Fromdate3rd AND ci_3rd.Todate3rd AND ci_3rd.ProductID = 0
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate 
			AND b.StatusId NOT IN (-1, 101, 102, 103) 
			AND b.CurrencyId <> 20 
			AND b.CustomerCategory NOT IN (27,28)
			AND b.ProductID = @ProductID
		GROUP BY b.rptDate, ci.PartyId, b.CurrencyId, ci.isDeposit
	
	END
	ELSE -- Another timezone
	BEGIN
	
		INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,isDeposit)
		SELECT ci.PartyId,
			b.rptDate3rd		  AS Winlostdate,
			b.CurrencyId,
			SUM(b.Turnover)   AS Turnover,
			SUM(b.BetCount)	  AS TotalTrans,
			SUM(b.Winloss)	  AS CustomerWinLoss,
			SUM(-b.Winloss)  AS LicenseeWinloss,
			SUM(-b.Winloss * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
			SUM(-b.Winloss * CASE WHEN ci.ProductID = 0 THEN ISNULL(ci_3rd.Rate3rd, 0) ELSE  ISNULL(ci.Rate3rd, 0) END)	AS PayToSupplier,
			ci.isDeposit
		FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.rptDate3rd BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN #ChargeRate ci_3rd ON b.SiteID = ci_3rd.LicenseeId AND b.rptDate3rd BETWEEN ci_3rd.Fromdate3rd AND ci_3rd.Todate3rd AND ci_3rd.ProductID = 0
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
		WHERE b.RptDate BETWEEN DATEADD(DAY, -1, @FromDate) AND DATEADD(DAY, 1, @ToDate)
			AND b.rptDate3rd BETWEEN @FromDate AND @ToDate 
			AND b.StatusId NOT IN (-1, 101, 102, 103) 
			AND b.CurrencyId <> 20 
			AND b.BetTypeId IN (SELECT x.BetTypeId FROM @BettypeIdList x)
		GROUP BY b.rptDate3rd, ci.PartyId, b.CurrencyId, ci.isDeposit
	
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
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		IsKeepNegativeAmount BIT
	)
	
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, IsKeepNegativeAmount)
	SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, td.CurrencyId, td.TotalTrans, td.Turnover, td.CustomerWinLoss, td.LicenseeWinloss, td.LicensingFee, td.PayToSupplier, p.IsKeepNegativeAmount
	FROM #TempData td
		INNER JOIN #PartyList p ON td.PartyId = p.PartyID
		INNER JOIN #PartyList pa ON p.ParentId = pa.PartyId	

	DECLARE @Total TABLE (
		PartyId			INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
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
						SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier
				FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e
				ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
				GROUP BY CASE WHEN  td.PartyId = 14 THEN 14 ELSE td.ParentId END, td.PartyId, td.IsKeepNegativeAmount
			)
			INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome)
			SELECT @tempCurrency,ParentId,
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinLoss),
				SUM(CASE WHEN LicensingFee < 0 AND  @IsConvertNegativeFeeToZero = 1 AND  IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END),
				SUM(CASE WHEN PayToSupplier < 0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END),
				SUM(CASE WHEN LicensingFee < 0 AND @IsConvertNegativeFeeToZero = 1 AND  IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END - CASE WHEN PayToSupplier < 0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END)
			FROM TotalByParty
			GROUP BY ParentId

			INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee, PayToSupplier, CompanyIncome)
			SELECT Currency,
				SUM(TotalTrans),
				SUM(Turnover),
				SUM(CustomerWinLoss),
				SUM(LicenseeWinLoss),
				SUM(LicensingFee),
				SUM(PayToSupplier),
				SUM(LicensingFee - PayToSupplier)
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
			CAST((r.LicensingFee) AS MONEY) AS LicensingFeeOriginal,
			CAST((r.PayToSupplier) AS MONEY) AS PayToSupplierOriginal,
			r.LicensingFee - r.PayToSupplier AS CompanyIncomeOriginal,
			-- Select by base currency
			r.Turnover * e.Rate AS Turnover,
			CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
			CAST((r.LicenseeWinLoss * e.Rate) AS MONEY) AS LicenseeWinLoss,
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
			SUM(r.LicensingFee * e.Rate) LicensingFee,
			SUM(r.PayToSupplier * e.Rate) PayToSupplier,
			r.IsKeepNegativeAmount
		FROM #Result r
			INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeId AND r.WinLossDate = e.ExchangeDate
		GROUP BY r.PartyId, r.PartyName, r.ParentId, r.IsKeepNegativeAmount
		)
		SELECT	PartyId, 
				PartyName, 
				CASE WHEN PartyId = 14 THEN 14 ELSE ParentId END ParentId, 
				TotalTrans, 
				Turnover, 
				CustomerWinLoss, 
				LicenseeWinLoss, 
				CASE WHEN LicensingFee < 0 AND IsKeepNegativeAmount = 0 AND @IsConvertNegativeFeeToZero = 1 THEN 0 ELSE  LicensingFee END LicensingFee, 
				CASE WHEN PayToSupplier <0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END PayToSupplier, 
				CASE WHEN LicensingFee < 0 AND IsKeepNegativeAmount = 0 AND @IsConvertNegativeFeeToZero = 1 THEN 0 ELSE  LicensingFee END - CASE WHEN PayToSupplier <0 AND @IsConvertNegativePaytoSupplierToZero = 1 THEN 0 ELSE PayToSupplier END  AS CompanyIncome
		FROM totalByParty
	
		-- Select Grand Total
		SELECT 	CurrencyName,
				TotalTrans		,
				Turnover		,
				CustomerWinLoss	,
				LicenseeWinLoss	,
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