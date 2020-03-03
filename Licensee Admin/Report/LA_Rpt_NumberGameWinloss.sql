/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_NumberGameWinloss]
	@PartyIds			VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20)
AS

/*
 * Created by : [20140904@Florent.Nguyen]
 * Task  : Get Number Game Winloss
 * DB   : DB052.bodb02
 * Revisions :
	- 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
	- 20150703@Florent: add GBP
	- 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
	- 20170621@Bruce: include paytosupplier & netincome [#78398]
	- 20171220@Parsons: increase length for variables [#88197]
	- 20180716@bruce: add new group TEST for credit [#98126]
	- 20180815@Scofield: Remove "Exclude Test Data" checkbox [#98623]
	- 20181224@Bruce: include happy 5 [#105723]
	- 20190626@Mason: Implement new view for Number Game [#113641]
	- 20190718@Mason: Integrate CN88 data in LA (PayToSupplier = 0.015 GRR) [#116859]
	- 20190808@Parsons: Provide House Turnover In NG WL Report [Redmine: #117674]
	- 20191217@Bruce: Update NG/H5 3rd rate [#125515]
	- 20191226@Mason: Set Term By Currency [#120005]
	- 20200203@Mason: Support HID currency [#128856]

 * Param's Explanation:
 EXEC LA_Rpt_NumberGameWinloss @PartyIds = '14,15,16,17,18,19', @FromDate = '20190101', @ToDate = '20190808', @BaseCurrencyName = 'EUR'
 */

