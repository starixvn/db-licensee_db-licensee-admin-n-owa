USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[OAS_Report_BAWinloss_NewStruct]    Script Date: 4/2/2014 11:21:52  ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



ALTER PROCEDURE [dbo].[OAS_Report_BAWinloss_NewStruct]
(
	@PartyID INT,
	@FromDate DATETIME,
	@ToDate DATETIME,
	@Currency INT = 0,
	@ExchangeID VARCHAR(5) = 'EUR',
	@ReportBy TINYINT = 1,
	@DrawFilter TINYINT = 0
)
AS

/*
 * Created by : 20131223@Francis
 * Task : Get Winloss report for Sportbook (compatible with the new structure)
 * DB: DB052.bodb02
 * Original: [OAS_Report_BAWinloss]
 * Revisions:
 *
 * Params explanation:
 *	- @ReportBy: 0 - Daily, 1 - Monthly
 *	- @DrawFilter: 
 *		+ 0  Normal 
 *		+ 1  No draw (only win and loss tickets are calculated) 
 *		+ 2  No draw for Turnover only (the draw tickets will be calculated in the Total Trans, Turnover of these tickets will not be calculated)
 */

BEGIN
	SET NOCOUNT ON

	CREATE TABLE #BAWinLoss  (  	
		WLDate			DATETIME,
		Currency		INT,
		TurnOver		MONEY,
		TotalTrans		INT,
		CustomerWL		MONEY,
		BAComm 			MONEY,
		AmountBA		MONEY
		)

	

	DECLARE @tempAg	TABLE( custID INT,currency INT)  
	DECLARE @LicenseeName VARCHAR(50)

	SELECT @LicenseeName = PartyName FROM bodb_Licensee.dbo.OAS_Party (NOLOCK) WHERE PartyID = @PartyID

	INSERT INTO @tempAg (custID, currency) 
		SELECT lc.custID, lc.currency 
		FROM bodb_Licensee.dbo.LicenseeCust lc (NOLOCK) inner JOIN bodb_licensee.dbo.OAS_Party p (NOLOCK)
			ON lc.LicenseeID = p.OldRefID AND p.PartyType = 1
		WHERE 																
			p.PartyID = @PartyID										
			AND (@Currency = 0 OR (@Currency<> 0 AND Currency=@Currency))	
			AND (Currency <> 20)

	DECLARE @Super AS TABLE (custid int primary key, currency int)				   
	INSERT INTO @Super(custid, currency)  
	SELECT CustID, currency FROM Dep_CustSuper (NOLOCK)  
	WHERE site = @licenseeName

	DECLARE @moveBetsDay SMALLDATETIME
	SELECT @moveBetsDay = MAX(m.eventdate) FROM dbo.match14 m (NOLOCK)

	DECLARE @TempFromDate DATETIME
	DECLARE @TempToDate DATETIME 	   
	DECLARE @MaxOldDate DATETIME	   
	DECLARE @FDate DATETIME 		   
	DECLARE @TDate DATETIME 		   

	SELECT @FDate=@fromDate, @TDate=@toDate 	
	IF @TDate > @moveBetsDay  
	BEGIN				
		IF @FDate <= @moveBetsDay 
			SET @TempFromDate =  DATEADD(DAY,1,@moveBetsDay)	 
		ELSE												 
			SET @TempFromDate = @FDate

			INSERT INTO #BAWinLoss  
			SELECT   
				b.winlostdate,  
				b.currency,
				SUM(b.stake*CASE 
						WHEN @DrawFilter IN (1,2) THEN
						CASE 
							WHEN b.statusID = 111 THEN 0 
							WHEN (b.statusID IN (112,113) AND ABS(b.modds) = 0.25 AND b.bettype IN (1,3,7,8,17,18)) THEN 0.5
							ELSE 1 
						END
						ELSE 1 
					END) AS TurnOver, 
				COUNT(b.transid) AS TotalTrans,
				SUM(b.winlost - b.actual_stake + PlayerComm) AS CustomerWL,
				SUM(comm) AS BAComm, 
				- SUM(b.winlost - b.actual_stake + awinlost + comm) AS AmountBA
			FROM 
				dbo.bettrans b WITH (NOLOCK,INDEX=IX_srecommend)    
				INNER JOIN @Super s ON b.srecommend = s.custid
				INNER JOIN @TempAg tma ON tma.CustID = b.recommend			
				INNER JOIN bodb_Licensee.dbo.LicenseeBATransaction_active BA WITH (NOLOCK) ON s.custid = BA.srecommend and b.transid = BA.transid 	 
			WHERE 
				b.winlostdate BETWEEN @TempFromDate AND @TDate AND  
				b.statusID  IN (111, 112, 113) AND 
				(@DrawFilter <> 1 OR b.statusID != 111) -- NoDraw filter
			GROUP BY   
				b.winlostdate, b.currency

	END  	
    
	IF @FDate <= @moveBetsDay  
	BEGIN 
		IF @TDate >= @moveBetsDay	  
			SET @TempToDate = @moveBetsDay	
		ELSE							   
			SET  @TempToDate = @TDate		  
		
		INSERT INTO #BAWinLoss  
		SELECT 
			b.winlostdate,  
			b.currency,
			SUM(b.turnover*	CASE 
								WHEN @DrawFilter IN (1,2) THEN
								CASE 
									WHEN b.statusID = 111 THEN 0 
									WHEN b.statusID IN (114,115) THEN 0.5
									ELSE 1 
								END
								ELSE 1 
							END) AS TurnOver, 
			SUM(b.BetCount) AS TotalTrans,
			SUM(b.winlost + b.playerComm) AS CustomerWL,
			SUM(comm) AS BAComm, 
			- SUM(b.winlost + b.awinlost + b.comm) AS AmountBA
		FROM 
			bodb_Licensee.dbo.rptLicWinloss2 b (NOLOCK)  
			INNER JOIN @TempAg ag ON ag.custid = b.recommend
		WHERE  
			b.Winlostdate BETWEEN @FDate AND @TempToDate  
			AND b.roleid = 2   
			AND b.statusID <> 101 --exclude REJECT bets
			AND ISNULL(b.isBA,0) = 1
			AND b.statusID IN (111,112,113,114,115)
			AND (@DrawFilter <> 1 OR b.statusID != 111) -- NoDraw filter
		GROUP BY  b.winlostdate, b.currency
			 
	END 
	CREATE NONCLUSTERED INDEX IDX_Index_BA ON #BAWinLoss(Currency)	

	-- Remove data before AffectedDate
	DECLARE @AffectedDate DATETIME
	SELECT @AffectedDate = FromDate
	FROM bodb_licensee.dbo.OAS_ChargeInfo (NOLOCK) 
	WHERE FromParty = @PartyID and
		  (@FromDate BETWEEN FromDate AND ToDate OR 
		  @ToDate BETWEEN FromDate AND ToDate)
		  AND ProductID = 3
		  AND ChargeType = 1
	
	DELETE FROM #BAWinLoss WHERE WLDate < @AffectedDate

	SELECT exchangedate, ExchangeId, Code,  
		CASE @ExchangeID
			WHEN 'USD' THEN USD
			WHEN 'EUR' THEN EUR
			ELSE CNY
		END AS ExRate
	INTO #TempExchange 									   
	FROM Lrf_f_GetExchangeDaily(@FromDate,@ToDate)						   
	WHERE exchangeid IN (SELECT DISTINCT Currency FROM #BAWinLoss)

	IF (@ReportBy = 0) -- Daily report
		BEGIN
			SELECT CONVERT(VARCHAR(10),wl.WLDate,101) AS WLDate, wl.Currency, wl.TurnOver, wl.TotalTrans, wl.CustomerWL, wl.BAComm, wl.AmountBA,
				   e.Code AS CurrencyName, 
				   wl.TurnOver * e.ExRate AS TurnOverEx,
				   wl.CustomerWL * e.ExRate AS CustomerWLEx,
				   wl.BAComm * e.ExRate AS BACommEx,
				   wl.AmountBA * e.ExRate AS AmountBAEx
			FROM #BAWinLoss wl
			       INNER JOIN #tempExchange e ON wl.WLDate = e.ExchangeDate AND wl.currency = e.ExchangeId
			ORDER BY CONVERT(VARCHAR(10),wl.WLDate,101), wl.Currency
		END
		ELSE -- Monthly report
		BEGIN
			SELECT SUBSTRING(CONVERT(VARCHAR(10),wl.WLDate,103),4,7) AS WLDate, 
				   wl.Currency, 
				   SUM(wl.TurnOver) AS TurnOver, 
				   SUM(wl.TotalTrans) AS TotalTrans, 
				   SUM(wl.CustomerWL) AS CustomerWL, 
				   SUM(wl.BAComm) AS BAComm, 
				   SUM(wl.AmountBA) AS AmountBA,
				   e.Code AS CurrencyName, 
				   SUM(wl.TurnOver * e.ExRate) AS TurnOverEx,
				   SUM(wl.CustomerWL * e.ExRate) AS CustomerWLEx,
				   SUM(wl.BAComm * e.ExRate) AS BACommEx,
				   SUM(wl.AmountBA * e.ExRate) AS AmountBAEx
			FROM #BAWinLoss wl
				 INNER JOIN #tempExchange e ON wl.WLDate = e.ExchangeDate AND wl.currency = e.ExchangeId
			GROUP BY SUBSTRING(CONVERT(VARCHAR(10),wl.WLDate,103),4,7), wl.Currency, e.Code
			ORDER BY SUBSTRING(CONVERT(VARCHAR(10),wl.WLDate,103),4,7), wl.Currency
		END
	

	DROP TABLE #BAWinLoss
	DROP TABLE #TempExchange
END
GO
GRANT EXECUTE ON [dbo].[OAS_SelCurrencyByParty] TO [bodbLicenseeNet] 
GRANT EXECUTE ON [dbo].[OAS_SelCurrencyByParty] TO bodbAdminNet 
GRANT VIEW DEFINITION ON [dbo].[OAS_SelCurrencyByParty] TO [vnteam] 

