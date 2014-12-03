USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_LicWinloss]    Script Date: 01/12/2014 14:34:14 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_Rpt_LicWinloss] 
      @PartyIDs	VARCHAR(1000)	 = ''
	,@Currency	INT			 = 0
	,@FromDate	SMALLDATETIME
	,@ToDate		SMALLDATETIME
	,@ProductCodes VARCHAR(1000)
	,@SportType	INT			 = 0
	,@Bettype		INT			 = 0
	,@ReportBy	TINYINT		 = 1
	,@DrawFilter	SMALLINT		 = 1
	,@excludeTest	BIT			 = 0
AS
/*   Created:  Florent.Nguyen
	Date: 20140827
     Original: OA_Rpt_LicWinloss_Summary
	Task : LA Get Party Winloss
     DB: DB052.bodb02  
   
     Revisions:  
	   - 20141021@Florent: get data from credit's licensee
	   - 20141111@Florent: using new OAS_ChargeInfo structure and use unique formula
	Param's Explanation:  
	  + @PartyIDs	: a string of list PartyID, separate by ','
	  + @Currency	:  0- All Currencies
	  + @ReportBy: 1-Daily; 2-Monthly;  
	  + @DrawFilter: 'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
	  + @excludeTest: add/remove currency UUS
	  + @ProductCodes	: Products code :
				. SB _ SportBook
				. NG _ Number Game
				...
	  +@SportType	:
				0  : selected all sporttype 
	  +@Bettype : 
			0: selected all bettype
*/
BEGIN
SET NOCOUNT ON
	SET @ReportBy = 2 -- only allow monthly  

	----DECLARE  	
	CREATE TABLE #WinLoss (
		PartyID		   INT
		,ProductID	   INT
		,ReportType	   VARCHAR(6)
		,TurnOver		   MONEY
		,Winlost		   MONEY
		,LicenseeWL	   MONEY
		,WinlossRB	   MONEY
		,AmtDueToBA	   MONEY
		,AmtDueToRB	   MONEY
		,CommBA		   MONEY
		,CommRB		   MONEY
		,Company		   MONEY
		,Playercomm	   MONEY
		,Betcount		   BIGINT
		,TurnOverMYR	   MONEY
		,WinlostMYR	   MONEY
		,LicenseeWLMYR	   MONEY
		,WinlossRBMYR	   MONEY
		,AmtDueToBAMYR	   MONEY
		,AmtDueToRBMYR	   MONEY
		,CommBAMYR	   MONEY
		,CommRBMYR	   MONEY
		,CompanyMYR	   MONEY
		,PlayercommMYR	   MONEY
		,TurnOverUSD	   MONEY
		,WinlostUSD	   MONEY
		,LicenseeWLUSD	   MONEY
		,WinlossRBUSD	   MONEY
		,AmtDueToBAUSD	   MONEY
		,AmtDueToRBUSD	   MONEY
		,CommBAUSD	   MONEY
		,CommRBUSD	   MONEY
		,CompanyUSD	   MONEY
		,PlayercommUSD	   MONEY
		,TurnOverEUR	   MONEY
		,WinlostEUR	   MONEY
		,LicenseeWLEUR	   MONEY
		,WinlossRBEUR	   MONEY
		,AmtDueToBAEUR	   MONEY
		,AmtDueToRBEUR	   MONEY
		,CommBAEUR	   MONEY
		,CommRBEUR	   MONEY
		,CompanyEUR	   MONEY
		,PlayercommEUR	   MONEY
		)
     CREATE TABLE #Temp (
		PartyID	    INT
		,ProductID    INT
		,ReportType   INT
		,Currency	    INT
		,TurnOver	    MONEY
		,Winlost	    MONEY
		,LicenseeWL   MONEY
		,WinlossRB    MONEY
		,AmtDueToBA   MONEY
		,AmtDueToRB   MONEY
		,CommBA	    MONEY
		,CommRB	    MONEY
		,Company	    MONEY
		,Playercomm   MONEY
		,Betcount	    BIGINT
		)
    CREATE TABLE #Data (
		   rptDate	 Datetime
		  ,SiteID		 INT
		  ,PartyID	 INT
		  ,ProductID	 INT
		  ,Bettype	 INT
		  ,Status		 SMALLINT
		  ,Currency	 INT
		  ,TurnOver	 MONEY
		  ,Winloss	 MONEY
		  ,AWinloss	 MONEY
		  ,AComm		 MONEY
		  ,PComm		 MONEY
		  ,Betcount	 BIGINT
		  )
	CREATE TABLE #Bettype (Bettype INT,ProductID INT)

	CREATE TABLE #tmpParty (
		PartyID	    INT
		,LicenseeID   INT
		,isDeposit    INT
		,AffectedDate SMALLDATETIME
		,ProductID    INT 
		,Rate	    MONEY
		,Fromdate	    SMALLDATETIME
		,Todate	    SMALLDATETIME
		)

	INSERT INTO #Bettype
	SELECT Bettype,ProductID FROM bodb_licensee.dbo.LA_f_BettypeProductMapping(@Bettype,@ProductCodes)

	INSERT INTO #tmpParty
	SELECT PartyID,LicenseeID,isDeposit,AffectedDate,ProductID,DI_Rate,Fromdate,Todate
	FROM bodb_licensee.dbo.LA_f_ChargeInfo(@PartyIDs,@FromDate,@ToDate,@ProductCodes,'OA')
	
	IF ( EXISTS (
		  SELECT TOP 1 1
		  FROM #tmpParty
		  WHERE AffectedDate > Fromdate
		  ) AND @excludeTest = 1)
	BEGIN
		UPDATE #tmpParty
		SET Fromdate = AffectedDate
		WHERE AffectedDate > Fromdate
	END

	SELECT p.PartyID, p.LicenseeID, p.ProductID, bt.Bettype 
     INTO #PartyBettype
     FROM #tmpParty p 
	   INNER JOIN #Bettype bt ON p.ProductID = bt.ProductID
		
	CREATE TABLE #Exchange (
		ExchangeDate  INT
		,ExchangeId   INT
		,USD		    FLOAT
		,EUR		    FLOAT
		,MYR		    FLOAT
		,PRIMARY KEY (
			ExchangeDate
			,ExchangeId
			)
		)

	INSERT INTO #Exchange (ExchangeDate, ExchangeId, USD, EUR, MYR)
	SELECT DISTINCT CONVERT(VARCHAR(6), ExchangeDate, 112)
		,ExchangeId, USD, EUR, MYR
	FROM Lrf_f_GetExchangeDaily(@FromDate, @ToDate)

	IF CHARINDEX('BA', @ProductCodes) <> 0
	BEGIN
		INSERT INTO #Temp (PartyID, ProductID, ReportType, Currency, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA
			, AmtDueToRB, CommBA, CommRB, Company, Playercomm, Betcount)
		SELECT p.PartyID
			,p.ProductID
			,CONVERT(VARCHAR(6), b.rptDate, 112) ReportType
			,b.currencyID
			,SUM(b.turnover * CASE 
					WHEN @drawfilter IN (2, 3)
						THEN CASE 
								WHEN b.STATUS = 111
									THEN 0
								WHEN b.STATUS IN (114, 115)
									THEN 0.5
								ELSE 1
								END
					ELSE 1
					END) TurnOver
			,SUM(b.winloss) Winloss
			,0 AS LicenseeWL
			,0 AS WinlossRB
			--,- SUM(b.winloss + b.winlossA + b.CommissionA) AS AmountDueToBA
			,- SUM((b.winloss * p.Rate )+ b.CommissionA) AS AmountDueToBA
			,0 AS AmountDueToRB
			,SUM(b.CommissionA) AS CommBA
			,0 AS CommRB
			,0 AS Company
			,SUM(commissionP) AS Playercomm
			,SUM(betcount) * CASE 
				WHEN @drawfilter = 2
					AND b.STATUS = 111
					THEN 0
				ELSE 1
				END BetCount
		FROM bodb_Licensee.dbo.rpt_Betting_BA b WITH (NOLOCK)
		INNER JOIN #tmpParty p ON b.SiteID = p.LicenseeID and p.ProductID = 3
		INNER JOIN #Bettype bt ON b.Bettype = bt.Bettype
		LEFT JOIN dbo.League l(NOLOCK) ON b.leagueid = l.leagueid
		WHERE b.rptDate BETWEEN p.Fromdate AND p.Todate
			AND b.STATUS NOT IN (- 1, 103)
			AND (
				@SportType = 0
				OR (
					@SportType <> 0
					AND l.sporttype = @SportType
					)
				)
			AND (
				@Currency = 0
				OR (
					@Currency <> 0
					AND b.CurrencyID = @Currency
					)
				)
			AND (
				@excludeTest = 0
				OR (
					@excludeTest = 1
					AND b.CurrencyID <> 20
					)
				)
		GROUP BY p.PartyID
			 ,p.ProductID
			,CONVERT(VARCHAR(6), b.rptDate, 112)
			,STATUS
			,currencyID
	END
	
	 --Filter again
	IF (REPLACE(@ProductCodes, 'BA', '') != '' AND REPLACE(@ProductCodes, 'BA', '') != ',')
	BEGIN
		DELETE #PartyBettype WHERE ProductID = 3 --remove BA product
		--get data
	    INSERT INTO #Data
	    SELECT  b.rptDate	
			 ,b.SiteID
			 ,p.PartyID
			 ,p.ProductID	
			 ,b.Bettype
			 ,b.Status		
			 ,b.currencyID
			 ,SUM(b.turnover)
			 ,SUM(b.winloss)
			 ,SUM(b.winlossA)
			 ,SUM(b.CommissionA)
			 ,SUM(b.commissionP)
			 ,SUM(b.betcount)
		  FROM bodb_Licensee.dbo.rpt_Betting b WITH (NOLOCK)
		  INNER JOIN #PartyBettype p ON b.Bettype = p.Bettype AND b.SiteID = p.LicenseeID
		  LEFT JOIN dbo.League l(NOLOCK) ON b.leagueid = l.leagueid
		  WHERE b.rptDate BETWEEN @FromDate AND @ToDate
			 AND b.STATUS NOT IN (- 1, 103)
			 AND (
				@SportType = 0
				OR (
					   @SportType <> 0
					   AND b.bettype NOT BETWEEN 31 AND 120
					   AND l.sporttype = @SportType
					   )
				)
			 AND (
				@Currency = 0
				OR (
					   @Currency <> 0
					   AND b.CurrencyID = @Currency
					   )
				)
			 AND (
				@excludeTest = 0
				OR (
					   @excludeTest = 1
					   AND b.CurrencyID <> 20
					   )
				)
			 AND b.customercategory NOT IN (27,28)
		GROUP BY  b.rptDate	
			 ,b.SiteID 
			 ,PartyID	 
			 ,p.ProductID	 
			 ,b.Bettype	 
			 ,Status		 
			 ,b.CurrencyID
	    CREATE INDEX CIX_Data ON #data (rptDate,ProductID,SiteID,Bettype,Currency)

		INSERT INTO #Temp (PartyID, ProductID, ReportType, Currency, TurnOver, Winlost, LicenseeWL, WinlossRB, AmtDueToBA
			, AmtDueToRB, CommBA, CommRB, Company, Playercomm, Betcount)
		SELECT p.PartyID
			,p.ProductID
			,CONVERT(VARCHAR(6), b.rptDate, 112) ReportType			
			,b.Currency
			,SUM(b.turnover * CASE 
					WHEN b.bettype = 33
						AND b.STATUS IN (114, 115)
						THEN 0.5
					ELSE 1
					END * CASE 
					WHEN @drawfilter IN (2, 3)
						THEN CASE 
								WHEN b.STATUS = 111
									THEN 0
								WHEN b.STATUS IN (114, 115)
									THEN 0.5
								ELSE 1
								END
					ELSE 1
					END) TurnOver
			,SUM(b.Winloss) Winloss
			,- SUM(CASE 
					WHEN (b.Bettype NOT BETWEEN 31 AND 33)
						THEN b.Winloss
					ELSE 0
					END) AS LicenseeWL
			,SUM(CASE 
					WHEN b.bettype BETWEEN 31 AND 33
						THEN b.Winloss
					ELSE 0
					END) AS WinlossRB
			,0 AS AmountDueToBA
			,- SUM(CASE 
					WHEN b.bettype BETWEEN 31 AND 33
						THEN (b.Winloss + b.AWinloss + b.AComm)						
					ELSE 0
					END) AS AmountDueToRB
			,0 AS CommBA
			,SUM(CASE 
					WHEN b.bettype BETWEEN 31 AND 33
						THEN b.AComm
					ELSE 0
					END) AS CommRB
			,- SUM(CASE 
					WHEN b.bettype NOT BETWEEN 31 AND 33						
						THEN ((b.Winloss * p.Rate))
					ELSE 0
					END) AS Company
			,SUM(b.PComm) AS Playercomm
			,SUM(b.betcount) * CASE 
				WHEN @drawfilter = 2
					AND b.STATUS = 111
					THEN 0
				ELSE 1
				END BetCount
		FROM #Data b WITH (NOLOCK)
		INNER JOIN #tmpParty p ON p.LicenseeID = b.SiteID AND p.ProductID NOT IN (3) AND b.ProductID = p.ProductID				
		WHERE b.rptDate BETWEEN p.Fromdate AND p.Todate			
		GROUP BY p.PartyID
			 ,p.ProductID
			,CONVERT(VARCHAR(6), b.rptDate, 112)			
			,b.STATUS
			,b.Currency
	END

	INSERT INTO #WinLoss
	SELECT b.PartyID
		,b.ProductID
		,ReportType
		,TurnOver
		,Winlost
		,LicenseeWL
		,WinlossRB
		,AmtDueToBA
		,AmtDueToRB
		,CommBA
		,CommRB
		,Company
		,Playercomm
		,Betcount
		,TurnOver * e.MYR	  AS TurnOverMYR
		,Winlost * e.MYR 	  AS WinlostMYR
		,LicenseeWL * e.MYR	  AS LicenseeWLMYR
		,WinlossRB * e.MYR	  AS WinlossRBMYR
		,AmtDueToBA * e.MYR	  AS AmtDueToBAMYR
		,AmtDueToRB * e.MYR	  AS AmtDueToRBMYR
		,CommBA * e.MYR	  AS CommBAMYR
		,CommRB * e.MYR	  AS CommRBMYR
		,Company * e.MYR	  AS CompanyMYR
		,Playercomm * e.MYR	  AS PlayercommMYR
		,TurnOver * e.USD	  AS TurnOverUSD
		,Winlost * e.USD	  AS WinlostUSD
		,LicenseeWL * e.USD	  AS LicenseeWLUSD
		,WinlossRB * e.USD	  AS WinlossRBUSD
		,AmtDueToBA * e.USD	  AS AmtDueToBAUSD
		,AmtDueToRB * e.USD	  AS AmtDueToRBUSD
		,CommBA * e.USD	  AS CommBAUSD
		,CommRB * e.USD	  AS CommRBUSD
		,Company * e.USD	  AS CompanyUSD
		,Playercomm * e.USD	  AS PlayercommUSD
		,TurnOver * e.EUR	  AS TurnOverEUR
		,Winlost * e.EUR	  AS WinlostEUR
		,LicenseeWL * e.EUR	  AS LicenseeWLEUR
		,WinlossRB * e.EUR	  AS WinlossRBEUR
		,AmtDueToBA * e.EUR	  AS AmtDueToBAEUR
		,AmtDueToRB * e.EUR	  AS AmtDueToRBEUR
		,CommBA * e.EUR	  AS CommBAEUR
		,CommRB * e.EUR	  AS CommRBEUR
		,Company * e.EUR	  AS CompanyEUR
		,Playercomm * e.EUR	  AS PlayercommEUR
	FROM #Temp b
	LEFT JOIN #Exchange e ON e.ExchangeDate = ReportType
		AND e.exchangeid = b.currency
