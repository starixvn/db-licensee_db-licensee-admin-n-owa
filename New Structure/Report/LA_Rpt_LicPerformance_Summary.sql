USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LicPerformance_Summary]    Script Date: 01/12/2014 14:39:13 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_Rpt_LicPerformance_Summary    Script Date: 3/6/2014 5:23:51 PM ******/
ALTER PROCEDURE [dbo].[LA_Rpt_LicPerformance_Summary] 
	 @PartyIDs	VARCHAR(1000)	 = ''
	,@Currency	INT			 = 0
	,@FromDate	SMALLDATETIME
	,@ToDate		SMALLDATETIME
	,@ProductCode	VARCHAR(6)
	,@ReportType	TINYINT		 = 2
	,@MoveBetsDay	SMALLDATETIME
	,@drawfilter	SMALLINT		 = 1
	,@excludeTest	BIT			 = 0

AS  
/*	Created by: 20140929@Florent
	Original: OA_Rpt_LicPerformance_Summary
	Task : LicenseeAdmin - Get Licensee Perfomance Summary Report 
     DB: DB052.bodb02  
   
    Revisions:  
	   
	Param's Explanation:  
	  + @PartyIDs : a string of list PartyID, separated by ','
	  + @Currency : 0-All Currencies
	  + @ReportType: 1-Daily; 2-Monthly
	  + @drawfilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: remove currency UUS
	  + @showSB: Show SportsBook bets
	  + @ShowRB: Show RB bets
	  + @ShowNG: Show Number game bets
	  + @ShowBA: Show Bet Aggregator bets (combined with Sportsbook or Number Game)
	  + @ShowLC: Show Live casino
	  + @ShowVS: Show Virtual Sports
	  + @ShowCS: Show RNG Casino 
	  + @SportID: 0-selected all sporttype 
	  + @BettypeID : 0-selected all bettype
	  + @MoveBetsDay: The day we move tickets to bettrans14
*/  
BEGIN  
SET NOCOUNT ON  

SET @ReportType = 2 -- only allow monthly  

CREATE TABLE #Bettype (Bettype INT,ProductID INT)
CREATE TABLE #tmpParty (
	   PartyID	    INT
	   ,LicenseeID   INT
	   ,isDeposit    INT
	   ,AffectedDate SMALLDATETIME
	   ,ProductID    INT 
	   ,Rate	    Money
	   ,Fromdate	    SMALLDATETIME
	   ,Todate	    SMALLDATETIME
	   )

INSERT INTO #Bettype
SELECT Bettype,ProductID FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(0, @ProductCode)

INSERT INTO #tmpParty
SELECT PartyID,LicenseeID,isDeposit,AffectedDate,ProductID,DI_Rate,Fromdate,Todate
FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs, @FromDate, @ToDate, @ProductCode, 'OA',@ExcludeTest)

----DECLARE  	

CREATE TABLE #Result (
	PartyID		    INT
	,ReportType	    VARCHAR(8)
	,TurnOver		    MONEY
	,CustomerWinlost   MONEY
	,CommBA		    MONEY
	,CommRB		    MONEY
	,Betcount		    BIGINT
	,LicensingFee	    MONEY
	,TurnOverMYR	    MONEY
	,CustomerWinlostMYR MONEY
	,CommBAMYR	    MONEY
	,CommRBMYR	    MONEY
	,LicensingFeeMYR   MONEY
	,TurnOverUSD	    MONEY
	,CustomerWinlostUSD MONEY
	,CommBAUSD	    MONEY
	,CommRBUSD	    MONEY
	,LicensingFeeUSD   MONEY
	,TurnOverEUR	    MONEY
	,CustomerWinlostEUR MONEY
	,CommBAEUR	    MONEY
	,CommRBEUR	    MONEY
	,LicensingFeeEUR   MONEY
	)


CREATE TABLE #WinLoss (
	PartyID		INT
	,ProductID	INT
	,rptDate	 	DATETIME
	,TurnOver		MONEY
	,Winlost		MONEY
	,CommBA		MONEY
	,CommRB		MONEY
	,Betcount		BIGINT
	,TurnOverMYR	MONEY
	,WinlostMYR	MONEY
	,CommBAMYR	MONEY
	,CommRBMYR	MONEY
	,TurnOverUSD	MONEY
	,WinlostUSD	MONEY
	,CommBAUSD	MONEY
	,CommRBUSD	MONEY
	,TurnOverEUR	MONEY
	,WinlostEUR	MONEY
	,CommBAEUR	MONEY
	,CommRBEUR	MONEY
	)


