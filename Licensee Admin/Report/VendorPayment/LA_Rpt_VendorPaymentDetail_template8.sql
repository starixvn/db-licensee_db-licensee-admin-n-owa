/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" viewers="" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[LA_Rpt_VendorPaymentDetail_template8]
	@PartyIds			VARCHAR(MAX)
	,@ProductID			INT
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@BaseCurrencyName	VARCHAR(20)
	,@TimeZoneId		INT
	,@PlatformId		TINYINT = 0
AS
/*
 * Created by : [20220405@Danny]
 * Task  : Vendor Payment Detail (template6 - for Arcada Gaming product, including some specific info such as: Promotion)
 * Revisions
	- 20210622@Danny: Initialize SP [#168387]
	- 20221003@Malcolm: Add platform filter [RedmineID: #165707]
	- 20220227@Danny: Incorporate USDTJP currency [RedmineID: #183461]
	- 20240924@Danny: exclude BTS currency [RedmineID: #210422]
	- 20241016@Danny: Extend parameter data length [RemineID: #212252]
 */

BEGIN
	SET NOCOUNT ON
	-- CC, SXG
	DECLARE @ProductCode VARCHAR(50)
	SELECT @ProductCode = ProductPrefix
	FROM dbo.Product3rd WITH(NOLOCK) WHERE Productid = @ProductID

	IF ISNULL(@PlatformId, 0) <> 0
	BEGIN
		SELECT @PartyIds = ISNULL(STRING_AGG(CONVERT(VARCHAR(50), p.PartyID), ','), '')
		FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
			INNER JOIN bodb_licensee.dbo.Licensees la WITH(NOLOCK) ON p.OldRefID = la.LicenseeID
		    INNER JOIN DBOIC.bodb_OIC.dbo.Licensee l WITH(NOLOCK) ON l.RegisteredLicenseeName = la.LicenseeName AND l.PlatformId = @PlatformId
		WHERE p.PartyID IN (SELECT value FROM STRING_SPLIT(@PartyIds, ',')) 
	END

	DECLARE @BonusBettype TABLE (bettype INT, ProductID INT)
	INSERT INTO @BonusBettype (bettype, ProductID)
	SELECT Bettype, ProductId FROM LA_f_GroupBettype()
	WHERE TypeID IN (5, 6) -- Lucky Draw, Bonus

	DECLARE @bettypeList TABLE (BettypeId INT, SubProduct VARCHAR(500))

	INSERT INTO @bettypeList (BettypeId, SubProduct)
	SELECT DISTINCT la.Bettype as BettypeId, ma.SubProduct
	FROM LA_f_BettypeProductMapping(0,@ProductCode) la
	INNER JOIN bodb02.dbo.SportBettypeMatrix ma (NOLOCK) ON la.Bettype = ma.BetType 

	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT, IsKeepNegativeAmount BIT DEFAULT 0)
	INSERT INTO #PartyList(PartyId, PartyName, BrandName, ParentId) EXEC LA_PartyListSel

	UPDATE #PartyList SET PartyName = REPLACE(PartyName,' Licensees','') WHERE ParentId = 0

	UPDATE t 
	SET t.IsKeepNegativeAmount = CASE WHEN u.PartyId IS NULL THEN 0 ELSE 1 END 
	FROM #PartyList t 
	LEFT JOIN bodb_Licensee.dbo.LA_f_JVPartyListSel() u ON u.PartyId = t.PartyId
	
	-- Get 3rd Rate
	DECLARE @3rdRate AS TABLE(PartyID INT, ProductID INT, DI_Rate MONEY, IsDeposit INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME)
	INSERT INTO @3rdRate (PartyID, ProductID, DI_Rate, IsDeposit, Fromdate, Todate)
	SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.IsDeposit, r.Fromdate, r.Todate 
	FROM LA_f_ChargeInfo3rd(@FromDate, @ToDate, @ProductCode, 'OA') r 
	INNER JOIN #PartyList p on p.ParentId = r.PartyID

	CREATE TABLE #ChargeRate (
		ChargeId		INT
		,PartyID		INT
		,LicenseeID		INT
		,isDeposit		INT
		,ProductID		INT
		,Rate			MONEY
		,Rate3rd		MONEY
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
	)
	
	INSERT INTO #ChargeRate (ChargeId, PartyID, LicenseeID, isDeposit, ProductID, Rate, Rate3rd, Fromdate, Todate)
	SELECT  c.ChargeID, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate AS Rate, r.DI_Rate AS Rate3rd, c.Fromdate, c.Todate
	FROM LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate,@ProductCode) c
	INNER JOIN @3rdRate r ON r.PartyID = c.PartyID and r.ProductID = c.ProductID
	WHERE (c.DI_Rate = 0 AND c.isDeposit = 0) OR (c.DI_Rate > 0 and c.isDeposit = 1)

	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(65),
		Rate			FLOAT
	)
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate, CurrencyCode)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate, CASE WHEN ExchangeID = 51 THEN 'INH' 
															WHEN ExchangeID = 92 THEN 'HID' 
															ELSE Code END
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
		Promotion MONEY)

	BEGIN
		/*
		  For normal tickets ( not Midas's tickets): Licensee WL x 2.5%
		  For Midas's tickets: Licensee WL x 3.5%
		*/
		DECLARE @MidasRate3rd DECIMAL(4,3) = 0.035
		;WITH cte_Summary AS(
			SELECT b.SiteID,
				b.Bettype,
				bt.SubProduct,
				b.rptDate AS Winlostdate,
				b.CurrencyId AS CurrencyId,
				SUM(b.Turnover) AS Turnover,
				SUM(CASE WHEN bt.SubProduct = 'Bonus' THEN 0 ELSE b.BetCount END) AS TotalTrans,
				SUM(CASE WHEN bt.SubProduct = 'Bonus' THEN 0 ELSE b.WinLoss END) AS CustomerWinLoss,
				SUM(CASE WHEN bt.SubProduct = 'Bonus' THEN b.WinLoss ELSE 0 END) AS Promotion
			FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
			INNER JOIN @bettypeList bt ON bt.BettypeId = b.Bettype
			WHERE b.rptDate BETWEEN @FromDate AND @ToDate 
				AND b.Status NOT IN (-1, 101, 102, 103) AND b.CurrencyId NOT IN ( SELECT x.ExchangeID FROM LA_f_ExcludedCurrencyListSel() x)
				AND b.CustomerCategory NOT IN (27,28)
			GROUP BY b.rptDate, b.CurrencyId, b.SiteID, b.Bettype, bt.SubProduct
		)
		INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier,Promotion)
		SELECT ci.PartyID,
			s.Winlostdate,
			s.CurrencyId,
			SUM(Turnover),
			SUM(TotalTrans),
			SUM(CustomerWinLoss),
			- SUM(CustomerWinLoss) AS LicenseeWinLoss,
			SUM(CASE WHEN ci.isDeposit = 1 THEN (-s.CustomerWinLoss  * ISNULL(cr.Rate, ci.Rate)) ELSE 0 END) AS LicensingFee,
			SUM(-CustomerWinLoss * (CASE WHEN s.SubProduct = 'Mini Game' THEN @MidasRate3rd ELSE ci.Rate3rd END) - s.Promotion),
			SUM(s.Promotion) AS Promotion
		FROM cte_Summary s INNER JOIN #ChargeRate ci ON s.SiteID = ci.LicenseeId AND Winlostdate BETWEEN ci.FromDate AND ci.ToDate
		LEFT JOIN LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeId = ci.ChargeId AND cr.CurrencyId = s.CurrencyId
		GROUP By s.Winlostdate, s.CurrencyID, ci.PartyID
	END
	-- EndRegion
	
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
		Promotion		MONEY,
		IsKeepNegativeAmount BIT
	)
	
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier, Promotion, IsKeepNegativeAmount)
	SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, td.CurrencyId, td.TotalTrans, td.Turnover, td.CustomerWinLoss, td.LicenseeWinloss, td.LicensingFee, td.PayToSupplier, td.Promotion, p.IsKeepNegativeAmount
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
	EXEC LA_SelBaseCurrency

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
			SELECT CASE WHEN td.PartyID = 14 THEN 14 ELSE td.ParentId END ParentId, td.IsKeepNegativeAmount,
				SUM(td.TotalTrans) TotalTrans,
				SUM(td.Turnover * e.BaseCurrencyRate) Turnover,
				SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss,
				SUM(td.LicenseeWinLoss * e.BaseCurrencyRate) LicenseeWinLoss,
				SUM(td.LicensingFee * e.BaseCurrencyRate) LicensingFee,
				SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier,
				SUM(td.Promotion * e.BaseCurrencyRate) Promotion
			FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e
			ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
			GROUP BY CASE WHEN td.PartyID = 14 THEN 14 ELSE td.ParentId END , td.PartyId, td.IsKeepNegativeAmount
		)
		INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,Promotion)
		SELECT @tempCurrency,ParentId,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(CASE WHEN LicensingFee < 0 AND IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END - Promotion),
			SUM(PayToSupplier),
			SUM(Promotion)
		FROM TotalByParty
		GROUP BY ParentId
		
		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee, PayToSupplier, CompanyIncome,Promotion)
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
		CASE WHEN r.PartyId = 14 THEN 14 ELSE r.ParentId END ParentId,
		CASE WHEN r.PartyId = 14 THEN '12Bet' ELSE r.ParentName END ParentName,
		r.WinLossDate,
		e.CurrencyCode AS CurrencyName,
		-- Select by origin currency
		r.TotalTrans,
		r.Turnover AS TurnoverOriginal,
		CAST((r.CustomerWinLoss) AS MONEY) AS CustomerWinLossOriginal,
		CAST((r.LicenseeWinLoss) AS MONEY) AS LicenseeWinLossOriginal,
		CAST((r.LicensingFee) AS MONEY) AS AmountWithoutPromotionOriginal,
		CAST((r.PayToSupplier) AS MONEY) AS PayToSupplierOriginal,
		CAST((r.Promotion) AS MONEY) AS PromotionOriginal,
		-- Select by base currency
		r.Turnover * e.Rate AS Turnover,
		CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
		CAST((r.LicenseeWinLoss * e.Rate) AS MONEY) AS LicenseeWinLoss,
		CAST((r.LicensingFee * e.Rate) AS MONEY) AS AmountWithoutPromotion,
		CAST((r.PayToSupplier * e.Rate)AS MONEY) AS PayToSupplier,
		CAST((r.Promotion * e.Rate)AS MONEY) AS Promotion
	FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.WinLossDate = e.ExchangeDate
	
	;WITH TotalByParty AS(
			SELECT td.ParentId , td.PartyId, td.PartyName, td.IsKeepNegativeAmount,
				SUM(td.TotalTrans) TotalTrans,
				SUM(td.Turnover * e.Rate) Turnover,
				SUM(td.CustomerWinLoss * e.Rate) CustomerWinLoss,
				SUM(td.LicenseeWinLoss * e.Rate) LicenseeWinLoss,
				SUM(td.LicensingFee * e.Rate) LicensingFee,
				SUM(td.PayToSupplier * e.Rate) PayToSupplier,
				SUM(td.Promotion * e.Rate) Promotion
			FROM #Result td INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND td.WinLossDate = e.ExchangeDate
			GROUP BY td.ParentId , td.PartyId, td.PartyName, td.IsKeepNegativeAmount
		)
	SELECT CASE WHEN PartyId = 14 THEN 14 ELSE ParentId END ParentId,
		PartyId,
		PartyName,
		TotalTrans,
		Turnover,
		CustomerWinLoss,
		LicenseeWinLoss,
		CASE WHEN LicensingFee < 0 AND IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END - Promotion AS  LicensingFee,
		PayToSupplier,
		CASE WHEN LicensingFee < 0 AND IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END - Promotion - PayToSupplier AS CompanyIncome,
		Promotion
	FROM TotalByParty

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
		(LicensingFee - PayToSupplier) AS CompanyIncome,
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
