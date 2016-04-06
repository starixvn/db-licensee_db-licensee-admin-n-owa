USE [bodb_Licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_AGCasinoWinLoss]    Script Date: 12/21/2015 06:47:11 ******/
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
	 Created: 20160225@Bravo
	 Task : Get report Cock Fighting Win Loss
	 DB: DB052.bodb_licensee
   
	 Revisions:  
	 - 20160225@Bravo: Get CF win loss data.
	 Params:			   
*/
BEGIN	
	-- Region: Charge Info
	DECLARE @tempBaseCurrency VARCHAR(10) = @BaseCurrencyName
	IF @tempBaseCurrency = ''
	BEGIN
		SET @tempBaseCurrency = 'GBP'
	END

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

	-- Region: Get exchange rate info
	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempBaseCurrency)

	UPDATE #Exchange 
	SET CurrencyCode = 'INH'
	WHERE ExchangeID = 51
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
		,TurnOver MONEY
		,TotalTrans INT
		,Winlost MONEY
		,LicenseeWinlost MONEY
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
	
	INSERT INTO #TempData (PartyID,PartyName,Winlostdate,CurrencyId,TurnOver,TotalTrans,Winlost,LicenseeWinlost,LicensingFee)
	SELECT ag.PartyID
		,ag.PartyName
		,c.Winlostdate
		,co.Currency
		,SUM(c.TurnOver) AS TurnOver
		,SUM(c.BetCount) AS TotalTrans
		,SUM(c.Winlost) AS Winlost
		,- SUM(c.Winlost) AS LicenseeWinlost
		,SUM(-c.Winlost * pc.Rate) AS LicensingFee
	FROM DBACC.bodb_report.dbo.rptDepWinlost_AGCasino c WITH (NOLOCK)
		INNER JOIN DBACC.bodb02.dbo.Custinfo co WITH (NOLOCK) ON c.CustID = co.CustID
		INNER JOIN #TempAgent ag ON co.recommend = ag.CustID AND co.currency=ag.Currency
		INNER JOIN @PartyChargeInfo pc ON pc.PartyId = ag.PartyID
	WHERE c.Winlostdate BETWEEN ag.FromDate AND ag.Todate --AND c.Winlost<0
	GROUP BY c.Winlostdate
		,co.Currency
		,ag.PartyID
		,ag.PartyName

	-- EndRegion
	
	CREATE TABLE #Result (
		PartyId			INT,
		PartyName		VARCHAR(100),
		ParentId		INT,
		ParentName		VARCHAR(100),
		WinLossDate		DATETIME,
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,		
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,		
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)

	IF @BaseCurrencyName = ''
	BEGIN 
		INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyName, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee)
		SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, e.CurrencyCode, td.TotalTrans, td.Turnover, td.Winlost, td.LicenseeWinlost, td.LicensingFee
		FROM #TempData td 
			INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.Winlostdate
			INNER JOIN @PartyList p ON td.PartyId = p.PartyID
			INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId
			
		
	END 
	ELSE 
	BEGIN
		INSERT INTO #Result (PartyId,PartyName,ParentId,ParentName,WinLossDate,CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee)
		SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.Winlostdate, e.CurrencyCode, td.TotalTrans, td.Turnover*e.Rate, td.Winlost*e.Rate, td.LicenseeWinlost*e.Rate, td.LicensingFee * e.Rate
		FROM #TempData td 
			INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.Winlostdate
			INNER JOIN @PartyList p ON td.PartyId = p.PartyID
			INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId		
			
	END
	
	DECLARE @Total TABLE (	
		PartyId			INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,		
		LicenseeWinLoss	MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)
	
	DECLARE @MYR MONEY
	DECLARE @USD MONEY
	SELECT @MYR = (SELECT TOP 1 15000000 * e.Rate
					FROM #Exchange e
					WHERE e.CurrencyCode = 'MYR'
					ORDER BY e.ExchangeDate DESC)	
	SELECT @USD = (SELECT TOP 1 2500000 * e.Rate
					FROM #Exchange e
					WHERE e.CurrencyCode = 'USD'
					ORDER BY e.ExchangeDate DESC)	

	DECLARE @3rdRate TABLE(
		GroupId  INT,
		MinValue MONEY,
		MaxValue MONEY,
		Rate	 MONEY,
		IsApply  BIT)
	
	INSERT INTO @3rdRate(GroupId,  MinValue, MaxValue, Rate)
	VALUES (1,  0, @MYR, 0.08) , 
		(1,  @MYR, 1000000000000, 0.07) , 
		(11,  0, @USD, 0.08) , 
		(11,  @USD, 1000000000000, 0.07)

	INSERT INTO @Total (PartyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee)
	SELECT d.ParentId,
		SUM(d.TotalTrans),
		SUM(d.Turnover),
		SUM(d.CustomerWinLoss),
		SUM(d.LicenseeWinLoss),
		CASE WHEN SUM(d.LicensingFee) < 0 THEN 0 ELSE SUM(d.LicensingFee) END LicensingFee
	FROM #Result d
	GROUP BY d.ParentId
	
	UPDATE t
	SET t.PayToSupplier = t.LicensingFee * r.Rate
	FROM @Total t INNER JOIN @3rdRate r ON t.PartyId = r.GroupId AND CASE WHEN -t.CustomerWinLoss < 0 THEN 0 ELSE -t.CustomerWinLoss END BETWEEN r.MinValue AND r.MaxValue
	UPDATE @Total SET PayToSupplier = ISNULL(PayToSupplier, 0), CompanyIncome = LicensingFee - ISNULL(PayToSupplier, 0)

	UPDATE r
	SET r.IsApply = 1
	FROM @Total t INNER JOIN @3rdRate r ON t.PartyId = r.GroupId AND CASE WHEN -t.CustomerWinLoss < 0 THEN 0 ELSE -t.CustomerWinLoss END BETWEEN r.MinValue AND r.MaxValue

	UPDATE r 
	SET r.PayToSupplier = r.LicensingFee * rd.Rate, r.CompanyIncome = r.LicensingFee - r.LicensingFee * rd.Rate
	FROM #Result r INNER JOIN @3rdRate rd ON r.ParentId = rd.GroupId AND rd.IsApply = 1

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
	
	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
		PRINT @tempCurrency
		DELETE FROM #Exchange
		INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
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
		FROM @Total td 
			INNER JOIN #Exchange e ON e.CurrencyCode = @tempBaseCurrency AND e.ExchangeDate = (SELECT MAX(ex.ExchangeDate)
																								FROM #Exchange ex
																								WHERE @tempBaseCurrency = ex.CurrencyCode)

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
	END
	
	SELECT * FROM #Result
	SELECT * FROM @GrandTotal
	
	IF @BaseCurrencyName <> ''
	BEGIN
		SELECT * FROM @Total
	END
	
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