/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

CREATE PROCEDURE [dbo].[LA_Rpt_BetBuilderWinLoss]
	@PartyIds			VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20)
AS
/*  
	 Created: 20190221@Scofield [#108995]
	 Task : Get report Pragmatic Win Loss
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20190221@Scofield: Bet Builder Win Loss [#108995]
	 Params:

	 Explannation: EXEC LA_Rpt_BetBuilderWinLoss @BaseCurrencyName='EUR',@ToDate='2018-04-30 00:00:00',@PartyIds='14,15,17,19,20,23,29,39,40,42,44,46,47,52,53,56,58,60,65,68,70,71,72,73,76,79,80,81,82,84,85,86,87,89,90,91,92,93,95,97,100,101,24,31,34,35,36,37,38,41,59,66,67,74,75,88,16,22,26,27,45,49,54,99,25,30',@FromDate='2018-04-01 00:00:00'
*/
BEGIN	
	-- Region: Charge Info	
	DECLARE @ChargeInfos AS TABLE (
		PartyId		INT,
		LicenseeId	INT,
		isDeposit	BIT,
		ProductID	INT,
		Rate		MONEY,
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME)	
	
	INSERT INTO @ChargeInfos(PartyId, ProductID, LicenseeId, isDeposit, Rate, Fromdate, Todate)
	(
		SELECT DISTINCT c.PartyID, c.ProductID, c.LicenseeID, ISNULL(c.isDeposit, 0) AS isDeposit, 
			CASE WHEN ISNULL(c.isDeposit, 0) = 1 THEN c.DI_Rate ELSE 0 END, c.Fromdate, c.Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'SB', 'OA', 1) c		
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
		PartyID		INT,
		PartyName	NVARCHAR(100),
		ParentId	INT,
		ParentName	VARCHAR(100),	
		Winlossdate DATETIME,
		CurrencyId	INT,
		Turnover	MONEY,
		TotalTrans	INT,
		CustomerWinLoss MONEY,
		LicenseeWinloss MONEY,
		LicensingFee	 MONEY,
		PayToSupplier	MONEY)	

	INSERT INTO #Result (PartyID,PartyName,ParentId,ParentName,Winlossdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,LicenseeWinloss,LicensingFee)
	SELECT ci.PartyId,
		p.PartyName,
		p.ParentId,
		p.ParentName,
		b.rptDate,
		b.CurrencyId,
		SUM(b.Turnover) AS Turnover,
		SUM(b.BetCount) AS TotalTrans,
		SUM(b.WinLoss) AS CustomerWinLoss,
		SUM(-(b.WinLoss)) AS LicenseeWinloss,
		SUM(CASE WHEN ci.isDeposit = 1 THEN (-b.WinLoss * ci.Rate)
			ELSE b.Winloss + b.WinLossA + b.WinLossM + b.WinLossS + b.CommissionS END) LicensingFee
	FROM bodb_LicenseeReport..rpt_Betting b WITH (NOLOCK)
		INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
		INNER JOIN @PartyList p ON ci.PartyId = p.PartyId 
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate 
		AND b.Status NOT IN (-1, 101, 102, 103) 
		AND b.CurrencyId <> 20
		AND b.Bettype = 38 
	GROUP BY b.rptDate, ci.PartyId, PartyName, ParentId, ParentName, b.CurrencyId
	
	UPDATE #Result
	SET PayToSupplier = LicensingFee * 0.2
	-- EndRegion #Result

	-- Region: Exchange
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
	-- End Region
	
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
		INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier)
		SELECT @tempCurrency,ParentId,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(LicenseeWinLoss),
			SUM(CASE WHEN LicensingFee < 0 THEN 0 ELSE LicensingFee END),
			SUM(CASE WHEN PayToSupplier < 0 THEN 0 ELSE PayToSupplier END)
		FROM TotalByParty
		GROUP BY ParentId

		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,LicenseeWinLoss,LicensingFee,PayToSupplier,CompanyIncome)
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
		CAST(LicenseeWinLoss * e.Rate AS MONEY) AS LicenseeWinLoss,
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
	FROM #Result r 
	INNER JOIN #Exchange e 
	ON r.CurrencyId = e.ExchangeID 
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
			LicenseeWinLoss,
			LicensingFee,
			PayToSupplier,
			(LicensingFee - PayToSupplier) AS CompanyIncome
		FROM @Total t
		WHERE Currency = @BaseCurrencyName
	END
	-- End Region

	DROP TABLE #Exchange
	DROP TABLE #Result
END
GO
