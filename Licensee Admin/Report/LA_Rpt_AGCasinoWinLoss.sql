USE [bodb_Licensee]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_AGCasinoWinLoss]          
	@PartyIds			VARCHAR(500),
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

	-- Region: Get base exchange rate info	
	CREATE TABLE #ExchangeUSD (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)
	
	INSERT INTO #ExchangeUSD(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'USD')

	CREATE TABLE #ExchangeCNY (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)
	
	INSERT INTO #ExchangeCNY(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, 'CNY')		
	-- End region
	
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
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)
		
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, ApplyValue)
	SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, td.CurrencyId, td.TotalTrans, td.Turnover, td.CustomerWinLoss, td.LicenseeWinloss, td.LicensingFee,
		CASE WHEN pa.PartyId = 1 THEN -td.CustomerWinLoss * ec.Rate ELSE -td.CustomerWinLoss * eu.Rate END AS ApplyValue
	FROM #TempData td 	
		INNER JOIN @PartyList p ON td.PartyId = p.PartyID
		INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId		
		INNER JOIN #ExchangeCNY ec ON td.CurrencyId = ec.ExchangeID AND ec.ExchangeDate = td.Winlostdate
		INNER JOIN #ExchangeUSD eu ON td.CurrencyId = eu.ExchangeID AND eu.ExchangeDate = td.Winlostdate
	
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
	SET r.PayToSupplier = a.ApplyRate * r.LicensingFee, r.CompanyIncome = r.LicensingFee - a.ApplyRate * r.LicensingFee
	FROM #Result r INNER JOIN @ApplyRange a ON r.ParentId = a.ParentId
	-- End Region

	-- Calculate Total
	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)	
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
		
	UPDATE #Exchange 
	SET CurrencyCode = 'INH'
	WHERE ExchangeID = 51

	DECLARE @LicensingFee TABLE (
		PartyId		INT,
		LicenseeWL	MONEY,
		IsApply		BIT)
	
	INSERT INTO @LicensingFee(PartyId, LicenseeWL)
	SELECT r.PartyId,SUM(r.LicenseeWinLoss * e.Rate)
	FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND r.WinLossDate = e.ExchangeDate
	GROUP BY r.PartyId
	
	UPDATE @LicensingFee
	SET IsApply = CASE WHEN LicenseeWL < 0 THEN 0 ELSE 1 END
	
	DECLARE @Total TABLE (	
		PartyId			INT,
		ParentId		INT,
		CurrencyId		INT,
		WinLossDate		DATETIME,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,		
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)

	INSERT INTO @Total (PartyId, ParentId, CurrencyId, WinLossDate, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee)
	SELECT 
		r.PartyId,
		r.ParentId,
		r.CurrencyId,
		r.WinLossDate,
		SUM(r.TotalTrans),
		SUM(r.Turnover),
		SUM(r.CustomerWinLoss),
		SUM(r.LicenseeWinLoss),
		SUM(CASE WHEN l.IsApply = 1 THEN r.LicensingFee ELSE 0 END)
	FROM #Result r INNER JOIN @LicensingFee l ON r.PartyId = l.PartyId
	GROUP BY r.PartyId, r.ParentId, r.CurrencyId, r.WinLossDate
	
	UPDATE t
	SET t.PayToSupplier = a.ApplyRate * t.LicensingFee, t.CompanyIncome = t.LicensingFee - a.ApplyRate * t.LicensingFee
	FROM @Total t INNER JOIN @ApplyRange a ON t.ParentId = a.ParentId
	-- End Region
	
	-- Region: Calculate Grand Total
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20),
		IsApply BIT
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

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
	
	CREATE TABLE #ExchangeBase (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)	
	
	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
		PRINT @tempCurrency
		DELETE FROM #ExchangeBase
		INSERT INTO #ExchangeBase(ExchangeDate, ExchangeID, CurrencyCode, Rate)
		SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
		FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency)
		
		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee, PayToSupplier, CompanyIncome)
		SELECT	@tempCurrency, 
				SUM(td.TotalTrans),
				SUM(td.Turnover*e.Rate), 
				SUM(td.CustomerWinLoss*e.Rate), 
				SUM(td.LicenseeWinLoss*e.Rate), 
				SUM(td.LicensingFee *e.Rate),
				SUM(td.PayToSupplier * e.Rate),
				SUM(td.CompanyIncome * e.Rate)
		FROM @Total td INNER JOIN #ExchangeBase e ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
	END
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
			r.CompanyIncome
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
			CAST(r.Turnover * e.Rate AS MONEY) AS Turnover,
			CAST(r.CustomerWinLoss * e.Rate AS MONEY) AS CustomerWinLoss,
			CAST(r.LicenseeWinLoss * e.Rate AS MONEY) AS LicenseeWinLoss,
			CAST(r.LicensingFee * e.Rate AS MONEY) AS LicensingFee,
			CAST(r.PayToSupplier * e.Rate AS MONEY) AS PayToSupplier,
			CAST(r.CompanyIncome * e.Rate AS MONEY) AS CompanyIncome
		FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.WinLossDate

		-- Grand Total
		SELECT * FROM @GrandTotal

		-- Total
		SELECT t.ParentId AS PartyId,
			SUM(TotalTrans) TotalTrans,
			CAST(SUM(Turnover * e.Rate) AS MONEY) Turnover,
			CAST(SUM(CustomerWinLoss * e.Rate) AS MONEY) CustomerWinLoss,		
			CAST(SUM(LicenseeWinLoss * e.Rate) AS MONEY) LicenseeWinLoss,
			CAST(SUM(LicensingFee * e.Rate) AS MONEY) LicensingFee,
			CAST(SUM(PayToSupplier * e.Rate) AS MONEY) PayToSupplier,
			CAST(SUM(CompanyIncome * e.Rate) AS MONEY) CompanyIncome
		FROM @Total t
			INNER JOIN #Exchange e ON t.CurrencyId = e.ExchangeID AND e.ExchangeDate = t.WinLossDate
		GROUP BY ParentId
	END
	-- End Region

	DROP TABLE #TempData
	DROP TABLE #TempAgent
	DROP TABLE #Exchange
	DROP TABLE #ExchangeCNY
	DROP TABLE #ExchangeUSD
	DROP TABLE #ExchangeBase
	DROP TABLE #Result
END

GO
GRANT EXECUTE ON [dbo].[LA_Rpt_AGCasinoWinLoss] TO [bodbLicenseeNet] AS [dbo]
GRANT EXECUTE ON [dbo].[LA_Rpt_AGCasinoWinLoss] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_AGCasinoWinLoss] TO [vnteam] AS [dbo]