set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
go




/*
exec OA_Rpt_NumberGameWinloss @NormalLicensee=N'1,4,2,14,6,9,10,16',@Operator=N'7,4,8,9',
@FromDate='2012-09-03 00:00:00:000',
@ToDate='2012-12-17 00:00:00:000'
*/
ALTER  PROCEDURE [dbo].[OA_Rpt_NumberGameWinloss]      
	@NormalLicensee VARCHAR(1000),  
	@Operator  VARCHAR(1000),  
	@FromDate  SMALLDATETIME,    
	@ToDate   SMALLDATETIME
AS      
  
/*  
 * Created by : [20120828@Henry]  
 * Task  : Get Number Game Winloss 
 * DB   : DB052.bodb02  
 * Revisions :  
	- 20121105@Henry: using new table ResellerProductChargeByDateRange
	- 20121217@Jim: return data  by month
 * Param's Explanation:    
 *  - @NormalLicensee : List of normal licensee ID separated by ','  
 *  - @Operator   : List of operator ID separated by ','  
 *  - @FromDate   : From date   
 *  - @ToDate   : To date  
 *  
 */  
    
BEGIN      

SET NOCOUNT ON

DECLARE @tmpLicenseeReseller AS TABLE (ResellerID INT, LicenseeID INT)


CREATE TABLE #Data 
			(	winlostdate  datetime,
				Currency  INT,
				ResellerID int,
				LicenseeID int,
				turnover MONEY,
				MemberWinloss MONEY,
				LicenseeWL MONEY,
				Betcount INT
			)
CREATE TABLE #Result 
			(	winlostdate varchar(6),
				ResellerID INT,
				LicenseeID int,
				turnover MONEY,
				MemberWinloss MONEY,
				GrossWinloss MONEY, 
				DistributorRevenue MONEY,
				Betcount INT,
				LupineRevenue MONEY,
				OneworksRevenue MONEY,
				DistributorsChargeRate MONEY,
				LupineChargeRate MONEY,
				OneworksChargeRate MONEY
			)

--Get normal licensee list:
IF LTRIM(RTRIM(ISNULL(@NormalLicensee,''))) <> ''
BEGIN
	INSERT INTO @tmpLicenseeReseller (ResellerID,LicenseeID)
	SELECT lr.ResellerID,lr.LicenseeID
	FROM	
		bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)
		INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) 
			  ON lr.ResellerID = r.ResellerID
	WHERE
		r.ResellerID <> 3 
		AND lr.LicenseeID IN(
								SELECT RTRIM(LTRIM(VAL)) 
								FROM strSplit(@NormalLicensee,',')
							)	
END		

-- Operator
IF LTRIM(RTRIM(ISNULL(@Operator,''))) <> ''
BEGIN
	INSERT INTO @tmpLicenseeReseller (ResellerID, LicenseeID)   
	SELECT lr.ResellerID, lr.LicenseeID   
	FROM 
		bodb_licensee.dbo.LicenseeReseller lr (NOLOCK)
		INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) 
			  ON lr.ResellerID = r.ResellerID
	WHERE
		r.ResellerID IN (
						SELECT RTRIM(LTRIM(VAL)) 
						FROM strSplit(@Operator,',')
						)
END
  
--exclude BA & IBC & PIH...
IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr 
					INNER JOIN bodb_licensee.dbo.licensees l WITH (nolock) 
					ON lr.licenseeid=l.licenseeid  
					WHERE l.IsDeposit=1 AND lr.ResellerID<>3
		)
BEGIN
	INSERT INTO #Data
	SELECT  b.rptDate,
			b.currencyID,
			lr.ResellerID,
			lr.licenseeid,
			SUM(Turnover) as Turnover, 
			SUM(Winloss) AS MemberWinloss, 
			sum(winlossA) AS LicenseeWL,
			SUM(BetCount) AS betcount
	FROM @tmpLicenseeReseller lr
		INNER JOIN bodb_licensee.dbo.licensees lic WITH ( NOLOCK) ON lic.licenseeid=lr.licenseeid
		INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON lr.LicenseeID = b.siteID
		INNER JOIN bodb_Licensee.dbo.SystemLicensee sl (NOLOCK) ON lic.LicenseeID=sl.LicenseeID
		INNER JOIN bodb_Licensee.dbo.Systems s (NOLOCK) ON sl.SystemID=s.ID
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
		AND bettype BETWEEN 81 AND 120
	GROUP BY b.rptDate,b.currencyID, lr.ResellerID, lr.licenseeid
