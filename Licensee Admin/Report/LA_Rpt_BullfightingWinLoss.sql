/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_Rpt_BullfightingWinLoss]
	  @PartyIds				VARCHAR(4000)
	, @FromDate				DATETIME
	, @ToDate				DATETIME
	, @BaseCurrencyName		VARCHAR(10)		= 'EUR'
WITH RECOMPILE
AS
/*  Created: 20180911@Parsons
	Task : Report - Bullfighting Win Loss
	DB: DBLIC-bodb_licensee
	Revisions:
		- 20180911@Parsons: WL report for Poker Games& Bullfighting [#98487]
		- 20200303@Mason: Support HID currency [#128856]

	Param's Explanation: 
	EXEC LA_Rpt_BullfightingWinLoss @BaseCurrencyName='EUR',@ToDate='2018-08-31',@PartyIds='1',@FromDate='2018-08-01'
*/
SET NOCOUNT ON
BEGIN

	DECLARE @ShareRate DECIMAL(7, 5) = 0.08

-- Region: Charge Info	
	DECLARE @ChargeInfos AS TABLE (
		PartyId		INT,
		LicenseeId	INT,
		ProductID	INT,
		Rate		DECIMAL(7, 5),
		FromDate	SMALLDATETIME,
		ToDate		SMALLDATETIME)	
	
	INSERT INTO @ChargeInfos(PartyId, ProductID, LicenseeId, Rate, Fromdate, Todate)
	(
		SELECT c.PartyID, c.ProductID, c.LicenseeID, c.DI_Rate, c.Fromdate, c.Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfoWithCredit(@PartyIDs, @FromDate, @ToDate, 'BF') c
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
		WinLossShare MONEY,
		CommissionGiven MONEY,
		CommissionShare MONEY,
		LicensingFee	 MONEY,
		PayToSupplier	MONEY)	

	INSERT INTO #Result (PartyID,PartyName,ParentId,ParentName,Winlossdate,CurrencyId,Turnover,TotalTrans,CustomerWinLoss,WinLossShare,CommissionGiven,CommissionShare,LicensingFee,PayToSupplier)
	SELECT ci.PartyId,
		p.PartyName,
		p.ParentId,
		p.ParentName,
		b.rptDate,
		b.CurrencyId,
		SUM(b.Turnover)				AS Turnover,
		SUM(b.BetCount)				AS TotalTrans,
		SUM(b.WinLoss)				AS CustomerWinLoss,
		SUM(-b.WinLoss * @ShareRate) AS WinLossShare,
		SUM(CommissionS) AS CommissionGiven,
		SUM((CommissionS * @ShareRate) / (1 - oddsspread)) AS CommissionShare,
		SUM(b.WinLoss * ci.Rate) AS LicensingFee,
		SUM(-b.WinLoss * @ShareRate) - SUM((CommissionS * @ShareRate) / (1 - oddsspread)) AS PayToSupplier
	FROM bodb_LicenseeReport.dbo.rpt_Betting b WITH (NOLOCK)
		INNER JOIN @ChargeInfos ci ON b.SiteID = ci.LicenseeId AND b.rptDate BETWEEN ci.FromDate AND ci.ToDate
		INNER JOIN @PartyList p ON ci.PartyId = p.PartyId
		INNER JOIN LA_f_BettypeProductMapping(0, 'BF') bt ON b.bettype = bt.Bettype
	WHERE b.rptDate BETWEEN @FromDate AND @ToDate AND
		b.[Status] NOT IN (-1, 101, 102, 103) AND b.CurrencyId <> 20
	GROUP BY b.rptDate, ci.PartyId, PartyName, ParentId, ParentName, b.CurrencyId
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

	UPDATE #Exchange SET CurrencyCode = CASE WHEN ExchangeID = 51 THEN 'INH' 
											 WHEN ExchangeID = 92 THEN 'HID' END
	WHERE ExchangeID IN (51, 92)
	-- End Region

	DECLARE @Total TABLE (
		PartyId			INT,
		TotalTrans		INT,
		Turnover		MONEY,
		CustomerWinLoss	MONEY,
		WinLossShare MONEY,
		CommissionGiven MONEY,
		CommissionShare MONEY,
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
		WinLossShare MONEY,
		CommissionGiven MONEY,
		CommissionShare MONEY,
		LicensingFee	MONEY,
		PayToSupplier	MONEY,
		CompanyIncome	MONEY
	)

	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
		
		INSERT INTO @Total (Currency,PartyId,TotalTrans,Turnover,CustomerWinLoss,WinLossShare,CommissionGiven,CommissionShare,LicensingFee,PayToSupplier)
		SELECT @tempCurrency,td.ParentId,
				SUM(td.TotalTrans) TotalTrans,
				SUM(td.Turnover * e.BaseCurrencyRate) Turnover, 
				SUM(td.CustomerWinLoss * e.BaseCurrencyRate) CustomerWinLoss, 
				SUM(td.WinLossShare * e.BaseCurrencyRate) WinLossShare, 
				SUM(td.CommissionGiven * e.BaseCurrencyRate) CommissionGiven, 
				SUM(td.CommissionShare * e.BaseCurrencyRate) CommissionShare, 
				SUM(td.LicensingFee * e.BaseCurrencyRate) LicensingFee,
				SUM(td.PayToSupplier * e.BaseCurrencyRate) PayToSupplier
			FROM #Result td INNER JOIN bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency) e 
			ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinLossDate
			GROUP BY td.ParentId
		
		INSERT INTO @GrandTotal (CurrencyName,TotalTrans,Turnover,CustomerWinLoss,WinLossShare,CommissionGiven,CommissionShare,LicensingFee,PayToSupplier,CompanyIncome)
		SELECT Currency,
			SUM(TotalTrans),
			SUM(Turnover),
			SUM(CustomerWinLoss),
			SUM(WinLossShare),
			SUM(CommissionGiven),
			SUM(CommissionShare),
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
		CAST(WinLossShare * e.Rate AS MONEY) AS WinLossShare,
		CAST(CommissionGiven * e.Rate AS MONEY) AS CommissionGiven,
		CAST(CommissionShare * e.Rate AS MONEY) AS CommissionShare,
		CAST(r.LicensingFee * e.Rate AS MONEY) AS LicensingFee,
		CAST(r.PayToSupplier * e.Rate AS MONEY) AS PayToSupplier,
		CAST((r.LicensingFee - r.PayToSupplier) * e.Rate AS MONEY) AS CompanyIncome,
		-- original
		r.Turnover AS TurnoverOriginal,
		r.CustomerWinLoss AS CustomerWinLossOriginal,
		r.WinLossShare AS WinLossShareOriginal,
		r.CommissionGiven AS CommissionGivenOriginal,
		r.CommissionShare AS CommissionShareOriginal,
		r.LicensingFee AS LicensingFeeOriginal,
		r.PayToSupplier AS PayToSupplierOriginal,
		(r.LicensingFee - r.PayToSupplier) AS CompanyIncomeOriginal
	FROM #Result r INNER JOIN #Exchange e ON r.CurrencyId = e.ExchangeID AND e.ExchangeDate = r.WinLossDate

	-- Grand Total
	SELECT * FROM @GrandTotal
			
	IF @BaseCurrencyName <> ''
	BEGIN		
		-- Total
		SELECT PartyId,
			TotalTrans,
			Turnover,
			CustomerWinLoss,	
			WinLossShare,
			CommissionGiven,
			CommissionShare,
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