/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Rpt_PokerGamesWinLoss]
	@PartyIds			VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20)
AS
/*  
	 Created: 20180910@Scofield [#94108]
	 Task : Get Poker Games Report
	 DB: DBLIC.bodb_licensee   

	 Revisions:  
		- 20180910@Scofield: Win loss reports for Poker Games & Bullfighting [#98487]
		- 20200303@Mason: Support HID currency [#128856]
	 Params:

	 Explannation: EXEC LA_Rpt_PokerGamesWinLoss @BaseCurrencyName='EUR',@ToDate='2018-04-30 00:00:00',@PartyIds='25,30,324',@FromDate='2018-04-01 00:00:00'
*/
BEGIN	
	DECLARE @PGProductID INT = 33
	
	-- Region: Charge Info	
	DECLARE @ChargeInfos AS TABLE (
		PartyId					INT,
		ProductID				INT,
		LicenseeId				INT,		
		PayToSupplierRate		MONEY,
		PayToExtraRate			MONEY,
		CompanyIncomeRate		MONEY,
		FromDate				SMALLDATETIME,
		ToDate					SMALLDATETIME)	
	
	INSERT INTO @ChargeInfos(PartyId, ProductID, LicenseeId, PayToSupplierRate, PayToExtraRate, CompanyIncomeRate, Fromdate, Todate)
	(
		SELECT c.PartyID, c.ProductID, c.LicenseeID, 0.04, 0.05, 0.06, c.Fromdate, c.Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIDs, @FromDate, @ToDate, 'PG') c
	)
	-- End region

	-- Region: Party List
	DECLARE @PartyList AS TABLE (PartyId INT, PartyName	VARCHAR(100), BranchName VARCHAR(100), ParentId	INT, ParentName VARCHAR(100))

	INSERT INTO @PartyList (PartyId, PartyName, BranchName, ParentId)
	EXEC LA_PartyListSel

	UPDATE p
	SET p.ParentName = pa.PartyName
	FROM @PartyList p
	INNER JOIN @PartyList pa ON pa.ParentId = 0 AND p.ParentId = pa.PartyId

	DELETE p
	FROM @PartyList p
	WHERE NOT EXISTS (SELECT 1 FROM @ChargeInfos ci WHERE ci.PartyId = p.PartyId)
	-- Endregion	

	-- Region: #Result
	CREATE TABLE #Result (
		PartyID			INT,
		PartyName		NVARCHAR(100),
		ParentId		INT,
		ParentName		VARCHAR(100),	
		Winlossdate 	DATETIME,
		CurrencyId		INT,
		Turnover		MONEY,
		TotalTrans		INT,
		CustomerWinLoss MONEY,
		GemBought 		MONEY,
		RakeAmount 		MONEY,
		InsuranceWinLoss	MONEY,		
		PayToSupplier	MONEY,
		PayToExtra	 	MONEY,		
		CompanyIncome	MONEY)	

	INSERT INTO #Result (PartyID,PartyName,ParentId,ParentName,Winlossdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,GemBought,RakeAmount,InsuranceWinLoss,PayToSupplier,PayToExtra,CompanyIncome)
	SELECT ci.PartyId,
		p.PartyName,
		p.ParentId,
		p.ParentName,
		b.rptDate,
		b.CurrencyId,
		SUM(b.Turnover) AS Turnover,
		SUM(b.BetCount) AS TotalTrans,
		SUM(b.MemberWL) AS CustomerWinLoss,
		SUM(CASE WHEN b.Bettype = 1499 THEN -b.ExtraAmount / 10000 ELSE 0 END) AS GemBought,
		SUM(b.ValidBetAmount) AS RakeAmount,
		SUM(CASE WHEN b.Bettype <> 1499 THEN -b.ExtraAmount / 10000 ELSE 0 END) AS InsuranceWinLoss,
		SUM((-b.ExtraAmount / 10000 + b.ValidBetAmount) * ci.PayToSupplierRate) AS PayToSupplier,
		SUM((-b.ExtraAmount / 10000 + b.ValidBetAmount) * ci.PayToExtraRate) AS PayToExtra,
		SUM((-b.ExtraAmount / 10000 + b.ValidBetAmount) * ci.CompanyIncomeRate) AS CompanyIncome		
	FROM bodb_LicenseeReport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
		INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId 
									AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
		INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate 
		AND b.StatusId NOT IN (-1, 101, 102, 103) 
		AND b.CurrencyId <> 20 
		AND b.ProductID = @PGProductID
	GROUP BY b.rptDate, ci.PartyId, PartyName, ParentId, ParentName, b.CurrencyId
	-- EndRegion #Result

	-- Region: Exchange
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
	-- End Region
	
	DECLARE @Total TABLE (
		PartyId				INT,
		TotalTrans			INT,
		Turnover			MONEY,
		CustomerWinLoss		MONEY,
		GemBought 			MONEY,
		RakeAmount 			MONEY,
		InsuranceWinLoss	MONEY,		
		PayToSupplier		MONEY,
		PayToExtra	 		MONEY,		
		CompanyIncome		MONEY,
		Currency			VARCHAR(20)
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

	DECLARE @GrandTotal TABLE (
		CurrencyName		VARCHAR(20),
		TotalTrans			INT,
		Turnover			MONEY,
		CustomerWinLoss		MONEY,
		GemBought 			MONEY,
		RakeAmount 			MONEY,
		InsuranceWinLoss	MONEY,		
		PayToSupplier		MONEY,
		PayToExtra	 		MONEY,		
		CompanyIncome		MONEY
	)	

	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
		
		;WITH TotalByParty AS(
			SELECT td.ParentId,
				SUM(td.TotalTrans) TotalTrans,
				SUM(td.Turnover * e.BaseCurrencyRate) Turnover, 
				SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss, 
				SUM(td.GemBought * e.BaseCurrencyRate) GemBought, 
				SUM(td.RakeAmount * e.BaseCurrencyRate) RakeAmount, 
				SUM(td.InsuranceWinLoss * e.BaseCurrencyRate) InsuranceWinLoss, 
				SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier,
				SUM(td.PayToExtra * e.BaseCurrencyRate) PayToExtra, 
				SUM(td.CompanyIncome * e.BaseCurrencyRate) CompanyIncome
			FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e 
			ON e.ExchangeID = td.CurrencyId 
				AND e.ExchangeDate = td.WinLossDate
			GROUP BY td.ParentId, td.PartyId
		)
		INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,GemBought,RakeAmount,InsuranceWinLoss,PayToSupplier,PayToExtra,CompanyIncome)
		SELECT @tempCurrency,ParentId,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(GemBought),
			SUM(RakeAmount),
			SUM(InsuranceWinLoss),
			SUM(PayToSupplier),
			SUM(PayToExtra),			
			SUM(CompanyIncome)
		FROM TotalByParty
		GROUP BY ParentId

		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,GemBought,RakeAmount,InsuranceWinLoss,PayToSupplier,PayToExtra,CompanyIncome)
		SELECT Currency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(GemBought),
			SUM(RakeAmount),
			SUM(InsuranceWinLoss),
			SUM(PayToSupplier),
			SUM(PayToExtra),			
			SUM(CompanyIncome)			
		FROM @Total
		WHERE Currency = @tempCurrency
		GROUP BY Currency

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
	END	
	-- End Region

	-- Region: Select Data
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
		CAST(r.GemBought * e.Rate AS MONEY) AS GemBought,
		CAST(r.RakeAmount * e.Rate AS MONEY) AS RakeAmount,
		CAST(r.InsuranceWinLoss * e.Rate AS MONEY) AS InsuranceWinLoss,
		CAST(r.PayToSupplier * e.Rate AS MONEY) AS PayToSupplier,
		CAST(r.PayToExtra * e.Rate AS MONEY) AS PayToExtra,
		CAST(r.CompanyIncome * e.Rate AS MONEY) AS CompanyIncome,
		-- original
		r.Turnover AS TurnoverOriginal,
		r.CustomerWinLoss AS CustomerWinLossOriginal,
		r.GemBought AS GemBoughtOriginal,
		r.RakeAmount AS RakeAmountOriginal,
		r.InsuranceWinLoss AS InsuranceWinLossOriginal,
		r.PayToSupplier AS PayToSupplierOriginal,
		r.PayToExtra AS PayToExtraOriginal,
		r.CompanyIncome AS CompanyIncomeOriginal
	FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID 
											AND e.ExchangeDate = r.WinLossDate

	-- Grand Total
	SELECT * FROM @GrandTotal
			
	IF @BaseCurrencyName <> ''
	BEGIN		
		-- Total
		SELECT PartyId,
			TotalTrans,
			Turnover,
			CustomerWinLoss,	
			GemBought,
			RakeAmount,
			InsuranceWinLoss,
			PayToExtra,
			PayToSupplier,
			CompanyIncome
		FROM @Total t
		WHERE Currency = @BaseCurrencyName
	END
	-- End Region

	DROP TABLE #Exchange
	DROP TABLE #Result
END
GO
