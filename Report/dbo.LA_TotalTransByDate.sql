USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_TotalTransByDate_xpre]    Script Date: 12/30/2014 4:00:33 PM ******/
SET ANSI_NULLS ON
GO 
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_TotalTransByDate]          
	@FromDate DATETIME,
	@ToDate DATETIME	
AS
/*  
	 Created: 20140814@Florent
	 Task : get total transaction of all licensee in Boping, OW, Credit site : FDL,PIH
	 DB: DB052.bodb_Licensee  
   
	 Revisions:  
	 --20141225@Winnie:  include AGCasino
	 - 20150706@Florent: Add Vegas Games, Gold Deluxe
	 Params:			   
*/
--declare @Fromdate Datetime,@Todate Datetime
--select @Fromdate = '2014-01-01',@Todate = '2014-12-31'

CREATE TABLE #tmpBetting (rptDate char(10),product varchar(10),siteID INT,betcount INT)
--getting data
INSERT INTO #tmpBetting(rptDate,siteID,product,betcount)
SELECT month(b.rptDate), 	b.SiteID,	
CASE WHEN (b.bettype<31) OR (b.bettype>=121 and b.bettype<1000) OR b.Bettype BETWEEN 1301 and 1399 THEN 'SB'
		WHEN bettype BETWEEN 81 AND 120 THEN 'NG'
		WHEN bettype between 1101 and 1199 THEN 'LC'
		WHEN bettype BETWEEN 31 AND 43 THEN 'RB'
		WHEN bettype BETWEEN 1201 AND 1299 THEN 'VS'
		WHEN Bettype BETWEEN 1501 and 1599 THEN 'KN'		
		WHEN Bettype =71 THEN 'CS'		 
		WHEN Bettype =73 THEN 'BG'	
	END product,
SUM(b.betcount) betcount
FROM dbo.rpt_betting b WITH (NOLOCK)
where 
b.SiteID !=N'' AND
b.rptDate BETWEEN @Fromdate AND @Todate 
AND b.status NOT IN (-1,103)
AND b.CurrencyID<>20
AND ISNULL(b.CustomerCategory,0) not in (27,28)
GROUP BY month(b.rptDate), b.SiteID, CASE WHEN (b.bettype<31) OR (b.bettype>=121 and b.bettype<1000) OR b.Bettype BETWEEN 1301 and 1399 THEN 'SB'
		WHEN bettype BETWEEN 81 AND 120 THEN 'NG'
		WHEN bettype between 1101 and 1199 THEN 'LC'
		WHEN bettype BETWEEN 31 AND 43 THEN 'RB'
		WHEN bettype BETWEEN 1201 AND 1299 THEN 'VS'
		WHEN Bettype BETWEEN 1501 and 1599 THEN 'KN'			 
		WHEN Bettype =71 THEN 'CS'	
		WHEN Bettype =73 THEN 'BG'	
	END

--BA
INSERT INTO #tmpBetting
SELECT month(b.rptDate), 
'BA' AS product,
b.SiteID,SUM(b.betcount) betcount
FROM dbo.rpt_Betting_BA b WITH (NOLOCK)
where b.rptDate between @Fromdate AND @Todate
AND b.status NOT IN (-1,103)
AND b.CurrencyID<>20
GROUP BY month(b.rptDate), b.SiteID

-- AG Casino
INSERT INTO #tmpBetting
SELECT MONTH(c.[Winlostdate]),
'AGC' AS product,
 ISNULL(site.SiteID,-1) siteid,
 SUM([BetCount])  betcount
 FROM
DBRPT.bodb_report.dbo.rptDepWinlost_AGCasino c WITH (NOLOCK)
INNER JOIN  bodb02.dbo.custInfo (NOLOCK) d ON c.custid=d.custid
INNER JOIN bodb02.dbo.customer ag (NOLOCK) ON  d.recommend = ag.custid AND ag.roleid = 2
INNER JOIN bodb02.dbo.Site ibcsite (NOLOCK) ON ag.site=ibcsite.site
INNER JOIN dbo.view_site_list [site] (NOLOCK) ON ibcsite.siteid=site.IbcSiteID	
WHERE  c.[Winlostdate] between @Fromdate AND @Todate
AND c.Currency<>20
GROUP BY MONTH(c.[Winlostdate]), ISNULL(site.SiteID,-1) 
--Vegas Game and Gold Deluxe
INSERT INTO #tmpBetting(rptDate, product, siteID, betcount)
SELECT MONTH(c.Winlostdate) AS rptDate, p.ProductPrefix AS product, lc.LicenseeID AS siteID, SUM(c.betcount) AS betcount
FROM bodb_LicenseeReport.dbo.rptDepWinlost_ThirdParty c WITH (NOLOCK)
	INNER JOIN bodb02.dbo.Custinfo co WITH (NOLOCK) ON c.CustID = co.CustID	
	INNER JOIN dbo.f_SelLicenseeCust(0) lc ON co.recommend = lc.CustID
	LEFT JOIN bodb_licensee.dbo.LRF_f_Products3rd('VG,GD') p ON c.ProductId = p.ProductID
WHERE c.Winlostdate BETWEEN @FromDate AND @Todate
	AND c.Currency <> 20
GROUP BY MONTH(c.Winlostdate), p.ProductPrefix, lc.LicenseeID	
---------------------------------------------------------------------------------

