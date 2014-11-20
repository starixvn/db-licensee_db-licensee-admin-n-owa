USE [bodb02]
GO
/****** Object:  StoredProcedure [dbo].[LA_Rpt_VirtualSportWinloss]    Script Date: 08/10/2014 11:27:16 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/****** Object:  Stored Procedure dbo.OA_Rpt_VirtualSportWinloss    Script Date: 9/10/2013 2:32:36 PM ******/
ALTER PROCEDURE [dbo].[LA_Rpt_VirtualSportWinloss]      	
	@PartyIDs		VARCHAR(5500),  
	@FromDate		SMALLDATETIME,    
	@ToDate		SMALLDATETIME,    
	@SportType	INT=0,
	@BetType		INT=0,
	@drawfilter	SMALLINT= 1,
	@excludeTest	BIT= 0	
AS      
  
/*  
 * Created by : [20140911@Florent]  
 * Task  : Get Virtual Sports Winloss 
 * DB   : DB052.bodb02  
 * Base on : [OA_Rpt_VirtualSportWinloss]
 * Revisions :  
 
 * Param's Explanation:    
 *  - @FromDate   : From date   
 *  - @ToDate   : To date  
 *  - @Sporttype   : Sporttype 
 *  - @BetList:  Bettype offered for Virtual sports (0:All Bettype)
 *  - @drawfilter:  'No Draw' filter is supportted (1:Normal 2:No Draw 3:No Draw for Turnover only)
 *  - @excludeTest:  0 Get all currency in date range from - to
				 1 get only real currency from licensee_launch_date/from_date to to_date
 */  
    
BEGIN      

SET NOCOUNT ON

CREATE TABLE #Data (winlostdate  DATETIME, Currency  INT,PartyID int,Sporttype int,bettype INT,turnover MONEY,
 MemberWinloss MONEY, Betcount INT)
CREATE TABLE #Result (PartyID int, TurnOver MONEY,SportType INT, BetType INT, MemberWinloss MONEY, GrossWinloss MONEY, DistributorRevenue MONEY,
 Betcount INT, OneworksIncome MONEY, AmtDueToInspired MONEY, DistributorsChargeRate MONEY, OneworksChargeRate MONEY,
  InspiredChargeRate MONEY,winlostdate  DATETIME, Currency INT)

DECLARE @tmpParty TABLE (
		PartyID INT
		,LicenseeID INT
		,ParentID INT
		,ParentName Varchar(100)
		,AffectedDate DATETIME
		,Fromdate DATETIME
		,Todate DATETIME
		)
/*
    CREATE table #PartyList
    (
	   PartyID INT,
	   PartyName VARCHAR(100),
	   ParentID INT
    )
    INSERT INTO #PartyList
    EXEC bodb_licensee.dbo.LA_PartyListSel
*/
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

 
-- normal Licensee
IF EXISTS(SELECT 1 FROM @tmpParty tp 
				    INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (nolock) ON tp.PartyID = pd.PartyID  
				    WHERE pd.IsDeposit=1)
BEGIN
	INSERT INTO #Data
	SELECT  b.rptDate,b.currencyID,lr.PartyID,l.sporttype, 
		   b.bettype,SUM(Turnover) as Turnover, 
		   SUM(Winloss) AS MemberWinloss,SUM(BetCount) AS betcount
	FROM bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) 
		INNER JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
		INNER JOIN @tmpParty lr ON lr.LicenseeID = b.siteID
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd (NOLOCK) ON lr.PartyID = pd.PartyID
	WHERE
		pd.IsDeposit = 1 AND
		b.rptDate BETWEEN lr.Fromdate AND lr.Todate
		AND b.status NOT IN (-1,103)
		AND (@excludeTest = 0 OR (@excludeTest = 1 AND CurrencyID <> 20))
		AND bettype BETWEEN 1201 AND 1299
		AND (@Sporttype = 0 OR ( @Sporttype<>0 AND l.Sporttype=@Sporttype)) 
		AND (@bettype = 0 OR (b.bettype=@bettype AND @bettype<>0))
	GROUP BY b.rptDate,b.currencyID,lr.PartyID,l.sporttype, b.bettype
END

--FDL + PIH...
IF EXISTS(SELECT 1 FROM @tmpParty tp 
			    INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH (nolock) ON tp.PartyID = pd.PartyID  
		 WHERE pd.IsDeposit=0)
