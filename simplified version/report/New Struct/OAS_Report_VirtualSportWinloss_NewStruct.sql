USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[OAS_Report_VirtualSportWinloss_NewStruct]    Script Date: 07/04/2014 11:08:43 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


ALTER PROCEDURE [dbo].[OAS_Report_VirtualSportWinloss_NewStruct]      
	@PartyID    INT,  
    @Currency  INT = 0,  
	@drawfilter  SMALLINT = 1, 
	@FromDate  SMALLDATETIME,    
	@ToDate   SMALLDATETIME,    
	@SportList	VARCHAR(1000)
	
AS      
  
/*  
 * Created by : 20131219@Francis 
 * Task  : Get Winloss report for Virtual Sports (compatible with the new structure)
 * DB   : DB052.bodb02
 * Revisions :  
	-20140331@Florent: Aplly new report template
	-20140416@Florent: change condition of time range 
 	
 * Param's Explanation:    
 *  
 *  
 */  
    
BEGIN      

	SET NOCOUNT ON
	
	DECLARE @tmpLicenseeReseller AS TABLE (FromPartyID INT, ToPartyID INT, FromDate DateTime, ToDate datetime, OldRefID INT)	
	DECLARE @sporttype TABLE(sporttype INT)
	
	CREATE TABLE #Data (winlostdate  DATETIME, Currency  INT,  FromPartyID int, ToPartyID int, TurnOver MONEY, MemberWinloss MONEY, Betcount INT)
	
	--Output table 
	CREATE TABLE #Result (ResellerID INT, LicenseeID int, TurnOver MONEY, MemberWinloss MONEY, GrossWinloss MONEY, DistributorRevenue MONEY, Betcount INT, OneworksIncome MONEY, AmtDueToInspired MONEY, DistributorsChargeRate MONEY, OneworksChargeRate MONEY, InspiredChargeRate MONEY,winlostdate  DATETIME, Currency  INT)

	DECLARE @tmpTable AS TABLE (PartyID INT)
	INSERT INTO @tmpTable (PartyID)
	SELECT PartyID FROM bodb_licensee.dbo.OAS_Party (NOLOCK)
		   WHERE PartyName IN ('Starlit','BA(FDL)')
	
	IF (RTRIM(LTRIM(ISNULL(@SportList,'')))) = ''
	BEGIN
		INSERT INTO @sporttype VALUES (180) --Virtual Soccer
	END
	ELSE
	BEGIN
		INSERT INTO @sporttype (sporttype)
		-- strSpit is a user-defined function
		SELECT RTRIM(LTRIM(VAL)) FROM strSplit(@SportList,',')
	END

	--hard code get licensee depend boping
	DECLARE @LicBoping int =0,@isDeposit int =0,@isBoping int =0
	SELECT @LicBoping=PartyID FROM bodb_licensee.dbo.OAS_Party with (nolock) WHERE PartyName='Boping'

	--Get normal licensee list	
	IF (@LicBoping!=@PartyID)
	BEGIN
		insert into @tmpLicenseeReseller (FromPartyID, ToPartyID, FromDate, ToDate, OldRefID)
		select DISTINCT ci.FromParty, ci.ToParty, case WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
		case WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END,
		p.OldRefID
		from bodb_licensee.dbo.OAS_ChargeInfo ci (NOLOCK) inner JOIN bodb_Licensee.dbo.OAS_Party p (NOLOCK)
		ON ci.FromParty = p.PartyID
		where (@FromDate BETWEEN ci.FromDate AND ci.ToDate OR 
			@ToDate BETWEEN ci.FromDate AND ci.ToDate)
			AND ci.ChargeType = 1
			AND ci.ProductID = 5
			and ci.FromParty =@PartyID
	END		
	ELSE -- get boping's licensees
	BEGIN
		INSERT INTO @tmpLicenseeReseller (FromPartyID, ToPartyID, FromDate, ToDate, OldRefID)
		SELECT DISTINCT ci.FromParty, ci.ToParty, 
		CASE WHEN @FromDate <= ci.FromDate THEN ci.FromDate ELSE @FromDate END,
		case WHEN @ToDate >= ci.ToDate THEN ci.ToDate ELSE @ToDate END,
		p.OldRefID
		FROM bodb_licensee.dbo.OAS_ChargeInfo ci WITH (NOLOCK) 
			INNER JOIN bodb_Licensee.dbo.OAS_Party p WITH (NOLOCK)ON ci.FromParty = p.PartyID
		WHERE (@FromDate BETWEEN ci.FromDate AND ci.ToDate OR 
			@ToDate BETWEEN ci.FromDate AND ci.ToDate)
			AND ci.ChargeType = 1
			AND ci.ProductID = 5
			and ci.ToParty =@PartyID
		set @isBoping =1
	END
	
	--For Deposit Licensees
	IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller tlr 
							INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd1 (NOLOCK) ON tlr.FromPartyID = pd1.PartyID
					   WHERE pd1.IsDeposit = 1 AND tlr.ToPartyID NOT IN (SELECT PartyID FROM @tmpTable))
	BEGIN
		INSERT INTO #Data (winlostdate, Currency,  FromPartyID, ToPartyID, TurnOver, MemberWinloss, Betcount)
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
		SUM(b.Winloss) AS MemberWinloss,
		SUM(BetCount * CASE   
						WHEN @drawfilter = 2 THEN  
							CASE   
							WHEN b.status = 111 THEN 0  
							ELSE 1   
							END  
						ELSE 1   
						END  ) AS BetCount
		FROM bodb_Licensee.dbo.rpt_Betting b (NOLOCK) 
			INNER JOIN @tmpLicenseeReseller lr 	ON b.SiteID = lr.OldRefID 
			INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd (NOLOCK) ON lr.FromPartyID = pd.PartyID 
			INNER JOIN bodb02.dbo.league l (NOLOCK)	ON l.leagueid = b.LeagueID
		WHERE pd.IsDeposit = 1 
	 		AND b.rptDate BETWEEN lr.FromDate AND lr.ToDate
			AND b.status NOT IN (-1,103)
			AND CurrencyID<>20
			AND bettype BETWEEN 1201 AND 1299
			AND l.Sporttype IN (SELECT sporttype FROM @sporttype)
			--Exclude Licensees from Starlit, BA(FDL)
	 		AND lr.ToPartyID NOT IN (SELECT PartyID FROM @tmpTable)
			AND (@Currency=0 OR  b.CurrencyID =@Currency)
		GROUP BY b.rptDate, b.CurrencyID, lr.ToPartyID, lr.FromPartyID
		set @isDeposit=1
	END	

	--For Credit Licensees
	IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller tlr
							INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd1 (NOLOCK)ON tlr.FromPartyID = pd1.PartyID
							WHERE pd1.IsDeposit = 0)
	BEGIN
		INSERT INTO #Data (winlostdate, Currency,  FromPartyID, ToPartyID, TurnOver, MemberWinloss, Betcount)
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
		 ) AS TurnOver
		, SUM(b.Winloss) AS MemberWinloss, 
		SUM(BetCount * CASE   
						WHEN @drawfilter = 2 THEN  
							CASE   
							WHEN b.status = 111 THEN 0  
							ELSE 1   
							END  
						ELSE 1   
						END  ) AS BetCount
		FROM @tmpLicenseeReseller lr 
			INNER JOIN bodb_Licensee.dbo.OAS_PartyDetail pd (NOLOCK) ON lr.FromPartyID = pd.PartyID 
			INNER JOIN bodb_Licensee.dbo.labels lb (NOLOCK) ON lr.OldRefID = lb.LicenseeID 
			INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID = lb.LabelID 
			INNER JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
		WHERE pd.IsDeposit = 0 
	 		AND b.rptDate BETWEEN lr.FromDate AND lr.ToDate
			AND b.status NOT IN (-1,103)
			AND CurrencyID<>20
			AND bettype BETWEEN 1201 AND 1299
			AND b.customercategory NOT IN (27,28) 
			AND l.Sporttype IN (SELECT sporttype FROM @sporttype)
			AND (@Currency=0 OR  b.CurrencyID =@Currency)
		GROUP BY b.rptDate, b.CurrencyID, lr.ToPartyID, lr.FromPartyID		
	END

	CREATE NONCLUSTERED INDEX IDX_Currency ON #Data(Currency,winlostdate)

	--get specified exchange value in time range	
	DECLARE @ExDate smalldatetime
	SELECT @ExDate = CONVERT(VARCHAR(10), CASE 
											WHEN DATEDIFF(month,@ToDate,GETDATE()) <= 0 THEN GETDATE() 
											ELSE DATEADD(day,-1,DATEADD(month,1,'01 '+SUBSTRING(CONVERT(VARCHAR(11),@ToDate,106),4,8)))
										  END,120)
	
	SELECT *
	INTO #Exchange	
	FROM Lrf_f_GetExchangeDaily(@ExDate,@ExDate) -- get exchange rate in last day of month
	WHERE exchangeid IN (SELECT DISTINCT Currency FROM #Data)
	
	--For Normal Licensees
	INSERT INTO #Result(ResellerID, LicenseeID, TurnOver, MemberWinloss, GrossWinloss, DistributorRevenue, 
						Betcount, OneworksIncome, AmtDueToInspired, DistributorsChargeRate, 
						OneworksChargeRate, InspiredChargeRate,winlostdate,Currency)
	SELECT	
		d.ToPartyID, d.FromPartyID,
		CAST(isnull(SUM(d.TurnOver ),0) AS MONEY) AS TurnOver,
		
		CAST(isnull(SUM(d.MemberWinloss ),0) AS MONEY) AS MemberWinloss,
		
		CAST(-1 * isnull(SUM(d.MemberWinloss ),0) AS money) AS GrossWinloss,
		CAST(CASE WHEN INS.Rate IS NOT NULL THEN
					-1 * isnull(SUM(d.MemberWinloss  * isnull(DI.Rate,0)),0) --normal lics
					ELSE 0 -- Direct licensee
			 END 
		 AS money) AS DistributorRevenue,
		ISNULL(SUM(d.betcount), 0) AS BetCount,
		CAST(CASE WHEN INS.Rate IS NOT NULL THEN --normal Licensee
					-1 * isnull(SUM(d.MemberWinloss  * isnull(OW.Rate,0)),0)--isnull(SUM(-1 * d.MemberWinloss ),0) < 0 THEN 0 
				  ELSE -1 * isnull(SUM(d.MemberWinloss  * isnull(DI.Rate,0)),0) --direct licensee
				  END AS money) AS OneworksIncome,
		CAST(CASE 
				WHEN INS.Rate IS NOT NULL THEN 
					isnull(SUM(-1 * d.MemberWinloss  * isnull(INS.Rate,0)),0) -- normal licensee
				--isnull(SUM(-1 * d.MemberWinloss ),0) < 0 THEN 0 
				ELSE isnull(SUM(-1 * d.MemberWinloss  * isnull(OW.Rate,0)),0) 
			 END AS money) AS AmtDueToInspired,
		isnull(DI.Rate,0) as DistributorsChargeRate,
		isnull(OW.Rate,0) as OneworksChargeRate,
		isnull(INS.Rate,0) as InspiredChargeRate
		,winlostdate,Currency
	FROM #Data d			
		LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo DI ON
				 d.ToPartyID = DI.ToParty 
				AND d.FromPartyID = DI.FromParty AND DI.ProductID = 5 
				AND d.winlostdate BETWEEN DI.FromDate AND DI.ToDate 
				AND DI.ChargeType = 1 
		LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo OW ON DI.ParentChargeID = OW.ChargeID
		LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo INS ON OW.ParentChargeID = INS.ChargeID
	GROUP BY
		d.ToPartyID, d.FromPartyID, DI.Rate, OW.Rate, INS.Rate, OW.ChargeType,winlostdate,Currency


	--return the result for deposit licensee
	IF (@isDeposit=1 and @isBoping=0) --normal Licensee and not Boping
	SELECT	
		CONVERT(VARCHAR(6),winlostdate,112) AS Winlostdate,
		re.Currency,
		CASE WHEN re.Currency = 20 THEN 'UUS'
			WHEN re.Currency = 51 THEN 'INH'
			ELSE e.Code 
		END AS CurrencyName
		 ,e.EUR,
		SUM(re.betcount) AS BetCount,

		SUM(re.turnover)AS Turnover,
		SUM(re.MemberWinloss) AS MemberWinloss,
		SUM(re.GrossWinloss)AS LicenseeWinloss,
		SUM(re.OneworksIncome-re.AmtDueToInspired) AS OneworksRevenue,

		--EUR
		SUM(re.turnover * e.EUR) AS TurnoverEUR,
		SUM(re.MemberWinloss * e.EUR) AS MemberWinlossEUR,
		SUM(re.GrossWinloss * e.EUR) AS LicenseeWinlossEUR,
		SUM(re.OneworksIncome-re.AmtDueToInspired) * e.EUR AS OneworksRevenueEUR,
		--USD
		SUM(re.turnover * e.USD) AS TurnoverUSD,
		SUM(re.MemberWinloss * e.USD) AS MemberWinlossUSD,
		SUM(re.GrossWinloss * e.USD) AS LicenseeWinlossUSD,
		SUM(re.OneworksIncome-re.AmtDueToInspired) * e.USD AS OneworksRevenueUSD
	FROM #Result re
		INNER JOIN #Exchange e ON re.currency = e.ExchangeId
	GROUP BY		
		re.Currency,e.EUR,e.code,e.USD,CONVERT(VARCHAR(6),winlostdate,112)

	--for credit
	IF (@isDeposit=0 or @isBoping=1) --credit Licensee or Boping
	SELECT	
		CONVERT(VARCHAR(6),winlostdate,112) AS Winlostdate,
		'EUR' CurrencyName ,1 EUR,
		ISNULL(SUM(re.betcount), 0) AS BetCount,
		--base on EUR
		SUM(re.turnover * e.EUR) AS Turnover,
		SUM(re.MemberWinloss * e.EUR) AS MemberWinloss,
		SUM(re.GrossWinloss * e.EUR) AS LicenseeWinloss,
		SUM(re.OneworksIncome * e.EUR-re.AmtDueToInspired * e.EUR)  AS OneworksRevenue,

		--EUR
		SUM(re.turnover * e.EUR) AS TurnoverEUR,
		SUM(re.MemberWinloss * e.EUR) AS MemberWinlossEUR,
		SUM(re.GrossWinloss * e.EUR) AS LicenseeWinlossEUR,
		SUM(re.OneworksIncome* e.EUR-re.AmtDueToInspired* e.EUR) AS OneworksRevenueEUR,
		--USD
		SUM(re.turnover * e.USD) AS TurnoverUSD,
		SUM(re.MemberWinloss * e.USD) AS MemberWinlossUSD,
		SUM(re.GrossWinloss * e.USD) AS LicenseeWinlossUSD,
		SUM(re.OneworksIncome* e.USD-re.AmtDueToInspired* e.USD) AS OneworksRevenueUSD
	FROM #Result re
		INNER JOIN #Exchange e ON re.currency = e.ExchangeId		
	GROUP BY		
		CONVERT(VARCHAR(6),winlostdate,112)		
	DROP TABLE	#Data
	DROP TABLE	#Result
	DROP TABLE	#Exchange
	
END  

GO
GRANT EXECUTE ON [dbo].[OAS_Report_VirtualSportWinloss_NewStruct] TO [bodbLicenseeNet] 
GRANT EXECUTE ON [dbo].[OAS_Report_VirtualSportWinloss_NewStruct] TO bodbAdminNet 
GRANT VIEW DEFINITION ON [dbo].[OAS_Report_VirtualSportWinloss_NewStruct] TO [vnteam] 