--DECLARE @product varchar(10)
--set @product ='SB'
SELECT CASE a.product 
	   WHEN 'SB' THEN 'Sportsbook' 
	   ELSE p.ProductName 
	  END AS product	  
	  ,rptdate,
	  CASE 
	   WHEN resellerName in ('PIH','FDL') THEN resellerName
	   ELSE SiteName
	   END siteName,A.resellerName
		,sum(A.betcount) betcount
INTO #data	 
FROM (
	SELECT b.rptDate,b.product,b.siteID,v.SiteName,sum(b.betcount) betcount,
	CASE WHEN lb.LabelID is null then 'Deposit' else 'Credit' end LicenseeType,
	CASE WHEN lb.LabelID is null and lbp.LicenseeID is not null then 'Boping'
			WHEN lb.LabelID is null and lbp.LicenseeID is null THEN 'OW' 
			WHEN lb.LabelID is not null THEN case when lb.LicenseeID =13 then 'FDL' else 'PIH' end
			
	END	resellerName
	
	from #tmpBetting b
	LEFT JOIN dbo.view_site_list v on b.SiteID=v.SiteID
	LEFT JOIN dbo.Labels lb WITH (NOLOCK) on b.SiteID = lb.LabelID
	LEFT JOIN (select lr.LicenseeID from dbo.LicenseeReseller lr WITH (NOLOCK)
				INNER JOIN dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID=r.ResellerID
				WHERE r.ResellerName ='Boping'
				) LBP ON b.SiteID = lbp.LicenseeID 
	WHERE b.product  in ('SB','RB','NG','VS','LC','BA','KN','AGC', 'VG', 'GD')
	GROUP BY b.rptDate,b.product,b.siteID,v.SiteName,CASE WHEN lb.LabelID is null then 'Deposit' else 'Credit' end,
	CASE WHEN lb.LabelID is null and lbp.LicenseeID is not null then 'Boping'
			WHEN lb.LabelID is null and lbp.LicenseeID is null THEN 'OW' 
			WHEN lb.LabelID is not null THEN case when lb.LicenseeID = 13 then 'FDL' else 'PIH' end
	END
	) A LEFT JOIN dbo.Product3rd p on a.product=p.ProductPrefix
	--where A.product = @product
	GROUP BY CASE a.product 
	   WHEN 'SB' THEN 'Sportsbook' 
	   ELSE p.ProductName 
	  END	  
	  ,rptdate,
	  CASE 
	   WHEN resellerName in ('PIH','FDL') THEN resellerName
	   ELSE SiteName
	   END ,A.resellerName

select  product ,resellerName,sitename,
ISNULL(a.[1],0) AS 'Jan', ISNULL(a.[2],0) AS 'Feb', ISNULL(a.[3],0) AS 'Mar', 
ISNULL(a.[4],0) AS 'Apr', ISNULL(a.[5],0) AS 'May', ISNULL(a.[6],0) AS 'Jun', 
ISNULL(a.[7],0) AS 'Jul', ISNULL(a.[8],0) AS 'Aug', ISNULL(a.[9],0) AS 'Sep', 
ISNULL(a.[10],0) AS 'Oct', ISNULL(a.[11],0) AS 'Nov', ISNULL(a.[12],0) AS 'Dec'
FROM
	(
	SELECT *
	FROM (
		SELECT *
		FROM #data where resellerName='Boping'
	) as s
	PIVOT
	(
		sum(betcount)
		FOR rptdate IN ([1], [2], [3], [4], 
		[5], [6], [7], [8], [9], [10], [11], [12])
	) as pivt
	) A
UNION ALL
select  product,resellerName,sitename,
ISNULL(a.[1],0) AS 'Jan', ISNULL(a.[2],0) AS 'Feb', ISNULL(a.[3],0) AS 'Mar', 
ISNULL(a.[4],0) AS 'Apr', ISNULL(a.[5],0) AS 'May', ISNULL(a.[6],0) AS 'Jun', 
ISNULL(a.[7],0) AS 'Jul', ISNULL(a.[8],0) AS 'Aug', ISNULL(a.[9],0) AS 'Sep', 
ISNULL(a.[10],0) AS 'Oct', ISNULL(a.[11],0) AS 'Nov', ISNULL(a.[12],0) AS 'Dec'
FROM
	(
	SELECT *
	FROM (
		SELECT *
		FROM #data where resellerName='OW'
	) as s
	PIVOT
	(
		sum(betcount)
		FOR rptdate IN ([1], [2], [3], [4], 
		[5], [6], [7], [8], [9], [10], [11], [12])
	) as pivt
	) A
UNION ALL
select  product,'Credit',sitename,
ISNULL(a.[1],0) AS 'Jan', ISNULL(a.[2],0) AS 'Feb', ISNULL(a.[3],0) AS 'Mar', 
ISNULL(a.[4],0) AS 'Apr', ISNULL(a.[5],0) AS 'May', ISNULL(a.[6],0) AS 'Jun', 
ISNULL(a.[7],0) AS 'Jul', ISNULL(a.[8],0) AS 'Aug', ISNULL(a.[9],0) AS 'Sep', 
ISNULL(a.[10],0) AS 'Oct', ISNULL(a.[11],0) AS 'Nov', ISNULL(a.[12],0) AS 'Dec'
FROM
	(
	SELECT *
	FROM (
		SELECT *
		FROM #data where resellerName IN ('PIH','FDL')
	) as s
	PIVOT
	(
		sum(betcount)
		FOR rptdate IN ([1], [2], [3], [4], 
		[5], [6], [7], [8], [9], [10], [11], [12])
	) as pivt
	) A	
---------------
DROP TABLE #tmpBetting 
DROP TABLE #data
