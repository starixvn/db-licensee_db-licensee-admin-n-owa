/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_BitCoinWinLoss]
	@PartyIds			VARCHAR(MAX)
	,@FromDate			DATETIME
	,@ToDate			DATETIME
	,@BaseCurrencyName	VARCHAR(20)
AS

/*
	Created: 20210812@Percy
	DB: DBLIC-bodb_Licensee
	Task: BitCoin Win Loss Report

	Revisions:
		- 20210812@Percy: Initialize SP [RedmineID: #159691]
*/

BEGIN
	SET NOCOUNT ON

	-- Get Party List
	BEGIN
		CREATE TABLE #PartyList (PartyId INT, LicenseeId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT, ParentName VARCHAR(100))
		INSERT INTO #PartyList (PartyId, PartyName, BrandName, ParentId)
		EXEC dbo.LA_PartyListSel

		DELETE #PartyList WHERE ',' + @PartyIds + ',' NOT LIKE '%,' + CONVERT(VARCHAR(20), PartyId) + ',%'
			AND ParentId <> 0

		UPDATE pl
		SET pl.ParentName = p.PartyName
		FROM #PartyList pl
			INNER JOIN #PartyList p ON pl.ParentId = p.PartyId

		DELETE #PartyList WHERE ParentId = 0

		SET @PartyIds = NULL
		SELECT @PartyIds = COALESCE(@PartyIds + ',', '') + CONVERT(VARCHAR(20), PartyId) FROM #PartyList WHERE ParentId <> 0

		-- Deposit
		UPDATE pl
		SET pl.LicenseeId = p.OldRefId
		FROM #PartyList pl
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON pl.PartyId = p.PartyId
			INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyId = pd.PartyId
		WHERE pd.IsDeposit = 1

		-- Credit
		INSERT INTO #PartyList (PartyId, LicenseeId, PartyName, ParentId, ParentName)
		SELECT pl.PartyId, l.LabelId, pl.PartyName, pl.ParentId, pl.ParentName
		FROM #PartyList pl
			INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON pl.PartyId = p.PartyId
			INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyId = pd.PartyId AND pd.IsDeposit = 0
			INNER JOIN dbo.Labels l WITH (NOLOCK) ON p.OldRefId = l.LicenseeId
			LEFT JOIN #PartyList t ON l.LabelId = t.LicenseeId
		WHERE t.LicenseeId IS NULL

		DELETE #PartyList WHERE LicenseeId IS NULL
	END

	-- Get Charge Rate
	BEGIN
		DECLARE @3rdRate TABLE (PartyId INT, FromDate DATE, ToDate DATE, Rate FLOAT)
		INSERT INTO @3rdRate (PartyId, FromDate, ToDate, Rate)
		SELECT pl.PartyId, r.FromDate, r.ToDate, r.DI_Rate
		FROM dbo.LA_f_ChargeInfo3rd(@FromDate, @ToDate, 'BTC', 'OA') r
			INNER JOIN #PartyList pl ON r.PartyId = pl.ParentId

		DECLARE @ChargeRate TABLE (ChargeId INT, PartyId INT, LicenseeId INT, FromDate DATE, ToDate DATE, Rate FLOAT)
		INSERT INTO @ChargeRate (ChargeId, PartyId, LicenseeId, FromDate, ToDate, Rate)
		SELECT c.ChargeId, c.PartyId, c.LicenseeId, c.FromDate, c.ToDate, c.DI_Rate
		FROM dbo.LA_f_ChargeInfoWithCredit(@PartyIds, @FromDate, @ToDate, 'SB') c -- BTC under SB
	END

	-- Get Exchange
	BEGIN
		DECLARE @Exchange TABLE (ExchangeDate DATE, ExchangeId INT, Code VARCHAR(10), Rate FLOAT)
		INSERT INTO @Exchange (ExchangeDate, ExchangeId, Rate, Code)
		SELECT ExchangeDate, ExchangeId, BaseCurrencyRate, CASE ExchangeId WHEN 51 THEN 'INH' WHEN 92 THEN 'HID' ELSE Code END
		FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	END

	-- Get Win Loss Data
	BEGIN
		CREATE TABLE #tmpData (rptDate DATE, PartyId INT, ParentId INT, CurrencyId INT, Turnover MONEY, BetCount INT, MemberWL MONEY)
		INSERT INTO #tmpData (rptDate, PartyId, ParentId, CurrencyId, Turnover, BetCount, MemberWL)
		SELECT r.rptDate, pl.PartyId, pl.ParentId, r.CurrencyId
			,SUM(r.Turnover) AS Turnover
			,SUM(r.BetCount) AS BetCount
			,SUM(r.MemberWL) AS MemberWL
		FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct r WITH (NOLOCK)
			INNER JOIN #PartyList pl ON r.SiteId = pl.LicenseeId
		WHERE r.rptDate BETWEEN @FromDate AND @ToDate
			AND r.ProductId = 69
			AND r.CurrencyId <> 20
			AND r.CustomerCategory NOT IN (27, 28)
			AND r.StatusId IN (111, 112, 113, 114, 115)
		GROUP BY r.rptDate, pl.PartyId, pl.ParentId, r.CurrencyId

		CREATE TABLE #tmpResult (rptDate DATE, PartyId INT, ParentId INT, CurrencyId INT, Turnover MONEY, BetCount INT, MemberWL MONEY, LicensingFee MONEY, PayToSupplier MONEY)
		INSERT INTO #tmpResult (rptDate, PartyId, ParentId, CurrencyId, Turnover, BetCount, MemberWL, LicensingFee, PayToSupplier)
		SELECT d.rptDate, d.PartyId, d.ParentId, d.CurrencyId, SUM(d.Turnover), SUM(d.BetCount), SUM(d.MemberWL), SUM(-d.MemberWL * ISNULL(bc.Rate, c.Rate)), SUM(-d.MemberWL * ISNULL(r.Rate, 0))
		FROM #tmpData d
			INNER JOIN @ChargeRate c ON d.PartyId = c.PartyId AND d.rptDate BETWEEN c.FromDate AND c.ToDate
			LEFT JOIN @3rdRate r ON d.PartyId = r.PartyId AND d.rptDate BETWEEN r.FromDate AND r.ToDate
			LEFT JOIN dbo.LA_ChargeRateByCurrency bc WITH (NOLOCK) ON c.ChargeId = bc.ChargeId AND d.CurrencyId = bc.CurrencyId
		GROUP BY d.rptDate, d.PartyId, d.ParentId, d.CurrencyId
	END
	
	-- Base Currency
	BEGIN
		DECLARE @BaseCurrencies TABLE (ExchangeId INT, ExchangeName VARCHAR(20))
		INSERT INTO @BaseCurrencies (ExchangeId, ExchangeName)
		EXEC dbo.LA_SelBaseCurrency

		DECLARE @BaseCurrencyRate TABLE (ExchangeDate DATE, ExchangeId INT, BaseExchangeName VARCHAR(20), BaseExchangeRate FLOAT)
		INSERT INTO @BaseCurrencyRate (ExchangeDate, ExchangeId, BaseExchangeName, BaseExchangeRate)
		SELECT e.ExchangeDate, e.ExchangeId, bc.ExchangeName, e.BaseCurrencyRate
		FROM @BaseCurrencies bc
			CROSS APPLY bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, bc.ExchangeName) e

		DECLARE @Total TABLE (CurrencyName VARCHAR(20), ParentId INT, BetCount INT, Turnover MONEY, MemberWL MONEY, LicensingFee MONEY, PayToSupplier MONEY)
		INSERT INTO @Total (CurrencyName, ParentId, BetCount, Turnover, MemberWL, LicensingFee, PayToSupplier)
		SELECT t.BaseExchangeName, t.ParentId, SUM(t.BetCount), SUM(t.Turnover), SUM(t.MemberWL), SUM(CASE WHEN t.LicensingFee < 0 AND jvp.PartyId IS NULL THEN 0 ELSE t.LicensingFee END), SUM(t.PayToSupplier)
		FROM (
			SELECT br.BaseExchangeName, r.PartyId, r.ParentId
				,SUM(r.BetCount) AS BetCount
				,SUM(r.Turnover * br.BaseExchangeRate) AS Turnover
				,SUM(r.MemberWL * br.BaseExchangeRate) AS MemberWL
				,SUM(r.LicensingFee * br.BaseExchangeRate) AS LicensingFee
				,SUM(r.PayToSupplier * br.BaseExchangeRate) AS PayToSupplier
			FROM #tmpResult r
				INNER JOIN @BaseCurrencyRate br ON r.CurrencyId = br.ExchangeId AND r.rptDate = br.ExchangeDate
			GROUP BY br.BaseExchangeName, r.PartyId, r.ParentId
		) t
			LEFT JOIN dbo.LA_f_JVPartyListSel() jvp ON t.PartyId = jvp.PartyId
		GROUP BY t.BaseExchangeName, t.ParentId
	END

	-- Return Data
		-- Detail
	SELECT 
		p.PartyId
		,p.PartyName
		,p.ParentId
		,p.ParentName
		,r.rptDate AS WinLossDate
		,e.Code AS CurrencyName
		,r.BetCount AS TotalTrans
		-- Original Currency
		,r.Turnover AS TurnoverOriginal
		,r.MemberWL AS CustomerWinLossOriginal
		,-r.MemberWL AS LicenseeWinLossOriginal
		,r.LicensingFee  AS LicensingFeeOriginal
		,r.PayToSupplier AS PayToSupplierOriginal
		,r.LicensingFee - r.PayToSupplier AS CompanyIncomeOriginal
		-- Base Currency
		,CONVERT(MONEY, r.Turnover * e.Rate) AS Turnover
		,CONVERT(MONEY, r.MemberWL * e.Rate) AS CustomerWinLoss
		,CONVERT(MONEY, -r.MemberWL * e.Rate) AS LicenseeWinLoss
		,CONVERT(MONEY, r.LicensingFee * e.Rate) AS LicensingFee
		,CONVERT(MONEY, r.PayToSupplier * e.Rate) AS PayToSupplier
		,CONVERT(MONEY, (r.LicensingFee - r.PayToSupplier) * e.Rate) AS CompanyIncome
	FROM #tmpResult r
		INNER JOIN #PartyList p ON r.PartyId = p.PartyId
		INNER JOIN @Exchange e ON r.CurrencyId = e.ExchangeId AND r.rptDate = e.ExchangeDate

		-- Grand Total
	SELECT CurrencyName
		,SUM(BetCount) AS TotalTrans
		,SUM(Turnover) AS Turnover
		,SUM(MemberWL) AS CustomerWinLoss
		,SUM(-MemberWL) AS LicenseeWinLoss
		,SUM(LicensingFee) AS LicensingFee
		,SUM(PayToSupplier) AS PayToSupplier
		,SUM(LicensingFee - PayToSupplier) AS CompanyIncome
	FROM @Total
	GROUP BY CurrencyName

		-- Total
	SELECT ParentId AS PartyId, BetCount AS TotalTrans, Turnover, MemberWL AS CustomerWinLoss, -MemberWL AS LicenseeWinLoss
		,LicensingFee, PayToSupplier, LicensingFee - PayToSupplier AS CompanyIncome
	FROM @Total
	WHERE CurrencyName = @BaseCurrencyName

	DROP TABLE #PartyList
	DROP TABLE #tmpData
	DROP TABLE #tmpResult
END
GO