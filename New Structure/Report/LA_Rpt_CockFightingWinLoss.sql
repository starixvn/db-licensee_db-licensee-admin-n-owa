USE [bodb_Licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_CockFightingWinLoss]    Script Date: 12/21/2015 06:47:11 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_CockFightingWinLoss]          
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
		FROM	dbo.LA_f_ChargeInfo(@PartyIds, @FromDate, @ToDate, 'CF', 'OA', 1)
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
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	UPDATE #Exchange 
	SET CurrencyCode = 'INH'
	WHERE ExchangeID = 51
	-- End region
	
	-- Region: Get Winloss data
	CREATE	TABLE #TempData (
		LicenseeId	INT,
		PartyId		INT,
		rptDate		DATETIME,
		CurrencyId	INT,
		TotalTrans	INT,
		Turnover	MONEY,
		MemberWL	MONEY,
		LicWL		MONEY,			
		AmountDue   MONEY
	)
	
	INSERT INTO #TempData (LicenseeId, PartyId, rptDate, CurrencyId, TotalTrans, Turnover, MemberWL, LicWL, AmountDue)
	(
		SELECT	b.SiteID,
				p.PartyId,
				b.rptDate,
				b.CurrencyID,
				SUM(ISNULL(b.BetCount, 0)) TotalTrans,
				SUM(ISNULL(b.Turnover, 0)) Turnover,
				SUM(ISNULL(b.MemberWL, 0)) MemberWL,
				SUM(ISNULL(-b.MemberWL, 0)) LicWL,
				SUM(ISNULL(-b.MemberWL * p.Rate, 0)) AmountDue
		FROM	bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
				INNER JOIN @PartyChargeInfo p ON b.ProductID = p.ProductID 
												AND b.SiteID = p.LicenseeId
												AND b.rptDate BETWEEN p.FromDate AND p.ToDate
		WHERE	b.rptDate BETWEEN @FromDate AND @ToDate
				AND (b.CurrencyID <> 20)
				AND b.customercategory NOT IN (27, 28)
				AND b.Bettype NOT IN (901,902,903)
		GROUP BY b.rptdate, b.SiteId, p.PartyId, b.CurrencyID, b.ProductId
	)
	
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
		AmountDueTo		MONEY
	)

	IF @BaseCurrencyName = ''
	BEGIN 
		INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyName, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, AmountDueTo)
		SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.rptDate, e.CurrencyCode, td.TotalTrans, td.Turnover, td.MemberWL, td.LicWL, td.AmountDue
		FROM #TempData td 
			INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate
			INNER JOIN @PartyList p ON td.PartyId = p.PartyID
			INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId
		
	END 
	ELSE 
	BEGIN
		INSERT INTO #Result (PartyId,PartyName,ParentId,ParentName,WinLossDate,CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,AmountDueTo)
		SELECT td.PartyId, p.PartyName, pa.PartyId, pa.PartyName, td.rptDate, e.CurrencyCode, td.TotalTrans, td.Turnover*e.Rate, td.MemberWL*e.Rate, td.LicWL*e.Rate, td.AmountDue*e.Rate
		FROM #TempData td 
			INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate
			INNER JOIN @PartyList p ON td.PartyId = p.PartyID
			INNER JOIN @PartyList pa ON p.ParentId = pa.PartyId		
	END
	
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20),
		IsApply BIT
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC LA_SelBaseCurrency

	CREATE TABLE #GrandTotal (		
		CurrencyName	VARCHAR(20),
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,		
		LicenseeWinLoss	MONEY,
		AmountDueTo		MONEY
	)
	
	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
		PRINT @tempCurrency
		DELETE FROM #Exchange
		INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
		SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
		FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency)

		INSERT INTO #GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,AmountDueTo)
		SELECT	@tempCurrency, 
				SUM(td.TotalTrans),
				SUM(td.Turnover*e.Rate), 
				SUM(td.MemberWL*e.Rate), 
				SUM(td.LicWL*e.Rate), 
				SUM(td.AmountDue*e.Rate)
		FROM #TempData td 
			INNER JOIN #Exchange e ON td.CurrencyId = e.ExchangeID AND e.ExchangeDate = td.rptDate				

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
	END
	
	SELECT * FROM #Result
	SELECT * FROM #GrandTotal
	
	DROP TABLE #TempData
	DROP TABLE #Exchange
	DROP TABLE #Result
	DROP TABLE #GrandTotal
END

GO
GRANT EXECUTE ON [dbo].[LA_Rpt_CockFightingWinLoss] TO [bodbLicenseeNet] AS [dbo]
GRANT EXECUTE ON [dbo].[LA_Rpt_CockFightingWinLoss] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_CockFightingWinLoss] TO [vnteam] AS [dbo]