END

--FDL + PIH...
IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr 
					inner JOIN bodb_licensee.dbo.licensees l WITH (nolock) 
					ON lr.licenseeid=l.licenseeid where l.IsDeposit=0
		)
BEGIN
	--1 PIH: 
	IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr WHERE lr.ResellerID = 8)
	BEGIN
		INSERT INTO #Data
		SELECT  b.rptDate,
				b.currencyID,
				lr.ResellerID,
				lr.licenseeid,
				SUM(Turnover) as Turnover, 
				SUM(Winloss) AS MemberWinloss, 
				0 AS LicenseeWL,
		SUM(BetCount) AS betcount
		FROM @tmpLicenseeReseller lr
			INNER JOIN bodb_Licensee.dbo.labels lb WITH (NOLOCK) ON lr.LicenseeID=lb.LicenseeID
			INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID=lb.LabelID
		WHERE
			b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.status NOT IN (-1,103)
			AND lr.ResellerID = 8
			--AND @FromDate >= isnull(lb.AffectedDate,'1999-01-01')
			AND b.rptDate >= isnull(lb.AffectedDate,'1999-01-01')
			AND CurrencyID<>20
			AND bettype BETWEEN 81 AND 120
			AND b.customercategory NOT IN (27,28) 
		GROUP BY b.rptDate,b.currencyID, lr.ResellerID, lr.licenseeid	
	END
	--2 FDL
	IF EXISTS(SELECT 1 FROM @tmpLicenseeReseller lr WHERE lr.ResellerID = 4)
	BEGIN
		INSERT INTO #Data
		SELECT  b.rptDate,
				b.currencyID,
				lr.ResellerID,
				lr.licenseeid,
				SUM(Turnover) as Turnover,
				SUM(Winloss) AS MemberWinloss,
				0 AS LicenseeWL,
				SUM(BetCount) AS betcount
		FROM @tmpLicenseeReseller lr
			INNER JOIN bodb_Licensee.dbo.labels lb WITH (NOLOCK) ON lr.LicenseeID=lb.LicenseeID
			INNER JOIN bodb_Licensee.dbo.rpt_Betting b WITH ( NOLOCK) ON b.siteID=lb.LabelID
		WHERE
			b.rptDate BETWEEN @FromDate AND @ToDate
			AND b.status NOT IN (-1,103)
			AND lr.ResellerID = 4
			--AND @FromDate >= isnull(lb.AffectedDate,'1999-01-01')
			AND b.rptDate >= isnull(lb.AffectedDate,'1999-01-01')
			AND CurrencyID<>20
			AND bettype BETWEEN 81 AND 120
			AND b.customercategory NOT IN (27,28) 
		GROUP BY b.rptDate,b.currencyID, lr.ResellerID, lr.licenseeid	
	END

END

CREATE NONCLUSTERED INDEX IDX_Currency ON #Data(Currency,winlostdate)


SELECT * INTO #TempExchange 
FROM Lrf_f_GetExchangeDaily(@FromDate,@ToDate)
WHERE exchangeid IN (SELECT DISTINCT Currency FROM #Data)

INSERT INTO #Result(winlostdate,
					ResellerID,
					LicenseeID,
					turnover, 
					MemberWinloss,
					GrossWinloss, 
					DistributorRevenue, 
					Betcount,
					LupineRevenue,
					OneworksRevenue,
					DistributorsChargeRate,
					LupineChargeRate,
					OneworksChargeRate)
SELECT	
	Convert(varchar(6),winlostdate,112) as winlostdate,
	r.ResellerID,
	d.LicenseeID,
	CAST(isnull(SUM(d.turnover * e.EUR),0) AS MONEY) AS Turnover,
	CAST(isnull(SUM(d.MemberWinloss * e.EUR),0) AS MONEY) AS MemberWinloss,
	CAST(CASE WHEN isnull(SUM(d.MemberWinloss * e.EUR),0) > 0 THEN 0 ELSE -1 * isnull(SUM(d.MemberWinloss * e.EUR),0) END AS money) AS GrossWinloss,
	CAST(CASE WHEN isnull(SUM(d.MemberWinloss * e.EUR),0) > 0 THEN 0 ELSE -1 * isnull(SUM(d.MemberWinloss * e.EUR * isnull(DI.ChargeRate,0)),0) END AS money) AS DistributorRevenue,
	ISNULL(SUM(d.betcount), 0) AS BetCount,
	CAST(CASE WHEN isnull(SUM(-1 * d.MemberWinloss * e.EUR),0) < 0 THEN 0 ELSE -1 * isnull(SUM(d.MemberWinloss * e.EUR * isnull(DI.ChargeRate,0) * isnull(LUP.ChargeRate,0) ),0) END AS money) AS LupineRevenue,
	CAST(CASE WHEN isnull(SUM(-1 * d.MemberWinloss * e.EUR),0) < 0 THEN 0 ELSE isnull(SUM(-1 * d.MemberWinloss * e.EUR * isnull(DI.ChargeRate,0) * isnull(LUP.ChargeRate,0) * isnull(OW.ChargeRate,0)),0) END AS money) AS OneworksRevenue,
	isnull(DI.ChargeRate,0) as DistributorsChargeRate,
	isnull(LUP.ChargeRate,0) as LupineChargeRate,
	isnull(OW.ChargeRate,0) as OneworksChargeRate
