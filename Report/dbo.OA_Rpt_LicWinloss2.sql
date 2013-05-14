ALTER  PROCEDURE [dbo].[OA_Rpt_LicWinloss2]  
 @LicenseeID	INT,
 @Currency		INT = 0,
 @FromDate		SMALLDATETIME,  
 @ToDate		SMALLDATETIME,   
 @showSB		BIT=1,  
 @ShowRB		BIT=0,  
 @ShowNG		BIT=0, 
 @ShowBA		BIT=0,
 @ShowLC		BIT=0,
 @ShowVS		BIT=0,
 @SportID		INT=0,
 @BettypeID		INT=0,
 @ReportType	TINYINT=1,  
 @MoveBetsDay SMALLDATETIME,
 @drawfilter SMALLINT = 1  ,
 @excludeTest BIT = 0
AS  
/*  Created:  Jim
	Date: 2012-04-11
    Original:OA_Rpt_LicWinloss
	Task : LicenseeAdmin - Add sports+bet types filter to Licensee Winloss reports 
    DB: DB052.bodb02  
    20121231@Henry: Enhance Performance
   
    Revisions:  

	Param's Explanation:  
	  + @ReportType: 1-Daily; 2-Monthly;  
	  +	@drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @IsOld: 0 - query in table rptLicWinloss, 1 - query in table rptLicWinloss_old. 
	  + @excludeTest: remove currency UUS
	  + @showSB: Show SportsBook bets
	  + @ShowRB: Show RB bets
	  + @ShowNG: Show Number game bets
	  + @ShowBA: Show Bet Aggregator bets (combined with Sportsbook or Number Game)
	  + @ShowLC: Show Live casino
	  + @ShowVS: Show Virtual Sports
	  +@SportID :
			0  : selected all sporttype 
	  +@BetID : 
			0: selected all bettype
	  + @MoveBetsDay: The day we move tickets to bettrans14
*/  
BEGIN  
SET NOCOUNT ON  

CREATE TABLE #SAgWinLoss  (  
	winlostdate		DATETIME,  
	Currency		INT,
	TurnOver		MONEY,   	
	Winlost			MONEY,  
	LicenseeWL		MONEY,
	WinlossRB		MONEY,
	AmtDueToBA	MONEY,   
	AmtDueToRB	MONEY,
	CommBA			MONEY,   
	CommRB		MONEY,   
	Company		MONEY,
	Betcount		BIGINT,
	Playercomm	MONEY
)  
 
DECLARE @VNDCurrencyName VARCHAR(20)
DECLARE @site VARCHAR(50)
SELECT @VNDCurrencyName = currency FROM exchange (NOLOCK) WHERE ExchangeId = 51
--- get CustID List with fileter by @Currency,@excludeTest