END

SELECT w.PartyID	
	,CASE p.PartyName
	   WHEN '18bb' THEN 'PIH'
	   WHEN 'IBC'	THEN 'FDL'
	   ELSE p.PartyName
	 END AS PartyName
	,w.ReportType
	,SUM(TurnOver) AS Turnover
	,SUM(Winlost) AS Winlost
	,SUM(LicenseeWL) AS LicenseeWL
	,SUM(WinlossRB) AS WinlossRB
	,SUM(CommBA) AS CommBA
	,SUM(CommRB) AS CommRB
	,SUM(AmtDuetoBA) AS AmtDuetoBA
	,SUM(AmtDuetoRB) AS AmtDuetoRB
	,SUM(Company) AS Company
	,SUM(Betcount) AS Betcount
	,SUM(Playercomm) AS Playercomm
	,
	--BaseRM  
	SUM(TurnOverMYR) AS TurnoverMYR
	,SUM(WinlostMYR) AS WinlostMYR
	,SUM(LicenseeWLMYR) AS LicenseeWLMYR
	,SUM(WinlossRBMYR) AS WinlossRBMYR
	,SUM(CommBAMYR) AS CommBAMYR
	,SUM(CommRBMYR) AS CommRBMYR
	,SUM(AmtDuetoBAMYR) AS AmtDuetoBAMYR
	,SUM(AmtDuetoRBMYR) AS AmtDuetoRBMYR
	,SUM(CompanyMYR) AS CompanyMYR
	,SUM(PlayercommMYR) AS PlayercommMYR
	,
	--BaseUSD  
	SUM(TurnOverUSD) AS TurnoverUSD
	,SUM(WinlostUSD) AS WinlostUSD
	,SUM(LicenseeWLUSD) AS LicenseeWLUSD
	,SUM(WinlossRBUSD) AS WinlossRBUSD
	,SUM(CommBAUSD) AS CommBAUSD
	,SUM(CommRBUSD) AS CommRBUSD
	,SUM(AmtDuetoBAUSD) AS AmtDuetoBAUSD
	,SUM(AmtDuetoRBUSD) AS AmtDuetoRBUSD
	,SUM(CompanyUSD) AS CompanyUSD
	,SUM(PlayercommUSD) AS PlayercommUSD
	,
	--BaseEUR  
	SUM(TurnOverEUR) AS TurnoverEUR
	,SUM(WinlostEUR) AS WinlostEUR
	,SUM(LicenseeWLEUR) AS LicenseeWLEUR
	,SUM(WinlossRBEUR) AS WinlossRBEUR
	,SUM(CommBAEUR) AS CommBAEUR
	,SUM(CommRBEUR) AS CommRBEUR
	,SUM(AmtDuetoBAEUR) AS AmtDuetoBAEUR
	,SUM(AmtDuetoRBEUR) AS AmtDuetoRBEUR
	,SUM(CompanyEUR) AS CompanyEUR
	,SUM(PlayercommEUR) AS PlayercommEUR
FROM #WinLoss w
INNER JOIN bodb_Licensee.dbo.OAS_Party p (NOLOCK) ON p.PartyID = w.PartyID
GROUP BY  w.PartyID
	    ,p.PartyName
	    ,w.ReportType	
ORDER BY ReportType ASC,p.PartyName

DROP TABLE #WinLoss
DROP TABLE #Exchange
DROP TABLE #Temp
DROP TABLE #Bettype
DROP TABLE #tmpParty
DROP TABLE #Data
DROP TABLE #PartyBettype

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_LicWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_LicWinloss] TO bodbAdminNet 
