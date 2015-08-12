 ALTER PROCEDURE [dbo].[OAS_Report_VirtualSportWinloss]      
	@NormalLicensee VARCHAR(1000),  
	@Operator  VARCHAR(1000),  
	@FromDate  SMALLDATETIME,    
	@ToDate   SMALLDATETIME,    
	@SportList	VARCHAR(1000)
	
AS      
  
/*  
 * Created by : [20120828@Henry]  
 * Task  : Get Virtual Sports Winloss 
 * DB   : DB052.bodb02  
 * Revisions :  
	- 20121105@Henry: using new table ResellerProductChargeByDateRange 
	- 20121129@Henry: add more columns
	- 20130613@Jim: change condition for Affectivedate
	- 20130724@Jim:  PIH and Starlit are no longer ONEWorks licensees since July 1st 2013
	- 20130905@Jim:  Boping is no longer ONEWorks licensee since August 1st 2013
 * Param's Explanation:    
 *  - @NormalLicensee : List of normal licensee ID separated by ','  
 *  - @Operator   : List of operator ID separated by ','  
 *  - @FromDate   : From date   
 *  - @ToDate   : To date  
 *  - @SportList   : List of Virtual Sports
 *  
 */  
    
BEGIN      

SET NOCOUNT ON

DECLARE @sporttype TABLE(sporttype INT)
DECLARE @tmpLicenseeReseller AS TABLE (ResellerID INT, LicenseeID INT,AffectedDate Datetime)

CREATE TABLE #Data (winlostdate  DATETIME, Currency  INT,  ResellerID int, LicenseeID int,turnover MONEY, MemberWinloss MONEY, Betcount INT)
CREATE TABLE #Result (ResellerID INT,LicenseeID int,turnover MONEY, MemberWinloss MONEY,GrossWinloss MONEY,DistributorRevenue MONEY, Betcount INT,OneworksIncome MONEY,AmtDueToInspired MONEY,DistributorsChargeRate MONEY,OneworksChargeRate MONEY, InspiredChargeRate MONEY)

IF (RTRIM(LTRIM(ISNULL(@SportList,'')))) = ''
BEGIN
	INSERT INTO @sporttype VALUES (180) --Virtual Soccer
END
ELSE
BEGIN
	INSERT INTO @sporttype (sporttype)
	SELECT RTRIM(LTRIM(VAL)) FROM strSplit(@SportList,',')
END

--Get normal licensee list:
IF LTRIM(RTRIM(ISNULL(@NormalLicensee,''))) <> ''
BEGIN
	INSERT INTO @tmpLicenseeReseller (ResellerID,LicenseeID,AffectedDate )
	SELECT lr.ResellerID,lr.LicenseeID,
				CASE WHEN @fromdate<=l.AffectedDate THEN l.AffectedDate ELSE @fromdate END AffectedDate
	FROM	
		bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)
		INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID = r.ResellerID
		INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON lr.LicenseeID=l.LicenseeID
	WHERE
		r.ResellerID <> 3 
		AND lr.LicenseeID IN (SELECT RTRIM(LTRIM(VAL)) FROM strSplit(@NormalLicensee,','))	
END		

-- Operator
IF LTRIM(RTRIM(ISNULL(@Operator,''))) <> ''
BEGIN
	INSERT INTO @tmpLicenseeReseller (ResellerID, LicenseeID,AffectedDate)   
	SELECT lr.ResellerID, lr.LicenseeID,
				CASE WHEN @fromdate<=l.AffectedDate THEN l.AffectedDate ELSE @fromdate END AffectedDate   
	FROM 
		bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)
		INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID = r.ResellerID
		INNER JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON lr.LicenseeID=l.LicenseeID
	WHERE
		r.ResellerID IN (SELECT RTRIM(LTRIM(VAL)) FROM strSplit(@Operator,','))		
END

DELETE FROM @tmpLicenseeReseller
WHERE (@FromDate BETWEEN '2013-07-01' AND '2013-07-31' AND ResellerID IN (3,8))
	  OR (@FromDate>='2013-08-01' AND ResellerID IN (3,7,8))
	
--exclude BA & IBC & PIH...
IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr INNER JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid  WHERE l.IsDeposit=1 AND lr.ResellerID<>3)
BEGIN
	INSERT INTO #Data
	SELECT  b.rptDate,b.currencyID,lr.ResellerID,lr.licenseeid,SUM(Turnover) as Turnover, SUM(b.Winloss) AS MemberWinloss,SUM(BetCount) AS betcount
	FROM @tmpLicenseeReseller lr
		INNER JOIN bodb_licensee.dbo.licensees lic WITH ( NOLOCK) ON lic.licenseeid=lr.licenseeid
		INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON lr.LicenseeID = b.siteID
		INNER JOIN bodb_Licensee.dbo.SystemLicensee sl (NOLOCK) ON lic.LicenseeID=sl.LicenseeID
		INNER JOIN bodb_Licensee.dbo.Systems s (NOLOCK) ON sl.SystemID=s.ID
		INNER JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
		INNER JOIN bodb_licensee.dbo.LicenseeProduct3rd p WITH (NOLOCK) ON lr.LicenseeID=p.LicenseeID AND p.ProductID=5
	WHERE
		b.rptDate BETWEEN lr.AffectedDate AND @ToDate
		AND b.rptDate >= isnull(p.EffectiveDate,DATEADD(DAY,1,@ToDate))
		AND lr.ResellerID<>3
		AND lic.isdeposit=1
		AND sl.IsActive = 1
		AND s.SystemName='OAS'
		AND b.status NOT IN (-1,103)
		AND CurrencyID<>20
		AND bettype BETWEEN 1201 AND 1299
		AND l.Sporttype IN (SELECT sporttype FROM @sporttype)
	GROUP BY b.rptDate,b.currencyID, lr.ResellerID, lr.licenseeid
