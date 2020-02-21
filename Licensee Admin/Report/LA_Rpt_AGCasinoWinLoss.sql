/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].LA_Rpt_AGCasinoWinLoss
	@PartyIds			VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20)
AS
/*
	 Created: 20160420@Bravo
	 Task : Get report AG Casino Win Loss
	 DB: DB052.bodb_licensee

	 Revisions:
	 - 20160420@Bravo: Get AG Casino win loss data.
	 - 20160920@Bruce: #64425-Update AG Casino PayToSupplier = winloss * rate
	 - 20170623@Bruce: include original currency [#78398]
	 - 20171219@Bruce: increase length for variables [#88197]
	 - 20180302@Harper: Support SGD as base currency for AG WL report [RedmineID: #91339]
	 - 20180716@bruce: add new group TEST for credit [#98126]
	 - 20180628@Scofield: Update calculation formula for AG& GD report [#94283]
	 - 20190627@Bruce: Select data from rpt_BettingByProduct [#113641]
	 - 20191226@Mason: Set billing term by currency [#120005]
	 
	 Params:
*/
BEGIN
	-- Region: Charge Info
	DECLARE @PartyChargeInfo AS TABLE (
		ChargeId	INT,
		PartyId		INT,
		LicenseeId	INT,
		ProductID	INT,
		Rate		MONEY,
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME
	)

	INSERT INTO @PartyChargeInfo(ChargeId, PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
	(
		SELECT	ChargeId, PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
		FROM	dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'AGC', 'OA', 1)
		WHERE	DI_Rate > 0
	)
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
	-- Endregion

	SELECT pc.PartyId
		,c.rptDate
		,c.CurrencyId
		,SUM(c.Turnover)								AS Turnover
		,SUM(c.BetCount)								AS TotalTrans
		,SUM(c.MemberWL)								AS CustomerWinLoss
		,-SUM(c.MemberWL)								AS LicenseeWinloss
		,SUM(-c.MemberWL * ISNULL(cr.Rate, pc.Rate))	AS LicensingFee
		,CAST(0 AS INT)									AS ParentId
		,CAST('' AS VARCHAR(50))						AS PartyName
		,CAST('' AS VARCHAR(50))						AS ParentName
		,CAST(0 AS MONEY)								AS ApplyValue
		,CAST(0 AS MONEY)								AS PayToSupplier
	INTO #TempData
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct c WITH (NOLOCK)
		INNER JOIN @PartyChargeInfo pc ON pc.LicenseeId = c.SiteID AND c.ProductID = pc.ProductID AND c.rptDate BETWEEN pc.FromDate AND pc.ToDate
		LEFT JOIN bodb_licensee.dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON pc.ChargeId = cr.ChargeID AND cr.CurrencyID = c.CurrencyId
	WHERE c.CurrencyId <> 20 -- exclude test currency
		AND c.customercategory NOT IN (27, 28)
		AND c.StatusId BETWEEN 111 AND 115
	GROUP BY c.rptDate,c.CurrencyId,pc.PartyId
	-- EndRegion

	-- Region: Calculate PayToSupplier

	-- oneworks: convert to CNY
	-- others: convert to USD
	UPDATE td SET
		PartyName = p.PartyName,
		ParentId = pa.PartyId,
		ParentName = pa.PartyName,
		ApplyValue = CASE WHEN pa.PartyId = 1 -- group Oneworks
			THEN -td.CustomerWinLoss * ec.BaseCurrencyRate
			ELSE -td.CustomerWinLoss * eu.BaseCurrencyRate
		END
	FROM #TempData td
		INNER JOIN @PartyList p ON td.PartyId = p.PartyID AND p.ParentId > 0		-- party
		INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId AND pa.ParentId = 0		-- billing group
		INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'CNY') ec ON td.CurrencyId = ec.ExchangeID AND ec.ExchangeDate = td.rptDate
		INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'USD') eu ON td.CurrencyId = eu.ExchangeID AND eu.ExchangeDate = td.rptDate

	DECLARE @ApplyRange TABLE (ParentId INT, SumApplyValue MONEY, ApplyRate MONEY)

	INSERT INTO @ApplyRange (ParentId, SumApplyValue)
	SELECT ParentId, SUM(ApplyValue)
	FROM #TempData
	GROUP BY ParentId

	UPDATE @ApplyRange
	SET ApplyRate = CASE WHEN ParentId = 1 -- Oneworks
		THEN CASE WHEN SumApplyValue <= 15000000 THEN 0.08 ELSE 0.07 END
		ELSE CASE WHEN SumApplyValue <= 2500000 THEN 0.08 ELSE 0.07 END
	END

	UPDATE r
	SET r.PayToSupplier = a.ApplyRate * r.LicenseeWinLoss
	FROM #TempData r INNER JOIN @ApplyRange a ON r.ParentId = a.ParentId
	-- End Region

	-- Exchange
	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate, CurrencyCode)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate, CASE WHEN ExchangeID = 51 THEN 'INH' ELSE Code END
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	-- End

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
	DECLARE @BaseCurrencies TABLE(Id INT, [Name] VARCHAR(20))
	INSERT INTO @BaseCurrencies(Id, [Name])
	EXEC LA_SelBaseCurrency

	INSERT INTO @BaseCurrencies(Id, [Name]) VALUES (1, 'SGD') -- Include SGD to report

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
			FROM #TempData td 
			INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.rptDate
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

		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee, PayToSupplier)
		SELECT Currency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(LicensingFee),
			SUM(PayToSupplier)
		FROM @Total
		WHERE Currency = @tempCurrency
		GROUP BY Currency

		DELETE @BaseCurrencies WHERE [Name] = @tempCurrency
	END
	UPDATE @GrandTotal SET CompanyIncome = LicensingFee - PayToSupplier
	-- End Region

	-- Region: Select Data
	SELECT r.PartyId,
		r.PartyName,
		r.ParentId,
		r.ParentName,
		r.rptDate AS WinLossDate,
		r.CurrencyId,
		e.CurrencyCode AS CurrencyName,
		r.TotalTrans,
		-- base
		CAST(r.Turnover * e.Rate AS MONEY) AS Turnover,
		CAST(r.CustomerWinLoss * e.Rate AS MONEY) AS CustomerWinLoss,
		CAST(r.LicenseeWinLoss * e.Rate AS MONEY) AS LicenseeWinLoss,
		CAST(r.LicensingFee * e.Rate AS MONEY) AS LicensingFee,
		CAST(r.PayToSupplier * e.Rate AS MONEY) AS PayToSupplier,
		CAST((r.LicensingFee - r.PayToSupplier) * e.Rate AS MONEY) AS CompanyIncome,
		-- original
		r.Turnover AS TurnoverOriginal,
		r.CustomerWinLoss AS CustomerWinLossOriginal,
		r.LicenseeWinLoss AS LicenseeWinLossOriginal,
		r.LicensingFee AS LicensingFeeOriginal,
		r.PayToSupplier AS PayToSupplierOriginal,
		(r.LicensingFee - r.PayToSupplier) AS CompanyIncomeOriginal
	FROM #TempData r 
	INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.rptDate

	-- Grand Total
	SELECT * FROM @GrandTotal

	IF @BaseCurrencyName <> ''
	BEGIN
		-- Total
		SELECT PartyId,
			TotalTrans,
			Turnover,
			CustomerWinLoss,
			LicenseeWinLoss,
			LicensingFee,
			PayToSupplier,
			(LicensingFee - PayToSupplier) CompanyIncome
		FROM @Total t
		WHERE Currency = @BaseCurrencyName
	END
	-- End Region: Select Data

	DROP TABLE #TempData
	DROP TABLE #Exchange
END
GO