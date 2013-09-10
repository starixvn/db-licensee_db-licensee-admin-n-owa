set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go



 ALTER   PROCEDURE [dbo].[OA_Rpt_VirtualSportWinloss]      
	@NormalLicensee VARCHAR(1000),  
	@Operator  VARCHAR(1000),  
	@FromDate  SMALLDATETIME,    
	@ToDate   SMALLDATETIME,    
	@Sporttype INT=0,
	@Bettype INT=0
	
AS      
  
/*  
 * Created by : [20120828@Henry]  
 * Task  : Get Virtual Sports Winloss 
 * DB   : DB052.bodb02  
 * Revisions :  
	- 20121105@Henry: using new table ResellerProductChargeByDateRange 	
	- 20121116@Jim: add @betlist input parameter and use @sporttype intead of @SportList
	- 20121129@Henry: add more columns
	- 20130624@Jim: Break down licensees under Boping 
	- 20130904@Jim: add more sporttype, bettype in the result
 
 * Param's Explanation:    
 *  - @NormalLicensee : List of normal licensee ID separated by ','  
 *  - @Operator   : List of operator ID separated by ','  
 *  - @FromDate   : From date   
 *  - @ToDate   : To date  
 *  - @Sporttype   : Sporttype 
 *  - @BetList:  Bettype offered for Virtual sports (0:All Bettype)
 */  
    
BEGIN      

SET NOCOUNT ON

DECLARE @tmpLicenseeReseller AS TABLE (ResellerID INT, LicenseeID INT)

CREATE TABLE #Data (winlostdate  DATETIME, Currency  INT,  ResellerID int, LicenseeID int,Sporttype int,bettype INT,turnover MONEY, MemberWinloss MONEY, Betcount INT)
CREATE TABLE #Result (ResellerID INT,LicenseeID int,sporttype int,bettype int ,winlostdate  varchar(6),turnover MONEY, MemberWinloss MONEY,GrossWinloss MONEY,DistributorRevenue MONEY, Betcount INT,OneworksIncome MONEY,AmtDueToInspired MONEY,DistributorsChargeRate MONEY,OneworksChargeRate MONEY, InspiredChargeRate MONEY)


--Get normal licensee list:
IF LTRIM(RTRIM(ISNULL(@NormalLicensee,''))) <> ''
BEGIN
	INSERT INTO @tmpLicenseeReseller (ResellerID,LicenseeID)
	SELECT lr.ResellerID,lr.LicenseeID
	FROM	
		bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)
		INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID = r.ResellerID
	WHERE
		r.ResellerID <> 3 
		AND lr.LicenseeID IN (SELECT RTRIM(LTRIM(VAL)) FROM strSplit(@NormalLicensee,','))	
END		

-- Operator
IF LTRIM(RTRIM(ISNULL(@Operator,''))) <> ''
BEGIN
	INSERT INTO @tmpLicenseeReseller (ResellerID, LicenseeID)   
	SELECT lr.ResellerID, lr.LicenseeID   
	FROM 
		bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)
		INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID = r.ResellerID
	WHERE
		r.ResellerID IN (SELECT RTRIM(LTRIM(VAL)) FROM strSplit(@Operator,','))		
END
  
--exclude BA & IBC & PIH...
IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr INNER JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid  WHERE l.IsDeposit=1 AND lr.ResellerID<>3)
BEGIN
	INSERT INTO #Data
	SELECT  b.rptDate,b.currencyID,lr.ResellerID,lr.licenseeid,l.sporttype, b.bettype,SUM(Turnover) as Turnover, SUM(Winloss) AS MemberWinloss,SUM(BetCount) AS betcount
	FROM @tmpLicenseeReseller lr
		INNER JOIN bodb_licensee.dbo.licensees lic WITH ( NOLOCK) ON lic.licenseeid=lr.licenseeid
		INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON lr.LicenseeID = b.siteID
		INNER JOIN bodb_Licensee.dbo.SystemLicensee sl (NOLOCK) ON lic.LicenseeID=sl.LicenseeID
		INNER JOIN bodb_Licensee.dbo.Systems s (NOLOCK) ON sl.SystemID=s.ID
		INNER JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
	WHERE
		b.rptDate BETWEEN @FromDate AND @ToDate
		AND lr.ResellerID<>3
		AND lic.isdeposit=1
		AND sl.IsActive = 1
		AND s.SystemName='OA'
		--AND @FromDate >= isnull(lic.AffectedDate,'1999-01-01')
		AND b.rptDate >= isnull(lic.AffectedDate,'1999-01-01')
		AND b.status NOT IN (-1,103)
		AND CurrencyID<>20
		AND bettype BETWEEN 1201 AND 1299
		AND (@Sporttype=0 OR ( @Sporttype<>0 AND l.Sporttype=@Sporttype)) 
		AND (@bettype=0 OR (b.bettype=@bettype AND @bettype<>0))
	GROUP BY b.rptDate,b.currencyID, lr.ResellerID, lr.licenseeid,l.sporttype, b.bettype
END

