USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_BettradeWinloss] 
	  @PartyIds				VARCHAR(1000)
	, @FromDate				DATETIME
	, @ToDate				DATETIME		
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'

AS
/*  Created: 20150825@Florent		
	Task : Report - Bettrade Winloss
	DB: DBEXT/bodb02
	Revisions: 
		-20160317@Bravo: Remove unused param: fix bug wrong actual stake in BTWinLoss report.
		-20160523@Bravo: https://nexdev.net/projects/owa/wiki/CR_20160519_UpdateBetTradeCommercialTerm
	Param's Explanation:  						
*/  
SET NOCOUNT ON
BEGIN			
	DECLARE @LicenseeID INT		
	DECLARE @ProductCode VARCHAR(6)	= 'BT'	
	CREATE TABLE #Result (
			 WinlossDate		DATETIME
			, CurrencyId		INT
			, PartyID			INT
			, ParentId			INT
			, ActualStake		MONEY
			, BuyBackAmountSB		MONEY
			, BuyBackAmountBA		MONEY
			, WinLossOnBoughtTickets MONEY		
			, WinLossOnBuyBackAmount MONEY -- Winloss on Buy back Amount	
			, BettradeComm		MONEY		
			, ProfitSharing		MONEY				
			, AmountDueTo		MONEY
			, TotalTransaction	BIGINT)	
	DECLARE @tmpParty AS TABLE (
		 PartyId			INT
		, ParentId			INT
		, LicenseeId		INT
		, ProductID			INT	
		, Rate				MONEY
		, FromDate			SMALLDATETIME
		, ToDate			SMALLDATETIME)
	
	CREATE TABLE #Exchange( ExchangeDate DATE, ExchangeID INT, CurrencyCode VARCHAR(10), Rate FLOAT)		
	CREATE TABLE #Bettype (Bettype INT, ProductID INT)

	INSERT INTO @tmpParty(PartyId, ParentId, LicenseeId, ProductID, Rate, Fromdate, Todate)
	(
		SELECT DISTINCT PartyID, ci.FromParty, LicenseeID, a.ProductID, ci.Rate, 
			CASE WHEN a.FromDate >= ci.FromDate THEN a.FromDate ELSE ci.FromDate END AS FromDate,
			CASE WHEN a.ToDate < ci.ToDate THEN a.ToDate ELSE ci.ToDate END AS ToDate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', 1) a
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON a.ChargeID = c.ChargeID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) 
				ON c.ToParty = ci.FromParty AND a.ProductID = ci.ProductID
					AND ((ci.FromDate BETWEEN a.FromDate AND a.ToDate) OR (ci.ToDate BETWEEN a.FromDate AND a.ToDate) OR (ci.FromDate<a.FromDate AND a.ToDate < ci.ToDate))
		WHERE ci.ChargeType != 8
				
	)
	
	--hardcode get bettype of SB, BA
	INSERT INTO #Bettype(Bettype, ProductID)
	SELECT Bettype,ProductID 
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, 'SB,BA,BT')

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
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
	WHERE c.ProductID = 13 AND c.ChargeType = 8

	BEGIN			
		INSERT INTO #Result(WinlossDate, PartyID, ParentId, CurrencyId, ActualStake, BuyBackAmountSB, BuyBackAmountBA, WinLossOnBoughtTickets, WinLossOnBuyBackAmount, BettradeComm, ProfitSharing, TotalTransaction)
		(
			SELECT
				d.RptDate
				, d.PartyId
				, d.ParentId
				, d.CurrencyID
				, SUM (d.Actual_stake) AS Actual_stake
				, SUM (d.BuyBackAmountSB) AS BuyBackAmountSB
				, SUM (d.BuyBackAmountBA) AS BuyBackAmountBA
				, SUM (d.WinLossOnBoughtTickets) AS WinLossOnBoughtTickets	
				, SUM (d.Actual_stake - (d.BuyBackAmountSB + d.BuyBackAmountBA)) AS WinLossOnBuyBackAmount	
				, SUM (d.BettradeComm) AS BettradeComm 
				, SUM ((d.Actual_stake - (d.BuyBackAmountSB + d.BuyBackAmountBA)) + d.WinLossOnBoughtTickets - d.BettradeComm) * c.Rate AS ProfitSharing
				, SUM (TotalTrans) AS TotalTrans	  
			FROM (
				SELECT p.PartyId, p.ParentId, b.RptDate, b.CurrencyId
					, SUM(CASE WHEN b.Bettype = 901 THEN (b.BuyBackAmount - b.WinLoss) ELSE 0 END) AS Actual_stake
					, SUM(CASE WHEN b.Bettype = 901 AND b.CustomerCategory = 1001 THEN b.BuyBackAmount ELSE 0 END) AS BuyBackAmountSB
					, SUM(CASE WHEN b.Bettype = 901 AND b.CustomerCategory = 1002 THEN b.BuyBackAmount ELSE 0 END) AS BuyBackAmountBA
					, SUM(CASE WHEN b.Bettype IN (901, 902, 903, 904) THEN 0 ELSE b.WinLoss END)	AS WinLossOnBoughtTickets
					, SUM(CASE WHEN b.Bettype = 901 THEN (b.BuyBackAmount * p.Rate) ELSE 0 END) AS BettradeComm	-- negative amount (meaning that house charges BetTrade this amount).							 					 								
					, SUM(CASE WHEN bt.ProductID = 0 THEN ISNULL(b.BetCount, 0) ELSE 0 END) TotalTrans
				FROM bodb_licensee.dbo.rpt_Betting b WITH (NOLOCK)
					INNER JOIN @tmpParty p ON b.SiteId = p.LicenseeID AND b.rptDate BETWEEN p.FromDate AND p.ToDate
					INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype AND bt.ProductID IN (0, 13)
				WHERE b.RptDate BETWEEN p.FromDate AND p.ToDate									
					AND b.CurrencyID <> 20
					AND b.Status NOT IN (- 1, 103)	
					AND b.CustomerCategory IN( 1001, 1002)
				GROUP BY p.PartyId, b.RptDate, b.CurrencyId, p.ParentId

				UNION ALL 
				-- rpt_betting_BA only contain original ticket, SOLD BOUGHT COMM ticket will be in rpt_betting
				SELECT p.PartyId, p.ParentId, b.RptDate, b.CurrencyId
					, 0 AS Actual_stake
					, 0 AS BuyBackAmountSB
					, 0 AS BuyBackAmountBA
					, SUM(b.WinLoss) AS WinLossOnBoughtTickets 
					, 0 AS BettradeComm		 					 								
					, SUM(ISNULL(b.BetCount, 0)) TotalTrans
				FROM bodb_licensee.dbo.rpt_Betting_BA b WITH (NOLOCK)
					INNER JOIN @tmpParty p ON b.SiteId = p.LicenseeID AND b.rptDate BETWEEN p.FromDate AND p.ToDate				
					INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype AND bt.ProductID IN(3)
				WHERE b.RptDate BETWEEN p.FromDate AND p.ToDate
					AND b.CurrencyID <> 20
					AND b.Status NOT IN (- 1, 103)	
					AND b.CustomerCategory IN( 1001, 1002)
				GROUP BY p.PartyId, b.RptDate, b.CurrencyId, p.ParentId

			) d 				
				LEFT JOIN @SharingCharge c ON d.ParentId = c.PartyId AND d.rptDate BETWEEN c.FromDate AND c.ToDate
			GROUP BY d.PartyId, d.ParentId,d.RptDate, d.CurrencyID, c.Rate
		)	
	END

	UPDATE #Result
	SET AmountDueTo = WinLossOnBuyBackAmount + WinLossOnBoughtTickets - BettradeComm - ProfitSharing

	CREATE TABLE #FinalResult (
			 WinlossDate		DATETIME
			, GroupId			INT
			, GroupName			VARCHAR(100)
			, PartyId			INT
			, PartyName			VARCHAR(100)
			, CurrencyId		INT
			, CurrencyName		VARCHAR(20)
			, TotalTransaction	BIGINT
			, ActualStake		MONEY
			, BuyBackAmountSB	MONEY
			, BuyBackAmountBA	MONEY
			, WinLossOnBoughtTickets MONEY		
			, WinLossOnBuyBackAmount MONEY -- Winloss on Buy back Amount	
			, BettradeComm		MONEY		
			, ProfitSharing		MONEY				
			, AmountDueTo		MONEY)	

	INSERT INTO #FinalResult
	SELECT
		d.WinlossDate
		, d.ParentId				AS GroupId
		, CASE WHEN d.ParentId = 999 
				THEN 'Credit' 
			ELSE pp.PartyName END	AS GroupName
		, d.PartyID					AS PartyID
		, p.PartyName				AS PartyName		
		, d.CurrencyId			
		, e.CurrencyCode			AS CurrencyName
		, SUM(TotalTransaction)		AS TotalTransaction		
		, SUM(d.ActualStake * e.Rate)		AS ActualStake
		, SUM(d.BuyBackAmountSB * e.Rate)		AS BuyBackAmountSB
		, SUM(d.BuyBackAmountBA * e.Rate)		AS BuyBackAmountBA
		, SUM(d.WinLossOnBoughtTickets * e.Rate)	AS WinLossOnBoughtTickets
		, SUM(d.WinLossOnBuyBackAmount * e.Rate)	AS WinLossOnBuyBackAmount
		, SUM(d.BettradeComm * e.Rate)		AS BetTradeComm			
		, SUM(d.ProfitSharing * e.Rate)		AS ProfitSharing
		, SUM(d.AmountDueTo * e.Rate)		AS AmountDueTo			
	FROM													  
		#Result d  		
		INNER JOIN #Exchange e ON d.CurrencyId = e.ExchangeID AND d.WinlossDate = e.ExchangeDate							  		
		LEFT JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON d.PartyID = p.PartyID		
		LEFT JOIN bodb_licensee.dbo.OAS_Party pp WITH (NOLOCK) ON d.ParentId = pp.PartyID
	GROUP BY d.ParentId, CASE WHEN d.ParentId = 999 
				THEN 'Credit' 
			ELSE pp.PartyName END, d.PartyID, p.PartyName, d.CurrencyId, e.CurrencyCode, d.WinlossDate
	ORDER BY ParentId ASC, p.PartyName ASC

	SELECT * FROM #FinalResult

	-- Region: Grand Total
	DECLARE @tempCurrency VARCHAR(20)
	DECLARE @BaseCurrencies TABLE(
		Id INT,
		Name VARCHAR(20),
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
		CurrencyName		VARCHAR(10)
		, TotalTransaction	BIGINT
		, ActualStake		MONEY
		, BuyBackAmountSB	MONEY
		, BuyBackAmountBA	MONEY
		, WinLossOnBoughtTickets MONEY		
		, WinLossOnBuyBackAmount MONEY
		, BettradeComm		MONEY		
		, ProfitSharing		MONEY				
		, AmountDueTo		MONEY)	
	
	WHILE EXISTS (SELECT * FROM @BaseCurrencies WHERE IsApply IS NULL)
	BEGIN
		SET @tempCurrency = (SELECT TOP 1 Name FROM @BaseCurrencies WHERE IsApply IS NULL)
		PRINT @tempCurrency
		DELETE FROM #ExchangeBase
		INSERT INTO #ExchangeBase(ExchangeDate, ExchangeID, CurrencyCode, Rate)
		SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
		FROM bodb02.dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @tempCurrency)
		
		INSERT INTO @GrandTotal (CurrencyName,TotalTransaction, ActualStake, BuyBackAmountSB, BuyBackAmountBA, WinLossOnBoughtTickets, WinLossOnBuyBackAmount, BettradeComm, ProfitSharing, AmountDueTo)
		SELECT	@tempCurrency, 
				SUM(td.TotalTransaction),
				SUM(td.ActualStake * e.Rate), 
				SUM(td.BuyBackAmountSB * e.Rate), 
				SUM(td.BuyBackAmountBA * e.Rate), 
				SUM(td.WinLossOnBoughtTickets * e.Rate), 
				SUM(td.WinLossOnBuyBackAmount * e.Rate),
				SUM(td.BettradeComm * e.Rate),
				SUM(td.ProfitSharing * e.Rate),
				SUM(td.AmountDueTo * e.Rate)
		FROM #Result td INNER JOIN #ExchangeBase e ON e.ExchangeID = td.CurrencyId AND e.ExchangeDate = td.WinlossDate

		UPDATE @BaseCurrencies SET IsApply = 1 WHERE Name = @tempCurrency
	END
	
	SELECT * FROM @GrandTotal
	-- End Region
	
	DROP TABLE #Exchange												   
	DROP TABLE #ExchangeBase
	DROP TABLE #Result	
	DROP TABLE #FinalResult
	DROP TABLE #Bettype
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_BettradeWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_BettradeWinloss] TO bodbAdminNet 
