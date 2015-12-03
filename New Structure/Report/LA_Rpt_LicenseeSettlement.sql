USE [bodb02]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

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
			- 20150407@Florent: add filter no draw for BA Settlement
			- 20150505@Florent: Integrate Gold Deluxe and Voidbridge
			- 20150519@Florent: Change Product Prefix from VB to VG
			- 20150722@Florent: Implement Microgaming Casino (MGC)
			- 20150910@Florent: Implement Bettrade
			- 20150914@Bravo: Add 2 Column for Grand Total Row.
		Param's Explanation:  				
			+ @@ProductCode:	'SB' -> Sportsbook			'RB' -> Racing
								'NG' -> Number Game			'BA' -> BA
								'LC' -> Live Casino			'VS' -> Virtual Sports
								'CS' -> RNG Casino			'BG' -> Bingo			
								'MGC'->Microgaming Casino
	*/  
SET NOCOUNT ON
BEGIN			
	DECLARE @ProductPrefix TABLE (ProductCode VARCHAR(20))
	INSERT INTO @ProductPrefix
	SELECT val FROM bodb02.dbo.Lrf_f_StringSplit(@ProductCode, ',')
	
	DECLARE @LicenseeID INT	
		, @DrawFilter SMALLINT = 1
	CREATE TABLE #Result (
			Winlostdate		DATETIME
			, CurrencyId	INT
			, Game			VARCHAR(100)
			, TurnOver		MONEY
			, ActualStake	MONEY
			, BuyBackAmount	MONEY
			, Winlost		MONEY
			, PlayerComm	MONEY
			, LicenseeWL	MONEY
			, LicenseeComm	MONEY
			, BettradeComm	MONEY
			, Company		MONEY
			, Betcount		BIGINT)
	DECLARE @tmpParty AS TABLE (
		PartyId				INT
		, LicenseeId		INT
		, ProductID			INT
		, Bettype			INT
		, Rate				MONEY
		, FromDate			SMALLDATETIME
		, ToDate			SMALLDATETIME)
	DECLARE @Bettype AS TABLE (
		Bettype				INT
		, ProductId			INT)
	CREATE TABLE #Exchange( ExchangeDate DATE, ExchangeID INT, CurrencyCode VARCHAR(10), Rate FLOAT)
	
	INSERT INTO @tmpParty(PartyId, LicenseeId, ProductID, Bettype, Rate, Fromdate, Todate)
	(
		SELECT DISTINCT PartyID, LicenseeID, ProductID, Bettype, DI_Rate, Fromdate, Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo_xtest(@PartyID, @FromDate, @ToDate, @ProductCode, 'OA', 1)
		WHERE DI_Rate > 0
	)
	
	INSERT INTO @Bettype (Bettype, ProductId)
	(
		SELECT Bettype, ProductID
		FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, @ProductCode)
	)
	
	SELECT @LicenseeID = LicenseeID 
	FROM @tmpParty
	
	IF @LicenseeID IS NULL
	BEGIN
		SELECT TOP 0  					
		''							AS Game									   
		, @ToDate					AS WinLostDate
		, 0							AS CurrencyId
		, ''						AS CurrencyName
		, CAST(0 AS MONEY)			AS Betcount
		--orginal
		, CAST(0 AS MONEY)			AS Turnover
		, CAST(0 AS MONEY)			AS ActualStake
		, CAST(0 AS MONEY)			AS BuyBackAmount
		, CAST(0 AS MONEY)			AS MemberWinLoss		
		, CAST(0 AS MONEY)			AS MemberComm
		, CAST(0 AS MONEY)			AS BettradeComm
		, CAST(0 AS MONEY)			AS LicenseeWL		
		, CAST(0 AS MONEY)			AS LicenseeComm		
		, CAST(0 AS MONEY)			AS Company
		
		--Base on currency
		, CAST(0 AS MONEY)			AS TurnoverBase
		, CAST(0 AS MONEY)			AS ActualStakeBase
		, CAST(0 AS MONEY)			AS BuyBackAmountBase
		, CAST(0 AS MONEY)			AS BettradeCommBase
		, CAST(0 AS MONEY)			AS MemberWinLossBase
		, CAST(0 AS MONEY)			AS MemberCommBase	
		, CAST(0 AS MONEY)			AS LicenseeWLBase
		, CAST(0 AS MONEY)			AS LicenseeCommBase			
		, CAST(0 AS MONEY)			AS CompanyBase

		RETURN
	END

	DECLARE @Recommend VARCHAR(8000) = '', @SQL VARCHAR(8000) = ''
	CREATE TABLE #DataWinloss3rd (Recommend	INT, Winlostdate DATETIME, SportType INT, Currency INT, TurnOver MONEY, TotalTrans INT, Winloss MONEY)
	DECLARE @TempAG AS TABLE( LicenseeeID INT, CustId INT, CurrencyId INT)
	
	-- Product <> BA
	IF (REPLACE(@ProductCode, 'BA', '') != '' AND REPLACE(@ProductCode, 'BA', '') != ',')
	BEGIN
		IF EXISTS (SELECT * FROM @ProductPrefix WHERE ProductCode = 'AGC') -- AG Casino
		BEGIN
			-- reset 
			DELETE @TempAG		
			SET @Recommend = ''
			--get licensee recommend				
			INSERT INTO @TempAG(LicenseeeID, CustId, CurrencyId)
			SELECT DISTINCT LicenseeID, CustID, Currency
			FROM bodb_licensee.dbo.f_SelLicenseeCust(@LicenseeID)
			WHERE (@CurrencyId = 0 OR (@CurrencyId <> 0 AND Currency = @CurrencyId))
				AND Currency <> 20

			SELECT @Recommend = @Recommend + CAST(CustID AS VARCHAR) + ',' 
			FROM @TempAG 

			--truncate last comma
			SET @Recommend = SUBSTRING(@Recommend, 0, LEN(@Recommend))	

			SELECT @sql = 'SELECT Recommend, Winlostdate, SportType, Currency, TurnOver, TotalTrans, Winloss
						  FROM OPENQUERY(DBACC,''EXEC bodb02.dbo.LA_Rpt_3rdProductWinloss
												 @ProductCodes		= ''''@ProductCodes_''''
												, @Recommend		= ''''@Recommend_''''
												, @Currency 		= @Currency_
												, @FromDate 		= ''''@FromDate_''''
												, @ToDate 			= ''''@ToDate_''''
												'')'
			SET @SQL = REPLACE(@SQL, '@ProductCodes_', @ProductCode)
			SET @SQL = REPLACE(@SQL, '@Recommend_', @Recommend)
			SET @SQL = REPLACE(@SQL, '@Currency_', @CurrencyId)
			SET @SQL = REPLACE(@SQL, '@FromDate_', CONVERT( VARCHAR(10),@FromDate, 120))
			SET @SQL = REPLACE(@SQL, '@ToDate_', CONVERT( VARCHAR(10),@ToDate, 120))			
			
			INSERT INTO #DataWinloss3rd(Recommend, Winlostdate, SportType, Currency, TurnOver, TotalTrans, Winloss)
			EXECUTE (@SQL)

			INSERT INTO #Result( Winlostdate, CurrencyId, Turnover, Winlost, PlayerComm, LicenseeWL, LicenseeComm, Company, Betcount)
			(
				SELECT   			   
					b.Winlostdate     
					, CurrencyID		   
					, SUM(Turnover) AS Turnover
					, SUM(WinLoss) AS Winlost
					, 0 AS PlayerComm
					, - SUM(Winloss * ( 1 - p.Rate)) AS LicenseeWL				
					, 0 AS LicenseeComm
					, - SUM(WinLoss * p.Rate) AS Company 
					, SUM(b.TotalTrans) AS BetCount	  
				FROM #DataWinloss3rd b WITH (NOLOCK)	
					INNER JOIN @TempAG ag ON b.Recommend = ag.CustId AND b.Currency = ag.CurrencyId								
					INNER JOIN @tmpParty p ON ag.LicenseeeID = p.LicenseeId
				WHERE b.Winlostdate BETWEEN p.Fromdate AND p.Todate
				GROUP BY b.Winlostdate, CurrencyID 
			)			
		END
		ELSE IF EXISTS (SELECT * FROM @ProductPrefix WHERE ProductCode IN ('GD','VG')) -- GD, VG
		BEGIN
			-- reset 
			DELETE @TempAG		
			SET @Recommend = ''

			--get licensee recommend			
			INSERT INTO @TempAG(LicenseeeID, CustId, CurrencyId)
			SELECT DISTINCT LicenseeID, CustID, Currency
			FROM bodb_licensee.dbo.f_SelLicenseeCust(@LicenseeID)
			WHERE (@CurrencyId = 0 OR (@CurrencyId <> 0 AND Currency = @CurrencyId))
				AND Currency <> 20

			SELECT @Recommend = @Recommend + CAST(CustID AS VARCHAR) + ',' 
			FROM @TempAG 

			--truncate last comma
			SET @Recommend = SUBSTRING(@Recommend, 0, LEN(@Recommend))	

			INSERT INTO #DataWinloss3rd(Recommend, Winlostdate, Currency, TurnOver, TotalTrans, Winloss)
			EXECUTE dbo.LA_Rpt_ThirdPartyProductWinloss
					@ProductCodes	= @ProductCode
					, @Recommend	= @Recommend
					, @Currency 	= @CurrencyId
					, @DrawFilter	= 1
					, @FromDate 	= @FromDate
					, @ToDate 		= @ToDate
			
			INSERT INTO #Result( Winlostdate, CurrencyId, Turnover, Winlost, PlayerComm, LicenseeWL, LicenseeComm, Company, Betcount)
			(
				SELECT   			   
					b.Winlostdate     
					, CurrencyID		   
					, SUM(Turnover) AS Turnover
					, SUM(WinLoss) AS Winlost
					, 0 AS PlayerComm
					, - SUM(Winloss * ( 1 - p.Rate)) AS LicenseeWL				
					, 0 AS LicenseeComm
					, - SUM(WinLoss * p.Rate) AS Company 
					, SUM(b.TotalTrans) AS BetCount	  
				FROM #DataWinloss3rd b WITH (NOLOCK)	
					INNER JOIN @TempAG ag ON b.Recommend = ag.CustId AND b.Currency = ag.CurrencyId								
					INNER JOIN @tmpParty p ON ag.LicenseeeID = p.LicenseeId
				WHERE b.Winlostdate BETWEEN p.Fromdate AND p.Todate
				GROUP BY b.Winlostdate, CurrencyID 
			)			
		END
		ELSE IF EXISTS (SELECT * FROM @ProductPrefix WHERE ProductCode IN ('MGCLC','MGCRNG')) 
		BEGIN
			-- product 3rd sub name
			CREATE TABLE #Product3rdSubName (Bettype INT, BettypeRef INT, ProductName VARCHAR(100))
			INSERT INTO #Product3rdSubName( Bettype, BettypeRef, ProductName)
			SELECT s.Bettype, p.BettypeRef, p.ProductName 			
			FROM bodb_licensee.dbo.Sport_Bettype_Reference s WITH (NOLOCK)
					LEFT JOIN bodb_licensee.dbo.LA_Product3rdSub p WITH (NOLOCK) ON s.BettypeRef = p.BettypeRef
						
			IF @ProductCode = 'MGCLC'
			BEGIN
				DELETE FROM #Product3rdSubName WHERE Bettype IN (2008,2009)
				DELETE FROM @tmpParty WHERE Bettype IN (2008,2009)
				
				UPDATE #Product3rdSubName
				SET ProductName = 'Live Casino - Generic Games'
				WHERE BettypeRef = 2001
				UPDATE #Product3rdSubName
				SET ProductName = 'Live Casino - Branded Games'
				WHERE BettypeRef = 2005
			END
			ELSE
			BEGIN
				DELETE FROM #Product3rdSubName WHERE Bettype NOT IN (2008,2009)
				DELETE FROM @tmpParty WHERE Bettype NOT IN (2008,2009)
				
				UPDATE #Product3rdSubName
				SET ProductName = 'RNG Casino - Generic Games'
				WHERE BettypeRef = 2001
				UPDATE #Product3rdSubName
				SET ProductName = 'RNG Casino - Branded Games'
				WHERE BettypeRef = 2005
			END			
						
			-- product 3rd sub name
			INSERT INTO #Result( Winlostdate, CurrencyId, Game, Turnover, Winlost, PlayerComm, LicenseeWL, LicenseeComm, Company, Betcount)
			(
				SELECT   			   
					rptDate     
					, CurrencyID	
					, ps.ProductName AS Game					
					, SUM(Turnover) AS turnover
					, SUM(WinLoss) AS Winlost
					, SUM(PComm) AS PlayerComm
					, - SUM(Winloss * ( 1 - p.Rate)) AS LicenseeWL				
					, SUM(AComm - PComm) AS LicenseeComm
					, - SUM(WinLoss * p.Rate + AComm) AS Company 
					, SUM(BetCount) AS BetCount	  
				FROM (
					SELECT b.SiteId, b.rptDate, b.CurrencyID, b.Bettype
					, SUM(ISNULL(b.turnover, 0)) AS TurnOver
					, SUM(ISNULL(b.winloss, 0)) Winloss					 			 					 				
					, SUM(ISNULL(b.CommissionP, 0)) AS PComm
					, SUM(ISNULL(b.CommissionA, 0)) AS AComm
					, SUM(ISNULL(b.betcount, 0)) BetCount
					FROM bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK)
						INNER JOIN (SELECT DISTINCT LicenseeId, Bettype FROM @tmpParty) p ON b.SiteId = p.LicenseeID AND b.Bettype = p.Bettype					
					WHERE
						b.SiteID = @LicenseeID
						AND b.rptDate BETWEEN @FromDate AND @ToDate			
						AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND b.CurrencyID = @CurrencyId))
						AND (b.CurrencyID <> 20)
						AND b.[Status] NOT IN (- 1, 103)
						AND b.customercategory NOT IN (27, 28)					
					GROUP BY b.rptdate, b.SiteId, b.CurrencyID, b.Bettype
				) d 
					INNER JOIN @tmpParty p ON d.SiteId = p.LicenseeID AND d.Bettype = p.Bettype					
					LEFT JOIN #Product3rdSubName ps ON d.Bettype = ps.Bettype
				WHERE d.rptDate BETWEEN p.Fromdate AND p.Todate
				GROUP BY rptDate, CurrencyID , ps.ProductName, d.Bettype
			)
			
			DROP TABLE #Product3rdSubName			
		END
		ELSE IF EXISTS (SELECT * FROM @ProductPrefix WHERE ProductCode = 'BT')--BetTrade
		BEGIN					
			-- add more bettype for SB, BA
			INSERT INTO @Bettype (Bettype, ProductId)
			(
				SELECT Bettype, ProductID
				FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, 'SB,BA')
			)
			
			INSERT INTO #Result( Winlostdate, CurrencyId, ActualStake, BuyBackAmount, LicenseeWL, Winlost, BettradeComm, Company, Betcount)
			(
				SELECT
					d.RptDate					AS  Winlostdate
					, d.CurrencyID					
					, SUM (d.Actual_stake)		AS ActualStake
					, SUM (d.BuyBackAmount )	AS BuyBackAmount
					, SUM (d.LicWinLoss )		AS LicenseeWL
					, SUM (d.BTWinLoss)			AS Winlost
					, SUM (d.BettradeComm)		AS BettradeComm 
					, SUM ((d.BTWinLoss + d.BettradeComm + d.Actual_stake - d.BuyBackAmount)) AS Company
					, SUM (BetCount) AS BetCount	  
				FROM (
					SELECT b.RptDate, b.CurrencyId
						, SUM(CASE WHEN b.Bettype = 901 THEN (b.BuyBackAmount - b.WinLoss)
								ELSE 0
								END) AS Actual_stake
						, SUM(CASE WHEN b.Bettype = 901 THEN b.BuyBackAmount ELSE 0 END) AS BuyBackAmount
						, SUM(CASE WHEN bt.ProductID = 0 THEN b.WinLoss ELSE 0 END)	AS BTWinLoss
						, - SUM(CASE WHEN bt.ProductID = 0 THEN b.WinLoss ELSE 0 END) AS LicWinLoss			 
						, SUM (CASE WHEN b.Bettype = 901 AND b.CustomerCategory = 1001 THEN - b.BuyBackAmount * p.Rate ELSE 0 END) AS BettradeComm			 					 								
						, SUM(CASE WHEN bt.ProductId = 0 THEN ISNULL(b.BetCount, 0) ELSE 0 END) BetCount
					FROM bodb_licensee.dbo.rpt_Betting b WITH (NOLOCK)
						INNER JOIN @tmpParty p ON b.SiteId = p.LicenseeID 
						INNER JOIN @Bettype bt ON b.Bettype = bt.Bettype AND bt.ProductId IN (0, 13)
					WHERE b.RptDate BETWEEN p.FromDate AND p.ToDate
						AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND b.CurrencyID = @CurrencyId))					
						AND b.CurrencyID <> 20
						AND b.Status NOT IN (- 1, 103)	
						AND b.CustomerCategory IN (1001, 1002)				
					GROUP BY b.RptDate, b.CurrencyId

					UNION ALL 
					-- rpt_betting_BA only contain original ticket, SOLD BOUGHT COMM ticket will be in rpt_betting
					SELECT b.RptDate, b.CurrencyId
						, 0 AS Actual_stake
						, 0 AS BuyBackAmount
						, SUM(b.WinLoss)	AS BTWinLoss
						, - SUM(b.WinLoss) AS LicWinLoss				 
						, 0 AS BettradeComm		 					 								
						, SUM(ISNULL(b.BetCount, 0)) BetCount
					FROM bodb_licensee.dbo.rpt_Betting_BA b WITH (NOLOCK)
						INNER JOIN @tmpParty p ON b.SiteId = p.LicenseeID 					
						INNER JOIN @Bettype bt ON b.Bettype = bt.Bettype AND bt.ProductID IN (3)
					WHERE b.RptDate BETWEEN p.FromDate AND p.ToDate
						AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND b.CurrencyID = @CurrencyId))					
						AND b.CurrencyID <> 20
						AND b.Status NOT IN (- 1, 103)	
						AND b.CustomerCategory = 1002 -- for BT BA									
					GROUP BY b.RptDate, b.CurrencyId

				) d 				
				GROUP BY d.RptDate, d.CurrencyID		
			)
		END
		ELSE
		BEGIN
			INSERT INTO #Result( Winlostdate, CurrencyId, TurnOver, Winlost, PlayerComm, LicenseeWL, LicenseeComm, Company, Betcount)
			(
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
			)
		END
	END	

	-- Product = BA
	IF EXISTS (SELECT * FROM @ProductPrefix WHERE ProductCode = 'BA')
	BEGIN
		SET @DrawFilter = 2 -- set case No Darw
		INSERT INTO #Result( Winlostdate, CurrencyId, TurnOver, Winlost, PlayerComm, LicenseeWL, LicenseeComm, Company, Betcount)
		(
			SELECT   			   
				b.rptDate     
				, b.CurrencyID		   
				, SUM(b.turnover * 
						CASE WHEN @drawfilter IN (2, 3) 
							THEN CASE WHEN b.STATUS = 111 THEN 0
								WHEN b.STATUS IN (114, 115)	THEN 0.5 ELSE 1	END
							ELSE 1
						END) AS turnover
				, SUM(b.WinLoss) AS Winlost
				, 0 AS PlayerComm
				, SUM(b.CommissionA) AS LicenseeWL				
				, 0 AS LicenseeComm
				, - SUM(b.WinLoss * p.Rate + b.CommissionA) AS Company 
				, SUM(betcount * CASE WHEN @drawfilter = 2 AND b.Status = 111 THEN 0 ELSE 1 END) AS BetCount	  
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
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)

	SELECT   					
		ISNULL(d.Game, '')			AS Game									   
		, @ToDate					AS WinLostDate
		, d.CurrencyId				AS CurrencyId
		, e.CurrencyCode			AS CurrencyName
		, SUM(Betcount)				AS Betcount
		--orginal
		, SUM(ISNULL(TurnOver, 0))				AS Turnover
		, SUM(ISNULL(d.ActualStake, 0))			AS ActualStake
		, SUM(ISNULL(d.BuyBackAmount, 0))		AS BuyBackAmount
		, SUM(ISNULL(Winlost, 0))				AS MemberWinLoss		
		, SUM(ISNULL(PlayerComm, 0))			AS MemberComm
		, SUM(ISNULL(d.BettradeComm, 0))		AS BettradeComm
		, SUM(ISNULL(LicenseeWL, 0))			AS LicenseeWL		
		, SUM(ISNULL(LicenseeComm, 0))			AS LicenseeComm		
		, SUM(ISNULL(Company, 0))				AS Company
		
		--Base on currency
		, SUM(TurnOver * e.Rate)	AS TurnoverBase
		, SUM(ISNULL(d.ActualStake * e.Rate, 0))		AS ActualStakeBase
		, SUM(ISNULL(d.BuyBackAmount * e.Rate, 0))		AS BuyBackAmountBase
		, SUM(ISNULL(d.BettradeComm * e.Rate, 0))		AS BettradeCommBase
		, SUM(Winlost * e.Rate)		AS MemberWinLossBase
		, SUM(PlayerComm * e.Rate)	AS MemberCommBase	
		, SUM(LicenseeWL * e.Rate)	AS LicenseeWLBase
		, SUM(LicenseeComm * e.Rate)AS LicenseeCommBase			
		, SUM(Company* e.Rate)		AS CompanyBase		
	FROM													  
		#Result d  									  
		INNER JOIN #Exchange e ON d.Winlostdate = e.ExchangeDate AND d.CurrencyId = e.ExchangeId
	GROUP BY   														   
		d.CurrencyId	
		, CurrencyCode												   	
		, d.Game
	ORDER BY CurrencyId ASC

	DROP TABLE #Exchange												   
	DROP TABLE #Result	
	DROP TABLE #DataWinloss3rd
END

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicenseeSettlement] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicenseeSettlement] TO bodbAdminNet 