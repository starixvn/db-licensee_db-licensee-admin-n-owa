/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_CardClubWinloss]
	@PartyIds			VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20)
AS
/*
 * Created by : [20190710@Mason.Nguyen]
 * Task  : Get Card Club Winloss
 * Revisions
	- 20190710@Mason: Intergrate Card Club [#116096]
	- 20191226@Mason: Set Billing Term By Currency [#120005]
	- 20200302@Mason: Support HID currency [#128856]
	- 20200311@Mason: Spadegaming Integration [#123959]
	- 20200312@Parsons: Add new bet type for Card club [#129061]
	- 20200409@Mason: Integrate SA Gaming [#129276]
	- 20200422@Parsons: Add new bet type for Card club [#132715]
 * Param's Explanation:
 *
 */

BEGIN
	SET NOCOUNT ON

	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT)
	INSERT INTO #PartyList EXEC LA_PartyListSel
	
	-- Get 3rd Rate
	DECLARE @3rdRate AS TABLE(PartyID INT, ProductID INT, DI_Rate MONEY, IsDeposit INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME)
	INSERT INTO @3rdRate
	SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.IsDeposit, r.Fromdate, r.Todate 
	FROM LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'CC', 'OA') r 
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
	
	-- ​Pay to Supplier: equals 2.5%(0.025) of [Licensing Fee] -- Join Charge rate and 3rd Rate
	INSERT INTO #ChargeRate
	SELECT  c.ChargeID, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate AS Rate, r.DI_Rate AS Rate3rd, c.Fromdate, c.Todate
	FROM LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, 'CC') c
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
		PayToSupplier MONEY)
	/*
	  For normal tickets ( not Midas's tickets): Licensee WL x 2.5%
	  For Midas's tickets: Licensee WL x 3.5%
	*/
	DECLARE @TaiXiu_BettypeId INT = 1902, @XocDia_BettypeId INT = 1903, @Lotto3_BettypeId INT = 1904, @HiLo_BettypeId INT = 1905, @MidasRate3rd DECIMAL(4,3) = 0.035
	
	INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee, PayToSupplier)
	SELECT ci.PartyId,
		b.rptDate as Winlostdate,
		b.CurrencyId,
		SUM(b.Turnover) AS Turnover,
		SUM(b.BetCount) AS TotalTrans,
		SUM(b.WinLoss) AS CustomerWinLoss,
		- SUM(b.WinLoss) AS LicenseeWinloss,
		- SUM(CASE WHEN ci.isDeposit = 1 THEN (b.WinLoss * ISNULL(cr.Rate, ci.Rate))
				ELSE (b.WinLoss + b.WinLossA + WinLossM + WinLossS + b.CommissionS) END) AS LicensingFee,
		- SUM(b.WinLoss * (CASE WHEN b.Bettype IN (@TaiXiu_BettypeId, @XocDia_BettypeId, @Lotto3_BettypeId, @HiLo_BettypeId) THEN @MidasRate3rd ELSE ci.Rate3rd END)) AS PayToSupplier
	FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH (NOLOCK)
		INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
		LEFT JOIN LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeId = ci.ChargeId AND cr.CurrencyId = b.CurrencyId 
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
		b.Status NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 AND b.CustomerCategory NOT IN (27,28)
		AND b.Bettype in (Select Bettype FROM LA_f_BettypeProductMapping(0,'CC'))
	GROUP BY b.rptDate, ci.PartyId, b.CurrencyId
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
		PayToSupplier	MONEY
	)
	
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier)
	SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, td.CurrencyId, td.TotalTrans, td.Turnover, td.CustomerWinLoss, td.LicenseeWinloss, td.LicensingFee, td.PayToSupplier
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
	EXEC LA_SelBaseCurrency

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
				SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier
			FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e
			ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
			GROUP BY td.ParentId, td.PartyId
		)
		INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier)
		SELECT @tempCurrency,ParentId,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(CASE WHEN LicensingFee < 0 THEN 0 ELSE LicensingFee END),
			SUM(PayToSupplier)
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
		r.ParentId,
		r.ParentName,
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
		CAST((r.LicensingFee - r.PayToSupplier) * e.Rate AS MONEY) AS CompanyIncome
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
		(LicensingFee - PayToSupplier) AS CompanyIncome
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