CREATE TABLE #Temp (  
	PartyID 		INT,	
	ProductID		INT,
	Rptdate	 	DATETIME,    
	Currency		INT, 	
	TurnOver		MONEY,   	
	Winlost		MONEY,  
	CommBA		MONEY,   
	CommRB		MONEY,   
	Betcount		BIGINT
)


CREATE TABLE #Exchange (ExchangeDate SMALLDATETIME, ExchangeId INT, USD FLOAT, EUR FLOAT,MYR FLOAT)	

BEGIN	
	INSERT INTO #Exchange(ExchangeDate,ExchangeId,USD,EUR,MYR)
	SELECT DISTINCT ExchangeDate, ExchangeId,USD,EUR,MYR 
	FROM Lrf_f_GetExchangeDaily(@Fromdate, @ToDate)	
		
	IF CHARINDEX('BA',@ProductCode) <> 0
	BEGIN
		INSERT INTO #Temp  (PartyID , ProductID, Rptdate,Currency,TurnOver,Winlost,CommBA,CommRB,Betcount)
		SELECT 
			ag.PartyID
			,bt.ProductID
			,b.rptDate 
			,b.currencyID
			,SUM(b.turnover
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
					     WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				) TurnOver
			,SUM(b.winloss) Winloss
			,SUM(b.CommissionA) as CommBA
			,0 as CommRB
			,SUM(betcount)
			* CASE WHEN @drawfilter = 2 AND b.status = 111 THEN 0
					ELSE 1 END BetCount
		FROM 
			bodb_Licensee.dbo.rpt_Betting_BA b WITH ( NOLOCK ) 
			INNER JOIN #tmpParty ag ON ag.LicenseeID = b.SiteID AND ag.ProductID = 3
			INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype AND ag.ProductID = bt.ProductID
			LEFT JOIN dbo.League l (NOLOCK) ON b.leagueid = l.leagueid
		WHERE  
			b.rptDate BETWEEN ag.FromDate AND ag.ToDate 
			AND b.status NOT IN (-1,103)
			AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))  
			AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20)) 
		GROUP BY ag.PartyID, bt.ProductID, b.rptDate, status, currencyID
	END
	

	
	--exclude BA tickets
	IF CHARINDEX('BA',@ProductCode) = 0
	BEGIN
		INSERT INTO #Temp  (PartyID , ProductID, Rptdate,Currency,TurnOver,Winlost,CommBA,CommRB,Betcount)
		SELECT 
			ag.PartyID
			,bt.ProductID
			,b.rptDate  
			,b.currencyID
			,SUM(b.turnover
				*
				CASE WHEN b.bettype=33 AND b.status IN (114,115) THEN 0.5 ELSE 1 END
				*
				CASE WHEN @drawfilter IN (2,3) THEN
					CASE WHEN b.status = 111  THEN 0	
					     WHEN b.status IN (114,115) THEN 0.5
						 ELSE 1 END 
					ELSE 1 END
				) TurnOver
			,SUM(b.winloss) Winloss
			,0 as CommBA
			,SUM(CASE WHEN  b.bettype  BETWEEN 31 AND 33   THEN b.CommissionA ELSE 0 END ) AS CommRB
			,SUM(b.betcount)
			* CASE WHEN @drawfilter = 2 AND b.status = 111 THEN 0
				  ELSE 1 END BetCount
			
		FROM 
			bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK ) 
			INNER JOIN #tmpParty ag ON ag.LicenseeID = b.SiteID
			INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
			LEFT JOIN dbo.League l (NOLOCK) ON b.leagueid = l.leagueid
		WHERE  
			b.rptDate  BETWEEN ag.Fromdate AND ag.ToDate
			AND b.status NOT IN (-1, 103)
			AND (@Currency = 0 OR (@Currency <> 0 AND b.CurrencyID = @Currency))  
			AND (@excludeTest = 0 OR (@excludeTest = 1 AND b.CurrencyID <> 20)) 
			--AND b.customercategory NOT IN (27,28)			
		GROUP BY ag.PartyID, bt.ProductID, b.rptDate, b.status,b.currencyID
	END		
END

