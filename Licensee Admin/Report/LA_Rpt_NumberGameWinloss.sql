/*<info serverAlias="DBEXT-bodb02" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
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
 * DB   : bodb_licensee
 * Revisions :
	- 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
	- 20150703@Florent: add GBP
	- 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
	- 20170621@Bruce: include paytosupplier & netincome [#78398]
	- 20171220@Parsons: increase length for variables [#88197]
	- 20180716@bruce: add new group TEST for credit [#98126]
	- 20180815@Scofield: Remove "Exclude Test Data" checkbox [#98623]
	- 20181224@Bruce: include happy 5 [#105723]
	- 20190626@Mason: Implement new view for Number Game
	
 * Param's Explanation:
 *
 */

BEGIN
	SET NOCOUNT ON

	-- Get party group by party group
	CREATE TABLE #Party (PartyId INT,PartyName VARCHAR(100),BrandName VARCHAR(100),ParentId INT)
	INSERT INTO #Party EXEC bodb_licensee.dbo.LA_PartyListSel
	-- End region
	
	-- Get Charge rate in period FromDate - ToDate
	-- Using bodb_licensee.dbo.LA_f_ChargeInfoWithCredit to get both deposit and credit
	-- ​Pay to Supplier: equals 40% of [Licensing Fee]
	CREATE TABLE #ChargeRate (
		PartyID			INT
		,LicenseeID		INT
		,isDeposit		INT
		,ProductID		INT
		,Rate			MONEY
		,Rate3rd		MONEY
		,Fromdate		SMALLDATETIME
		,Todate			SMALLDATETIME
	)
	
	INSERT INTO #ChargeRate
	SELECT c.PartyID, c.LicenseeID, c.isDeposit, c.ProductID, c.DI_Rate, 0.4, c.Fromdate, c.Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIDs, @FromDate, @ToDate, 'NG') c
	-- End region

	-- Get Exchange Rate
	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	-- End Region
	
	-- Create a temp table to store Total of turnover, BetCount, CustomerWL, LicenseeFee, PayToSupplier in perriod FromDate - ToDate
	CREATE TABLE #TempData (
		PartyID INT,
		PartyName NVARCHAR(100),
		Winlostdate DATETIME,
		CurrencyId INT,
		Turnover MONEY,
		TotalTrans INT,
		CustomerWinLoss MONEY,
		LicenseeWinloss MONEY,
		LicensingFee MONEY,
		PayToSupplier MONEY)
		
	INSERT INTO #TempData (PartyID,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee, PayToSupplier)
	SELECT ci.PartyId,
		b.rptDate,
		b.CurrencyId,
		SUM(b.Turnover) AS Turnover,
		SUM(b.BetCount) AS TotalTrans,
		SUM(b.MemberWL) AS CustomerWinLoss,
		- SUM(b.MemberWL) AS LicenseeWinloss,
		SUM(-b.MemberWL * ci.Rate) AS LicensingFee,
		SUM(-b.MemberWL * ci.Rate3rd) AS PayToSupplier
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN #ChargeRate ci ON b.SiteID = ci.LicenseeId AND b.ProductID = ci.ProductID AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
		b.StatusId NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 AND b.CustomerCategory NOT IN (27,28)
	GROUP BY b.rptDate, ci.PartyId, b.CurrencyId
	-- End Region
	
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
	
	-- Get ParentId and ParentName
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier)
	SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, td.CurrencyId, td.TotalTrans, td.Turnover, td.CustomerWinLoss, td.LicenseeWinloss, td.LicensingFee, td.PayToSupplier
	FROM #TempData td
		INNER JOIN #Party p ON td.PartyId = p.PartyID
		INNER JOIN #Party pa ON p.ParentId = pa.PartyId
	-- End Region
	
	-- Calculate Total for each currency and Grand Total
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
		
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20),
		IsApply BIT
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
	
	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)

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
		INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee, PayToSupplier)
		SELECT @tempCurrency,ParentId,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(CASE WHEN LicensingFee < 0 THEN 0 ELSE LicensingFee END),
			SUM(PayToSupplier)
		FROM TotalByParty
		GROUP BY ParentId

		UPDATE @Total
		SET PayToSupplier = 0
		WHERE PayToSupplier < 0

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

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
	END
	-- End Region
	
	-- Region: Select Data
	-- Select data by currency
	SELECT
		r.WinLossDate,
		e.CurrencyCode,
		r.PartyId,
		SUM(r.TotalTrans),
		CAST(SUM(r.Turnover * e.Rate) AS MONEY) AS Turnover,
		CAST(SUM(r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
		CAST(SUM(r.LicenseeWinLoss * e.Rate) AS MONEY) AS LicenseeWinLoss,
		CAST(SUM(r.LicensingFee * e.Rate) AS MONEY) AS LicenseeFee,
		CAST(SUM(r.PayToSupplier * e.Rate) AS MONEY) AS PayToSupplier,
		CAST(SUM(r.LicensingFee - r.PayToSupplier)) AS CompanyIncome
	FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.WinLossDate = e.ExchangeDate 
	GROUP BY e.CurrencyCode, PartyId, r.WinLossDate
	
	-- Select data by Parties
	SELECT 
		r.PartyId,
		r.PartyName,
		r.ParentId,
		r.ParentName,
		e.CurrencyCode AS CurrencyName,
		-- Select by origin currency
		r.TotalTrans,
		r.Turnover AS Turnover,
		CAST((r.CustomerWinLoss) AS MONEY) AS CustomerWinLoss,
		CAST((r.LicenseeWinLoss) AS MONEY) AS LicenseeWinLoss,
		CAST((r.LicensingFee) AS MONEY) AS LicenseeFee,
		CAST((r.PayToSupplier)AS MONEY) AS PayToSupplier,
		r.LicensingFee - r.PayToSupplier AS CompanyIncome,
		-- Select by base currency
		r.Turnover * e.Rate AS Turnover,
		CAST((r.CustomerWinLoss * e.Rate) AS MONEY) AS CustomerWinLoss,
		CAST((r.LicenseeWinLoss * e.Rate) AS MONEY) AS LicenseeWinLoss,
		CAST((r.LicensingFee * e.Rate) AS MONEY) AS LicenseeFee,
		CAST((r.PayToSupplier * e.Rate)AS MONEY) AS PayToSupplier,
		r.LicensingFee - r.PayToSupplier AS CompanyIncome
	FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.WinLossDate = e.ExchangeDate
	
	-- Total
	SELECT PartyId,
		TotalTrans,
		Turnover,
		CustomerWinLoss,
		LicenseeWinLoss,
		LicensingFee,
		PayToSupplier,
		(LicensingFee - PayToSupplier) AS CompanyIncome
	FROM @Total t
	WHERE Currency = @BaseCurrencyName
	
	SELECT * FROM @GrandTotal
	-- End Region
	
	DROP TABLE	#Party
	DROP TABLE	#Exchange
	DROP TABLE	#ChargeRate
	DROP TABLE  #Result
	DROP TABLE	#TempData	
END
GO
