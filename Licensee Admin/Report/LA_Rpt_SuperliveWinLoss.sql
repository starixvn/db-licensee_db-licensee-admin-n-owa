/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_SuperliveWinLoss]
	@PartyIds			VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(10)		= 'GBP'
AS

/*
	 Created: 20160322@Forrest
	 Task : Superlive Win Loss Report
	 DB: DBEXT.bodb02

	 Revisions:
	 - 20160322@Forrest: Get Superlive Report Data.
	 - 20161022@Jim:move table to bodb_licenseereport [RedmineID :#60449]
	 - 20171219@Bruce: increase length for variables [#88197]
	 - 20180716@bruce: add new group TEST for credit [#98126]
	 - 20181106@bruce: move sp to bodb_licensee [#103999]
	 - 20200302@Mason: Support HID currency [#128856]
	 
	 Params:
	 - PartyIds: List Party Id.
	 - FromDate: From Date.
	 - ToDate: To Date.
	 - BaseCurrencyName: Base Currency needs to be converted to.
*/

BEGIN
SET NOCOUNT ON

	-- Region: Charge Info

	DECLARE @PartyChargeInfo AS TABLE (
		PartyId		INT,
		LicenseeId	INT,
		IsDeposit   BIT,
		ProductID	INT,
		Rate		MONEY,
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME
	)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, IsDeposit, ProductID, Rate, Fromdate, Todate)
	SELECT	PartyID, LicenseeID, isDeposit, ProductID, DI_Rate, Fromdate, Todate
	FROM	dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'SB', 'OA', 0)
	WHERE	DI_Rate > 0

	-- End region

	-- Region: Party List

	DECLARE @PartyList AS TABLE (
		PartyId		INT,
		PartyName	VARCHAR(100),
		BranchName	VARCHAR(100),
		ParentId	INT
	)

	INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC LA_PartyListSel

	-- End region

	-- Region: Get exchange rate info

	CREATE TABLE #Exchange(
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)

	INSERT INTO #Exchange
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	UPDATE #Exchange
	SET CurrencyCode =  CASE WHEN ExchangeID = 51 THEN 'INH'
							 WHEN ExchangeID = 92 THEN 'HID' END
	WHERE ExchangeID IN (51, 92)

	-- End region

	-- Region: Get Winloss data

	CREATE TABLE #TempData(
		LicenseeId	INT,
		PartyId		INT,
		RptDate		DATETIME,
		CurrencyId	INT,
		TotalTrans	INT,
		Turnover	MONEY,
		CustomerWL	MONEY,
		LicenseeWL	MONEY,
		AmtLicensee MONEY
	)

	INSERT INTO #TempData (LicenseeId, PartyId, RptDate, CurrencyId, TotalTrans, Turnover, CustomerWL, LicenseeWL, AmtLicensee)
	(
		SELECT	b.SiteID,
				p.PartyId,
				b.rptDate,
				b.CurrencyID,
				SUM(ISNULL(b.BetCount, 0)) TotalTrans,
				SUM(ISNULL(b.Turnover, 0)) Turnover,
				SUM(ISNULL(b.WinLoss, 0)) CustomerWL,
				SUM(CASE WHEN p.IsDeposit = 0
						 THEN (-b.WinLoss - b.WinLossA - b.WinLossS - b.WinLossM - b.CommissionS)
						 ELSE -b.WinLoss
					END) LicenseeWL,
				SUM(CASE WHEN p.IsDeposit = 0
						 THEN (-b.WinLoss - b.WinLossA - b.WinLossS - b.WinLossM - b.CommissionS) * p.Rate
						 ELSE -b.WinLoss * p.Rate
					END) AmtLicensee
		FROM	bodb_licenseereport.dbo.rpt_Betting b WITH (NOLOCK)
				INNER JOIN @PartyChargeInfo p ON b.SiteID = p.LicenseeId
				AND b.rptDate BETWEEN p.FromDate AND p.ToDate
		WHERE	b.rptDate BETWEEN @FromDate AND @ToDate
				AND (b.CurrencyID <> 20)
				AND b.[Status] BETWEEN 111 AND 113
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype BETWEEN 800 AND 899 -- Metric Gaming Bettype In Sportsbook
		GROUP BY b.rptdate, b.SiteId, b.CurrencyID, p.PartyId
	)

	-- End region

	-- Region: Result data

	DECLARE @Result TABLE (
		PartyId				INT,
		PartyName			VARCHAR(100),
		ParentId			INT,
		ParentName			VARCHAR(100),
		WinLossDate			DATETIME,
		CurrencyName		VARCHAR(20),
		TotalTrans			INT,
		Turnover			MONEY,
		CustomerWinLoss		MONEY,
		LicenseeWinLoss		MONEY,
		AmountDueLicensee	MONEY
	)

	IF @BaseCurrencyName = ''
	BEGIN
		INSERT INTO @Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyName, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, AmountDueLicensee)
		SELECT p.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.rptDate, e.CurrencyCode, td.TotalTrans, td.Turnover, td.CustomerWL, td.LicenseeWL, td.AmtLicensee
		FROM #TempData td
			INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate
			INNER JOIN @PartyList p ON td.PartyId = p.PartyID
			INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId

	END
	ELSE
	BEGIN
		INSERT INTO @Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyName, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, AmountDueLicensee)
		SELECT p.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.rptDate, e.CurrencyCode, td.TotalTrans, td.Turnover*e.Rate, td.CustomerWL*e.Rate, td.LicenseeWL*e.Rate, td.AmtLicensee*e.Rate
		FROM #TempData td
			INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate
			INNER JOIN @PartyList p ON td.PartyId = p.PartyID
			INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId
	END

	-- End region

	-- Region: Grand total data

	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20),
		IsApply BIT
	)

	DECLARE @ProductChargeInfo TABLE (
		Rate FLOAT,
		FromDate SMALLDATETIME,
		ToDate SMALLDATETIME,
		MinAmount MONEY,
		MaxAmount MONEY,
		BaseCurrenyCode VARCHAR(20)
	)

	DECLARE @GrandTotal TABLE (
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss		MONEY,
		LicenseeWinLoss		MONEY,
		AmountDueLicensee	MONEY,
		AmountDueSuperlive	MONEY,
		AmountDueCompany	MONEY
	)

	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

	DECLARE @AmountDueSuperlive MONEY

	IF(SELECT COUNT(*) FROM @Result) > 0
	BEGIN
		WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
		BEGIN
			SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
			DELETE FROM #Exchange
			INSERT INTO #Exchange
			SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
			FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency)

			INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,AmountDueLicensee)
			SELECT	@tempCurrency,
					SUM(td.TotalTrans),
					SUM(td.Turnover * e.Rate),
					SUM(td.CustomerWL * e.Rate),
					SUM(td.LicenseeWL * e.Rate),
					SUM(td.AmtLicensee * e.Rate)
			FROM #TempData td
			INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate

			DELETE FROM @ProductChargeInfo

			INSERT INTO @ProductChargeInfo(Rate, FromDate, ToDate, MinAmount, MaxAmount, BaseCurrenyCode)
			SELECT	ci.Rate,
					ci.FromDate,
					ci.ToDate,
					ci.MinAmount * ex.Rate,
					ci.MaxAmount * ex.Rate,
					@tempCurrency
			FROM OAS_ChargeInfo ci
			INNER JOIN #Exchange ex ON ci.BaseCurrencyId = ex.ExchangeID AND ex.ExchangeDate = @ToDate
			WHERE ci.ProductID = 0 AND ci.FromParty = 1 AND ci.ChargeType = 4 -- Get Charge Rate to Billing for Metric Gaming

			SELECT @AmountDueSuperlive = ISNULL(SUM(pci.AmountDueSuperlive),0) FROM @GrandTotal gt OUTER APPLY (
			SELECT
			CASE WHEN (gt.AmountDueLicensee BETWEEN MinAmount AND MaxAmount) AND MinAmount = 0 THEN (gt.AmountDueLicensee - MinAmount) * Rate
				 WHEN (gt.AmountDueLicensee BETWEEN MinAmount AND MaxAmount) AND MinAmount > 0 THEN (gt.AmountDueLicensee - MinAmount) * Rate
				 WHEN (gt.AmountDueLicensee > MaxAmount) THEN (MaxAmount - MinAmount) * Rate
				 ELSE 0 END AS AmountDueSuperlive, pci.MinAmount, pci.MaxAmount
			FROM @ProductChargeInfo pci
			WHERE gt.CurrencyName = pci.BaseCurrenyCode) pci
			WHERE gt.CurrencyName = @tempCurrency
			GROUP BY gt.CurrencyName

			UPDATE @GrandTotal SET AmountDueSuperlive = @AmountDueSuperlive, AmountDueCompany = AmountDueLicensee - @AmountDueSuperlive WHERE CurrencyName = @tempCurrency
			UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
		END
	END
	-- End region

	SELECT * FROM @Result
	SELECT * FROM @GrandTotal

	DROP TABLE #Exchange
	DROP TABLE #TempData
END

GO
GRANT EXECUTE ON [dbo].[LA_Rpt_SuperliveWinLoss] TO [bodbLicenseeNet] AS [dbo]
GRANT EXECUTE ON [dbo].[LA_Rpt_SuperliveWinLoss] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_SuperliveWinLoss] TO [vnteam] AS [dbo]
GO