FROM #Data d
	INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = d.ResellerID
	INNER JOIN #TempExchange e ON d.winlostdate = e.ExchangeDate AND d.currency = e.ExchangeId
	LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange LUP ON d.ResellerID = LUP.ResellerID AND LUP.PartyID = 3 AND LUP.ProductID = 2 AND d.winlostdate BETWEEN LUP.FromDate AND LUP.ToDate	
	LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange OW ON d.ResellerID = OW.ResellerID AND OW.PartyID = 1 AND OW.ProductID = 2 AND d.winlostdate BETWEEN OW.FromDate AND OW.ToDate
	LEFT JOIN bodb_licensee.dbo.ResellerProductChargeByDateRange DI ON d.ResellerID = DI.ResellerID AND DI.PartyID = 4 AND DI.ProductID = 2 AND d.winlostdate BETWEEN DI.FromDate AND DI.ToDate
GROUP BY
	Convert(varchar(6),winlostdate,112),r.ResellerID,d.LicenseeID,DI.ChargeRate,LUP.ChargeRate,OW.ChargeRate
	
--return the result
SELECT	
	re.winlostdate,
	r.ResellerID,
	r.ResellerName,
	r.ResellerType,
	l.LicenseeName  AS LicenseeName,
	--CASE WHEN r.ResellerType = 2 THEN '' ELSE l.LicenseeName END AS LicenseeName,
	ISNULL(SUM(re.betcount), 0) AS BetCount,
	CAST(isnull(SUM(re.turnover),0) AS MONEY) AS Turnover,
	CAST(isnull(SUM(re.MemberWinloss),0) AS MONEY) AS MemberWinloss,
	CAST(isnull(SUM(re.GrossWinloss),0) AS MONEY) AS GrossWinloss,
	CAST(isnull(SUM(re.DistributorRevenue),0) AS MONEY) AS DistributorRevenue,
	CAST(CASE WHEN r.ResellerType = 1 THEN isnull(SUM(re.LupineRevenue),0) WHEN r.ResellerType = 2 THEN isnull(SUM(re.GrossWinloss),0) * LupineChargeRate END  AS MONEY) AS LupineRevenue,
	CAST(CASE WHEN r.ResellerType = 1 THEN isnull(SUM(re.OneworksRevenue),0) WHEN r.ResellerType = 2 THEN isnull(SUM(re.GrossWinloss),0) * LupineChargeRate * OneworksChargeRate END  AS MONEY) AS OneworksRevenue,
	DistributorsChargeRate,
	LupineChargeRate,
	OneworksChargeRate
FROM #Result re
	INNER JOIN bodb_licensee.dbo.Resellers r WITH (NOLOCK) ON r.ResellerID = re.ResellerID
	LEFT JOIN bodb_licensee.dbo.Licensees l WITH (NOLOCK) ON l.LicenseeID = re.LicenseeID
		
GROUP BY
	re.winlostdate,r.ResellerType,r.ResellerID,r.ResellerName, l.LicenseeName,
	DistributorsChargeRate,LupineChargeRate,OneworksChargeRate	
ORDER BY
	 re.winlostdate,r.ResellerType DESC,r.ResellerName,DistributorsChargeRate DESC, 
	l.LicenseeName
			
DROP TABLE	#Data
DROP TABLE	#Result
DROP TABLE #TempExchange
			
END  
GO
GRANT EXECUTE ON [dbo].[OA_Rpt_NumberGameWinloss] TO [bodbAdminNet] 
GO
GRANT VIEW DEFINITION ON [dbo].[OA_Rpt_NumberGameWinloss] TO [vnteam]      
