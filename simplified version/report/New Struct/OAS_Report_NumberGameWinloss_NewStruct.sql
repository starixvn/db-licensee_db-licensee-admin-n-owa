USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[OAS_Report_NumberGameWinloss_NewStruct]    Script Date: 01/04/2014 5:30:22 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[OAS_Report_NumberGameWinloss_NewStruct]  
	@PartyID    INT,  
    @Currency  INT = 0,  
	@drawfilter  SMALLINT = 1, 
	@FromDate  SMALLDATETIME,    
	@ToDate   SMALLDATETIME    
AS  
  
/*  
 * Created by : 20131213@Francis 
 * Task  : Get Winloss report for Number Game (compatible with the new structure)
 * DB   : DB052.bodb02
 * Revisions :  
	- 20140104@Florent: Apply new report template
	- 20140404@Florent: Fix group by currency for Credit Licensees
 	
 * Param's Explanation:    
 *  - @NormalLicensee : List of normal licensee ID separated by ','  
 *  - @Operator   : List of operator ID separated by ','. Direct Licensees also include in this list.
 */  
 
BEGIN
	SET NOCOUNT ON
	--select @FromDate='2013-07-01 00:00:00',@ToDate='2013-09-30 00:00:00'
	--DECLARE @Exchange TABLE(ExchangeDate SMALLDATETIME, ExchangeId INT, EUR FLOAT,USD FLOAT, PRIMARY KEY(ExchangeDate,ExchangeId))	
	
	DECLARE @tmpLicenseeReseller AS TABLE (FromPartyID INT, ToPartyID INT, FromDate DateTime, OldRefID INT)		

	CREATE TABLE #Data (winlostdate  DATETIME, Currency  INT,  FromPartyID int, ToPartyID int, TurnOver MONEY, MemberWinloss MONEY, LicenseeWL MONEY, Betcount INT)		
	
	--Output table 
	CREATE TABLE #Result (ResellerID INT, LicenseeID int,Currency int, TurnOver MONEY, MemberWinloss MONEY, GrossWinloss MONEY, DistributorRevenue MONEY, Betcount INT, LupineRevenue MONEY, OneworksRevenue MONEY,DistributorsChargeRate MONEY, LupineChargeRate MONEY, OneworksChargeRate MONEY, winlostdate datetime)
	
	DECLARE @tmpTable AS TABLE (PartyID INT)
	INSERT INTO @tmpTable (PartyID)
	SELECT PartyID FROM bodb_licensee.dbo.OAS_Party (NOLOCK)
		   WHERE PartyName IN ('Starlit','BA(FDL)')
	
	--hard code get licensee depend boping
	DECLARE @LicBoping int =0
	SELECT @LicBoping=PartyID FROM bodb_licensee.dbo.OAS_Party with (nolock) WHERE PartyName='Boping'

	--Get normal licensee list	
	IF (@LicBoping!=@PartyID)
	BEGIN
		INSERT INTO @tmpLicenseeReseller (FromPartyID, ToPartyID, FromDate, OldRefID)
		SELECT DISTINCT ci.FromParty, ci.ToParty, 
		CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END, p.OldRefID
		FROM bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) 
			INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK)ON ci.FromParty = p.PartyID
		WHERE (@FromDate BETWEEN ci.FromDate AND ci.ToDate OR 
			@ToDate BETWEEN ci.FromDate AND ci.ToDate)
			AND ci.ChargeType = 1
			AND ci.ProductID = 2
			and ci.FromParty =@PartyID			
	END	
	ELSE
	BEGIN
		INSERT INTO @tmpLicenseeReseller (FromPartyID, ToPartyID, FromDate, OldRefID)
		SELECT DISTINCT ci.FromParty, ci.ToParty, 
		CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END, p.OldRefID
		FROM bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) 
			INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK)ON ci.FromParty = p.PartyID
		WHERE (@FromDate BETWEEN ci.FromDate AND ci.ToDate OR 
			@ToDate BETWEEN ci.FromDate AND ci.ToDate)
			AND ci.ChargeType = 1
			AND ci.ProductID = 2
			and ci.ToParty =@PartyID
	END	

	-- For Deposit Licensees
	IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller tlr INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd1 (NOLOCK)
					   ON tlr.FromPartyID = pd1.PartyID
					   WHERE pd1.IsDeposit = 1 AND tlr.ToPartyID NOT IN (SELECT PartyID FROM @tmpTable))
	BEGIN
		INSERT INTO #Data (winlostdate, Currency,  FromPartyID, ToPartyID, TurnOver, MemberWinloss, LicenseeWL, Betcount)
		SELECT  b.rptDate, b.currencyID, lr.FromPartyID, lr.ToPartyID,
		 SUM(Turnover * 
				CASE   
					WHEN @drawfilter IN (2, 3) THEN  
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
						WHEN @drawfilter = 2 THEN  
							CASE   
							WHEN b.status = 111 THEN 0  
							ELSE 1   
							END  
						ELSE 1   
						END  ) AS BetCount
		FROM bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK) 
			INNER JOIN @tmpLicenseeReseller lr ON b.SiteID = lr.OldRefID 
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd (NOLOCK) ON lr.FromPartyID = pd.PartyID				
		WHERE pd.IsDeposit = 1 
	 		AND b.rptDate BETWEEN lr.FromDate AND @ToDate
			AND b.status NOT IN (-1,103)
			AND CurrencyID<>20
			AND bettype BETWEEN 81 AND 120
			--Exclude Licensees from Starlit, BA(FDL)
	 		AND lr.ToPartyID NOT IN (SELECT PartyID FROM @tmpTable)
			AND (@Currency=0 OR  b.CurrencyID =@Currency)
		GROUP BY b.rptDate, b.CurrencyID, lr.ToPartyID, lr.FromPartyID
	END
	
	--For Credit Licensees
	IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller tlr
							INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd1 (NOLOCK)
							ON tlr.FromPartyID = pd1.PartyID
							WHERE pd1.IsDeposit = 0)
	BEGIN
		INSERT INTO #Data (winlostdate, Currency,  FromPartyID, ToPartyID, TurnOver, MemberWinloss, LicenseeWL, Betcount)
		SELECT  b.rptDate, b.currencyID, lr.FromPartyID, lr.ToPartyID,
				SUM(Turnover* CASE   
					WHEN @drawfilter IN (2, 3) THEN  
					CASE   
						WHEN b.status = 111 THEN 0  
						WHEN (b.status = 114 OR b.status = 115) THEN 0.5  
					ELSE 1   
					END  
				ELSE 1   
				END) AS TurnOver, SUM(b.Winloss) AS MemberWinloss, 0 AS LicenseeWL, 
				SUM(BetCount* CASE   
								WHEN @drawfilter = 2 THEN  
									CASE   
									WHEN b.status = 111 THEN 0  
									ELSE 1   
									END  
								ELSE 1   
								END) AS BetCount
		FROM @tmpLicenseeReseller lr 
			INNER JOIN bodb_Licensee.dbo.OAS_PartyDetail pd (NOLOCK) ON lr.FromPartyID = pd.PartyID 
			INNER JOIN bodb_Licensee.dbo.labels lb (NOLOCK) ON lr.OldRefID = lb.LicenseeID 
			INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID = lb.LabelID
		WHERE pd.IsDeposit = 0 
	 		AND b.rptDate BETWEEN lr.FromDate AND @ToDate
			AND b.status NOT IN (-1,103)
			AND CurrencyID<>20
			AND bettype BETWEEN 81 AND 120
			AND b.customercategory NOT IN (27,28)
			AND (@Currency=0 OR  b.CurrencyID =@Currency)			
		GROUP BY b.rptDate, b.CurrencyID, lr.ToPartyID, lr.FromPartyID		
	END
	
	CREATE NONCLUSTERED INDEX IDX_Currency ON #Data(Currency,winlostdate)
	

	--get specified exchange value in time range
	--INSERT INTO @Exchange(ExchangeDate,ExchangeId,EUR,USD)
	SELECT *
	INTO #Exchange
	FROM Lrf_f_GetExchangeDaily(@FromDate,@ToDate)
	WHERE exchangeid IN (SELECT DISTINCT Currency FROM #Data)
	
	--check whether Lupine is terminated in the time range
	DECLARE @PartyTerminated BIT
	SET @PartyTerminated = 0
	IF EXISTS (SELECT TOP 1 1 
			   FROM bodb_licensee.dbo.LicenseeEventLog (NOLOCK) 
				WHERE SystemID = 4 AND ActionID = 3 AND ObjectID = 3 
						AND (@FromDate >= FromDate AND (ToDate IS NULL OR @ToDate <= ToDate))
				)												
	SET @PartyTerminated = 1
		
	--For Normal Licensees	
	IF @PartyTerminated = 0 --time when Lupine has not been terminated
	BEGIN
		INSERT INTO #Result(ResellerID, LicenseeID, TurnOver, MemberWinloss, GrossWinloss, DistributorRevenue, 
							Betcount, LupineRevenue, OneworksRevenue, DistributorsChargeRate, 
							LupineChargeRate, OneworksChargeRate,winlostdate,Currency)
		SELECT	
			d.ToPartyID, d.FromPartyID,
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
			--INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = d.ResellerID
			INNER JOIN #Exchange e ON d.winlostdate = e.ExchangeDate AND d.currency = e.ExchangeId
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo DI ON 
					d.ToPartyID = DI.ToParty AND d.FromPartyID = DI.FromParty 
					AND DI.ProductID = 2 
					AND d.winlostdate BETWEEN DI.FromDate AND DI.ToDate 
					AND DI.ChargeType = 1 
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo LUP ON DI.ParentChargeID = LUP.ChargeID
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo OW ON LUP.ParentChargeID = OW.ChargeID
		GROUP BY
			d.ToPartyID, d.FromPartyID, DI.Rate, LUP.Rate, OW.Rate, LUP.ChargeType,d.Currency,winlostdate
	END
	ELSE
	BEGIN --time when Lupine has been terminated
		INSERT INTO #Result(ResellerID, LicenseeID, TurnOver, MemberWinloss, GrossWinloss, DistributorRevenue, 
							Betcount, LupineRevenue, OneworksRevenue, DistributorsChargeRate, 
							LupineChargeRate, OneworksChargeRate,winlostdate,Currency)
		SELECT	
			d.ToPartyID, d.FromPartyID,
			CAST(isnull(SUM(d.TurnOver ),0) AS MONEY) AS TurnOver,
			--MemberWinloss is often < 0
			CAST(isnull(SUM(d.MemberWinloss ),0) AS MONEY) AS MemberWinloss,
			--IF MemberWinloss is < 0 (that means Licensees' GrossWinLoss > 0)
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
			--INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = d.ResellerID
			INNER JOIN #Exchange e ON d.winlostdate = e.ExchangeDate AND d.currency = e.ExchangeId
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo DI ON 
					d.ToPartyID = DI.ToParty AND d.FromPartyID = DI.FromParty 
					AND DI.ProductID = 2 
					AND d.winlostdate BETWEEN DI.FromDate AND DI.ToDate 
					AND DI.ChargeType = 1 
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo OW ON DI.ParentChargeID = OW.ChargeID
		GROUP BY
			d.ToPartyID, d.FromPartyID, DI.Rate, OW.Rate,winlostdate,d.Currency
	END	
	--return the result for deposit Licensee
	IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller tlr INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd1 (NOLOCK)
					   ON tlr.FromPartyID = pd1.PartyID
					   WHERE pd1.IsDeposit = 1 AND tlr.ToPartyID NOT IN (SELECT PartyID FROM @tmpTable))
	SELECT	
		CONVERT(VARCHAR(6),winlostdate,112)   AS Winlostdate,
		re.Currency,e.code currencyName,e.EUR,
		ISNULL(SUM(re.betcount), 0) AS BetCount,
		--base
		CAST(isnull(SUM(re.turnover),0) AS MONEY) AS Turnover,
		CAST(isnull(SUM(re.MemberWinloss),0) AS MONEY) AS MemberWinloss,
		CAST(SUM(re.GrossWinloss)AS MONEY) AS LicenseeWinloss,
		CAST(SUM(re.OneworksRevenue) AS MONEY) AS OneworksRevenue,
		--EUR

		CAST(isnull(SUM(re.turnover * e
		.EUR),0) AS MONEY) AS TurnoverEUR,
		CAST(isnull(SUM(re.MemberWinloss * e.EUR),0) AS MONEY) AS MemberWinlossEUR,
		CAST(SUM(re.GrossWinloss * e.EUR) AS MONEY) AS LicenseeWinlossEUR,
		CAST(SUM(re.OneworksRevenue * e.EUR) AS MONEY) AS OneworksRevenueEUR,

		--USD

		CAST(isnull(SUM(re.turnover * e.USD),0) AS MONEY) AS TurnoverUSD,
		CAST(isnull(SUM(re.MemberWinloss * e.USD),0) AS MONEY) AS MemberWinlossUSD,
		CAST(SUM(re.GrossWinloss * e.USD) AS MONEY) AS LicenseeWinlossUSD,
		CAST(SUM(re.OneworksRevenue * e.USD) AS MONEY) AS OneworksRevenueUSD
	FROM #Result re
		INNER JOIN #Exchange e ON re.winlostdate = e.ExchangeDate AND re.currency = e.ExchangeId
		INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON p.PartyID = re.ResellerID
		INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON p.OldRefID = r.ResellerID		
		LEFT JOIN bodb_licensee.dbo.OAS_Party p1 WITH (NOLOCK) ON p1.PartyID = re.LicenseeID
	GROUP BY
		re.Currency,e.EUR,e.code,CONVERT(VARCHAR(6),winlostdate,112)
	IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller tlr
							INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd1 (NOLOCK)
							ON tlr.FromPartyID = pd1.PartyID
							WHERE pd1.IsDeposit = 0)
	BEGIN
		SELECT	
		CONVERT(VARCHAR(6),winlostdate,112)   AS Winlostdate,
		'EUR' currencyName,1 EUR,
		ISNULL(SUM(re.betcount), 0) AS BetCount,
		--base in EUR
		CAST(isnull(SUM(re.turnover * e.EUR),0) AS MONEY) AS Turnover,
		CAST(isnull(SUM(re.MemberWinloss * e.EUR),0) AS MONEY) AS MemberWinloss,
		CAST(SUM(re.GrossWinloss * e.EUR)AS MONEY) AS LicenseeWinloss,
		CAST(SUM(re.OneworksRevenue * e.EUR) AS MONEY) AS OneworksRevenue,
		--EUR

		CAST(isnull(SUM(re.turnover * e
		.EUR),0) AS MONEY) AS TurnoverEUR,
		CAST(isnull(SUM(re.MemberWinloss * e.EUR),0) AS MONEY) AS MemberWinlossEUR,
		CAST(SUM(re.GrossWinloss * e.EUR) AS MONEY) AS LicenseeWinlossEUR,
		CAST(SUM(re.OneworksRevenue * e.EUR) AS MONEY) AS OneworksRevenueEUR,

		--USD

		CAST(isnull(SUM(re.turnover * e.USD),0) AS MONEY) AS TurnoverUSD,
		CAST(isnull(SUM(re.MemberWinloss * e.USD),0) AS MONEY) AS MemberWinlossUSD,
		CAST(SUM(re.GrossWinloss * e.USD) AS MONEY) AS LicenseeWinlossUSD,
		CAST(SUM(re.OneworksRevenue * e.USD) AS MONEY) AS OneworksRevenueUSD
	FROM #Result re
		INNER JOIN #Exchange e ON re.winlostdate = e.ExchangeDate AND re.currency = e.ExchangeId
		INNER JOIN bodb_licensee.dbo.OAS_Party p WITH (NOLOCK) ON p.PartyID = re.ResellerID
		INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON p.OldRefID = r.ResellerID		
		LEFT JOIN bodb_licensee.dbo.OAS_Party p1 WITH (NOLOCK) ON p1.PartyID = re.LicenseeID
	GROUP BY
		CONVERT(VARCHAR(6),winlostdate,112)
	END
	DROP TABLE	#Data
	DROP TABLE  #Exchange
	DROP TABLE	#Result
END  
GO
GRANT EXECUTE ON [dbo].[OAS_Report_NumberGameWinloss_NewStruct] TO [bodbLicenseeNet] 
GRANT EXECUTE ON [dbo].[OAS_Report_NumberGameWinloss_NewStruct] TO bodbAdminNet 
GRANT VIEW DEFINITION ON [dbo].[OAS_Report_NumberGameWinloss_NewStruct] TO [vnteam] 
