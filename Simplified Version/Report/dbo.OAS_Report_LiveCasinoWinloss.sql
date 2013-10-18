set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go

 ALTER PROCEDURE [dbo].[OAS_Report_LiveCasinoWinloss]      
	@NormalLicensee VARCHAR(1000),  
	@Operator  VARCHAR(1000), 
	@GameType 	INT=0,	
	@FromDate  SMALLDATETIME,    
	@ToDate   SMALLDATETIME
	
AS      
  
/*  
 * Created by : [20121015@Henry]  
 * Task  : Get Live Casino Winloss 
 * DB   : DB052.bodb02  
 * Revisions :  
	- 20121105@Henry: using new table ResellerProductChargeByDateRange 	
	- 20130219@Jim: add more filter for Licensee From table LicenseeProduct3rd
	- 20130405@Jim: only Baccarat data included in the report
	- 20130612@Jim: change condition for AffectedDate
	- 20130724@Jim:  PIH and Starlit are no longer ONEWorks licensees since July 1st 2013
	- 20130905@Jim: Boping is no longer ONEWorks licensee since August 1st 2013
	- 20131017@Victor: OW charge licensees directly from Oct 01 2013
	- 20131018@Victor: Fix zero OneWorks revenue issue
 * Param's Explanation:    
 *  - @NormalLicensee : List of normal licensee ID separated by ','  
 *  - @Operator   : List of operator ID separated by ','  
 *  - @FromDate   : From date   
 *  - @ToDate   : To date  
 
 *  
 */  
    
BEGIN      

SET NOCOUNT ON

DECLARE @tmpLicenseeReseller AS TABLE (ResellerID INT, LicenseeID INT,AffectedDate Datetime)

CREATE TABLE #Data (winlostdate  DATETIME, Currency  INT,  ResellerID int, LicenseeID int,turnover MONEY, MemberWinloss MONEY, Betcount INT)
CREATE TABLE #Result (ResellerID INT,LicenseeID int,turnover MONEY, MemberWinloss MONEY,GrossWinloss MONEY, DistributorRevenue MONEY, Betcount INT,StarExpressRevenue MONEY, OneworksRevenue MONEY,DistributorsChargeRate MONEY, StarExpressChargeRate MONEY,OneworksChargeRate MONEY)

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
	SELECT lr.ResellerID, lr.LicenseeID ,
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

-- Remove reseller that are diabled for Live Casino
DELETE FROM @tmpLicenseeReseller
WHERE ResellerID IN(SELECT DISTINCT ObjectID 
					FROM bodb_licensee.dbo.LicenseeEventLog (NOLOCK) 
					WHERE SystemID = 4 -- OAS
						AND ProductID = 4 -- LC 
						AND ActionID = 5 
						AND (@FromDate >= FromDate AND (ToDate IS NULL OR @ToDate <= ToDate)))

--exclude BA & IBC & PIH...
IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr INNER JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid  WHERE l.IsDeposit=1 AND lr.ResellerID<>3)
BEGIN
	INSERT INTO #Data
	SELECT  b.rptDate,b.currencyID,lr.ResellerID,lr.licenseeid,SUM(Turnover) as Turnover, SUM(b.Winloss) AS MemberWinloss, SUM(BetCount) AS betcount
	FROM @tmpLicenseeReseller lr
		INNER JOIN bodb_licensee.dbo.licensees lic WITH ( NOLOCK) ON lic.licenseeid=lr.licenseeid
		INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON lr.LicenseeID = b.siteID
		INNER JOIN bodb_Licensee.dbo.SystemLicensee sl (NOLOCK) ON lic.LicenseeID=sl.LicenseeID
		INNER JOIN bodb_Licensee.dbo.Systems s (NOLOCK) ON sl.SystemID=s.ID
		INNER JOIN bodb_licensee.dbo.LicenseeProduct3rd p WITH (NOLOCK) ON lic.LicenseeID=p.LicenseeID AND p.ProductID=4
	WHERE
		b.rptDate BETWEEN lr.AffectedDate AND @ToDate
		AND b.rptDate >= isnull(p.EffectiveDate,DATEADD(DAY,1,@ToDate))
		AND lr.ResellerID<>3
		AND lic.isdeposit=1
		AND sl.IsActive = 1
		AND s.SystemName='OA'
		AND b.status NOT IN (-1,103)
		AND CurrencyID<>20
		AND bettype=1101
		--AND bettype BETWEEN 1101 AND 1199
	GROUP BY b.rptDate,b.currencyID, lr.ResellerID, lr.licenseeid
