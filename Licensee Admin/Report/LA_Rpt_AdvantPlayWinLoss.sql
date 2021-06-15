/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

CREATE PROCEDURE [dbo].[LA_Rpt_AdvantPlayWinLoss]
	@PartyIds			VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20),
	@Timezone			INT
AS
/*
 * Created by : [20210615@Danny]
 * Task  : Get Advant Play Winloss
 * Revisions
	- 20210615@Danny: Initialize SP [#154787]
	
 * Param's Explanation:
 *		@Timezone: = 1: GMT-4
 *				   = 2: GMT+8	 
 */

BEGIN
	SET NOCOUNT ON

	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT)
	INSERT INTO #PartyList EXEC bodb_licensee.dbo.LA_PartyListSel
	
	-- Get 3rd Rate
	DECLARE @3rdRate AS TABLE(PartyID INT, ProductID INT, DI_Rate MONEY, IsDeposit INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME)
	INSERT INTO @3rdRate
	SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.IsDeposit, r.Fromdate, r.Todate 
	FROM bodb_licensee.dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'AP', 'OA') r 
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
	
	-- ​Pay to Supplier: equals 5% (0.05) of [Licensee Win Loss]
	INSERT INTO #ChargeRate
	SELECT DISTINCT c.ChargeID, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate AS Rate, r.DI_Rate AS Rate3rd, c.Fromdate, c.Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, 'AP') c
	INNER JOIN @3rdRate r ON r.PartyID = c.PartyID and r.ProductID = c.ProductID
	WHERE (c.DI_Rate = 0 AND c.isDeposit = 0) OR (c.DI_Rate > 0 and c.isDeposit = 1)

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

	-- Calculate for desposit & credit
	
	--GMT -4
	INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier)
	SELECT ci.PartyId,
		b.rptDate		  AS Winlostdate,
		b.CurrencyId,
		SUM(b.Turnover)   AS Turnover,
		SUM(b.BetCount)	  AS TotalTrans,
		SUM(b.MemberWL)	  AS CustomerWinLoss,
		SUM(-b.MemberWL)  AS LicenseeWinloss,
		SUM(-b.MemberWL * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
		SUM(-b.MemberWL * ISNULL(ci.Rate3rd, 0))	AS PayToSupplier
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.ProductID = ci.ProductID AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate 
		AND b.StatusId NOT IN (-1, 101, 102, 103) 
		AND b.CurrencyId <> 20 
		AND b.CustomerCategory NOT IN (27,28)
	GROUP BY b.rptDate, ci.PartyId, b.CurrencyId
	
	
	
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
		INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome)
		SELECT @tempCurrency,ParentId,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(CASE WHEN LicensingFee < 0 THEN 0 ELSE LicensingFee END),
			SUM(PayToSupplier),
			SUM(CASE WHEN LicensingFee < 0 THEN 0 ELSE LicensingFee END - PayToSupplier)
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
		CAST(((r.LicensingFee - r.PayToSupplier) * e.Rate)AS MONEY) AS CompanyIncome
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
		CompanyIncome
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