END

--FDL + PIH...
IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr inner JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid where l.IsDeposit=0)
BEGIN
	INSERT INTO #Data
	SELECT  b.rptDate,b.currencyID,lr.ResellerID,lr.licenseeid,SUM(Turnover) as Turnover, SUM(b.Winloss) AS MemberWinloss,SUM(BetCount) AS betcount
	FROM @tmpLicenseeReseller lr
		INNER JOIN bodb_Licensee.dbo.labels lb WITH (NOLOCK) ON lr.LicenseeID=lb.LicenseeID
		INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID=lb.LabelID
		INNER JOIN league l WITH (NOLOCK) ON b.LeagueID = l.LeagueID
		INNER JOIN bodb_licensee.dbo.LicenseeProduct3rd p WITH (NOLOCK) ON lr.LicenseeID=p.LicenseeID AND p.ProductID=5
	WHERE
		b.rptDate BETWEEN lr.AffectedDate AND @ToDate
		AND b.rptDate >= isnull(p.EffectiveDate,DATEADD(DAY,1,@ToDate))
		AND b.status NOT IN (-1,103)
		AND lr.ResellerID<>3
		AND CurrencyID<>20
		AND bettype BETWEEN 1201 AND 1299
		AND b.customercategory NOT IN (27,28) 
		AND l.Sporttype IN (SELECT sporttype FROM @sporttype)
	GROUP BY b.rptDate,b.currencyID, lr.ResellerID, lr.licenseeid	
END

CREATE NONCLUSTERED INDEX IDX_Currency ON #Data(Currency)

SELECT * INTO #TempExchange 
FROM Lrf_f_GetExchangeDaily(@FromDate,@ToDate)
WHERE exchangeid IN (SELECT DISTINCT Currency FROM #Data)

INSERT INTO #Result(ResellerID,LicenseeID,turnover, MemberWinloss,GrossWinloss,DistributorRevenue, Betcount,OneworksIncome,AmtDueToInspired,DistributorsChargeRate,OneworksChargeRate, InspiredChargeRate)
SELECT	
	r.ResellerID,d.LicenseeID,
	CAST(isnull(SUM(d.turnover * e.EUR),0) AS MONEY) AS Turnover,
	CAST(isnull(SUM(d.MemberWinloss * e.EUR),0) AS MONEY) AS MemberWinloss,
	CAST(CASE WHEN isnull(SUM(d.MemberWinloss * e.EUR),0) > 0 THEN 0 ELSE -1 * isnull(SUM(d.MemberWinloss * e.EUR),0) END AS money) AS GrossWinloss,
	CAST(CASE WHEN isnull(SUM(d.MemberWinloss * e.EUR),0) > 0 THEN 0 ELSE -1 * isnull(SUM(d.MemberWinloss * e.EUR * isnull(DI.ChargeRate,0)),0) END AS money) AS DistributorRevenue,
	ISNULL(SUM(d.betcount), 0) AS BetCount,
	CAST(CASE WHEN isnull(SUM(-1 * d.MemberWinloss * e.EUR * OW.ChargeRate),0) < 0 THEN 0 ELSE isnull(SUM(-1 * d.MemberWinloss * e.EUR * OW.ChargeRate),0) END AS money) AS OneworksIncome,
	CAST(CASE WHEN isnull(SUM(-1 * d.MemberWinloss * e.EUR * INS.ChargeRate),0) < 0 THEN 0 ELSE isnull(SUM(-1 * d.MemberWinloss * e.EUR * INS.ChargeRate),0) END AS money) AS AmtDueToInspired,
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
	r.ResellerID,d.LicenseeID,DI.ChargeRate,OW.ChargeRate,INS.ChargeRate
	
--return the result
SELECT	
	r.ResellerID,r.ResellerName,
	CASE WHEN r.ResellerType = 2 THEN '' ELSE l.LicenseeName END AS LicenseeName,
	r.ResellerType,
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
	r.ResellerType,r.ResellerID,r.ResellerName, CASE WHEN r.ResellerType = 2 THEN '' ELSE l.LicenseeName END,DistributorsChargeRate, OneworksChargeRate, InspiredChargeRate	
ORDER BY
	r.ResellerType DESC,r.ResellerName, CASE WHEN r.ResellerType = 2 THEN '' ELSE l.LicenseeName END
			
DROP TABLE	#Data
DROP TABLE	#Result
DROP TABLE #TempExchange
			
END  
GO
GRANT EXECUTE ON [dbo].[OAS_Report_VirtualSportWinloss] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Report_VirtualSportWinloss] TO [vnteam]    