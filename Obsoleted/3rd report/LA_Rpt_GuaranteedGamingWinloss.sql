/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_GuaranteedGamingWinloss]
	@PartyIds			VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20),
	@Timezone			INT
AS
/*
 * Created by : [20220328@Danny]
 * Task  : Get Guaranteed Gaming Winloss
 * Revisions
	- 20220328@Danny: Intergrate Guaranteed Gaming [#167626]

 * Param's Explanation:
 *				@Timezone: = 1: GMT-4
						   = 2: GMT+8	
 */

BEGIN
	SET NOCOUNT ON
	DECLARE @f_date3rd		DATE = DATEADD(DAY, -1, @FromDate)
	DECLARE @t_date3rd		DATE = DATEADD(DAY, 1, @ToDate)
	DECLARE @f_date			DATE = @FromDate
	DECLARE @t_date			DATE = @ToDate

	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT, IsKeepNegativeAmount BIT DEFAULT 0)
	INSERT INTO #PartyList (PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	UPDATE t 
	SET t.IsKeepNegativeAmount = CASE WHEN u.PartyId IS NULL THEN 0 ELSE 1 END 
	FROM #PartyList t 
	LEFT JOIN bodb_Licensee.dbo.LA_f_JVPartyListSel() u ON u.PartyId = t.PartyId
	
	-- Get 3rd Rate
	DECLARE @3rdRate AS TABLE(PartyID INT, ProductID INT, DI_Rate MONEY, IsDeposit INT, Fromdate SMALLDATETIME, Todate SMALLDATETIME, ChargeType INT)
	INSERT INTO @3rdRate (PartyID, ProductID, DI_Rate, IsDeposit, Fromdate, Todate, ChargeType)
	SELECT DISTINCT p.PartyId, r.ProductID, r.DI_Rate, r.IsDeposit, r.Fromdate, r.Todate , r.ChargeType
	FROM dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'FGGL', 'OA') r 
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
		,RollingCommRate MONEY
		,FromDate3rd	SMALLDATETIME
		,ToDate3rd		SMALLDATETIME
	)
	
	INSERT INTO #ChargeRate (ChargeID, PartyID, LicenseeID, isDeposit, ProductID, Rate, Rate3rd, Fromdate, Todate, RollingCommRate , FromDate3rd, ToDate3rd)
	SELECT DISTINCT c.ChargeID, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate AS Rate, r.DI_Rate AS Rate3rd, c.Fromdate, c.Todate, r1.DI_Rate AS RollingCommRate, r.Fromdate, r.Todate
	FROM LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, 'FGGL') c
	INNER JOIN @3rdRate r ON r.PartyID = c.PartyID and r.ProductID = c.ProductID AND r.ChargeType = 1
	LEFT JOIN @3rdRate r1 ON r1.PartyID = c.PartyID and r1.ProductID = c.ProductID AND r1.ChargeType = 11
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

	DECLARE @FGGL_bettypeList TABLE (BetTypeId INT)
	INSERT INTO @FGGL_bettypeList (BetTypeId) 
	SELECT	DISTINCT bettype
	FROM	bodb_licensee.dbo.LA_f_BettypeProductMapping(0,'FGGL') la

	-- Region: TempData
	CREATE TABLE #TempData (
		PartyID			INT,
		Winlostdate		DATETIME,
		CurrencyId		INT,
		Turnover		MONEY,
		ValidBetAmount	MONEY,
		TotalTrans		INT,
		CustomerWinLoss MONEY,
		LicensingFee	MONEY,
		RollingComm		MONEY,
		NetWinloss		MONEY,
		PayToSupplier	MONEY
		)

	-- Calculate for desposit & credit
	IF @Timezone = 1
	BEGIN
		;WITH cte_Summary AS(
			SELECT
				b.SiteID,
				b.RptDate  AS Winlostdate,
				b.CurrencyId,
				SUM(b.Turnover) AS Turnover,
				SUM(b.BetCount) AS TotalTrans,
				SUM(b.ValidBetAmount)  AS ValidBetAmount,
				SUM(b.MemberWL) AS CustomerWinLoss
			FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.RptDate BETWEEN ci.FromDate AND ci.ToDate
			WHERE b.RptDate BETWEEN @f_date AND @t_date
				AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 
				AND b.ProductId = 70
				AND b.CustomerCategory NOT IN (27, 28)
			GROUP BY b.SiteID, b.RptDate, b.CurrencyId
		)
		INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,ValidBetAmount,TotalTrans,CustomerWinLoss,LicensingFee,RollingComm,NetWinloss,PayToSupplier)
		SELECT ci.PartyId,
			b.Winlostdate,
			b.CurrencyId,
			SUM(b.Turnover) AS Turnover,
			SUM(b.ValidBetAmount) AS ValidBetAmount,
			SUM(b.TotalTrans) AS TotalTrans,
			SUM(b.CustomerWinLoss) AS CustomerWinLoss,
			SUM(-b.CustomerWinLoss  * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
			SUM(b.ValidBetAmount * ISNULL(ci.RollingCommRate,0)) AS  RollingComm,
			SUM(-b.CustomerWinLoss)  - SUM(b.ValidBetAmount * ISNULL(ci.RollingCommRate,0)) AS NetWinloss,
			SUM((-b.CustomerWinLoss  - b.ValidBetAmount * ISNULL(ci.RollingCommRate,0))  * ISNULL(ci.Rate3rd, 0) )  PayToSupplier

		FROM cte_Summary b WITH (NOLOCK)
			INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.Winlostdate BETWEEN ci.FromDate AND ci.ToDate
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeID = ci.ChargeID AND cr.CurrencyID = b.CurrencyId
		GROUP BY b.Winlostdate, ci.PartyId, b.CurrencyId
	END
	ELSE
	BEGIN
		;WITH cte_Summary AS(
			SELECT
				b.SiteID,
				b.RptDate3rd  AS Winlostdate,
				b.CurrencyId,
				SUM(b.Turnover) AS Turnover,
				SUM(b.BetCount) AS TotalTrans,
				SUM(b.ValidBetAmount)  AS ValidBetAmount,
				SUM(b.Winloss) AS CustomerWinLoss
			FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
				INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.RptDate3rd BETWEEN ci.FromDate AND ci.ToDate
			WHERE b.RptDate BETWEEN @f_date3rd AND @t_date3rd
				AND b.RptDate3rd BETWEEN @f_date AND @t_date
				AND b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 
				AND b.BetTypeId IN (SELECT x.BetTypeId FROM @FGGL_bettypeList x)
			GROUP BY b.SiteID, b.RptDate3rd, b.CurrencyId
		)
		INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,ValidBetAmount,TotalTrans,CustomerWinLoss,LicensingFee,RollingComm,NetWinloss,PayToSupplier)
		SELECT ci.PartyId,
			b.Winlostdate,
			b.CurrencyId,
			SUM(b.Turnover) AS Turnover,
			SUM(b.ValidBetAmount) AS ValidBetAmount,
			SUM(b.TotalTrans) AS TotalTrans,
			SUM(b.CustomerWinLoss) AS CustomerWinLoss,
			SUM(-b.CustomerWinLoss  * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
			SUM(b.ValidBetAmount * ISNULL(ci.RollingCommRate,0)) AS  RollingComm,
			SUM(-b.CustomerWinLoss)  - SUM(b.ValidBetAmount * ISNULL(ci.RollingCommRate,0)) AS NetWinloss,
			SUM((-b.CustomerWinLoss  - b.ValidBetAmount * ISNULL(ci.RollingCommRate,0))  * ISNULL(ci.Rate3rd, 0) ) PayToSupplier

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
		ValidBetAmount	MONEY,
		CustomerWinLoss	MONEY,
		LicensingFee	MONEY,
		RollingComm		MONEY,
		NetWinloss		MONEY,
		PayToSupplier	MONEY,
		IsKeepNegativeAmount BIT
	)
	
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover,ValidBetAmount, CustomerWinLoss, LicensingFee, RollingComm, NetWinloss, PayToSupplier, IsKeepNegativeAmount)
	SELECT	td.PartyId, 
			p.PartyName, 
			pa.PartyId, 
			pa.PartyName, 
			td.Winlostdate, 
			td.CurrencyId, 
			td.TotalTrans, 
			td.Turnover, 
			td.ValidBetAmount, 
			td.CustomerWinLoss, 
			td.LicensingFee, 
			td.RollingComm, 
			td.NetWinloss, 
			td.PayToSupplier,
			p.IsKeepNegativeAmount
	FROM #TempData td
		INNER JOIN #PartyList p ON td.PartyId = p.PartyID
		INNER JOIN #PartyList pa ON p.ParentId = pa.PartyId	
	
	DECLARE @Total TABLE (
		PartyId			INT,
		Currency		VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		ValidBetAmount	MONEY,
		CustomerWinLoss	MONEY,
		LicensingFee	MONEY,
		RollingComm		MONEY,
		NetWinloss		MONEY,
		PayToSupplier	MONEY,
		CompanyIncome		MONEY
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
		ValidBetAmount	MONEY,
		LicensingFee	MONEY,
		RollingComm		MONEY,
		PayToSupplier	MONEY,
		NetWinloss		MONEY,
		CompanyIncome		MONEY
	)
	
	WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies)

		;WITH TotalByParty AS(
			SELECT td.ParentId, td.PartyId, td.IsKeepNegativeAmount,
				SUM(td.TotalTrans) TotalTrans,
				SUM(td.Turnover * e.BaseCurrencyRate) Turnover,
				SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss,
				SUM(td.ValidBetAmount * e.BaseCurrencyRate) ValidBetAmount,
				SUM(td.LicensingFee * e.BaseCurrencyRate) LicensingFee,
				SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier,
				SUM(td.NetWinloss * e.BaseCurrencyRate) NetWinloss,
				SUM(td.RollingComm * e.BaseCurrencyRate) RollingComm
			FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e
			ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
			GROUP BY td.ParentId, td.PartyId, td.IsKeepNegativeAmount
		)
		INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,ValidBetAmount,CustomerWinLoss,NetWinloss,LicensingFee,RollingComm,PayToSupplier, CompanyIncome)
		SELECT @tempCurrency,ParentId,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(ValidBetAmount),
			SUM(CustomerWinLoss),
			SUM(NetWinloss),
			SUM(CASE WHEN LicensingFee < 0 AND IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END) LicensingFee,
			SUM(RollingComm),
			SUM(PayToSupplier),
			SUM(CASE WHEN LicensingFee < 0 AND IsKeepNegativeAmount = 0 THEN 0 ELSE LicensingFee END - PayToSupplier)
		FROM TotalByParty
		GROUP BY ParentId
		
		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,ValidBetAmount,CustomerWinLoss,NetWinloss,LicensingFee, RollingComm ,PayToSupplier, CompanyIncome)
		SELECT Currency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(ValidBetAmount),
			SUM(CustomerWinLoss),
			SUM(NetWinloss),
			SUM(LicensingFee),
			SUM(RollingComm),
			SUM(PayToSupplier),
			SUM(CompanyIncome)
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
		CAST((r.ValidBetAmount) AS MONEY) AS ValidBetAmountOriginal,
		CAST((r.CustomerWinLoss) AS MONEY) AS CustomerWinLossOriginal,
		CAST((r.LicensingFee) AS MONEY) AS LicensingFeeOriginal,
		CAST((r.RollingComm) AS MONEY) AS RollingCommOriginal,
		CAST((r.NetWinloss) AS MONEY) AS NetWinlossOriginal,
		CAST((r.PayToSupplier) AS MONEY) AS PayToSupplierOriginal,
		r.LicensingFee - r.PayToSupplier AS CompanyIncomeOriginal,
		-- Select by base currency

		r.Turnover * e.Rate  AS Turnover,
		CAST((r.ValidBetAmount * e.Rate) AS MONEY) AS ValidBetAmount,
		CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
		CAST((r.LicensingFee * e.Rate) AS MONEY) AS LicensingFee,
		CAST((r.RollingComm * e.Rate) AS MONEY) AS RollingComm,
		CAST((r.NetWinloss * e.Rate) AS MONEY) AS NetWinloss,
		CAST((r.PayToSupplier * e.Rate)  AS MONEY) AS PayToSupplier,
		CAST((r.LicensingFee - r.PayToSupplier) * e.Rate  AS MONEY)  AS  CompanyIncome
	FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.WinLossDate = e.ExchangeDate
	
	-- Select Grand Total
	SELECT CurrencyName,TotalTrans,Turnover,ValidBetAmount,CustomerWinLoss,LicensingFee,RollingComm,NetWinloss, PayToSupplier, CompanyIncome FROM @GrandTotal
	
	-- Total
	SELECT  PartyId,TotalTrans,Turnover,ValidBetAmount,CustomerWinLoss,LicensingFee,RollingComm,NetWinloss, PayToSupplier, CompanyIncome
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