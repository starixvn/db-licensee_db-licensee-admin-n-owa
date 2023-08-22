/*<info serverAlias="DBLIC-bodb_Licensee" executers="bodbAdminNet,bodbLicenseeNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

ALTER PROCEDURE [dbo].[LA_Rpt_MacauGamesWinLoss]          
	@PartyIds			VARCHAR(4000),
	@FromDate			DATETIME,
	@ToDate				DATETIME,
	@BaseCurrencyName	VARCHAR(20)
AS
/*  
	 Created: 20171201@Scofield [#86573]
	 Task : Get report Macau Games Win Loss
	 DB: DBLIC.bodb_licensee   

	 Revisions:  
		- 20171201@Scofield: Create Macau Games Win Loss [#86573]
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20200217@Mason: Set billing term by currency [#120005]
		- 20200302@Parsons: Support-HID-currency [#128856]
		- 20200411@Parsons: Add new Macau Games [#130955]
		- 20200903@Parsons: Add new games and bet types for Macau Games [#139815]
		
	 Params:
*/
BEGIN		

	-- Region: Charge Info	
	DECLARE @ChargeInfos AS TABLE (
		ChargeId	INT,
		PartyId		INT,
		ParentId	INT,		
		LicenseeId	INT,
		ProductID	INT,
		Rate		MONEY,
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME,
		IsDeposit	BIT)	
	
	INSERT INTO @ChargeInfos(ChargeId, PartyId, ProductID, LicenseeId, Rate, Fromdate, Todate, IsDeposit)
	(
		SELECT c.ChargeID, c.PartyID, c.ProductID, c.LicenseeID, 
			CASE WHEN ISNULL(c.IsDeposit,0)=0 THEN 0 ELSE c.DI_Rate END,
			c.Fromdate, c.Todate, ISNULL(c.IsDeposit,0)
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, 'VB', 'OA', 1) c		
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

	DECLARE @BlueprintBettype TABLE(Bettype INT )
	INSERT INTO @BlueprintBettype
	SELECT BetType
	FROM bodb02.dbo.SportBettypeMatrix WITH(NOLOCK)
	WHERE SubProduct = 'Blueprint'

	-- Region: TempData
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
		SUM(b.WinLoss) AS CustomerWinLoss,
		- SUM(b.WinLoss) AS LicenseeWinloss,
		SUM(-b.WinLoss * ISNULL(cr.Rate, ci.Rate)) AS LicensingFee,
		SUM(-b.WinLoss * 
		CASE 
			WHEN ci.IsDeposit = 1 THEN (CASE WHEN bp.Bettype IS NOT NULL THEN 0.045 ELSE 0.035 END)
			ELSE (CASE WHEN bp.Bettype IS NOT NULL THEN 0.03 ELSE 0.02 END)
		END) AS PayToSupplier
	FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH (NOLOCK)
		INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
		LEFT JOIN @BlueprintBettype bp ON b.Bettype = bp.Bettype
		LEFT JOIN dbo.LA_ChargeRateByCurrency cr WITH (NOLOCK) ON ci.ChargeId = cr.ChargeID AND cr.CurrencyID = b.CurrencyId
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
		b.Status NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20 AND b.CustomerCategory NOT IN (27,28)
		AND b.Bettype in (Select Bettype FROM LA_f_BettypeProductMapping(0,'VB'))
	GROUP BY b.rptDate, ci.PartyId, b.CurrencyId
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
		LicensingFee	MONEY,		
		PayToSupplier	MONEY
	)
		
	INSERT INTO #Result (PartyId, PartyName, ParentId, ParentName, WinLossDate, CurrencyId, TotalTrans, Turnover, CustomerWinLoss, LicenseeWinLoss, LicensingFee, PayToSupplier)
	SELECT td.PartyId, p.PartyName, p.ParentId, p.ParentName, td.Winlostdate, td.CurrencyId, td.TotalTrans, td.Turnover, td.CustomerWinLoss, td.LicenseeWinloss, td.LicensingFee, td.PayToSupplier
	FROM #TempData td 	
		INNER JOIN @PartyList p ON td.PartyId = p.PartyID
	-- End Region

	-- Region: Exchange
	CREATE TABLE #Exchange (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)	
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate, CurrencyCode)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate, CASE WHEN ExchangeId = 92 THEN 'HID' 
															WHEN ExchangeId = 51 THEN 'INH' ELSE Code 
													   END
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
		
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
			PayToSupplier,
			(LicensingFee - PayToSupplier) AS CompanyIncome
		FROM @Total t
		WHERE Currency = @BaseCurrencyName
	END
	-- End Region

	DROP TABLE #TempData	
	DROP TABLE #Exchange
	DROP TABLE #Result
END
GO