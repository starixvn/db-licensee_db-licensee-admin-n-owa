USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[OAS_Report_NumberGameWinloss_NewStruct]    Script Date: 21/04/2014 10:46:53 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[OAS_Report_NumberGameWinloss_NewStruct]  
	@PartyID    INT,  
    @Currency  INT = 0,  
	@drawfilter  SMALLINT = 0, 
	@FromDate  SMALLDATETIME,                                                                                              
	@ToDate   SMALLDATETIME    
AS  
  
/*  
 * Created by : 20131213@Francis 
 * Task  : Get Winloss report for Number Game (compatible with the new structure)
 * DB   : DB052.bodb02
 * Revisions :  
	-20140327@Florent: Apply new report template
	-20140411@Florent: Show Boping in one total line
	-20140416@Florent: Change condition of time range 
	-20140410@Francis: Alter @drawfilter param's value to 0,1,2
 	
 * Param's Explanation:    
 */  
 
BEGIN
	SET NOCOUNT ON	
	
	DECLARE @tmpLicenseeReseller AS TABLE (FromPartyID INT, ToPartyID INT, FromDate DateTime,ToDate datetime, OldRefID INT)		

	CREATE TABLE #Data (winlostdate  DATETIME, Currency  INT,  FromPartyID int, ToPartyID int, TurnOver MONEY, MemberWinloss MONEY, LicenseeWL MONEY, Betcount INT)		
	
	--Output table 
	CREATE TABLE #Result (ResellerID INT, LicenseeID int,Currency int, TurnOver MONEY, MemberWinloss MONEY, GrossWinloss MONEY, DistributorRevenue MONEY, Betcount INT, LupineRevenue MONEY, OneworksRevenue MONEY,DistributorsChargeRate MONEY, LupineChargeRate MONEY, OneworksChargeRate MONEY, winlostdate datetime)
	
	DECLARE @tmpTable AS TABLE (PartyID INT)
	INSERT INTO @tmpTable (PartyID)
	SELECT PartyID FROM bodb_licensee.dbo.OAS_Party (NOLOCK)
		   WHERE PartyName IN ('Starlit','BA(FDL)')
	
	--hard code get licensee depend boping
	DECLARE @LicBoping int =0,@isDeposit int =0, @isBoping INT =0
	SELECT @LicBoping=PartyID FROM bodb_licensee.dbo.OAS_Party with (nolock) WHERE PartyName='Boping'

	--Get normal licensee list	
	IF (@LicBoping!=@PartyID)
	BEGIN
		INSERT INTO @tmpLicenseeReseller (FromPartyID, ToPartyID, FromDate,ToDate, OldRefID)
		SELECT DISTINCT ci.FromParty, ci.ToParty, 
		CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
		case WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END,
		p.OldRefID
		FROM bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) 
			INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK)ON ci.FromParty = p.PartyID
		WHERE (@FromDate BETWEEN ci.FromDate AND ci.ToDate OR 
			@ToDate BETWEEN ci.FromDate AND ci.ToDate)
			AND ci.ChargeType = 1
			AND ci.ProductID = 2
			and ci.FromParty =@PartyID			
	END	
	ELSE --for Boping's Licensee
	BEGIN
		INSERT INTO @tmpLicenseeReseller (FromPartyID, ToPartyID, FromDate,ToDate, OldRefID)
		SELECT DISTINCT ci.FromParty, ci.ToParty, 
		CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
		case WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END,
		p.OldRefID
		FROM bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) 
			INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK)ON ci.FromParty = p.PartyID
		WHERE (@FromDate BETWEEN ci.FromDate AND ci.ToDate OR 
			@ToDate BETWEEN ci.FromDate AND ci.ToDate)
			AND ci.ChargeType = 1
			AND ci.ProductID = 2
			and ci.ToParty =@PartyID
		set @isBoping=1
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
			INNER JOIN @tmpLicenseeReseller lr ON b.SiteID = lr.OldRefID 
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd (NOLOCK) ON lr.FromPartyID = pd.PartyID				
		WHERE pd.IsDeposit = 1 
	 		AND b.rptDate BETWEEN lr.FromDate AND lr.ToDate
			AND b.status NOT IN (-1,103)
			AND CurrencyID<>20
			AND bettype BETWEEN 81 AND 120
			--Exclude Licensees from Starlit, BA(FDL)
	 		AND lr.ToPartyID NOT IN (SELECT PartyID FROM @tmpTable)
			AND (@Currency=0 OR  b.CurrencyID =@Currency)
		GROUP BY b.rptDate, b.CurrencyID, lr.ToPartyID, lr.FromPartyID
		set @isDeposit=1
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
		FROM @tmpLicenseeReseller lr 
			INNER JOIN bodb_Licensee.dbo.OAS_PartyDetail pd (NOLOCK) ON lr.FromPartyID = pd.PartyID 
			INNER JOIN bodb_Licensee.dbo.labels lb (NOLOCK) ON lr.OldRefID = lb.LicenseeID 
			INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID = lb.LabelID
		WHERE pd.IsDeposit = 0 
	 		AND b.rptDate BETWEEN lr.FromDate AND lr.ToDate
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
	DECLARE @ExDate smalldatetime
	SELECT @ExDate = CONVERT(VARCHAR(10), CASE 
											WHEN DATEDIFF(month,@ToDate,GETDATE()) <= 0 THEN GETDATE() 
											ELSE DATEADD(day,-1,DATEADD(month,1,'01 '+SUBSTRING(CONVERT(VARCHAR(11),@ToDate,106),4,8)))
										  END,120)
	
	SELECT *
	INTO #Exchange1
	--FROM Lrf_f_GetExchangeDaily(@FromDate,@ToDate)
	FROM Lrf_f_GetExchangeDaily(@ExDate,@ExDate) -- get exchange rate in last day of month
	WHERE exchangeid IN (SELECT DISTINCT Currency FROM #Data)
	
	SELECT *
	INTO #Exchange	
	FROM Lrf_f_GetExchangeDaily(@FromDate,@ToDate) -- get exchange rate in last day of month
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
					d.ToPartyID = DI.ToParty AND d.FromPartyID = DI.FromParty 
					AND DI.ProductID = 2 
					AND d.winlostdate BETWEEN DI.FromDate AND DI.ToDate 
					AND DI.ChargeType = 1 
			LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo OW ON DI.ParentChargeID = OW.ChargeID
		GROUP BY
			d.ToPartyID, d.FromPartyID, DI.Rate, OW.Rate,winlostdate,d.Currency
	END	

	--return the result for deposit Licensee
	IF (@isDeposit=1 AND @isBoping=0) -- normal Licensees and not Boping's
	SELECT	
		CONVERT(VARCHAR(6),winlostdate,112)   AS Winlostdate,
		re.Currency,
		CASE WHEN re.Currency = 20 THEN 'UUS'
			WHEN re.Currency = 51 THEN 'INH'
			ELSE e.Code 
		END AS CurrencyName,
		ISNULL(e1.EUR,0) EUR,
		SUM(re.betcount) AS BetCount,
		--base
		SUM(re.turnover) AS Turnover,
		SUM(re.MemberWinloss) AS MemberWinloss,
		SUM(re.GrossWinloss) AS LicenseeWinloss,
		SUM(re.OneworksRevenue) AS OneworksRevenue,
		--EUR

		SUM(re.turnover * e.EUR) AS TurnoverEUR,
		SUM(re.MemberWinloss * e.EUR) AS MemberWinlossEUR,
		SUM(re.GrossWinloss * e.EUR) AS LicenseeWinlossEUR,
		SUM(re.OneworksRevenue * e.EUR) AS OneworksRevenueEUR,

		--USD

		SUM(re.turnover * e.USD) AS TurnoverUSD,
		SUM(re.MemberWinloss * e.USD) AS MemberWinlossUSD,
		SUM(re.GrossWinloss * e.USD) AS LicenseeWinlossUSD,
		SUM(re.OneworksRevenue * e.USD) AS OneworksRevenueUSD
	FROM #Result re
		INNER JOIN #Exchange e ON re.currency = e.ExchangeId AND re.winlostdate=e.ExchangeDate
		LEFT JOIN #Exchange1 e1 ON re.currency = e1.ExchangeId 
	GROUP BY
		re.Currency,ISNULL(e1.EUR,0),e.code,CONVERT(VARCHAR(6),winlostdate,112)

	IF (@isDeposit=0 or @isBoping=1)--credit licensee or Boping Licensee
	BEGIN
		SELECT A.Winlostdate,A.currencyName,A.EUR,
				SUM(A.BetCount)			AS BetCount ,
				SUM(A.Turnover)			AS Turnover ,
				SUM(A.MemberWinloss)	AS MemberWinloss,
				SUM(A.LicenseeWinloss)	AS LicenseeWinloss,
				SUM(A.OneworksRevenue)	AS OneworksRevenue,
				--EUR
				SUM(A.TurnoverEUR)		AS TurnoverEUR,
				SUM(A.MemberWinlossEUR) AS MemberWinlossEUR,
				SUM(A.LicenseeWinlossEUR) AS LicenseeWinlossEUR,
				SUM(A.OneworksRevenueEUR) AS OneworksRevenueEUR,
				--USD
				SUM(A.TurnoverUSD) AS TurnoverUSD,
				SUM(A.MemberWinlossUSD) AS MemberWinlossUSD,
				SUM(A.LicenseeWinlossUSD) AS LicenseeWinlossUSD,
				SUM(A.OneworksRevenueUSD) AS OneworksRevenueUSD
		FROM (
				SELECT	
				CONVERT(VARCHAR(6),winlostdate,112)   AS Winlostdate,
				'EUR' currencyName,1 EUR,
				ISNULL(SUM(re.betcount), 0) AS BetCount,
				--base in EUR
				SUM(re.turnover * e.EUR) AS Turnover,
				CASE WHEN SUM(re.MemberWinloss * e.EUR) > 0 AND @isBoping = 1 THEN 0
					 ELSE SUM(re.MemberWinloss * e.EUR)
					 END AS MemberWinloss,
				CASE WHEN SUM(re.GrossWinloss * e.EUR) < 0 AND @isBoping = 1 THEN 0
							  ELSE SUM(re.GrossWinloss * e.EUR)
							  END AS LicenseeWinloss,
				CASE WHEN SUM(re.OneworksRevenue * e.EUR) < 0 AND @isBoping = 1 THEN 0
							  ELSE SUM(re.OneworksRevenue * e.EUR)
							  END AS OneworksRevenue,
				--EUR
				SUM(re.turnover * e.EUR)  AS TurnoverEUR,
				CASE WHEN SUM(re.MemberWinloss * e.EUR) > 0 AND @isBoping = 1 THEN 0 
					 ELSE SUM(re.MemberWinloss * e.EUR)
					 END						AS MemberWinlossEUR,
				CASE WHEN SUM(re.GrossWinloss * e.EUR) < 0 AND @isBoping = 1 THEN 0
							  ELSE SUM(re.GrossWinloss * e.EUR)
							  END AS LicenseeWinlossEUR,
				CASE WHEN SUM(re.OneworksRevenue * e.EUR) < 0 AND @isBoping = 1 THEN 0
							  ELSE SUM(re.OneworksRevenue * e.EUR)
							  END AS OneworksRevenueEUR,
				--USD
				SUM(re.turnover * e.USD) AS TurnoverUSD,
				CASE WHEN SUM(re.MemberWinloss * e.USD) > 0 AND @isBoping = 1 THEN 0
					 ELSE SUM(re.MemberWinloss * e.USD)
					 END						 AS MemberWinlossUSD,
				CASE WHEN SUM(re.GrossWinloss * e.USD ) < 0 AND @isBoping = 1 THEN 0
							  ELSE SUM(re.GrossWinloss * e.USD)
							  END AS LicenseeWinlossUSD,
				CASE WHEN SUM(re.OneworksRevenue * e.USD) < 0 AND @isBoping = 1 THEN 0 
							  ELSE SUM(re.OneworksRevenue * e.USD)
							  END AS OneworksRevenueUSD
			FROM #Result re
				INNER JOIN #Exchange e ON re.currency = e.ExchangeId AND re.winlostdate=e.ExchangeDate				
			GROUP BY
				RE.LicenseeID,CONVERT(VARCHAR(6),winlostdate,112)
		) A
		GROUP BY A.Winlostdate,A.currencyName,A.EUR
	END
	DROP TABLE	#Data
	DROP TABLE  #Exchange
	DROP TABLE  #Exchange1
	DROP TABLE	#Result
END  


GO
GRANT EXECUTE ON [dbo].[OAS_Report_NumberGameWinloss_NewStruct] TO [bodbLicenseeNet] 
GRANT EXECUTE ON [dbo].[OAS_Report_NumberGameWinloss_NewStruct] TO bodbAdminNet 
GRANT VIEW DEFINITION ON [dbo].[OAS_Report_NumberGameWinloss_NewStruct] TO [vnteam] 
