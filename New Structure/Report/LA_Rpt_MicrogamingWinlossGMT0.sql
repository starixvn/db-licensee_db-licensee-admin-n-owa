USE [bodb02]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_MicrogamingWinlossGMT0] 
	  @PartyId				VARCHAR(1000)
	, @FromDate				DATETIME
	, @ToDate				DATETIME	
	, @ProductCode			VARCHAR(6)		= 'MGC'
	, @CurrencyId			INT				= 0
	, @BaseCurrencyName		VARCHAR(3)		= 'GBP'
	, @DrawFilter			SMALLINT		= 1
	, @ExcludeTest			BIT				= 0
WITH RECOMPILE
AS
/*  Created: 20150804@Florent		
	Task : Report - Microgaming Casino GMT 0
	DB: DB052.bodb02
	Revisions:  			
	Param's Explanation:  						
*/  
SET NOCOUNT ON
BEGIN			
	DECLARE @LicenseeID INT			
	CREATE TABLE #Result (
			PartyID			INT
			, ParentId		INT			
			, BettypeRef	INT
			, Game			VARCHAR(20)
			, TurnOver		MONEY
			, Winlost		MONEY			
			, LicenseeWL	MONEY			
			, Company		MONEY
			, Amtdueto		MONEY
			, Betcount		BIGINT)	
	DECLARE @tmpParty AS TABLE (
		ChargeId			INT
		, PartyId			INT
		, ParentId			INT
		, LicenseeId		INT
		, ProductID			INT
		, Bettype			INT
		, Rate				MONEY
		, FromDate			SMALLDATETIME
		, ToDate			SMALLDATETIME)
	
	DECLARE @CompanyChargeRate AS TABLE (ParentId INT, BettypeRef INT,ChargeType INT, Rate MONEY, MinAmount MONEY, MaxAmount MONEY)
	DECLARE @AmtDueTo AS TABLE (ParentID INT, BettypeRef INT, AmtDueto MONEY)

	CREATE TABLE #Exchange( ExchangeDate DATE, ExchangeID INT, CurrencyCode VARCHAR(10), Rate FLOAT)	
	CREATE TABLE #PartyList(PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT)
		
	INSERT INTO #PartyList(PartyId, PartyName, BrandName, ParentId)
	EXEC bodb_licensee.dbo.LA_PartyListSel

	INSERT INTO @tmpParty(ChargeId, PartyId, ParentId, LicenseeId, ProductID, Bettype, Rate, Fromdate, Todate)
	(
		SELECT DISTINCT a.ChargeID, a.PartyID, p.ParentId, LicenseeID, a.ProductID, a.Bettype, DI_Rate, a.Fromdate, a.Todate
		FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA', @ExcludeTest) a
			LEFT JOIN #PartyList p ON a.PartyID = p.PartyId		
	)
	
	INSERT INTO #Exchange(ExchangeDate, ExchangeID, CurrencyCode, Rate)
	SELECT ExchangeDate, ExchangeID, Code, BaseCurrencyRate
	FROM dbo.LA_f_ExchangeDailySel(@FromDate, @ToDate, @BaseCurrencyName)
	
	BEGIN	
		-- product 3rd sub name
		CREATE TABLE #Product3rdSubName (Bettype INT, BettypeRef INT, ProductName VARCHAR(100))
		INSERT INTO #Product3rdSubName( Bettype, BettypeRef, ProductName)
		SELECT s.Bettype, p.BettypeRef, p.ProductName 			
		FROM bodb_licensee.dbo.Sport_Bettype_Reference s WITH (NOLOCK)
				LEFT JOIN bodb_licensee.dbo.LA_Product3rdSub p WITH (NOLOCK) ON s.BettypeRef = p.BettypeRef
			
		UPDATE #Product3rdSubName
		SET ProductName = 'Generic Games'
		WHERE BettypeRef = 2001
		UPDATE #Product3rdSubName
		SET ProductName = 'Branded Games'
		WHERE BettypeRef = 2005

		-- product 3rd sub name
		INSERT INTO #Result( ParentId, PartyID, BettypeRef, Game, Turnover, Winlost, LicenseeWL, Company, Betcount)
		(
			SELECT p.ParentId AS ParentId
				, p.PartyId
				, ps.BettypeRef
				, ps.ProductName AS Game
				, SUM(Turnover * e.Rate) AS Turnover
				, SUM(WinLoss * e.Rate) AS Winlost				
				, - SUM(Winloss * e.Rate) AS LicenseeWL								
				, - SUM((WinLoss * p.Rate) * e.Rate) AS Company 
				, SUM(BetCount) AS BetCount	  
			FROM (
				SELECT b.SiteId, b.RptDate3rd, b.CurrencyId, b.BetTypeId
				, SUM(ISNULL(b.Turnover, 0) * CASE WHEN @DrawFilter IN (2, 3)
												THEN CASE WHEN b.StatusId = 111 THEN 0
													WHEN b.StatusId IN (114, 115) THEN 0.5 
													ELSE 1 END
												ELSE 1 
												END) AS TurnOver
				, SUM(ISNULL(b.Winloss, 0)) Winloss					 			 					 								
				, SUM(ISNULL(b.BetCount, 0) * CASE WHEN @DrawFilter = 2 AND b.StatusId = 111 THEN 0 ELSE 1 END) BetCount
				FROM bodb_LicenseeReport.dbo.rpt_ThirdPartyWL_ExtraGMT b WITH (NOLOCK)
					INNER JOIN (SELECT DISTINCT LicenseeId, Bettype FROM @tmpParty) p ON b.SiteId = p.LicenseeID AND b.BetTypeId = p.Bettype					
				WHERE b.RptDate3rd BETWEEN @FromDate AND @ToDate			
					AND (@CurrencyId = 0 OR (@CurrencyId <> 0 AND b.CurrencyID = @CurrencyId))
					AND (@ExcludeTest = 0 OR (@ExcludeTest = 1 AND b.CurrencyID <> 20))
					AND b.StatusId NOT IN (- 1, 103)					
				GROUP BY b.RptDate3rd, b.SiteId, b.CurrencyID, b.BetTypeId
			) d 
				INNER JOIN @tmpParty p ON d.SiteId = p.LicenseeID AND d.BetTypeId = p.Bettype									
				INNER JOIN #Exchange e ON d.CurrencyId = e.ExchangeID AND d.RptDate3rd = e.ExchangeDate
				LEFT JOIN #Product3rdSubName ps ON d.BetTypeId = ps.Bettype
			WHERE d.RptDate3rd BETWEEN p.Fromdate AND p.Todate
			GROUP BY ps.ProductName, ps.BettypeRef, p.ParentId, p.PartyId
		)
			
		DROP TABLE #Product3rdSubName				
	END		

	--Calculate Amount due to MGC	
	DECLARE @AmountGap MONEY
	INSERT INTO @CompanyChargeRate(ParentId, BettypeRef, ChargeType, Rate, MinAmount, MaxAmount)
	SELECT DISTINCT a.FromParty, a.BettypeRef, a.ChargeType, a.Rate, CASE WHEN a.ChargeType = 4 THEN a.MinAmount * e.Rate ELSE 0 END MinAmount, CASE WHEN a.ChargeType = 4 THEN a.MaxAmount * e.Rate ELSE 0 END MaxAmount
	FROM 
		(
			SELECT DISTINCT ci2.ChargeID, cis.FromParty, cis.BettypeRef, cis.ChargeType, cis.Rate, cis.MinAmount, cis.MaxAmount , cis.BaseCurrencyId
			FROM @tmpParty tp
			INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) ON tp.ChargeId = ci.ChargeID
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo ci2 WITH (NOLOCK) ON ci.ToParty = ci2.FromParty AND ci2.ProductID = tp.ProductID
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfoSub cis WITH (NOLOCK) ON ci2.ChargeID = cis.ChargeIdRef
		) a 
		LEFT JOIN #Exchange e ON a.BaseCurrencyId = e.ExchangeID		
		
	INSERT INTO @AmtDueTo([@GroupWinloss].BettypeRef, ParentID, AmtDueto)
	SELECT BettypeRef, ParentId, SUM(CASE WHEN oa.kq > 0 THEN oa.kq ELSE 0 END) AS AmtDueto 
	FROM (SELECT BettypeRef, ParentId, SUM(LicenseeWL) AS GroupWinloss	
		FROM #Result	
		GROUP BY BettypeRef, ParentId
		) d
		OUTER APPLY
		(
			SELECT 
			CASE WHEN(ChargeType = 4 AND GroupWinloss BETWEEN MinAmount AND ISNULL(MaxAmount,100000000000)) THEN (GroupWinloss - MinAmount) * Rate ELSE 0 END
			+ 
			CASE WHEN(ChargeType = 4 AND GroupWinloss > MaxAmount) THEN (MaxAmount - MinAmount) * Rate ELSE 0 END	
			+ 
			CASE WHEN(ChargeType = 1) THEN GroupWinloss * Rate ELSE 0 END
			AS kq
			FROM @CompanyChargeRate WHERE ParentId = d.ParentId AND BettypeRef = d.BettypeRef
		) oa 
	GROUP BY BettypeRef, ParentId
	ORDER BY BettypeRef, ParentId	
	
	UPDATE r
	SET r.Amtdueto = g.AmtDueto
	FROM #Result r LEFT JOIN @AmtDueTo g ON r.ParentId = g.ParentID AND r.BettypeRef = g.BettypeRef
		
	SELECT   														   
		d.ParentId					AS ParentId
		, pp.PartyName				AS ParentName
		, d.PartyID					AS PartyID
		, p.PartyName				AS PartyName
		, d.BettypeRef				AS BettypeRef
		, d.Game					AS Game
		, SUM(Betcount)				AS Betcount
		--orginal
		, SUM(TurnOver)				AS Turnover
		, SUM(Winlost)				AS MemberWinLoss		
		, SUM(LicenseeWL)			AS LicenseeWL		
		, CASE WHEN SUM(d.Company) < 0 THEN 0
			ELSE SUM(d.Company)
			END 					AS Company		
		, Amtdueto					AS Amtdueto			
	FROM													  
		#Result d  									  		
		LEFT JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON d.PartyID = p.PartyID
		LEFT JOIN bodb_licensee.dbo.OAS_Party pp WITH (NOLOCK) ON d.ParentId = pp.PartyID
	GROUP BY d.ParentId
		, pp.PartyName
		, d.PartyID		
		, p.PartyName	
		, d.BettypeRef	
		, d.Game
		, Amtdueto
	ORDER BY pp.PartyName ASC

	DROP TABLE #Exchange												   
	DROP TABLE #Result	
	DROP TABLE #PartyList	
END

GO

SET QUOTED_IDENTIFIER OFF 
GO
SET ANSI_NULLS ON 
GO


GO 
 GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_MicrogamingWinlossGMT0] TO [vnteam]
GO 
 GRANT EXECUTE ON [dbo].[LA_Rpt_MicrogamingWinlossGMT0] TO [bodbAdminNet]
GO 