END

--FDL + PIH...
IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr inner JOIN bodb_licensee.dbo.licensees l WITH (nolock) ON lr.licenseeid=l.licenseeid where l.IsDeposit=0)
BEGIN
	INSERT INTO #Data
	SELECT  b.rptDate,b.currencyID,lr.ResellerID,lr.licenseeid,SUM(Turnover) as Turnover, SUM(b.Winloss) AS MemberWinloss, SUM(BetCount) AS betcount
	FROM @tmpLicenseeReseller lr
		INNER JOIN bodb_Licensee.dbo.labels lb WITH (NOLOCK) ON lr.LicenseeID=lb.LicenseeID
		INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID=lb.LabelID
		INNER JOIN bodb_licensee.dbo.LicenseeProduct3rd p WITH (NOLOCK) ON lr.LicenseeID=p.LicenseeID AND p.ProductID=4
	WHERE
		b.rptDate BETWEEN lr.AffectedDate AND @ToDate
		AND b.rptDate > =isnull(p.EffectiveDate,DATEADD(DAY,1,@ToDate))
		AND b.status NOT IN (-1,103)
		AND lr.ResellerID<>3
		AND CurrencyID<>20
		AND b.bettype=1101
		--AND bettype BETWEEN 1101 AND 1199
		AND b.customercategory NOT IN (27,28) 
	GROUP BY b.rptDate,b.currencyID, lr.ResellerID, lr.licenseeid	
END

CREATE NONCLUSTERED INDEX IDX_Currency ON #Data(Currency,winlostdate)