BEGIN

	IF @ShowBA=1 
	BEGIN
		INSERT INTO #SAgWinLoss  
		SELECT 
			b.rptDate,
			b.CurrencyID,
			SUM(b.turnover
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0
					WHEN b.status IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			) TurnOver,     
			SUM(b.winloss) Winloss,  
			0 as LicenseeWL,
			0 AS WinlossRB,
			- SUM(b.winloss+b.winlossA+	b.CommissionA)as AmountDueToBA,
			0 as AmountDueToRB,
			SUM(b.CommissionA) as CommBA,
			0 as CommRB,
			0 as Company,
			SUM(betcount)
			* CASE WHEN @drawfilter = 2 AND b.status=111 THEN 0
					ELSE 1 END BetCount,
			SUM(commissionP) AS Playercomm	
		FROM 
			bodb_Licensee.dbo.rpt_Betting_BA b WITH ( NOLOCK ) 
			LEFT JOIN dbo.League l (NOLOCK) ON b.leagueid=l.leagueid
		WHERE  
			b.rptDate BETWEEN @FromDate	 AND @Todate
			AND b.siteID = @LicenseeID
			AND  b.status NOT IN (-1,103)
			AND (@sportID=0 OR (@sportID<>0  AND l.sporttype=@sportID)
				)
			AND (@bettypeID=0 OR (@bettypeID<>0 AND b.bettype=@bettypeID))
			AND (b.bettype <31 OR b.bettype BETWEEN 121 AND 999)
			AND (@Currency=0 OR (@Currency<>0 AND b.CurrencyID=@Currency))
			AND (@excludeTest=0 OR (@excludeTest=1 AND b.CurrencyID<>20))
		GROUP BY  b.rptdate,b.currencyID, b.status
	END
	
	--exclude BA tickets
	IF (@showSB = 1 or @ShowRB = 1 or @ShowNG = 1 OR @ShowLC = 1 OR @ShowVS=1)
	BEGIN
		INSERT INTO #SAgWinLoss  
		SELECT 
			b.rptDate,
			b.CurrencyID,
			SUM(b.turnover
			*
				CASE WHEN b.bettype=33 AND b.status IN (114,115) THEN 0.5 ELSE 1 END
			*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0
					WHEN b.status IN (114,115) THEN 0.5
					ELSE 1 END
				ELSE 1 END
			)TurnOver,     
			SUM(b.winloss) Winloss,  
			-SUM(CASE WHEN (b.bettype NOT BETWEEN 31 AND 33) THEN b.winloss ELSE 0 END) AS LicenseeWL,
			SUM(CASE WHEN b.bettype BETWEEN 31 AND 33  THEN b.winlossA ELSE 0 END) AS WinlossRB,
			0 as AmountDueToBA,
			-SUM(CASE WHEN b.bettype BETWEEN 31 AND 33  THEN (b.winloss+b.winlossA+	b.CommissionA) ELSE 0 END ) AS AmountDueToRB,
			0 as CommBA,
			SUM(CASE WHEN b.bettype BETWEEN 31 AND 33 THEN b.CommissionA ELSE 0 END ) AS CommRB,
			-SUM(CASE WHEN b.bettype NOT BETWEEN 31 AND 33 THEN (b.winloss+b.winlossA+ b.CommissionA) ELSE 0 END ) AS Company,
			SUM(b.betcount)
			* CASE WHEN @drawfilter = 2 THEN
					CASE WHEN b.status = 111 THEN 0
					ELSE 1 END
				ELSE 1 END BetCount,
			SUM(commissionP) AS Playercomm
		FROM 
			bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK )
			LEFT JOIN dbo.League l (NOLOCK) ON b.leagueid=l.leagueid
		WHERE  
			b.rptdate BETWEEN @FromDate AND @Todate 
			AND b.siteID = @LicenseeID
			AND  b.status NOT IN (-1,103) 
			AND (@sportID=0 
				OR (@sportID<>0  AND b.bettype NOT BETWEEN 31 AND 120 AND l.sporttype=@sportID )
				)
			AND (@bettypeID=0 OR (@bettypeID<>0 AND b.bettype=@bettypeID))
			AND (@Currency=0 OR (@Currency<>0 AND b.CurrencyID=@Currency))
			AND (@excludeTest=0 OR (@excludeTest=1 AND b.CurrencyID<>20))
			AND ( (@showSB=1 AND (b.bettype <31 OR b.bettype BETWEEN 121 AND 999))
				OR(@showRB=1 AND b.bettype BETWEEN 31 AND 33)
				OR(@showNG=1 AND b.bettype BETWEEN 81 AND 120)
				OR(@showLC=1 AND b.bettype BETWEEN 1101 AND 1199)
				OR(@showVS=1 AND b.bettype BETWEEN 1201 AND 1299)
				)	
		GROUP BY  b.rptdate, b.currencyID, b.status
	END
	
END 