INSERT INTO #Result	
	SELECT   
		b.PartyID,
		CONVERT(VARCHAR(6),b.rptDate,112),  
		SUM(TurnOver)				AS Turnover,   
		SUM(Winlost)				AS CustomerWinlost,  
		SUM(CommBA)				AS CommBA,
		SUM(CommRB)				AS CommRB,
		SUM(Betcount)				AS Betcount,
		-SUM(Winlost * tp.Rate)		AS Winlost ,
	 --BaseRM  
		SUM(TurnOver * e.MYR)		 AS TurnoverMYR,   
		SUM(Winlost * e.MYR)		 AS CustomerWinlostMYR,  
		SUM(CommBA * e.MYR)			 AS CommBAMYR,
		SUM(CommRB * e.MYR)			 AS CommRBMYR,
		-SUM(Winlost * e.MYR * tp.Rate)AS LicensingFeeMYR,
	--BaseUSD  
		SUM(TurnOver * e.USD)		 AS TurnoverUSD,   
		SUM(Winlost * e.USD)		 AS CustomerWinlostUSD,  
		SUM(CommBA * e.USD)			 AS CommBAUSD,
		SUM(CommRB * e.USD)			 AS CommRBUSD,
		-SUM(Winlost * e.USD * tp.Rate)AS LicensingFeeUSD,
	--BaseEUR  
		SUM(TurnOver * e.EUR)		 AS TurnoverEUR,   
		SUM(Winlost * e.EUR)		 AS CustomerWinlostEUR,  
		SUM(CommBA * e.EUR)			 AS CommBAEUR,
		SUM(CommRB * e.EUR)			 AS CommRBEUR,
		-SUM(Winlost * e.EUR * tp.Rate)AS LicensingFeeEUR
	FROM #Temp b
	   LEFT JOIN #Exchange e  ON e.ExchangeDate = b.Rptdate AND e.exchangeid = b.currency
	   LEFT JOIN (SELECT DISTINCT PartyID, Fromdate, Todate, Rate FROM #tmpParty) tp ON b.PartyID = tp.PartyID AND b.Rptdate BETWEEN tp.Fromdate AND tp.Todate
	GROUP BY CONVERT(VARCHAR(6), b.rptDate, 112), b.PartyID
	ORDER BY CONVERT(VARCHAR(6), b.rptDate, 112), b.PartyID

UPDATE #Result
	SET LicensingFee = 0, LicensingFeeMYR = 0, LicensingFeeUSD = 0, LicensingFeeEUR = 0
	WHERE LicensingFeeMYR < 0

select CAST((ReportType + '01') AS date) AS [DateTime],
	SUM(TurnOver) AS TurnOver,   	
	SUM(CustomerWinlost) AS CustomerWinlost,  
	SUM(CommBA) AS AmtDueToBA,   
	SUM(CommRB) AS AmtDueToRB,
	SUM(Betcount)AS BetCount,
	CASE WHEN SUM(LicensingFee) < 0 THEN 0
		 ELSE SUM(LicensingFee)
		 END
		 AS LicensingFee,
	
	SUM(TurnOverMYR) AS TurnOverMYR,   	
	SUM(CustomerWinlostMYR) AS CustomerWinlostMYR,  
	SUM(CommBAMYR) AS AmtDueToBAMYR,   
	SUM(CommRBMYR) AS AmtDueToRBMYR,
	CASE WHEN SUM(LicensingFeeMYR) < 0 THEN 0
		 ELSE SUM(LicensingFeeMYR)
		 END
	AS LicensingFeeMYR,
	
	SUM(TurnOverUSD) AS TurnOverUSD,   	
	SUM(CustomerWinlostUSD) AS CustomerWinlostUSD,  
	SUM(CommBAUSD) AS AmtDueToBAUSD,   
	SUM(CommRBUSD) AS AmtDueToRBUSD,
	CASE WHEN SUM(LicensingFeeUSD) < 0 THEN 0
		 ELSE SUM(LicensingFeeUSD)
		 END
	AS LicensingFeeUSD,
	
	SUM(TurnOverEUR) AS TurnOverEUR,   	
	SUM(CustomerWinlostEUR) AS CustomerWinlostEUR,  
	SUM(CommBAEUR) AS AmtDueToBAEUR,   
	SUM(CommRBEUR) AS AmtDueToRBEUR,
	CASE WHEN SUM(LicensingFeeEUR) < 0 THEN 0
		 ELSE SUM(LicensingFeeEUR)
		 END
	AS LicensingFeeEUR
	   
FROM #Result
GROUP BY ReportType
ORDER BY ReportType ASC


DROP TABLE #Result
DROP TABLE #WinLoss
DROP TABLE #Exchange
DROP TABLE #Bettype
DROP TABLE #Temp
DROP TABLE #tmpParty
END

GO
GRANT EXECUTE ON [dbo].[LA_Rpt_LicPerformance_Summary] TO [bodbLicenseeNet] 
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicPerformance_Summary] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicPerformance_Summary] TO bodbAdminNet 
