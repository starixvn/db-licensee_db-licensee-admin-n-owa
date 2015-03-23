USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LicenseeSettlement]    Script Date: 23/03/2015 10:41:55 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.LA_Rpt_LicenseeSettlement    Script Date: 19/03/2015 14:00:56 PM ******/

ALTER PROCEDURE [dbo].[LA_Rpt_LicenseeSettlement] 
	  @PartyId				INT
	, @FromDate				DATETIME
	, @ToDate				DATETIME
	, @ProductCode			VARCHAR(6)
	, @CurrencyId			INT				= 0
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'
WITH RECOMPILE
AS
	/*  Created: 20150313@Florent		
		Task : Report - Licensee Settlement Report
		Base on : IMS_Rpt_LicenseeSettlement
		DB: DB052.bodb02
		Revisions:  

		Param's Explanation:  				
			+ @@ProductCode:	'SB' -> Sportsbook			'RB' -> Racing
								'NG' -> Number Game			'BA' -> BA
								'LC' -> Live Casino			'VS' -> Virtual Sports
								'CS' -> RNG Casino			'BG' -> Bingo			
	*/  
SET NOCOUNT ON
BEGIN			
	DECLARE @LicenseeID INT	
	CREATE TABLE #Result (
			Winlostdate		DATETIME
			, CurrencyId	INT
			, TurnOver		MONEY
			, Winlost		MONEY
			, PlayerComm	MONEY
			, LicenseeWL	MONEY
			, LicenseeComm	MONEY
			, Company		MONEY
			, Betcount		BIGINT)
	DECLARE @tmpParty AS TABLE (
		PartyId				INT
		, LicenseeId		INT
		, ProductID			INT
		, Rate				MONEY
		, FromDate			SMALLDATETIME
		, ToDate			SMALLDATETIME)
	DECLARE @Bettype AS TABLE (
		Bettype				INT
		, ProductId			INT)
	CREATE TABLE #Exchange( ExchangeDate DATE, ExchangeID INT, CurrencyCode VARCHAR(10), Rate FLOAT)
	
	INSERT INTO @tmpParty(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
	(
		SELECT PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyID, @FromDate, @ToDate, @ProductCode, 'OA', 1)
	)

	INSERT INTO @Bettype (Bettype)
	(
		SELECT Bettype
		FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, @ProductCode)
	)

	SELECT @LicenseeID = LicenseeID 
	FROM @tmpParty
	-- Product <> BA
	IF (REPLACE(@ProductCode, 'BA', '') != '' AND REPLACE(@ProductCode, 'BA', '') != ',')
	BEGIN
		INSERT INTO #Result( Winlostdate, CurrencyId, TurnOver, Winlost, PlayerComm, LicenseeWL, LicenseeComm, Company, Betcount)
			SELECT   			   
				rptDate     
				, CurrencyID		   
				, SUM(Turnover) AS turnover
				, SUM(WinLoss) AS Winlost
				, SUM(PComm) AS PlayerComm
				, - SUM(Winloss * ( 1 - p.Rate)) AS LicenseeWL				
				, SUM(AComm - PComm) AS LicenseeComm
				, - SUM(WinLoss * p.Rate + AComm) AS Company 
				, SUM(BetCount) AS BetCount	  
			FROM (
				SELECT b.SiteId, b.rptDate, b.CurrencyID
				, SUM(ISNULL(b.turnover, 0)) AS TurnOver
				, SUM(ISNULL(b.winloss, 0)) Winloss					 			 					 				
				, SUM(ISNULL(b.CommissionP, 0)) AS PComm
				, SUM(ISNULL(b.CommissionA, 0)) AS AComm
				, SUM(ISNULL(b.betcount, 0)) BetCount
				FROM bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK)
					INNER JOIN @Bettype bt ON b.Bettype = bt.Bettype					
				WHERE 
					b.SiteID = @LicenseeID					
					AND b.rptDate BETWEEN @FromDate AND @ToDate			
					AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND b.CurrencyID = @CurrencyId))
					AND (b.CurrencyID <> 20)
					AND b.[Status] NOT IN (- 1, 103)
					AND b.customercategory NOT IN (27, 28)					
				GROUP BY b.rptdate, b.SiteId, b.CurrencyID
			) d 
				INNER JOIN @tmpParty p ON d.SiteId = p.LicenseeID 
			WHERE d.rptDate BETWEEN p.Fromdate AND p.Todate
			GROUP BY rptDate, CurrencyID
	END	

	-- Product = BA
	IF CHARINDEX('BA', @ProductCode) <> 0
	BEGIN
		INSERT INTO #Result( Winlostdate, CurrencyId, TurnOver, Winlost, PlayerComm, LicenseeWL, LicenseeComm, Company, Betcount)
		(
			SELECT   			   
				b.rptDate     
				, b.CurrencyID		   
				, SUM(b.Turnover) AS turnover
				, SUM(b.WinLoss) AS Winlost
				, 0 AS PlayerComm
				, SUM(b.CommissionA) AS LicenseeWL				
				, 0 AS LicenseeComm
				, - SUM(b.WinLoss * p.Rate + b.CommissionA) AS Company 
				, SUM(b.BetCount) AS BetCount	  
			FROM 			
				bodb_licensee.dbo.rpt_Betting_BA b WITH (NOLOCK)
				INNER JOIN @tmpParty p ON b.SiteID = p.LicenseeId 				
			WHERE 											  
				b.rptDate BETWEEN p.FromDate AND p.ToDate
				AND b.SiteID = @LicenseeID
				AND b.Bettype IN (SELECT Bettype FROM @Bettype)	
				AND b.Status NOT IN (- 1, 103)
				AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND b.CurrencyID = @CurrencyId))
				AND b.CurrencyID <> 20
			GROUP BY   						  
				b.rptDate, b.CurrencyID	
		)
	END	

	INSERT INTO #Exchange(ExchangeDate, ExchangeID, Rate)
	SELECT ExchangeDate, ExchangeID, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	SELECT   														   
		(
			CASE WHEN GETDATE() < (DATEADD(s, -1, DATEADD(mm, DATEDIFF(m, 0, d.Winlostdate) + 1, 0))) 
			THEN GETDATE() 
			ELSE (DATEADD(s,-1, DATEADD(mm, DATEDIFF(m, 0, d.Winlostdate) + 1, 0))) END													   
		)							AS WinLostDate
		, d.CurrencyId				AS CurrencyId
		, e.CurrencyCode			AS CurrencyName
		, SUM(Betcount)				AS Betcount
		--orginal
		, SUM(TurnOver)				AS Turnover
		, SUM(Winlost)				AS MemberWinLoss		
		, SUM(PlayerComm)			AS MemberComm		
		, SUM(LicenseeWL)			AS LicenseeWL		
		, SUM(LicenseeComm)			AS LicenseeComm		
		, SUM(Company)				AS Company
		
		--Base on currency
		, SUM(TurnOver * e.Rate)	AS TurnoverBase
		, SUM(Winlost * e.Rate)		AS MemberWinLossBase	
		, SUM(LicenseeWL * e.Rate)	AS LicenseeWLBase		
		, SUM(Company* e.Rate)		AS CompanyBase		
	FROM													  
		#Result d  									  
		INNER JOIN #Exchange e ON d.Winlostdate = e.ExchangeDate AND d.CurrencyId = e.ExchangeId
	GROUP BY   														   
		d.CurrencyId	
		, CurrencyCode												   
		, (
			CASE WHEN GETDATE() < (DATEADD(s, -1, DATEADD(mm, DATEDIFF(m, 0, d.Winlostdate) + 1, 0))) 
			THEN GETDATE() 
			ELSE (DATEADD(s,-1, DATEADD(mm, DATEDIFF(m, 0, d.Winlostdate) + 1, 0))) END													   
			)
	ORDER BY WinLostDate  													   

	DROP TABLE #Exchange												   
	DROP TABLE #Result	
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicenseeSettlement] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicenseeSettlement] TO bodbAdminNet 