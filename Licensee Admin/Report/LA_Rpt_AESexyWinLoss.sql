/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_AESexyWinLoss]
	@PartyIds			VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20),
	@Timezone			INT
AS
/*
 * Created by : [20200325@Mason.Nguyen]
 * Task  : Get AESexy Winloss
 * Revisions
	- 20200325@Mason: Intergrate SexyGaming [#130948]
	- 20200409@Mason: Integrate SA Gaming [#129276]
	- 20200508@Parsons: Integrate Sexy Gaming for deposit licensees [#132665] 
	- 20200910@Parsons: Provide timezone filter for Sexy Gaming report [#138248]
	- 20210422@Mason: Change product name into AE Sexy
	- 20210609@Danny: Add Promotion Info [#152141]
 * Param's Explanation:
 *				@Timezone: = 1: GMT-4
						   = 2: GMT+8	
 */

BEGIN
	SET NOCOUNT ON

	DECLARE @LuclyDrawBettype SMALLINT = 3150

	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT)
	INSERT INTO #PartyList EXEC dbo.LA_PartyListSel
	
	-- Get 3rd Rate
	DECLARE @3rdRate AS TABLE(PartyID INT, ProductID INT, DI_Rate MONEY, IsDeposit INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME)
	INSERT INTO @3rdRate
	SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.IsDeposit, r.Fromdate, r.Todate 
	FROM dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'SXG', 'OA') r 
	INNER JOIN #PartyList p on p.ParentId = r.PartyID

	CREATE TABLE #ChargeRate (
		ChargeID		INT
		,PartyID		INT
		,LicenseeID		INT
		,isDeposit		INT
		,ProductID		INT
		,Rate			MONEY
		,Rate3rd		MONEY
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
	)
	
	-- ​Pay to Supplier: equals 3% of [Licensee Win Loss]
	INSERT INTO #ChargeRate
	SELECT DISTINCT c.ChargeID, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate AS Rate, r.DI_Rate AS Rate3rd, c.Fromdate, c.Todate
	FROM LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, 'SXG') c
	INNER JOIN @3rdRate r ON r.PartyID = c.PartyID and r.ProductID = c.ProductID
	WHERE (c.DI_Rate = 0 AND c.isDeposit = 0) OR (c.DI_Rate > 0 and c.isDeposit = 1)

	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate, CurrencyCode)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate, CASE WHEN ExchangeID = 51 THEN 'INH'
															WHEN ExchangeID = 92 THEN 'HID' 
															ELSE Code 
														END
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	-- Region: TempData
	CREATE TABLE #TempData (
		PartyID INT,
		PartyName NVARCHAR(100),
		ParentId INT,
		ParentName NVARCHAR(100),
		Winlostdate DATETIME,
		CurrencyId INT,
		Turnover MONEY,
		TotalTrans INT,
		CustomerWinLoss MONEY,
		LicenseeWinloss MONEY,
		LicensingFee MONEY,
		PayToSupplier MONEY,
		Promotion MONEY
		)

	-- Calculate for desposit & credit
	IF(@Timezone = 2) --GMT+8
	BEGIN
		;WITH cte_Summary AS(
			SELECT
				b.SiteID,
				b.RptDate3rd  AS Winlostdate,
				b.CurrencyId,
				SUM(b.Turnover) AS Turnover,
				SUM(CASE WHEN b.BetTypeId = @LuclyDrawBettype THEN 0 ELSE b.BetCount END) AS TotalTrans,
				SUM(CASE WHEN b.BetTypeId = @LuclyDrawBettype THEN 0 ELSE b.Winloss END) AS CustomerWinLoss,
				SUM(CASE WHEN b.BetTypeId = @LuclyDrawBettype THEN b.Winloss ELSE 0 END) Promotion
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
				INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
			WHERE b.RptDate3rd BETWEEN @FromDate AND @ToDate
				AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 
				AND b.BetTypeId BETWEEN 3101 AND 3150
			GROUP BY b.SiteID, b.RptDate3rd, b.CurrencyId
		)
		INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,Promotion)
		SELECT ci.PartyId,
			b.Winlostdate,
			b.CurrencyId,
			SUM(b.Turnover) AS Turnover,
			SUM(b.TotalTrans) AS TotalTrans,
			SUM(b.CustomerWinLoss) AS CustomerWinLoss,
			-SUM(b.CustomerWinLoss) AS LicenseeWinloss,
			SUM(-b.CustomerWinLoss  * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
			SUM((-b.CustomerWinLoss * ISNULL(ci.Rate3rd, 0)) -  b.Promotion) AS PayToSupplier,
			SUM(b.Promotion) Promotion
		FROM cte_Summary b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
		GROUP BY b.Winlostdate, ci.PartyId, b.CurrencyId
	END
	ELSE --GMT-4
	BEGIN
		;WITH cte_Summary AS(
			SELECT
				b.SiteID,
				b.rptDate  AS Winlostdate,
				b.CurrencyId,
				SUM(b.Turnover) AS Turnover,
				SUM(CASE WHEN b.BetType = @LuclyDrawBettype THEN 0 ELSE b.BetCount END) AS TotalTrans,
				SUM(CASE WHEN b.BetType = @LuclyDrawBettype THEN 0 ELSE b.MemberWL END) AS CustomerWinLoss,
				SUM(CASE WHEN b.BetType = @LuclyDrawBettype THEN b.MemberWL ELSE 0 END) Promotion
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate
				AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 
				AND b.BetType BETWEEN 3101 AND 3150
			GROUP BY b.SiteID, b.rptDate, b.CurrencyId
		)
		INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,Promotion)
		SELECT ci.PartyId,
			b.Winlostdate,
			b.CurrencyId,
			SUM(b.Turnover) AS Turnover,
			SUM(b.TotalTrans) AS TotalTrans,
			SUM(b.CustomerWinLoss) AS CustomerWinLoss,
			-SUM(b.CustomerWinLoss) AS LicenseeWinloss,
			SUM(-b.CustomerWinLoss  * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
			SUM((-b.CustomerWinLoss * ISNULL(ci.Rate3rd, 0)) -  b.Promotion) AS PayToSupplier,
			SUM(b.Promotion) Promotion
		FROM cte_Summary b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
		GROUP BY b.Winlostdate, ci.PartyId, b.CurrencyId

	END
	-- End region

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
		Promotion		MONEY
	)
	
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, Promotion)
	SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, td.CurrencyId, td.TotalTrans, td.Turnover, td.CustomerWinLoss, td.LicenseeWinloss, td.LicensingFee, td.PayToSupplier, td.Promotion
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
		Currency		VARCHAR(20),
		Promotion		MONEY
	)

	-- Region: Calculate Grand Total
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20)
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC dbo.LA_SelBaseCurrency

	DECLARE @GrandTotal TABLE (
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY,
		Promotion		MONEY
	)
	
	WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies)

		;WITH TotalByParty AS(
			SELECT td.ParentId,
				SUM(td.TotalTrans) TotalTrans,
				SUM(td.Turnover * e.BaseCurrencyRate) Turnover,
				SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss,
				SUM(td.LicenseeWinLoss * e.BaseCurrencyRate) LicenseeWinLoss,
				SUM(td.LicensingFee * e.BaseCurrencyRate) LicensingFee,
				SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier,
				SUM(td.Promotion * e.BaseCurrencyRate) Promotion
			FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e
			ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
			GROUP BY td.ParentId, td.PartyId
		)
		INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome, Promotion)
		SELECT @tempCurrency,ParentId,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(CASE WHEN LicensingFee < 0 THEN 0 ELSE LicensingFee END - Promotion),
			SUM(PayToSupplier),
			SUM(CASE WHEN LicensingFee < 0 THEN 0 ELSE LicensingFee END - PayToSupplier),
			SUM(Promotion)
		FROM TotalByParty
		GROUP BY ParentId
		
		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee, PayToSupplier, CompanyIncome, Promotion)
		SELECT Currency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(LicensingFee),
			SUM(PayToSupplier),
			SUM(LicensingFee - PayToSupplier),
			SUM(Promotion)
		FROM @Total
		WHERE Currency = @tempCurrency
		GROUP BY Currency

		DELETE @BaseCurrencies WHERE [Name] = @tempCurrency
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
		CAST((r.CustomerWinLoss) AS MONEY) AS CustomerWinLossOriginal,
		CAST((r.LicenseeWinLoss) AS MONEY) AS LicenseeWinLossOriginal,
		CAST((r.LicensingFee) AS MONEY) AS AmountWithoutPromotionOriginal,
		CAST((r.LicensingFee) AS MONEY) AS LicensingFeeOriginal,
		CAST((r.PayToSupplier) AS MONEY) AS PayToSupplierOriginal,
		r.LicensingFee - r.PayToSupplier AS CompanyIncomeOriginal,
		r.Promotion AS PromotionOriginal,
		-- Select by base currency
		r.Turnover * e.Rate AS Turnover,
		CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
		CAST((r.LicenseeWinLoss * e.Rate) AS MONEY) AS LicenseeWinLoss,
		CAST((r.LicensingFee * e.Rate) AS MONEY) AS AmountWithoutPromotion,
		CAST((r.LicensingFee * e.Rate) AS MONEY) AS LicensingFee,
		CAST((r.PayToSupplier * e.Rate)AS MONEY) AS PayToSupplier,
		CAST((r.LicensingFee - r.PayToSupplier) * e.Rate AS MONEY) AS CompanyIncome,
		CAST((r.Promotion * e.Rate)AS MONEY) AS Promotion
	FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.WinLossDate = e.ExchangeDate
	
	-- Select Grand Total
	SELECT * FROM @GrandTotal
	
	-- Total
	SELECT 
		PartyId,
		TotalTrans,
		Turnover,
		CustomerWinLoss,
		LicenseeWinLoss,
		LicensingFee,
		PayToSupplier,
		CompanyIncome,
		Promotion
	FROM @Total t
	WHERE Currency = @BaseCurrencyName
	-- End Region
	
	DROP TABLE	#PartyList
	DROP TABLE	#Exchange
	DROP TABLE	#ChargeRate
	DROP TABLE  #TempData	
	DROP TABLE  #Result
END
GO