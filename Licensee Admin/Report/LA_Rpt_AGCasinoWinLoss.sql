/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="1" isNested="0"></info>*/
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
	 
	 Params:
*/
BEGIN
	-- Region: Charge Info
	DECLARE @PartyChargeInfo AS TABLE (
		PartyId		INT,
		LicenseeId	INT,
		ProductID	INT,
		Rate		MONEY,
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME
	)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
	(
		SELECT	PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
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

	-- Region: Get Winloss data
	CREATE TABLE #TempAgent (
		CustId INT
		,Currency INT
		,PartyID INT
		,PartyName NVARCHAR(100)
		,FromDate DATETIME
		,Todate DATETIME)
	CREATE TABLE #TempData (
		PartyID INT
		,PartyName NVARCHAR(100)
		,Winlostdate DATETIME
		,CurrencyId INT
		,Turnover MONEY
		,TotalTrans INT
		,CustomerWinLoss MONEY
		,LicenseeWinloss MONEY
		,LicensingFee MONEY)

	INSERT INTO #TempAgent (CustID,Currency,PartyID,PartyName,FromDate,Todate)
	SELECT	CustID,
		Currency,
		p.PartyID,
		p.PartyName,
		CASE WHEN @FromDate < ci.FromDate THEN ci.FromDate ELSE @FromDate END AS FromDate,
		CASE WHEN @ToDate > ci.ToDate THEN ci.ToDate ELSE @ToDate END AS ToDate
	FROM bodb_Licensee.dbo.f_SelLicenseeCust(0) lc
		INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK) ON lc.LicenseeID = p.OldRefID AND p.PartyType = 1
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON ci.FromParty = p.PartyID
		INNER JOIN bodb_licensee.dbo.LA_ChargeInfo_SystemMapping cs WITH (NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
	WHERE lc.Currency <> 20
		AND p.PartyID IN (SELECT val FROM bodb02.dbo.Lrf_f_StringSplit(@PartyIDs, ','))
		AND ci.ChargeType = 1
		AND ci.ProductID = 10
		AND (@FromDate BETWEEN ci.FromDate AND ci.ToDate OR @ToDate BETWEEN ci.FromDate AND ci.ToDate)

	INSERT INTO #TempData (PartyID,PartyName,Winlostdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee)
	SELECT ag.PartyID
		,ag.PartyName
		,c.Winlostdate
		,co.Currency
		,SUM(c.Turnover) AS Turnover
		,SUM(c.BetCount) AS TotalTrans
		,SUM(c.WinLost) AS CustomerWinLoss
		,- SUM(c.WinLost) AS LicenseeWinloss
		,SUM(-c.WinLost * pc.Rate) AS LicensingFee
	FROM DBACC.bodb_report.dbo.rptDepWinlost_AGCasino c WITH (NOLOCK)
		INNER JOIN DBACC.bodb02.dbo.Custinfo co WITH (NOLOCK) ON c.Custid = co.CustID
		INNER JOIN #TempAgent ag ON co.recommend = ag.CustID AND co.currency=ag.Currency
		INNER JOIN @PartyChargeInfo pc ON pc.PartyId = ag.PartyID AND c.Winlostdate BETWEEN pc.FromDate AND pc.ToDate
	WHERE c.Winlostdate BETWEEN ag.FromDate AND ag.Todate
	GROUP BY c.Winlostdate
		,co.Currency
		,ag.PartyID
		,ag.PartyName
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
		ApplyValue		MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY
	)

	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, ApplyValue)
	SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, td.CurrencyId, td.TotalTrans, td.Turnover, td.CustomerWinLoss, td.LicenseeWinloss, td.LicensingFee,
		CASE WHEN pa.PartyId = 1
			THEN -td.CustomerWinLoss * ec.BaseCurrencyRate
			ELSE -td.CustomerWinLoss * eu.BaseCurrencyRate
		END AS ApplyValue
	FROM #TempData td
		INNER JOIN @PartyList p ON td.PartyId = p.PartyID
		INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId
		INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'CNY') ec ON td.CurrencyId = ec.ExchangeID AND ec.ExchangeDate = td.Winlostdate
		INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'USD') eu ON td.CurrencyId = eu.ExchangeID AND eu.ExchangeDate = td.Winlostdate

	DECLARE @ApplyRange TABLE (ParentId INT, SumApplyValue MONEY, ApplyRate MONEY)

	INSERT INTO @ApplyRange (ParentId, SumApplyValue)
	SELECT ParentId, SUM(ApplyValue)
	FROM #Result
	GROUP BY ParentId

	UPDATE @ApplyRange
	SET ApplyRate = CASE WHEN ParentId = 1
						THEN
							CASE WHEN SumApplyValue <= 15000000 THEN 0.08 ELSE 0.07 END
						ELSE
							CASE WHEN SumApplyValue <= 2500000 THEN 0.08 ELSE 0.07 END
						END

	UPDATE r
	SET r.PayToSupplier = a.ApplyRate * r.LicenseeWinLoss
	FROM #Result r INNER JOIN @ApplyRange a ON r.ParentId = a.ParentId
	-- End Region

	-- Exchange
	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	UPDATE #Exchange SET CurrencyCode = 'INH' WHERE ExchangeID = 51
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
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20),
		IsApply BIT
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

	INSERT INTO @BaseCurrencies(Id, Name) VALUES (1, 'SGD') -- Include SGD to report

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

		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee, PayToSupplier)
		SELECT Currency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(LicensingFee),
			SUM(CASE WHEN PayToSupplier < 0 THEN 0 ELSE PayToSupplier END)
		FROM @Total
		WHERE Currency = @tempCurrency
		GROUP BY Currency

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
	END
	UPDATE @GrandTotal SET CompanyIncome = LicensingFee - PayToSupplier
	-- End Region

	-- Region: Select Data
	IF @BaseCurrencyName = ''
	BEGIN
		--Result
		SELECT r.PartyId,
			r.PartyName,
			r.ParentId,
			r.ParentName,
			r.WinLossDate,
			r.CurrencyId,
			e.CurrencyCode AS CurrencyName,
			r.TotalTrans,
			r.Turnover,
			r.CustomerWinLoss,
			r.LicenseeWinLoss,
			r.LicensingFee,
			r.PayToSupplier,
			(r.LicensingFee - r.PayToSupplier) AS CompanyIncome
		FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.WinLossDate

		-- Grand Total
		SELECT * FROM @GrandTotal
	END
	ELSE
	BEGIN
		-- Result
		SELECT r.PartyId,
			r.PartyName,
			r.ParentId,
			r.ParentName,
			r.WinLossDate,
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
		FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.WinLossDate

		-- Grand Total
		SELECT * FROM @GrandTotal

		-- Total
		SELECT PartyId,
			TotalTrans,
			Turnover,
			CustomerWinLoss,
			LicenseeWinLoss,
			LicensingFee,
			CASE WHEN PayToSupplier < 0 THEN 0 ELSE PayToSupplier END PayToSupplier,
			(LicensingFee - (CASE WHEN PayToSupplier < 0 THEN 0 ELSE PayToSupplier END)) CompanyIncome
		FROM @Total t
		WHERE Currency = @BaseCurrencyName
	END
	-- End Region

	DROP TABLE #TempData
	DROP TABLE #TempAgent
	DROP TABLE #Exchange
	DROP TABLE #Result
END

GO
GRANT EXECUTE ON [dbo].[LA_Rpt_AGCasinoWinLoss] TO [bodbLicenseeNet] AS [dbo]
GRANT EXECUTE ON [dbo].[LA_Rpt_AGCasinoWinLoss] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_AGCasinoWinLoss] TO [vnteam] AS [dbo]
GO