CREATE NONCLUSTERED INDEX IDX_Index_SA ON #SAgWinLoss(Currency)
SELECT * INTO #TempExchange 
FROM Lrf_f_GetExchangeDaily(@FromDate,@Todate)
WHERE exchangeid IN (SELECT DISTINCT Currency FROM #SAgWinLoss)

SELECT   
   CASE WHEN @ReportType = 1 THEN CONVERT(VARCHAR(8),w.winlostdate,112)  
		WHEN @ReportType = 2 THEN CONVERT(VARCHAR(6),w.winlostdate,112)  
		ELSE '0' END ReportType,  
   w.Currency ,   
		CASE WHEN Currency = 51 THEN @VNDCurrencyName 
			ELSE e.Code END currencyName,
   SUM(TurnOver)	AS Turnover,   
   SUM(Winlost)		AS Winlost,  
   SUM(LicenseeWL) AS LicenseeWL,
   SUM(WinlossRB)	AS WinlossRB,
   SUM(CommBA) AS CommBA,
   SUM(CommRB) AS CommRB,
   SUM(AmtDuetoBA) AS AmtDuetoBA,
   SUM(AmtDuetoRB) AS AmtDuetoRB,
   SUM(Company) AS Company,
   SUM(Betcount)	AS Betcount,
   SUM(playercomm) AS Playercomm,
   
   --BaseRM  
   CAST(SUM(TurnOver*e.MYR) AS MONEY)	AS TurnoverMYR,   
   CAST(SUM(Winlost*e.MYR) AS MONEY)	AS WinlostMYR,  
   CAST(SUM(LicenseeWL*e.MYR) AS MONEY) AS LicenseeWLMYR,
   CAST(SUM(WinlossRB*e.MYR) AS MONEY)	AS WinlossRBMYR,
   CAST(SUM(CommBA * e.MYR) AS MONEY) AS CommBAMYR,
   CAST(SUM(CommRB * e.MYR) AS MONEY) AS CommRBMYR,
   CAST(SUM(AmtDuetoBA*e.MYR) AS MONEY) AS AmtDuetoBAMYR,
   CAST(SUM(AmtDuetoRB*e.MYR) AS MONEY) AS AmtDuetoRBMYR,
   CAST(SUM(Company * e.MYR) AS MONEY) AS CompanyMYR,
   CAST(SUM(playercomm * e.MYR) AS MONEY) AS PlayercommMYR,
   
   --BaseUSD  
   CAST(SUM(TurnOver*e.USD) AS MONEY)	AS TurnoverUSD,   
   CAST(SUM(Winlost*e.USD) AS MONEY)	AS WinlostUSD,  
   CAST(SUM(LicenseeWL*e.USD) AS MONEY) AS LicenseeWLUSD,
   CAST(SUM(WinlossRB*e.USD) AS MONEY)	AS WinlossRBUSD,
   CAST(SUM(CommBA * e.USD) AS MONEY) AS CommBAUSD,
   CAST(SUM(CommRB * e.USD) AS MONEY) AS CommRBUSD,
   CAST(SUM(AmtDuetoBA*e.USD) AS MONEY) AS AmtDuetoBAUSD,
   CAST(SUM(AmtDuetoRB*e.USD) AS MONEY) AS AmtDuetoRBUSD,
   CAST(SUM(Company * e.USD) AS MONEY) AS CompanyUSD,
   CAST(SUM(playercomm * e.USD) AS MONEY) AS PlayercommUSD,
   
    --BaseEUR  
   CAST(SUM(TurnOver*e.EUR) AS MONEY)	AS TurnoverEUR,   
   CAST(SUM(Winlost*e.EUR) AS MONEY)	AS WinlostEUR,  
   CAST(SUM(LicenseeWL*e.EUR) AS MONEY) AS LicenseeWLEUR,
   CAST(SUM(WinlossRB*e.EUR) AS MONEY)	AS WinlossRBEUR,
   CAST(SUM(CommBA * e.EUR) AS MONEY) AS CommBAEUR,
   CAST(SUM(CommRB * e.EUR) AS MONEY) AS CommRBEUR,
   CAST(SUM(AmtDuetoBA*e.EUR) AS MONEY) AS AmtDuetoBAEUR,
   CAST(SUM(AmtDuetoRB*e.EUR) AS MONEY) AS AmtDuetoRBEUR,
   CAST(SUM(Company * e.EUR) AS MONEY) AS CompanyEUR,
   CAST(SUM(playercomm * e.EUR) AS MONEY) AS PlayercommEUR
  
FROM	
	#SAgWinLoss w 
	INNER JOIN 
	#TempExchange e	
	ON w.winlostdate = e.ExchangeDate AND w.currency = e.ExchangeId
GROUP BY   
	Currency
	,CASE WHEN @ReportType = 1 THEN CONVERT(VARCHAR(8),w.winlostdate,112)  
		  WHEN @ReportType = 2 THEN CONVERT(VARCHAR(6),w.winlostdate,112)  
		  ELSE '0' END   
	, CASE WHEN Currency = 51 THEN @VNDCurrencyName 
			ELSE e.Code END
ORDER BY ReportType  

DROP TABLE #SAgWinLoss
DROP TABLE #TempExchange
END   
GO
GRANT EXECUTE ON [dbo].[OA_Rpt_LicWinloss2] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_Rpt_LicWinloss2]TO [vnteam]  