--FDL + PIH...
IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr inner JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid where l.IsDeposit=0)
BEGIN
	INSERT INTO #Data
	SELECT  b.rptDate,b.currencyID,lr.ResellerID,lr.licenseeid,l.sporttype, b.bettype,SUM(Turnover) as Turnover, SUM(Winloss) AS MemberWinloss,SUM(BetCount) AS betcount
	FROM @tmpLicenseeReseller lr
		INNER JOIN bodb_Licensee.dbo.labels lb WITH (NOLOCK) ON lr.LicenseeID=lb.LicenseeID
		INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID=lb.LabelID
		INNER JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
	WHERE
		b.rptDate BETWEEN @FromDate AND @ToDate
		AND b.status NOT IN (-1,103)
		AND lr.ResellerID<>3
		--AND @FromDate >= isnull(lb.AffectedDate,'1999-01-01')
		AND b.rptDate >= isnull(lb.AffectedDate,'1999-01-01')
		AND CurrencyID<>20
		AND bettype BETWEEN 1201 AND 1299
		AND b.customercategory NOT IN (27,28) 
		AND (@Sporttype=0 OR ( @Sporttype<>0 AND l.Sporttype=@Sporttype)) 
		AND (@bettype=0 OR (b.bettype=@bettype AND @bettype<>0))
	GROUP BY b.rptDate,b.currencyID, lr.ResellerID, lr.licenseeid,l.sporttype, b.bettype	
END

CREATE NONCLUSTERED INDEX IDX_Currency ON #Data(Currency)

SELECT * INTO #TempExchange 
FROM Lrf_f_GetExchangeDaily(@FromDate,@ToDate)
WHERE exchangeid IN (SELECT DISTINCT Currency FROM #Data)

INSERT INTO #Result(ResellerID,LicenseeID,sporttype,bettype,winlostdate,turnover, MemberWinloss,GrossWinloss,DistributorRevenue, Betcount,OneworksIncome,AmtDueToInspired,DistributorsChargeRate,OneworksChargeRate, InspiredChargeRate)
SELECT	
	r.ResellerID,
	d.LicenseeID,
	d.sporttype,
	d.bettype,
	Convert(varchar(6),d.winlostdate,112) as winlostdate,
	CAST(isnull(SUM(d.turnover * e.EUR),0) AS MONEY) AS Turnover,
	CAST(isnull(SUM(d.MemberWinloss * e.EUR),0) AS MONEY) AS MemberWinloss,
	CAST( -1 * isnull(SUM(d.MemberWinloss * e.EUR),0) AS money) AS GrossWinloss,
	CAST( -1 * isnull(SUM(d.MemberWinloss * e.EUR * isnull(DI.ChargeRate,0)),0)  AS money) AS DistributorRevenue,
	ISNULL(SUM(d.betcount), 0) AS BetCount,
	CAST(isnull(SUM(-1 * d.MemberWinloss * e.EUR * OW.ChargeRate),0)  AS money) AS OneworksIncome,
	CAST(isnull(SUM(-1 * d.MemberWinloss * e.EUR * INS.ChargeRate),0) AS money) AS AmtDueToInspired,
	isnull(DI.ChargeRate,0) as DistributorsChargeRate,
	isnull(OW.ChargeRate,0) as OneworksChargeRate ,
	isnull(INS.ChargeRate,0) as InspiredChargeRate
FROM #Data d
	INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = d.ResellerID
	INNER JOIN #TempExchange e ON d.winlostdate = e.ExchangeDate AND d.currency = e.ExchangeId
	LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange OW ON d.ResellerID = OW.ResellerID AND OW.PartyID = 1 AND OW.ProductID = 5 AND d.winlostdate BETWEEN OW.FromDate AND OW.ToDate
	LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange INS ON d.ResellerID = INS.ResellerID AND INS.PartyID = 2 AND INS.ProductID = 5 AND d.winlostdate BETWEEN INS.FromDate AND INS.ToDate	
	LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange DI ON d.ResellerID = DI.ResellerID AND DI.PartyID = 4 AND DI.ProductID = 5 AND d.winlostdate BETWEEN DI.FromDate AND DI.ToDate
GROUP BY
	r.ResellerID,d.LicenseeID,d.sporttype,d.bettype,Convert(varchar(6),d.winlostdate,112),DI.ChargeRate,OW.ChargeRate,INS.ChargeRate
	
--return the result
SELECT	
	r.ResellerID,r.ResellerName,
	CASE WHEN (r.ResellerType = 2 and re.resellerID NOT IN (1,7)) THEN '' ELSE l.LicenseeName END AS LicenseeName,
	re.winlostdate,
	r.ResellerType,
	re.sporttype,
	re.bettype,
	ISNULL(SUM(re.betcount), 0) AS BetCount,
	CAST(isnull(SUM(re.turnover),0) AS MONEY) AS Turnover,
	CAST(isnull(SUM(re.MemberWinloss),0) AS MONEY) AS MemberWinloss,
	CAST(isnull(SUM(re.GrossWinloss),0) AS MONEY) AS GrossWinloss,
	CAST(isnull(SUM(re.DistributorRevenue),0) AS MONEY) AS DistributorRevenue,
	CAST(isnull(SUM(re.OneworksIncome),0) AS MONEY) AS OneworksIncome,
	CAST(isnull(SUM(re.AmtDueToInspired),0) AS MONEY) AS AmtDueToInspired,
	DistributorsChargeRate,
	OneworksChargeRate, InspiredChargeRate
	
FROM #Result re
	INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = re.ResellerID
	LEFT JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON l.LicenseeID = re.LicenseeID
		
GROUP BY
	r.ResellerType,r.ResellerID,r.ResellerName,re.sporttype,re.bettype,re.winlostdate,CASE WHEN (r.ResellerType = 2 and re.resellerID NOT IN (1,7)) THEN '' ELSE l.LicenseeName END,DistributorsChargeRate, OneworksChargeRate, InspiredChargeRate	
ORDER BY
	r.ResellerID,r.ResellerType DESC,r.ResellerName, CASE WHEN (r.ResellerType = 2 and re.resellerID NOT IN (1,7)) THEN '' ELSE l.LicenseeName END,re.sporttype,re.bettype
			
DROP TABLE	#Data
DROP TABLE	#Result
DROP TABLE #TempExchange
			
END  