SELECT * INTO #TempExchange 
FROM Lrf_f_GetExchangeDaily(@FromDate,@ToDate)
WHERE exchangeid IN (SELECT DISTINCT Currency FROM #Data)

-- Check Star Express party
DECLARE @PartyTerminated BIT
SET @PartyTerminated = 0
IF EXISTS (SELECT TOP 1 1 	FROM bodb_licensee.dbo.LicenseeEventLog (NOLOCK) WHERE SystemID = 4 AND ActionID = 3 AND ObjectID = 5 
													AND (@FromDate >= FromDate AND (ToDate IS NULL OR @ToDate <= ToDate)))
	SET @PartyTerminated = 1

INSERT INTO #Result(ResellerID,LicenseeID,turnover, MemberWinloss,GrossWinloss, DistributorRevenue, Betcount,StarExpressRevenue,OneworksRevenue,DistributorsChargeRate, StarExpressChargeRate,OneworksChargeRate)
SELECT	
	r.ResellerID,d.LicenseeID,
	CAST(isnull(SUM(d.turnover * e.EUR),0) AS MONEY) AS Turnover,
	CAST(isnull(SUM(d.MemberWinloss * e.EUR),0) AS MONEY) AS MemberWinloss,
	CAST(CASE WHEN isnull(SUM(d.MemberWinloss * e.EUR),0) > 0 THEN 0 ELSE -1 * isnull(SUM(d.MemberWinloss * e.EUR),0) END AS money) AS GrossWinloss,
	CAST(CASE WHEN isnull(SUM(d.MemberWinloss * e.EUR),0) > 0 THEN 0 ELSE -1 * isnull(SUM(d.MemberWinloss * e.EUR * isnull(DI.ChargeRate,0)),0) END AS money) AS DistributorRevenue,
	ISNULL(SUM(d.betcount), 0) AS BetCount,
	CAST(CASE WHEN isnull(SUM(-1 * d.MemberWinloss * e.EUR),0) < 0 THEN 0 ELSE -1 * isnull(SUM(d.MemberWinloss * e.EUR * isnull(DI.ChargeRate,0) * isnull(STAR.ChargeRate,0) ),0) END AS money) AS StarExpressRevenue,
	CAST(CASE 
			WHEN isnull(SUM(-1 * d.MemberWinloss * e.EUR),0) < 0 THEN 0 
			ELSE isnull(SUM(-1 * d.MemberWinloss * e.EUR * isnull(OW.ChargeRate,0) * CASE WHEN @PartyTerminated = 0 THEN isnull(DI.ChargeRate,0) * isnull(STAR.ChargeRate,0) ELSE 1 END
			),0) 
		END AS money) AS OneworksRevenue,
	isnull(DI.ChargeRate,0) as DistributorsChargeRate,
	isnull(STAR.ChargeRate,0) as StarExpressChargeRate,
	isnull(OW.ChargeRate,0) as OneworksChargeRate
FROM #Data d
	INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = d.ResellerID
	INNER JOIN #TempExchange e ON d.winlostdate = e.ExchangeDate AND d.currency = e.ExchangeId
	LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange STAR ON d.ResellerID = STAR.ResellerID AND STAR.PartyID = 5 AND STAR.ProductID = 4 AND d.winlostdate BETWEEN STAR.FromDate AND STAR.ToDate	
	LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange OW ON d.ResellerID = OW.ResellerID AND OW.PartyID = 1 AND OW.ProductID = 4 AND d.winlostdate BETWEEN OW.FromDate AND OW.ToDate
	LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange DI ON d.ResellerID = DI.ResellerID AND DI.PartyID = 4 AND DI.ProductID = 4 AND d.winlostdate BETWEEN DI.FromDate AND DI.ToDate
GROUP BY
	r.ResellerID,d.LicenseeID,DI.ChargeRate,STAR.ChargeRate,OW.ChargeRate



--return the result
SELECT	
	r.ResellerID,r.ResellerName,r.ResellerType,
	CASE WHEN r.ResellerType = 2 THEN '' ELSE l.LicenseeName END AS LicenseeName,
	ISNULL(SUM(re.betcount), 0) AS BetCount,
	CAST(isnull(SUM(re.turnover),0) AS MONEY) AS Turnover,
	CAST(isnull(SUM(re.MemberWinloss),0) AS MONEY) AS MemberWinloss,
	CAST(isnull(SUM(re.GrossWinloss),0) AS MONEY) AS GrossWinloss,
	CAST(isnull(SUM(re.DistributorRevenue),0) AS MONEY) AS DistributorRevenue,
	CAST(CASE WHEN r.ResellerType = 1 THEN isnull(SUM(re.StarExpressRevenue),0) WHEN r.ResellerType = 2 THEN isnull(SUM(re.GrossWinloss),0) * StarExpressChargeRate END  AS MONEY) AS StarExpressRevenue,
	CAST(CASE 
			WHEN r.ResellerType = 1 THEN isnull(SUM(re.OneworksRevenue),0) 
			WHEN r.ResellerType = 2 THEN isnull(SUM(re.GrossWinloss),0) * OneworksChargeRate * CASE WHEN @PartyTerminated = 0 THEN StarExpressChargeRate ELSE 1 END
		END  AS MONEY) AS OneworksRevenue,
	DistributorsChargeRate,
	StarExpressChargeRate,
	OneworksChargeRate
FROM #Result re
	INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = re.ResellerID
	LEFT JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON l.LicenseeID = re.LicenseeID
		
GROUP BY
	r.ResellerType,r.ResellerID,r.ResellerName, CASE WHEN r.ResellerType = 2 THEN '' ELSE l.LicenseeName END,
	DistributorsChargeRate,StarExpressChargeRate,OneworksChargeRate	
ORDER BY
	r.ResellerType DESC,r.ResellerName,DistributorsChargeRate DESC, CASE WHEN r.ResellerType = 2 THEN '' ELSE l.LicenseeName END
			
DROP TABLE	#Data
DROP TABLE	#Result
DROP TABLE #TempExchange
END  
GO
GRANT EXECUTE ON [dbo].[OAS_Report_LiveCasinoWinloss] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OAS_Report_LiveCasinoWinloss] TO [vnteam]       
