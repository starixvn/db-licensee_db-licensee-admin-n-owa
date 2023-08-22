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
 * DB   : DBLIC.bodb_Licensee
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
	- 20200409@Mason: Integrate SA Gaming [#129276]
	- 20201109@Parsons: Add ExtraPT in Number Game Win Loss Report [RedmineID: #142969]

 * Param's Explanation:
 EXEC LA_Rpt_NumberGameWinloss @PartyIds = '14,15,16,17,18,19', @FromDate = '20190101', @ToDate = '20190808', @BaseCurrencyName = 'EUR'
 */

BEGIN
	SET NOCOUNT ON

	CREATE TABLE #PartyList (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT)
	INSERT INTO #PartyList EXEC LA_PartyListSel

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
	FROM LA_f_ChargeInfoWithCredit(@PartyIDs, @FromDate, @ToDate, 'NG') c

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

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate, CurrencyCode)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate, CASE WHEN ExchangeID = 51 THEN 'INH' 
															WHEN ExchangeID = 92 THEN 'HID' 
															ELSE Code END
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	-- Region: TempData
	CREATE TABLE #TempData (
		PartyID			INT,
		PartyName		NVARCHAR(100),
		ParentId		INT,
		ParentName		NVARCHAR(100),
		Winlostdate		DATETIME,
		CurrencyId		INT,
		Turnover		MONEY,
		HouseTurnover	MONEY,
		TotalTrans		INT,
		CustomerWinLoss MONEY,
		LicenseeWinloss MONEY,
		LicensingFee	MONEY,
		ExtraPT 		MONEY,
		PayToSupplier	MONEY)

	INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,ExtraPT,Turnover,HouseTurnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier)
	SELECT ci.PartyId,
		b.rptDate as Winlostdate,
		b.CurrencyId,
		0,
		SUM(b.Turnover) AS Turnover,
		SUM(b.ExtraAmount) AS HouseTurnover,
		SUM(b.BetCount) AS TotalTrans,
		SUM(b.MemberWL) AS CustomerWinLoss,
		SUM(-b.MemberWL) AS LicenseeWinloss,
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
	;WITH cte_CreditData AS 
	(
		SELECT b.SiteID, b.rptDate as Winlostdate, b.CurrencyId,
		SUM(ISNULL(b.WinLossE, 0) +  ISNULL(b.CommissionE, 0)) AS ExtraPT,
		SUM(b.Turnover)		AS Turnover,
		SUM(b.ExtraAmount)	AS HouseTurnover,
		SUM(b.BetCount)		AS TotalTrans,
		SUM(b.WinLoss)		AS CustomerWinLoss,
		SUM(-b.WinLoss)		AS LicenseeWinloss,
		- SUM(b.WinLoss + b.WinLossA + WinLossM + WinLossS + b.CommissionS)		AS LicensingFee
		FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH (NOLOCK)
		WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
			b.Status NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 AND b.CustomerCategory NOT IN (27,28)
			AND b.Bettype in (Select Bettype FROM LA_f_BettypeProductMapping(0,'NG'))
		GROUP BY b.SiteID, b.rptDate, b.CurrencyId
	)
	INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,ExtraPT,Turnover,HouseTurnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee,PayToSupplier)
	SELECT ci.PartyID, r.Winlostdate, r.CurrencyID,
			SUM(r.ExtraPT),
			SUM(r.Turnover), 
			SUM(r.HouseTurnover), 
			SUM(r.TotalTrans), 
			SUM(r.CustomerWinLoss), 
			SUM(r.LicenseeWinloss), 
			SUM(r.LicensingFee),
			SUM((r.LicensingFee - CASE
									WHEN r.SiteID IN (1487/*IBCIndo*/, 1547/*76666b*/) THEN ExtraPT
									ELSE 0
								  END) * ci.Rate3rd) AS PayToSupplier
	FROM cte_CreditData r
	INNER JOIN #ChargeRate ci ON r.SiteID = ci.LicenseeId AND r.Winlostdate BETWEEN ci.FromDate AND ci.ToDate
	WHERE ci.isDeposit = 0
	GROUP BY ci.PartyID, r.Winlostdate, r.CurrencyId

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
	WHERE PartyID IN (SELECT p.PartyID FROM OAS_Party p WITH(NOLOCK) WHERE p.PartyName = 'CN88')
	
	DECLARE @Total TABLE (
		ParentId		INT,
		TotalTrans		INT,
		Turnover		MONEY,
		HouseTurnover	MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		ExtraPT 		MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY,
		Currency		VARCHAR(20)
	)

	-- Region: Calculate Grand Total
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(Id INT, [Name] VARCHAR(20))
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

	DECLARE @GrandTotal TABLE (
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		HouseTurnover	MONEY,
		CustomerWinLoss	MONEY,
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		ExtraPT 		MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)
	
	WHILE EXISTS (SELECT TOP 1 1 FROM @BaseCurrencies)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies)

		INSERT INTO @Total (ParentId, Currency,TotalTrans,Turnover,HouseTurnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,ExtraPT,PayToSupplier,CompanyIncome)
		SELECT 
			ParentId,
			@tempCurrency AS Currency,
			SUM(td.TotalTrans),
			SUM(td.Turnover * e.BaseCurrencyRate),
			SUM(td.HouseTurnover * e.BaseCurrencyRate),
			SUM(td.CustomerWinLoss * e.BaseCurrencyRate),
			SUM(td.LicenseeWinLoss * e.BaseCurrencyRate),
			SUM(td.LicensingFee * e.BaseCurrencyRate),
			SUM(td.ExtraPT * e.BaseCurrencyRate),
			SUM(td.PayToSupplier * e.BaseCurrencyRate),
			SUM((LicensingFee - ExtraPT - PayToSupplier) * e.BaseCurrencyRate) AS CompanyIncome
			FROM #TempData td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e
			ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.Winlostdate
			GROUP BY td.ParentId

		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,HouseTurnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,ExtraPT,PayToSupplier,CompanyIncome)
		SELECT Currency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(HouseTurnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(LicensingFee),
			SUM(ExtraPT),
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
		r.Winlostdate				AS WinLossDate,
		e.CurrencyCode				AS CurrencyName,
		-- Select by origin currency
		r.TotalTrans,
		r.Turnover					AS TurnoverOriginal,
		r.HouseTurnover				AS HouseTurnoverOriginal,
		CAST((r.CustomerWinLoss) AS MONEY)	AS CustomerWinLossOriginal,
		CAST((r.LicenseeWinLoss) AS MONEY)	AS LicenseeWinLossOriginal,
		CAST((r.LicensingFee) AS MONEY)		AS LicensingFeeOriginal,
		CAST((r.ExtraPT) AS MONEY)			AS ExtraPTOriginal,
		CAST((r.PayToSupplier) AS MONEY)	AS PayToSupplierOriginal,
		r.LicensingFee - ExtraPT - r.PayToSupplier	AS CompanyIncomeOriginal,
		-- Select by base currency
		r.Turnover * e.Rate AS Turnover,
		r.HouseTurnover * e.Rate AS HouseTurnover,
		CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
		CAST((r.LicenseeWinLoss * e.Rate) AS MONEY) AS LicenseeWinLoss,
		CAST((r.LicensingFee * e.Rate) AS MONEY)	AS LicensingFee,
		CAST((r.ExtraPT * e.Rate) AS MONEY)			AS ExtraPT,
		CAST((r.PayToSupplier * e.Rate)AS MONEY) AS PayToSupplier,
		CAST((r.LicensingFee - ExtraPT - r.PayToSupplier) * e.Rate AS MONEY) AS CompanyIncome
	FROM #TempData r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.Winlostdate = e.ExchangeDate
	
	-- Select Grand Total
	SELECT * FROM @GrandTotal
	
	-- Total
	SELECT * FROM @Total WHERE Currency = @BaseCurrencyName
	
	-- End Region
	
	DROP TABLE	#PartyList
	DROP TABLE	#Exchange
	DROP TABLE	#ChargeRate
	DROP TABLE  #TempData	
END
GO