BEGIN
	INSERT INTO #Data
	SELECT  b.rptDate,b.currencyID,lr.PartyID,l.sporttype, b.bettype,SUM(Turnover) as Turnover, SUM(Winloss) AS MemberWinloss,SUM(BetCount) AS betcount
	FROM @tmpParty lr
		INNER JOIN bodb_Licensee.dbo.labels lb WITH (NOLOCK) ON lr.LicenseeID=lb.LicenseeID
		INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID=lb.LabelID
		INNER JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
		INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd (NOLOCK) ON lr.PartyID = pd.PartyID
	WHERE
		pd.IsDeposit = 0 AND
		b.rptDate BETWEEN lr.Fromdate AND lr.Todate
		AND b.status NOT IN (-1,103)
		AND (@excludeTest = 0 OR (@excludeTest = 1 AND CurrencyID <> 20))
		AND bettype BETWEEN 1201 AND 1299
		AND b.customercategory NOT IN (27,28) 
		AND (@Sporttype=0 OR ( @Sporttype<>0 AND l.Sporttype=@Sporttype)) 
		AND (@bettype=0 OR (b.bettype=@bettype AND @bettype<>0))
	GROUP BY b.rptDate,b.currencyID, lr.PartyID,l.sporttype, b.bettype	
END

CREATE NONCLUSTERED INDEX IDX_Currency ON #Data(Currency)

SELECT * INTO #TempExchange 
FROM Lrf_f_GetExchangeDaily(@FromDate,@ToDate)
WHERE exchangeid IN (SELECT DISTINCT Currency FROM #Data)

INSERT INTO #Result (PartyID,TurnOver,SportType,BetType,MemberWinloss,GrossWinloss,DistributorRevenue,Betcount,
OneworksIncome,AmtDueToInspired,DistributorsChargeRate,OneworksChargeRate,InspiredChargeRate,winlostdate,Currency)
SELECT	
		d.PartyID,
		CAST(isnull(SUM(d.TurnOver ),0) AS MONEY) AS TurnOver,		
		d.Sporttype,d.bettype,
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
		INNER JOIN bodb_licensee.dbo.OAS_ChargeInfo DI ON
				 d.PartyID = DI.FromParty 
				AND DI.ProductID = 5 
				AND d.winlostdate BETWEEN DI.FromDate AND DI.ToDate 
				AND DI.ChargeType = 1 
		LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo OW ON DI.ParentChargeID = OW.ChargeID
		LEFT JOIN bodb_licensee.dbo.OAS_ChargeInfo INS ON OW.ParentChargeID = INS.ChargeID
	GROUP BY
		d.PartyID, DI.Rate, OW.Rate, INS.Rate, OW.ChargeType,winlostdate,Currency,d.Sporttype,d.bettype

--return the result
SELECT	
	CASE WHEN p.PartyName='IBC' THEN 'FDL'
		     WHEN p.PartyName='18bb' THEN 'PIH'
		     ELSE p.PartyName 
		END AS PartyName,
	CONVERT(Varchar(6),re.winlostdate,112) AS winlostdate,	
	re.sporttype,
	re.bettype,
	ISNULL(SUM(re.betcount), 0) AS BetCount,
	CAST(isnull(SUM(re.turnover * ex.EUR),0) AS MONEY) AS Turnover,
	--CAST(isnull(SUM(re.MemberWinloss * ex.EUR),0) AS MONEY) AS MemberWinloss,
	CAST(isnull(SUM(re.GrossWinloss * ex.EUR),0) AS MONEY) AS GrossWinloss,
	--CAST(isnull(SUM(re.DistributorRevenue * ex.EUR),0) AS MONEY) AS DistributorRevenue,
	CAST(isnull(SUM(re.OneworksIncome * ex.EUR),0) AS MONEY) AS OneworksIncome
	--CAST(isnull(SUM(re.AmtDueToInspired * ex.EUR),0) AS MONEY) AS AmtDueToInspired
FROM #Result re
    INNER JOIN #TempExchange ex ON re.winlostdate = ex.exchangedate and re.Currency = ex.ExchangeId
    LEFT JOIN @tmpParty tp ON re.PartyID = tp.PartyID
    LEFT JOIN bodb_licensee.dbo.OAS_Party p on tp.PartyID = p.PartyID    
GROUP BY
	re.sporttype,re.bettype,
	CONVERT(Varchar(6),re.winlostdate,112),
	CASE WHEN p.PartyName='IBC' THEN 'FDL'
		     WHEN p.PartyName='18bb' THEN 'PIH'
		     ELSE p.PartyName 
		END
ORDER BY
     CONVERT(Varchar(6),re.winlostdate,112) ASC,
	CASE WHEN p.PartyName='IBC' THEN 'FDL'
		     WHEN p.PartyName='18bb' THEN 'PIH'
		     ELSE p.PartyName 
		END,re.sporttype,re.bettype
	
DROP TABLE  #Data
DROP TABLE  #Result
DROP TABLE  #TempExchange
END  

GO
GRANT VIEW DEFINITION ON [dbo].[LA_Rpt_VirtualSportWinloss] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_Rpt_VirtualSportWinloss] TO bodbAdminNet 