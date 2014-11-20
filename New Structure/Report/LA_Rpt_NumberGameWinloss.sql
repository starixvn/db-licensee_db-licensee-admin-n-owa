USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_NumberGameWinloss]    Script Date: 08/10/2014 11:30:33 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER  PROCEDURE [dbo].[LA_Rpt_NumberGameWinloss]      
	@PartyIDs		VARCHAR(5500),  
	@FromDate		SMALLDATETIME,                                                                                              
	@ToDate		SMALLDATETIME,
	@Currency		INT			 = 0,  
	@drawfilter	SMALLINT		 = 0, 	
	@excludeTest	BIT			 = 0
AS      
  
/*  
 * Created by : [20140904@Florent.Nguyen]  
 * Task  : Get Number Game Winloss 
 * DB   : DB052.bodb02  
 * Revisions :  	
 * Param's Explanation:
 *  
 */  

BEGIN
	SET NOCOUNT ON	
	
	CREATE TABLE #Data (winlostdate  DATETIME, Currency  INT,  PartyID int,  TurnOver MONEY, MemberWinloss MONEY, LicenseeWL MONEY, Betcount INT)		
	--get list PartyIDs
	DECLARE @tmpParty TABLE (
		PartyID INT
		,LicenseeID INT
		,AffectedDate DATETIME
		,Fromdate DATETIME
		,Todate DATETIME
		)

	INSERT INTO @tmpParty (
		PartyID
		,LicenseeID
		,AffectedDate
		,Fromdate
		,Todate
		)
	SELECT p.PartyID
		,l.LicenseeID
		,l.AffectedDate
		,@FromDate
		,@ToDate
	FROM bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) 
	INNER JOIN bodb_licensee.dbo.Licensees l(NOLOCK) ON p.OldRefID = l.LicenseeID
		AND p.PartyType = 1     
	LEFT JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (NOLOCK) ON pd.PartyID = p.PartyID
	WHERE p.PartyID IN (
			SELECT VAL
			FROM strSplit(@PartyIDs, ',')
			)
		AND (l.AffectedDate IS NOT NULL OR pd.IsDeposit = 0)

	-- filter with exclude test data before launch date
	IF (EXISTS (
			SELECT TOP 1 1
			FROM @tmpParty
			WHERE AffectedDate > Fromdate
			) AND @excludeTest =1 )
	BEGIN
		UPDATE @tmpParty
		SET Fromdate = AffectedDate
		WHERE AffectedDate > Fromdate
	END
	--Output table 
	CREATE TABLE #Result (PartyID int,Currency int, TurnOver MONEY, MemberWinloss MONEY, GrossWinloss MONEY, DistributorRevenue MONEY, Betcount INT, LupineRevenue MONEY, OneworksRevenue MONEY,DistributorsChargeRate MONEY, LupineChargeRate MONEY, OneworksChargeRate MONEY, winlostdate datetime)
	
	-- For Deposit Licensees
	IF EXISTS(SELECT 1 FROM @tmpParty tp INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd1 (NOLOCK)
					   ON tp.PartyID = pd1.PartyID
					   WHERE pd1.IsDeposit = 1)
	BEGIN
		INSERT INTO #Data (winlostdate, Currency,  PartyID,  TurnOver, MemberWinloss, LicenseeWL, Betcount)
		SELECT  b.rptDate, b.currencyID, lr.PartyID,
		 SUM(Turnover * 
				CASE   
					WHEN @drawfilter IN (1, 2) THEN  
					CASE   
						WHEN b.status = 111 THEN 0  
						WHEN (b.status = 114 OR b.status = 115) THEN 0.5  
					ELSE 1   
					END  
				ELSE 1   
				END  			
		 ) AS TurnOver, 
		 SUM(b.Winloss) AS MemberWinloss, SUM(winlossA) AS LicenseeWL, 
		 SUM(BetCount * CASE   
						WHEN @drawfilter = 1 THEN  
							CASE   
							WHEN b.status = 111 THEN 0  
							ELSE 1   
							END  
						ELSE 1   
						END  ) AS BetCount
		FROM bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK) 
			INNER JOIN @tmpParty lr ON b.SiteID = lr.LicenseeID 
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd (NOLOCK) ON lr.PartyID = pd.PartyID				
		WHERE pd.IsDeposit = 1 
	 		AND b.rptDate BETWEEN lr.FromDate AND lr.ToDate
			AND b.status NOT IN (-1,103)
			AND (@excludeTest = 0 OR (@excludeTest = 1 AND CurrencyID<>20))
			AND bettype BETWEEN 81 AND 120			
		GROUP BY b.rptDate, b.CurrencyID, lr.PartyID
	END
	
	--For Credit Licensees
	IF EXISTS(SELECT 1 FROM @tmpParty tlr
							INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd1 (NOLOCK)
							ON tlr.PartyID = pd1.PartyID
							WHERE pd1.IsDeposit = 0)
	BEGIN
		INSERT INTO #Data (winlostdate, Currency,  PartyID, TurnOver, MemberWinloss, LicenseeWL, Betcount)
		SELECT  b.rptDate, b.currencyID, lr.PartyID,
				SUM(Turnover* CASE   
					WHEN @drawfilter IN (1, 2) THEN  
					CASE   
						WHEN b.status = 111 THEN 0  
						WHEN (b.status = 114 OR b.status = 115) THEN 0.5  
					ELSE 1   
					END  
				ELSE 1   
				END) AS TurnOver, SUM(b.Winloss) AS MemberWinloss, 0 AS LicenseeWL, 
				SUM(BetCount* CASE   
								WHEN @drawfilter = 1 THEN  
									CASE   
									WHEN b.status = 111 THEN 0  
									ELSE 1   
									END  
								ELSE 1   
								END) AS BetCount
		FROM @tmpParty lr 
			INNER JOIN bodb_Licensee.dbo.OAS_PartyDetail pd (NOLOCK) ON lr.PartyID = pd.PartyID 
			INNER JOIN bodb_Licensee.dbo.labels lb (NOLOCK) ON lr.LicenseeID = lb.LicenseeID 
			INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID = lb.LabelID
		WHERE pd.IsDeposit = 0 
	 		AND b.rptDate BETWEEN lr.FromDate AND lr.ToDate
			AND b.status NOT IN (-1,103)
			AND (@excludeTest = 0 OR (@excludeTest = 1 AND CurrencyID<>20))
			AND bettype BETWEEN 81 AND 120
			AND b.customercategory NOT IN (27,28)
		GROUP BY b.rptDate, b.CurrencyID, lr.PartyID
	END
	
	CREATE NONCLUSTERED INDEX IDX_Currency ON #Data(Currency,winlostdate)
	
	SELECT *
	INTO #Exchange	
	FROM Lrf_f_GetExchangeDaily(@FromDate,@ToDate) 
	WHERE exchangeid IN (SELECT DISTINCT Currency FROM #Data)
		
	--check whether Lupine is terminated in the time range
	DECLARE @PartyTerminated BIT = 0	
	IF EXISTS (SELECT TOP 1 1 
			   FROM bodb_licensee.dbo.LicenseeEventLog (NOLOCK) 
				WHERE SystemID = 4 AND ActionID = 3 AND ObjectID = 3 
						AND (@FromDate >= FromDate AND (ToDate IS NULL OR @ToDate <= ToDate))
				)												
	SET @PartyTerminated = 1
		
	--For Normal Licensees	
	IF @PartyTerminated = 0 --time when Lupine has not been terminated
	BEGIN
		INSERT INTO #Result(PartyID, TurnOver, MemberWinloss, GrossWinloss, DistributorRevenue, 
							Betcount, LupineRevenue, OneworksRevenue, DistributorsChargeRate, 
							LupineChargeRate, OneworksChargeRate,winlostdate,Currency)
		SELECT	
			d.PartyID,
			CAST(isnull(SUM(d.TurnOver ),0) AS MONEY) AS TurnOver,
			--MemberWinloss is often < 0
			CAST(isnull(SUM(d.MemberWinloss ),0) AS MONEY) AS MemberWinloss,
			--IF MemberWinloss is < 0 (that means Licensees' GrossWinLoss > 0)
			CAST(-1 * isnull(SUM(d.MemberWinloss ),0) AS money) AS GrossWinloss,
			CAST(-1 * isnull(SUM(d.MemberWinloss  * isnull(DI.Rate,0)),0) AS money) AS DistributorRevenue,
			ISNULL(SUM(d.betcount), 0) AS BetCount,
			CAST(CASE WHEN isnull(SUM(-1 * d.MemberWinloss ),0) < 0 THEN 0 ELSE -1 * 
			--check the charge type in case Lupine directly charges Licensees from some Resellers (ex: FDL)
					CASE WHEN LUP.ChargeType = 3 THEN 
						isnull(SUM(d.MemberWinloss  * isnull(DI.Rate,0) * isnull(LUP.Rate,0)),0)
					ELSE 
						isnull(SUM(d.MemberWinloss  * isnull(LUP.Rate,0)),0)
					END
				 END AS money) AS LupineRevenue, --dont care
			CAST( isnull(SUM(-1 * d.MemberWinloss  * isnull(OW.Rate,DI.Rate) * 
					CASE WHEN LUP.ChargeType = 3 and ow.Rate IS NOT NULL THEN 
						isnull(DI.Rate,0) * isnull(LUP.Rate,0) 
					ELSE  
						isnull(LUP.Rate,0)
					END
					),0) 
				 AS money) AS OneworksRevenue,
			isnull(DI.Rate,0) as DistributorsChargeRate,
			isnull(LUP.Rate,0) as LupineChargeRate,
			isnull(OW.Rate,0) as OneworksChargeRate
			,winlostdate,d.Currency
		FROM #Data d						
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo DI ON 
					d.PartyID = DI.FromParty 
					AND DI.ProductID = 2 
					AND d.winlostdate BETWEEN DI.FromDate AND DI.ToDate 
					AND DI.ChargeType = 1 
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo LUP ON DI.ParentChargeID = LUP.ChargeID
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo OW ON LUP.ParentChargeID = OW.ChargeID
		GROUP BY
			 d.PartyID, DI.Rate, LUP.Rate, OW.Rate, LUP.ChargeType,d.Currency,winlostdate
	END
	ELSE
	BEGIN --time when Lupine has been terminated
		INSERT INTO #Result(PartyID, TurnOver, MemberWinloss, GrossWinloss, DistributorRevenue, 
							Betcount, LupineRevenue, OneworksRevenue, DistributorsChargeRate, 
							LupineChargeRate, OneworksChargeRate,winlostdate,Currency)
		SELECT	
			d.PartyID,
			CAST(isnull(SUM(d.TurnOver ),0) AS MONEY) AS TurnOver,
			
			CAST(isnull(SUM(d.MemberWinloss ),0) AS MONEY) AS MemberWinloss,
			
			CAST(-1 * isnull(SUM(d.MemberWinloss ),0) AS money) AS GrossWinloss,
			CAST(-1 * isnull(SUM(d.MemberWinloss  * isnull(DI.Rate,0)),0)AS money) AS DistributorRevenue,
			ISNULL(SUM(d.betcount), 0) AS BetCount,
			--Lupine's Revenue now equals 0
			CAST(0 AS money) AS LupineRevenue,
			CAST( isnull(SUM(-1 * d.MemberWinloss  * isnull(OW.Rate,Di.Rate)),0) 
				 AS money) AS OneworksRevenue,
			isnull(DI.Rate,0) as DistributorsChargeRate,
			--Lupine's ChargeRate now equals 0
			CAST (0 AS money) as LupineChargeRate,
			isnull(OW.Rate,0) as OneworksChargeRate
			,winlostdate,d.Currency
		FROM #Data d						
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo DI ON 
				     d.PartyID = DI.FromParty 
					AND DI.ProductID = 2 
					AND d.winlostdate BETWEEN DI.FromDate AND DI.ToDate 
					AND DI.ChargeType = 1 
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo OW ON DI.ParentChargeID = OW.ChargeID
		GROUP BY
			d.PartyID, DI.Rate, OW.Rate,winlostdate,d.Currency
	END	

	
	SELECT	
		CASE	WHEN p.PartyName='IBC' THEN 'FDL'
		     WHEN p.PartyName='18bb' THEN 'PIH'
		     ELSE p.PartyName 
		END AS PartyName,
		CONVERT(VARCHAR(6),winlostdate,112)   AS Winlostdate,
		SUM(re.betcount) AS BetCount,
		--base
		--SUM(re.turnover) AS Turnover,
		--SUM(re.MemberWinloss) AS MemberWinloss,
		--SUM(re.GrossWinloss) AS LicenseeWinloss,
		--SUM(re.OneworksRevenue) AS OneworksRevenue,
		--EUR

		SUM(re.turnover * e.EUR) AS Turnover,
		SUM(re.MemberWinloss * e.EUR) AS MemberWinloss,
		SUM(re.GrossWinloss * e.EUR) AS LicenseeWinloss,
		SUM(re.OneworksRevenue * e.EUR) AS OneworksRevenue

		--USD

		--SUM(re.turnover * e.USD) AS TurnoverUSD,
		--SUM(re.MemberWinloss * e.USD) AS MemberWinlossUSD,
		--SUM(re.GrossWinloss * e.USD) AS LicenseeWinlossUSD,
		--SUM(re.OneworksRevenue * e.USD) AS OneworksRevenueUSD
	FROM #Result re
		INNER JOIN #Exchange e ON re.currency = e.ExchangeId AND re.winlostdate=e.ExchangeDate
		LEFT JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON re.PartyID = p.PartyID		
	GROUP BY
		CONVERT(VARCHAR(6),winlostdate,112),CASE WHEN p.PartyName='IBC' THEN 'FDL'
		     WHEN p.PartyName='18bb' THEN 'PIH'
		     ELSE p.PartyName 
		END
     ORDER BY CONVERT(VARCHAR(6),winlostdate,112) ASC
	
	DROP TABLE	#Data
	DROP TABLE	#Exchange
	DROP TABLE	#Result
END  

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_NumberGameWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_NumberGameWinloss] TO bodbAdminNet 
