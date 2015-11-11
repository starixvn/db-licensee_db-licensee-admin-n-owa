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
	, @ProductCode			VARCHAR(6)		= 'BT'
	, @CurrencyId			INT				= 0
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'
	, @DrawFilter			SMALLINT		= 1
	, @ExcludeTest			BIT				= 0
WITH RECOMPILE
AS
/*  Created: 20150825@Florent		
	Task : Report - Bettrade Winloss
	DB: DBEXT/bodb02
	Revisions:  			
	Param's Explanation:  						
*/  
SET NOCOUNT ON
BEGIN			
	DECLARE @LicenseeID INT			
	CREATE TABLE #Result (
			 WinlostDate		VARCHAR(6)
			, PartyID			INT
			, ParentId			INT
			, Actual_stake		MONEY
			, BuyBackAmount		MONEY
			, BettradeWinloss	MONEY		
			, WLonBBA			MONEY -- Winloss on Buy back Amount	
			, LicenseeWL		MONEY
			, BettradeComm		MONEY						
			, Total				MONEY
			, Betcount			BIGINT)	
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
		FROM bodb_licensee.dbo.LA_f_ChargeInfo_xtest(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', @ExcludeTest) a
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo c WITH (NOLOCK) ON a.ChargeID = c.ChargeID
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) 
				ON c.ToParty = ci.FromParty AND a.ProductID = ci.ProductID
					AND ((ci.FromDate BETWEEN a.FromDate AND a.ToDate) OR (ci.ToDate BETWEEN a.FromDate AND a.ToDate) OR (ci.FromDate<a.FromDate AND a.ToDate < ci.ToDate))
				
	)
	--hardcode get bettype of SB, BA
	INSERT INTO #Bettype(Bettype, ProductID)
	SELECT Bettype,ProductID 
	FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, 'SB,BA,BT')

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	BEGIN			
		INSERT INTO #Result(WinlostDate, PartyID, ParentId, Actual_stake, BuyBackAmount, BettradeWinloss, WLonBBA, LicenseeWL, BettradeComm, Total, Betcount)
		(
			SELECT
				CONVERT(VARCHAR(6), d.RptDate, 112) AS  WinlostDate
				, d.PartyId
				, d.ParentId
				, SUM (d.Actual_stake * e.Rate) AS Actual_stake
				, SUM (d.BuyBackAmount * e.Rate) AS BuyBackAmount
				, SUM (d.BTWinLoss * e.Rate) AS BettradeWinloss	
				, SUM ((d.Actual_stake - d.BuyBackAmount) * e.Rate) AS WLonBBA
				, SUM (d.LicWinLoss * e.Rate) AS LicenseeWL								
				, SUM (d.BettradeComm * e.Rate) AS BettradeComm 
				, SUM ((d.BTWinLoss + d.BettradeComm + (d.Actual_stake - d.BuyBackAmount)) * e.Rate) AS Total
				, SUM (BetCount) AS BetCount	  
			FROM (
				SELECT p.PartyId, p.ParentId, b.RptDate, b.CurrencyId
					, SUM(CASE WHEN b.Bettype = 901 THEN ((b.BuyBackAmount - b.WinLoss) * CASE WHEN @DrawFilter IN (1, 2)
															THEN CASE WHEN b.Status = 111 THEN 0
															ELSE 1
															END 
														ELSE 1 END)
							ELSE 0
							END) AS Actual_stake
					, SUM(CASE WHEN b.Bettype = 901 THEN b.BuyBackAmount ELSE 0 END) AS BuyBackAmount
					, SUM(CASE WHEN bt.ProductID = 0 THEN b.WinLoss ELSE 0 END)	AS BTWinLoss
					, - SUM(CASE WHEN bt.ProductID = 0 THEN b.WinLoss ELSE 0 END) AS LicWinLoss			 
					, - SUM (CASE WHEN b.Bettype = 901 THEN (b.BuyBackAmount * p.Rate) ELSE 0 END) AS BettradeComm	-- negative amount (meaning that house charges BetTrade this amount).		 					 								
					, SUM(CASE WHEN bt.ProductID = 0 THEN ISNULL(b.BetCount, 0) * CASE WHEN @DrawFilter = 2 AND b.Status = 111 THEN 0 ELSE 1 END 
						ELSE 0 END) BetCount
				FROM bodb_licensee.dbo.rpt_Betting b WITH (NOLOCK)
					INNER JOIN @tmpParty p ON b.SiteId = p.LicenseeID 
					INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype AND bt.ProductID IN (0, 13)
				WHERE b.RptDate BETWEEN p.FromDate AND p.ToDate
					AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND b.CurrencyID = @CurrencyId))					
					AND (@ExcludeTest = 0 OR (@ExcludeTest <> 0 AND b.CurrencyID <> 20))
					AND b.Status NOT IN (- 1, 103)	
					AND b.CustomerCategory IN( 1001, 1002)
				GROUP BY p.PartyId, b.RptDate, b.CurrencyId, p.ParentId

				UNION ALL 
				-- rpt_betting_BA only contain original ticket, SOLD BOUGHT COMM ticket will be in rpt_betting
				SELECT p.PartyId, p.ParentId, b.RptDate, b.CurrencyId
					, 0 AS Actual_stake
					, 0 AS BuyBackAmount
					, SUM(b.WinLoss)	AS BTWinLoss
					, - SUM(b.WinLoss) AS LicWinLoss				 
					, 0 AS BettradeComm		 					 								
					, SUM(ISNULL(b.BetCount, 0) * CASE WHEN @DrawFilter = 2 AND b.Status = 111 THEN 0 ELSE 1 END) BetCount
				FROM bodb_licensee.dbo.rpt_Betting_BA b WITH (NOLOCK)
					INNER JOIN @tmpParty p ON b.SiteId = p.LicenseeID 					
					INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype AND bt.ProductID IN(3)
				WHERE b.RptDate BETWEEN p.FromDate AND p.ToDate
					AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND b.CurrencyID = @CurrencyId))					
					AND (@ExcludeTest = 0 OR (@ExcludeTest <> 0 AND b.CurrencyID <> 20))
					AND b.Status NOT IN (- 1, 103)	
					AND b.CustomerCategory IN( 1001, 1002)
				GROUP BY p.PartyId, b.RptDate, b.CurrencyId, p.ParentId

			) d 
				INNER JOIN #Exchange e ON d.CurrencyId = e.ExchangeID AND d.RptDate = e.ExchangeDate							
			GROUP BY d.PartyId, d.ParentId, CONVERT(VARCHAR(6), d.RptDate, 112)
		)	
	END		

	SELECT
		d.ParentId					AS GroupId
		, CASE WHEN d.ParentId = 999 
				THEN 'Credit' 
			ELSE pp.PartyName END	AS GroupName
		, d.PartyID					AS PartyID
		, p.PartyName				AS PartyName		
		, SUM(Betcount)				AS TotalTransaction		
		, SUM(d.Actual_stake)		AS ActualStake
		, SUM(d.BuyBackAmount)		AS BuyBackAmount
		, SUM(d.BettradeWinloss)	AS BetTradeWinLoss
		, SUM(d.WLonBBA)			AS BuyBackWinLoss
		--, SUM(d.LicenseeWL)			AS LicenseeWinLoss
		, SUM(d.BettradeComm)		AS BetTradeComm				
		, SUM(d.Total)				AS AmountDueTo			
	FROM													  
		#Result d  									  		
		LEFT JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON d.PartyID = p.PartyID		
		LEFT JOIN bodb_licensee.dbo.OAS_Party pp WITH (NOLOCK) ON d.ParentId = pp.PartyID
	GROUP BY d.ParentId, CASE WHEN d.ParentId = 999 
				THEN 'Credit' 
			ELSE pp.PartyName END, d.PartyID, p.PartyName		
	ORDER BY ParentId ASC, p.PartyName ASC

	DROP TABLE #Exchange												   
	DROP TABLE #Result	
	DROP TABLE #Bettype
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_BettradeWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_BettradeWinloss] TO bodbAdminNet 