BEGIN
	SET NOCOUNT ON

	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT)
	INSERT INTO #PartyList EXEC bodb_licensee.dbo.LA_PartyListSel

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
	-- ​Pay to Supplier: equals 40%(0.4) of [Licensing Fee]
	-- Except CN88 = 1.5%
	INSERT INTO #ChargeRate
	SELECT c.ChargeID, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate, 0.4, c.Fromdate, c.Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIDs, @FromDate, @ToDate, 'NG') c

	-- From 01 Dec 2019, pay to supplier = 50%
	BEGIN
		DECLARE @EffectiveDateForNewRate DATE = '20191201'

		INSERT INTO #ChargeRate
		SELECT c.ChargeId, c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.Rate, c.Rate3rd, c.Fromdate, DATEADD(DAY,-1,@EffectiveDateForNewRate)
		FROM #ChargeRate c
		WHERE Fromdate < @EffectiveDateForNewRate AND @EffectiveDateForNewRate <= ToDate

		UPDATE #ChargeRate SET
			Fromdate = (CASE WHEN Fromdate < @EffectiveDateForNewRate THEN @EffectiveDateForNewRate ELSE Fromdate END),
			Rate3rd = 0.5
		WHERE @EffectiveDateForNewRate <= Todate
	END

	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, 
	ExchangeID, 
	CASE WHEN ExchangeID = 51 THEN 'INH' 
		 WHEN ExchangeID = 92 THEN 'HID' 
		 ELSE Code END, 
	BaseCurrencyRate
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
		HouseTurnover MONEY,
		TotalTrans INT,
		CustomerWinLoss MONEY,
		LicenseeWinloss MONEY,
		LicensingFee MONEY,
		PayToSupplier MONEY)

	INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,HouseTurnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier)
	SELECT ci.PartyId,
		b.rptDate as Winlostdate,
		b.CurrencyId,
		SUM(b.Turnover) AS Turnover,
		SUM(b.ExtraAmount) AS HouseTurnover,
		SUM(b.BetCount) AS TotalTrans,
		SUM(b.MemberWL) AS CustomerWinLoss,
		- SUM(b.MemberWL) AS LicenseeWinloss,
		SUM(-b.MemberWL * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
		SUM(-b.MemberWL * ISNULL(cr.Rate, ci.Rate) * ci.Rate3rd) AS PayToSupplier
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.ProductID = ci.ProductID AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON ci.ChargeId = cr.ChargeId AND cr.CurrencyId = b.CurrencyId
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
		b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 AND b.CustomerCategory NOT IN (27,28)
		AND ci.isDeposit = 1
	GROUP BY b.rptDate, ci.PartyId, b.CurrencyId
	
	-- Calculate for credit
	INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,HouseTurnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee, PayToSupplier)
	SELECT ci.PartyId,
		b.rptDate as Winlostdate,
		b.CurrencyId,
		SUM(b.Turnover) AS Turnover,
		SUM(b.ExtraAmount) AS HouseTurnover,
		SUM(b.BetCount) AS TotalTrans,
		SUM(b.WinLoss) AS CustomerWinLoss,
		- SUM(b.WinLoss) AS LicenseeWinloss,
		- SUM(b.WinLoss + b.WinLossA + WinLossM + WinLossS + b.CommissionS) AS LicensingFee,
		- SUM((b.WinLoss + b.WinLossA + WinLossM + WinLossS + b.CommissionS) * ci.Rate3rd) AS PayToSupplier
	FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH (NOLOCK)
		INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
		b.Status NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 AND b.CustomerCategory NOT IN (27,28)
		AND b.Bettype in (Select Bettype FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0,'NG'))
		AND ci.isDeposit = 0
	GROUP BY b.rptDate, ci.PartyId, b.CurrencyId
	-- EndRegion
	
	UPDATE td SET
		PartyName = p.PartyName,
		ParentId = pa.PartyId,
		ParentName = pa.PartyName
	FROM #TempData td
		INNER JOIN #PartyList p ON td.PartyID = p.PartyId
		INNER JOIN #PartyList pa ON P.ParentId = PA.PartyId
		
	--Region Update PayToSupplier = 0.015 * Licensee WL for CN88
	UPDATE td SET
		td.PayToSupplier = td.LicenseeWinloss * 0.015
	FROM #TempData td 
	WHERE PartyID IN (SELECT p.PartyID FROM OAS_Party p WHERE p.PartyName = 'CN88')
	
	DECLARE @Total TABLE (
		ParentId		INT,
		TotalTrans		INT,
		Turnover		MONEY,
		HouseTurnover	MONEY,
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
		HouseTurnover	MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)
	
	WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies)

		INSERT INTO @Total (ParentId, Currency,TotalTrans,Turnover,HouseTurnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier)
		SELECT 
			ParentId,
			@tempCurrency AS Currency,
			SUM(td.TotalTrans) TotalTrans,
			SUM(td.Turnover * e.BaseCurrencyRate) Turnover,
			SUM(td.HouseTurnover * e.BaseCurrencyRate) HouseTurnover,
			SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss,
			SUM(td.LicenseeWinLoss * e.BaseCurrencyRate) LicenseeWinLoss,
			SUM(td.LicensingFee * e.BaseCurrencyRate) LicensingFee,
			SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier
			FROM #TempData td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e
			ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.Winlostdate
			GROUP BY td.ParentId

		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,HouseTurnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee, PayToSupplier, CompanyIncome)
		SELECT Currency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(HouseTurnover),
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
		r.Winlostdate AS WinLossDate,
		e.CurrencyCode AS CurrencyName,
		-- Select by origin currency
		r.TotalTrans,
		r.Turnover AS TurnoverOriginal,
		r.HouseTurnover AS HouseTurnoverOriginal,
		CAST((r.CustomerWinLoss) AS MONEY) AS CustomerWinLossOriginal,
		CAST((r.LicenseeWinLoss) AS MONEY) AS LicenseeWinLossOriginal,
		CAST((r.LicensingFee) AS MONEY) AS LicensingFeeOriginal,
		CAST((r.PayToSupplier) AS MONEY) AS PayToSupplierOriginal,
		r.LicensingFee - r.PayToSupplier AS CompanyIncomeOriginal,
		-- Select by base currency
		r.Turnover * e.Rate AS Turnover,
		r.HouseTurnover * e.Rate AS HouseTurnover,
		CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
		CAST((r.LicenseeWinLoss * e.Rate) AS MONEY) AS LicenseeWinLoss,
		CAST((r.LicensingFee * e.Rate) AS MONEY) AS LicensingFee,
		CAST((r.PayToSupplier * e.Rate)AS MONEY) AS PayToSupplier,
		r.LicensingFee - r.PayToSupplier AS CompanyIncome
	FROM #TempData r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.Winlostdate = e.ExchangeDate
	
	-- Select Grand Total
	SELECT * FROM @GrandTotal
	
	-- Total
	SELECT ParentId,
		TotalTrans,
		Turnover,
		HouseTurnover,
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
END
GO