USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_CashoutWinloss] 
	  @PartyIds				VARCHAR(1000),
	  @FromDate				DATETIME,
	  @ToDate				DATETIME,		
	  @BaseCurrencyName		VARCHAR(3)		= 'GBP'

AS
/*  Created: 20170328@scofield.huynh
	Task : Report - Cashout Winloss
	DB: DBEXT/bodb02
	Revisions: 		
		- 20170328@scofield.huynh: #73310 - Support new Keno report
	Param's Explanation:  						
*/  
SET NOCOUNT ON
BEGIN			
	DECLARE @LicenseeID INT		
	DECLARE @ProductCode VARCHAR(6)	= 'CO'	
	DECLARE @ProductId INT = (SELECT Productid FROM dbo.Product3rd WHERE ProductPrefix = 'CO') 
	DECLARE @ProfitSharingChargeType INT = 8
	DECLARE @SBProductId INT = 0
	DECLARE @BAProductId INT = 3
	CREATE TABLE #Result (
					WinlossDate				DATETIME,
					CurrencyId				INT,
					PartyID					INT,
					ParentId				INT,
					CashoutTimes			MONEY,
					CashoutTickets			MONEY,
					CashoutValue			MONEY,
					BuyBackAmountSB			MONEY,
					BuyBackAmountBA			MONEY,
					BuyBackAmountTotal		MONEY,
					TicketsPayout			MONEY,
					CashoutCommission		MONEY,
					IncomeOnBB				MONEY,
					IncomeOnProfitSharing 	MONEY,
					AmtDueToOnBB			MONEY,
					AmtDueToOnProfitSharing	MONEY
				)	

	DECLARE @tmpParty AS TABLE (
					PartyId			INT,
					ParentId		INT,
					LicenseeId		INT,
					ProductID		INT,
					DI_Rate			MONEY,
					Rate			MONEY,
					FromDate		SMALLDATETIME,
					ToDate			SMALLDATETIME
				)
	
	CREATE TABLE #Exchange(ExchangeDate DATE, ExchangeID INT, CurrencyCode VARCHAR(10), Rate FLOAT)		
	CREATE TABLE #Bettype (Bettype INT, ProductID INT)

	INSERT INTO @tmpParty(PartyId, ParentId, LicenseeId, ProductID, DI_Rate, Rate, Fromdate, Todate)
	(
		SELECT DISTINCT PartyID, ci.FromParty, LicenseeID, a.ProductID, a.DI_Rate, ci.Rate, 
			CASE WHEN a.FromDate >= ci.FromDate THEN a.FromDate ELSE ci.FromDate END AS FromDate,
			CASE WHEN a.ToDate < ci.ToDate THEN a.ToDate ELSE ci.ToDate END AS ToDate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', 1) a
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON a.ChargeID = c.ChargeID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) 
				ON c.ToParty = ci.FromParty AND a.ProductID = ci.ProductID
					AND ((ci.FromDate BETWEEN a.FromDate AND a.ToDate) OR (ci.ToDate BETWEEN a.FromDate AND a.ToDate) OR (ci.FromDate<a.FromDate AND a.ToDate < ci.ToDate))
		WHERE ci.ChargeType != @ProfitSharingChargeType				
	)
	
	-- Get bettype of SB, BA
	INSERT INTO #Bettype(Bettype, ProductID)
	SELECT Bettype,ProductID 
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, 'SB,BA,CO')

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	DECLARE @SharingCharge TABLE (
		PartyId INT,
		FromDate DATE,
		ToDate DATE,
		Rate MONEY)
	INSERT INTO @SharingCharge(PartyId, FromDate, ToDate, Rate)
	SELECT c.FromParty, 
		CASE WHEN c.FromDate > @ToDate THEN @FromDate ELSE c.FromDate END, 
		CASE WHEN c.FromDate > @ToDate THEN @ToDate ELSE c.ToDate END, 
		CASE WHEN c.FromDate > @ToDate THEN 0 ELSE c.Rate END
	FROM bodb_licensee..OAS_ChargeInfo c
	WHERE c.ProductID = @ProductId AND c.ChargeType = @ProfitSharingChargeType

	BEGIN			
		INSERT INTO #Result(WinlossDate, PartyID, ParentId, CurrencyId, CashoutTimes, CashoutTickets, CashoutValue, 
			BuyBackAmountSB, BuyBackAmountBA, BuyBackAmountTotal, TicketsPayout, CashoutCommission, IncomeOnBB)
		(
			SELECT
				d.RptDate,
				d.PartyId,
				d.ParentId,
				d.CurrencyID,
				SUM(CashoutTimes) AS CashoutTimes,
				SUM(CashoutTickets) AS CashoutTickets,
				SUM(CashoutValue) AS CashoutValue,					
				SUM(BuyBackAmountSB) AS BuyBackAmountSB,
				SUM(BuyBackAmountBA) AS BuyBackAmountBA,
				SUM(BuyBackAmountSB + BuyBackAmountBA) AS BuyBackAmountTotal,
				SUM(TicketsPayout) AS TicketsPayout,					
				SUM(CashoutCommission) AS CashoutCommission,
				SUM(IncomeOnBB) AS IncomeOnBB						
			FROM (
				SELECT p.PartyId, p.ParentId, b.RptDate, b.CurrencyId,
					SUM(CASE WHEN b.Bettype = 911 THEN ISNULL(b.BetCount, 0) ELSE 0 END) AS CashoutTimes,
					SUM(CASE WHEN b.Bettype = 911 THEN ISNULL(b.COTicketCount, 0) ELSE 0 END) AS CashoutTickets,
					SUM(CASE WHEN b.Bettype = 911 THEN ISNULL(b.CashOutAmount, 0) ELSE 0 END) AS CashoutValue,					
					SUM(CASE WHEN b.Bettype = 911 AND b.CustomerCategory = 1003 THEN b.BuyBackAmount ELSE 0 END) AS BuyBackAmountSB,
					SUM(CASE WHEN b.Bettype = 911 AND b.CustomerCategory = 1004 THEN b.BuyBackAmount ELSE 0 END) AS BuyBackAmountBA,
					SUM(CASE WHEN b.Bettype = 911 THEN ISNULL(b.TicketPayout, 0) ELSE 0 END) AS TicketsPayout,					
					SUM(CASE WHEN b.Bettype = 911 THEN (b.BuyBackAmount * p.DI_Rate) ELSE 0 END) AS CashoutCommission,	
					SUM(CASE WHEN b.Bettype = 911 THEN (b.BuyBackAmount * p.Rate) ELSE 0 END) AS IncomeOnBB						
				FROM bodb_licenseereport.dbo.rpt_BettingByProduct b WITH (NOLOCK)
					INNER JOIN @tmpParty p ON b.SiteId = p.LicenseeID AND b.rptDate BETWEEN p.FromDate AND p.ToDate
					INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype AND bt.ProductID IN (@ProductId)
				WHERE b.RptDate BETWEEN p.FromDate AND p.ToDate									
					AND b.CurrencyID <> 20
					AND b.StatusID NOT IN (-1, 101, 102, 103)
					AND b.CustomerCategory IN( 1003, 1004)
				GROUP BY p.PartyId, b.RptDate, b.CurrencyId, p.ParentId				
			) d
			GROUP BY d.PartyId, d.ParentId,d.RptDate, d.CurrencyID
		)	
	END

	UPDATE #Result
	SET IncomeOnProfitSharing = (d.TicketsPayout - d.BuyBackAmountTotal - d.CashoutCommission) * c.Rate,
		AmtDueToOnBB = d.TicketsPayout - d.BuyBackAmountTotal - d.CashoutCommission - d.IncomeOnBB,
		AmtDueToOnProfitSharing = (d.TicketsPayout - d.BuyBackAmountTotal - d.CashoutCommission) * c.Rate
	FROM #Result d
	LEFT JOIN @SharingCharge c ON d.ParentId = c.PartyId AND d.WinlossDate BETWEEN c.FromDate AND c.ToDate

	SELECT
		d.WinlossDate,
		d.ParentId				AS GroupId,
		CASE WHEN d.ParentId = 999 THEN 'Credit' ELSE pp.PartyName END AS GroupName,
		d.PartyID				AS PartyID,
		p.PartyName				AS PartyName,		
		d.CurrencyId,			
		e.CurrencyCode			AS CurrencyName,
		SUM(CashoutTimes) AS CashoutTimes,
		SUM(CashoutTickets) AS CashoutTickets,
		SUM(CashoutValue * e.Rate) AS CashoutValue,
		SUM(BuyBackAmountSB * e.Rate) AS BuyBackAmountSB,
		SUM(BuyBackAmountBA * e.Rate) AS BuyBackAmountBA,
		SUM(BuyBackAmountTotal * e.Rate) AS BuyBackAmountTotal,
		SUM(TicketsPayout * e.Rate) AS TicketsPayout,					
		SUM(CashoutCommission * e.Rate) AS CashoutCommission,	
		SUM(IncomeOnBB * e.Rate) AS IncomeOnBB,						
		SUM(IncomeOnProfitSharing * e.Rate) AS IncomeOnProfitSharing,
		SUM(AmtDueToOnBB * e.Rate) AS AmtDueToOnBB,
		SUM(AmtDueToOnProfitSharing * e.Rate) AS AmtDueToOnProfitSharing		
	FROM													  
		#Result d  		
		INNER JOIN #Exchange e ON d.CurrencyId = e.ExchangeID AND d.WinlossDate = e.ExchangeDate							  		
		INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON d.PartyID = p.PartyID		
		INNER JOIN bodb_licensee.dbo.OAS_Party pp WITH (NOLOCK) ON d.ParentId = pp.PartyID
	GROUP BY d.ParentId, CASE WHEN d.ParentId = 999 THEN 'Credit' ELSE pp.PartyName END, 
		d.PartyID, p.PartyName, d.CurrencyId, e.CurrencyCode, d.WinlossDate
	ORDER BY ParentId ASC, p.PartyName ASC

	-- Region: Grand Total
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id 		INT,
		Name 	VARCHAR(20),
		IsApply BIT
	)
	INSERT INTO @BaseCurrencies(Id, Name)
	EXEC bodb_licensee..LA_SelBaseCurrency

	CREATE TABLE #ExchangeBase (
		ExchangeDate	DATE,
		ExchangeID		INT,
		CurrencyCode	VARCHAR(10),
		Rate			FLOAT
	)	

	DECLARE @GrandTotal AS TABLE(
		CurrencyName			VARCHAR(10),
		CashoutTimes			MONEY,
		CashoutTickets			MONEY,
		CashoutValue			MONEY,
		BuyBackAmountSB			MONEY,
		BuyBackAmountBA			MONEY,
		BuyBackAmountTotal		MONEY,
		TicketsPayout			MONEY,
		CashoutCommission		MONEY,
		IncomeOnBB				MONEY,
		IncomeOnProfitSharing 	MONEY,
		AmtDueToOnBB			MONEY,
		AmtDueToOnProfitSharing	MONEY)	
	
	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
		PRINT @tempCurrency
		DELETE FROM #ExchangeBase
		INSERT INTO #ExchangeBase(ExchangeDate, ExchangeID, CurrencyCode, Rate)
		SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
		FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency)
		
		INSERT INTO @GrandTotal (CurrencyName, CashoutTimes, CashoutTickets, CashoutValue, BuyBackAmountSB, BuyBackAmountBA, BuyBackAmountTotal, 
			TicketsPayout, CashoutCommission, IncomeOnBB, IncomeOnProfitSharing, AmtDueToOnBB, AmtDueToOnProfitSharing)
		SELECT	@tempCurrency,
				SUM(CashoutTimes) AS CashoutTimes,
				SUM(CashoutTickets) AS CashoutTickets,
				SUM(CashoutValue * e.Rate) AS CashoutValue,
				SUM(BuyBackAmountSB * e.Rate) AS BuyBackAmountSB,
				SUM(BuyBackAmountBA * e.Rate) AS BuyBackAmountBA,
				SUM(BuyBackAmountTotal * e.Rate) AS BuyBackAmountTotal,
				SUM(TicketsPayout * e.Rate) AS TicketsPayout,					
				SUM(CashoutCommission * e.Rate) AS CashoutCommission,	
				SUM(IncomeOnBB * e.Rate) AS IncomeOnBB,						
				SUM(IncomeOnProfitSharing * e.Rate) AS IncomeOnProfitSharing,
				SUM(AmtDueToOnBB * e.Rate) AS AmtDueToOnBB,
				SUM(AmtDueToOnProfitSharing * e.Rate) AS AmtDueToOnProfitSharing		
		FROM #Result td INNER JOIN #ExchangeBase e ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinlossDate

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
	END
	
	SELECT * FROM @GrandTotal
	-- End Region
	
	DROP TABLE #Exchange												   
	DROP TABLE #ExchangeBase
	DROP TABLE #Result	
	DROP TABLE #Bettype
END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_CashoutWinloss] TO [vnteam] 
GO

GRANT EXECUTE ON [dbo].[LA_Rpt_CashoutWinloss] TO [bodbAdminNet] 
GO
