/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_GDGWinloss]
	  @PartyIds			VARCHAR(4000)
	, @FromDate			DATETIME
	, @ToDate			DATETIME
	, @BaseCurrencyName	VARCHAR(10) = 'EUR'
AS

/*  Created: 20201207@Happy
	Task : Report - GDG win loss
	DB: DB052.bodb_licensee
	Revisions: 
	    - 20201207@Happy: Integrate GDG [#145340]
		
	Param's Explanation:
*/
BEGIN
	SET NOCOUNT ON

	-- charge type
	DECLARE @DepositServiceCharge	INT = 9
	DECLARE @CreditServiceCharge	INT = 10
	DECLARE @RollingCommType		INT = 11

	-- Get partylist and parent group
	DECLARE @PartyList AS TABLE (PartyId INT, PartyName	VARCHAR(100), BranchName VARCHAR(100), ParentId	INT, ParentName VARCHAR(100), IsSelected BIT)

	INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC LA_PartyListSel
	
	UPDATE p1
	SET IsSelected = 1
	FROM @PartyList p1
	INNER JOIN bodb02.dbo.strSplit(@PartyIds, ',') p2 ON p1.PartyId = p2.val

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
		FROM dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, 'GDG')
	)

	-- Region: Insert Rate3rd
	INSERT INTO #ChargeInfo(PartyId, LicenseeId, ProductId, Rate, IsDeposit, ChargeType, IsPayToSupplier, Fromdate, Todate)
	SELECT DISTINCT CI3rd.PartyID, LicenseeID, CI3rd.ProductID, CI3rd.DI_Rate, 0, CI3rd.ChargeType, 1,
		(CASE WHEN CI3rd.Fromdate < @FromDate THEN @FromDate ELSE CI3rd.Fromdate END),
		(CASE WHEN CI3rd.Todate > @ToDate THEN @ToDate ELSE CI3rd.Todate END)
	FROM #ChargeInfo ci
	INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
	INNER JOIN LA_f_ChargeInfo3rd (@FromDate, @ToDate, 'GDG', 'OA') CI3rd ON p.ParentId = CI3rd.PartyID AND ci.ProductID = CI3rd.ProductID
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
		Totaltrans		INT,
		Turnover		MONEY,
		ValidBetAmount	MONEY,
		CustomerWL		MONEY,
		LicensingFee	MONEY,
		RollingComm		MONEY,
		NetWinLoss		MONEY,
		PayToSupplier	MONEY
	)
	
	INSERT INTO #Data(PartyId, ReportDate, CurrencyId, IsDeposit, Totaltrans, Turnover, ValidBetAmount, CustomerWL, LicensingFee, RollingComm, NetWinLoss, PayToSupplier)
	(
		SELECT  ci.PartyID, b.rptDate, b.currencyID, ci.IsDeposit
			, SUM(b.betcount) AS Totaltrans
			, SUM(b.Turnover) AS Turnover
			, SUM(ISNULL(b.ValidBetAmount, 0)) AS ValidBetAmount
			, SUM(b.MemberWL) AS CustomerWL
			, SUM(-b.MemberWL * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee
			, SUM(ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) AS RollingComm
			, SUM(-b.MemberWL - ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) AS NetWinLoss
			, SUM((-b.MemberWL - ISNULL(b.ValidBetAmount, 0) * ISNULL(r.Rate, 0)) * ISNULL(s.Rate, 0)) AS PayToSupplier
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
			INNER JOIN #ChargeInfo ci ON ( -- licensee charge rate
				b.SiteID = ci.LicenseeID AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate AND
				ci.IsPayToSupplier = 0)
			LEFT JOIN #ChargeInfo r ON ( -- RollingComm rate
				b.SiteID = r.LicenseeID AND b.rptDate BETWEEN r.FromDate AND r.ToDate AND
				r.IsPayToSupplier = 1 AND 
				r.ChargeType = @RollingCommType)
			LEFT JOIN #ChargeInfo s ON ( -- service charge rate
				b.SiteID = s.LicenseeID AND b.rptDate BETWEEN s.FromDate AND s.ToDate AND
				s.IsPayToSupplier = 1 AND
				s.ChargeType IN (@DepositServiceCharge, @CreditServiceCharge))
			LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON cr.ChargeId = ci.ChargeId AND cr.CurrencyID = b.CurrencyId
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
			  b.StatusId NOT IN (- 1, 101, 102, 103) AND
			  b.ProductID = 59 AND
			  b.CurrencyId <> 20 -- UUS - Currency testing
		GROUP BY b.rptDate, ci.PartyID, b.CurrencyID, ci.IsDeposit
	)
	
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
		CustomerWinLoss	MONEY,
		LicensingFee	MONEY,
		RollingComm		MONEY,
		NetWinLoss		MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)
	
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, ValidBetAmount, CustomerWinLoss, LicensingFee, RollingComm, NetWinLoss, PayToSupplier, CompanyIncome)
	SELECT d.PartyId, p.PartyName, pa.PartyId, pa.PartyName, d.ReportDate, CurrencyId, TotalTrans, Turnover, ValidBetAmount, CustomerWL, LicensingFee, RollingComm, NetWinLoss, PayToSupplier, LicensingFee - PayToSupplier
	FROM #Data d
		INNER JOIN @PartyList p ON d.PartyId = p.PartyID
		INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId	
	
	DECLARE @Total TABLE (
		PartyId			INT,
		TotalTrans		INT,
		Turnover		MONEY,
		ValidBetAmount	MONEY,
		CustomerWinLoss	MONEY,
		LicensingFee	MONEY,
		RollingComm		MONEY,
		NetWinLoss		MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY,
		Currency		VARCHAR(20)
	)

	DECLARE @GrandTotal TABLE (
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		ValidBetAmount	MONEY,
		CustomerWinLoss	MONEY,
		LicensingFee	MONEY,
		RollingComm 	MONEY,
		NetWinLoss		MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
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
				SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss,
				SUM(td.LicensingFee * e.BaseCurrencyRate) LicensingFee,
				SUM(td.RollingComm * e.BaseCurrencyRate) RollingComm,
				SUM(td.NetWinLoss * e.BaseCurrencyRate) NetWinLoss,
				SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier
			FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @Currency) e
			ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
			GROUP BY td.ParentId, td.PartyId
		)
		INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,ValidBetAmount,CustomerWinLoss,LicensingFee,RollingComm,NetWinLoss,PayToSupplier,CompanyIncome)
		SELECT @Currency,ParentId,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(ValidBetAmount),
			SUM(CustomerWinLoss),
			SUM(CASE WHEN LicensingFee < 0 THEN 0 ELSE LicensingFee END),
			SUM(RollingComm),
			SUM(NetWinLoss),
			SUM(PayToSupplier),
			SUM(CASE WHEN LicensingFee < 0 THEN 0 ELSE LicensingFee END - PayToSupplier)
		FROM TotalByParty
		GROUP BY ParentId
		
		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,ValidBetAmount,CustomerWinLoss,LicensingFee,RollingComm,NetWinLoss,PayToSupplier,CompanyIncome)
		SELECT Currency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(ValidBetAmount),
			SUM(CustomerWinLoss),
			SUM(LicensingFee),
			SUM(RollingComm),
			SUM(NetWinLoss),
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
		CAST((r.CustomerWinLoss) AS MONEY) AS CustomerWinLossOriginal,
		CAST((r.LicensingFee) AS MONEY) AS LicensingFeeOriginal,
		CAST((r.RollingComm) AS MONEY) AS RollingCommOriginal,
		CAST((r.NetWinLoss) AS MONEY) AS NetWinLossOriginal,
		CAST((r.PayToSupplier) AS MONEY) AS PayToSupplierOriginal,
		r.LicensingFee - r.PayToSupplier AS CompanyIncomeOriginal,
		-- Select by base currency
		r.Turnover * e.Rate AS Turnover,
		CAST((r.ValidBetAmount * e.Rate) AS MONEY) AS ValidBetAmount,
		CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
		CAST((r.LicensingFee * e.Rate) AS MONEY) AS LicensingFee,
		CAST((r.RollingComm * e.Rate) AS MONEY) AS RollingComm,
		CAST((r.NetWinLoss * e.Rate) AS MONEY) AS NetWinLoss,
		CAST((r.PayToSupplier * e.Rate) AS MONEY) AS PayToSupplier,
		CAST((r.LicensingFee - r.PayToSupplier) * e.Rate AS MONEY) AS CompanyIncome
	FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.WinLossDate = e.ExchangeDate
	
	-- Select Grand Total
	SELECT * FROM @GrandTotal
	
	-- Total
	SELECT 
		PartyId,
		TotalTrans,
		Turnover,
		ValidBetAmount,
		CustomerWinLoss,
		LicensingFee,
		RollingComm,
		NetWinLoss,
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