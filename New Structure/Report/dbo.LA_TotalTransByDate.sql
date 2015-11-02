USE [bodb_licensee]
GO
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
	 - 20141225@Winnie:  include AGCasino
	 - 20150706@Florent: Add Vegas Games, Gold Deluxe
	 - 20151028@Bravo:	 Exclude trial data
	 Params:			   
*/
BEGIN
 
	DECLARE @PartyIdString VARCHAR(500) 
	SELECT	@PartyIdString = COALESCE(@PartyIdString + ',', '') + CAST(PartyId AS VARCHAR(5))
	FROM	OAS_Party
	WHERE	PartyType=1
	
	DECLARE @ProductCode VARCHAR(200) = 'SB,RB,NG,LC,VS,KN,VG,BG,BA,AGC,GD'
	
	DECLARE @PartyChargeInfo AS TABLE (
			PartyId		INT,
			ToParty		INT,
			LicenseeId	INT,
			ProductID	INT,
			ProductCode VARCHAR(10),
			Rate		MONEY,
			FromDate	SMALLDATETIME,
			ToDate		SMALLDATETIME)

	INSERT INTO @PartyChargeInfo(PartyId, LicenseeId, ProductID, Rate, Fromdate, Todate)
	(
		SELECT	PartyID, LicenseeID, ProductID, DI_Rate, Fromdate, Todate
		FROM	dbo.LA_f_ChargeInfo(@PartyIdString, @FromDate, @ToDate, @ProductCode, 'OA', 1)
		WHERE	DI_Rate > 0 AND ProductId <> 1 --exclude RB	
	)
	UPDATE	c
	SET		ProductCode = CASE WHEN c.ProductID = 0 THEN 'SB' ELSE p.ProductPrefix END
	FROM	@PartyChargeInfo c LEFT JOIN Product3rd p ON c.ProductID = p.Productid
		
	DECLARE @TempPartyList TABLE (PartyId INT, PartyName VARCHAR(200), BrandName VARCHAR(200), ParentId INT)
	INSERT INTO @TempPartyList
	EXEC dbo.LA_PartyListSel
	
	UPDATE  c
	SET		c.ToParty = ci.ToParty
	FROM	@PartyChargeInfo c INNER JOIN OAS_ChargeInfo ci 
			ON c.PartyId = ci.FromParty	
			AND c.ProductID = ci.ProductID
			AND c.FromDate BETWEEN ci.FromDate AND ci.ToDate
			AND c.ToDate BETWEEN ci.FromDate AND ci.ToDate
	WHERE	ci.ChargeType != 2
	
	CREATE TABLE #tmpBetting (rptDate char(10),rptDateFull DATETIME, product varchar(10),siteID INT,betcount INT, FromParty INT, ToParty INT)
	
	INSERT	INTO #tmpBetting(rptDate,rptDateFull,siteID,product,betcount)
	SELECT	month(b.rptDate), b.rptDate, b.SiteID,	
	CASE	WHEN (b.bettype<31) OR (b.bettype>=121 and b.bettype<1000 AND b.Bettype NOT IN (901,902,903)) OR b.Bettype BETWEEN 1301 and 1399 THEN 'SB'
			WHEN bettype BETWEEN 81 AND 120 THEN 'NG'
			WHEN bettype between 1101 and 1199 THEN 'LC'
			WHEN bettype BETWEEN 31 AND 43 THEN 'RB'
			WHEN bettype BETWEEN 1201 AND 1299 THEN 'VS'
			WHEN Bettype BETWEEN 1501 and 1599 THEN 'KN'		
			WHEN Bettype =71 THEN 'CS'		 
			WHEN Bettype =73 THEN 'BG'	
			END product,
			SUM(b.betcount) betcount
	FROM	dbo.rpt_betting b WITH (NOLOCK)
	where 	b.SiteID !=N'' AND
			b.rptDate BETWEEN @Fromdate AND @Todate 
			AND b.status NOT IN (-1,103)
			AND b.CurrencyID<>20
			AND ISNULL(b.CustomerCategory,0) not in (27,28)
	GROUP BY month(b.rptDate),b.rptDate, 
			b.SiteID, 
			CASE WHEN (b.bettype<31) OR (b.Bettype>=121 AND b.Bettype<1000 AND b.Bettype NOT IN (901,902,903)) OR b.Bettype BETWEEN 1301 AND 1399 THEN 'SB'
				WHEN bettype BETWEEN 81 AND 120 THEN 'NG'
				WHEN bettype between 1101 and 1199 THEN 'LC'
				WHEN bettype BETWEEN 31 AND 43 THEN 'RB'
				WHEN bettype BETWEEN 1201 AND 1299 THEN 'VS'
				WHEN Bettype BETWEEN 1501 and 1599 THEN 'KN'			 
				WHEN Bettype =71 THEN 'CS'	
				WHEN Bettype =73 THEN 'BG'	
			END

	--BA
	INSERT	INTO #tmpBetting(rptDate,rptDateFull,product,siteID,betcount, FromParty, ToParty)
	SELECT	month(b.rptDate), b.rptDate,
			'BA' AS product,
			b.SiteID,SUM(b.betcount) betcount,
			c.PartyId,
			c.ToParty
	FROM	dbo.rpt_Betting_BA b WITH (NOLOCK) INNER JOIN @PartyChargeInfo c on b.SiteID = c.LicenseeId AND b.rptDate BETWEEN c.FromDate AND c.ToDate
	where	b.rptDate between @Fromdate AND @Todate
			AND b.status NOT IN (-1,103)
			AND b.CurrencyID<>20
	GROUP BY month(b.rptDate),b.rptDate, b.SiteID, c.ToParty, c.PartyId

	-- AG Casino
	INSERT	INTO #tmpBetting(rptDate, rptDateFull,product, siteID, betcount)
	SELECT	MONTH(c.[Winlostdate]),c.[Winlostdate],
			'AGC' AS product,
			ISNULL(site.SiteID,-1) siteid,
			SUM([BetCount])  betcount
	FROM	DBRPT.bodb_report.dbo.rptDepWinlost_AGCasino c WITH (NOLOCK)
			INNER JOIN  bodb02.dbo.custInfo (NOLOCK) d ON c.custid=d.custid
			INNER JOIN bodb02.dbo.customer ag (NOLOCK) ON  d.recommend = ag.custid AND ag.roleid = 2
			INNER JOIN bodb02.dbo.Site ibcsite (NOLOCK) ON ag.site=ibcsite.site
			INNER JOIN dbo.view_site_list [site] (NOLOCK) ON ibcsite.siteid=site.IbcSiteID			
	WHERE	c.[Winlostdate] between @Fromdate AND @Todate
			AND c.Currency<>20
	GROUP BY MONTH(c.[Winlostdate]), c.[Winlostdate], ISNULL(site.SiteID,-1)

	--Vegas Game and Gold Deluxe
	INSERT	INTO #tmpBetting(rptDate,rptDateFull, product, siteID, betcount)
	SELECT	MONTH(c.Winlostdate) AS rptDate, c.Winlostdate,
			p.ProductPrefix AS product, 
			lc.LicenseeID AS siteID, 
			SUM(c.betcount) AS betcount
	FROM	bodb_LicenseeReport.dbo.rptDepWinlost_ThirdParty c WITH (NOLOCK)
			INNER JOIN bodb02.dbo.Custinfo co WITH (NOLOCK) ON c.CustID = co.CustID	
			INNER JOIN dbo.f_SelLicenseeCust(0) lc ON co.recommend = lc.CustID
			LEFT JOIN bodb_licensee.dbo.LRF_f_Products3rd('VG,GD') p ON c.ProductId = p.ProductID				
	WHERE	c.Winlostdate BETWEEN @FromDate AND @Todate
			AND c.Currency <> 20
	GROUP BY MONTH(c.Winlostdate), c.Winlostdate, p.ProductPrefix, lc.LicenseeID
	---------------------------------------------------------------------------------	

	UPDATE	t
	SET		t.FromParty = c.PartyId,
			t.ToParty = c.ToParty
	FROM	#tmpBetting t INNER JOIN @PartyChargeInfo c ON
			t.rptDateFull BETWEEN c.FromDate AND c.ToDate AND
			t.product = c.ProductCode AND
			t.siteID = c.LicenseeId	
	---------------------------------------------------------------------------------

	SELECT	CASE a.product 
				WHEN 'SB' THEN 'Sportsbook' 
				ELSE p.ProductName 
			END AS product,
			rptdate,
			CASE 
				WHEN resellerName in ('PIH','FDL') THEN resellerName
				ELSE SiteName
			END siteName,
			A.resellerName,
			sum(A.betcount) betcount
	INTO	#data	 
	FROM(
			SELECT	b.rptDate,b.product,b.siteID,v.SiteName,sum(b.betcount) betcount,
					CASE WHEN b.FromParty IN (25,30) THEN 'Credit' ELSE 'Deposit' END LicenseeType,
					CASE WHEN b.FromParty = 25 THEN 'FDL' 
						 WHEN b.FromParty = 30 THEN 'PIH' 
						 WHEN b.ToParty = 11 then 'Boping'
						 WHEN b.ToParty = 1 THEN 'OW'
						 WHEN b.ToParty = 98 THEN 'Zelianta'						 
						 ELSE '' END				
					resellerName
		
			FROM	#tmpBetting b
					LEFT JOIN dbo.view_site_list v on b.SiteID=v.SiteID					
					LEFT JOIN (SELECT lr.LicenseeID from dbo.LicenseeReseller lr WITH (NOLOCK)
								INNER JOIN dbo.Resellers r WITH (NOLOCK) ON lr.ResellerID=r.ResellerID
								WHERE r.ResellerName ='Boping'
								) LBP ON b.SiteID = lbp.LicenseeID 
			WHERE	b.product  in ('SB','RB','NG','VS','LC','BA','KN','AGC', 'VG', 'GD')
			GROUP BY b.rptDate,b.product,b.siteID,v.SiteName,b.ToParty,b.FromParty,
					CASE WHEN b.FromParty IN (25,30) THEN 'Credit' ELSE 'Deposit' END,
					CASE WHEN b.FromParty = 25 THEN 'FDL' 
						 WHEN b.FromParty = 30 THEN 'PIH' 
						 WHEN b.ToParty = 11 then 'Boping'
						 WHEN b.ToParty = 1 THEN 'OW'	
						 WHEN b.ToParty = 98 THEN 'Zelianta'					 
						 ELSE '' END
		) A LEFT JOIN dbo.Product3rd p on a.product=p.ProductPrefix
		
		GROUP BY CASE a.product 
		   WHEN 'SB' THEN 'Sportsbook' 
		   ELSE p.ProductName 
		  END	  
		  ,rptdate,
		  CASE 
		   WHEN resellerName in ('PIH','FDL') THEN resellerName
		   ELSE SiteName
		   END ,A.resellerName

	SELECT  product ,resellerName,sitename,
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
	SELECT  product,resellerName,sitename,
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
	SELECT  product,'Credit',sitename,
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
	UNION ALL
	SELECT  product,'Zelianta',sitename,
		ISNULL(a.[1],0) AS 'Jan', ISNULL(a.[2],0) AS 'Feb', ISNULL(a.[3],0) AS 'Mar', 
		ISNULL(a.[4],0) AS 'Apr', ISNULL(a.[5],0) AS 'May', ISNULL(a.[6],0) AS 'Jun', 
		ISNULL(a.[7],0) AS 'Jul', ISNULL(a.[8],0) AS 'Aug', ISNULL(a.[9],0) AS 'Sep', 
		ISNULL(a.[10],0) AS 'Oct', ISNULL(a.[11],0) AS 'Nov', ISNULL(a.[12],0) AS 'Dec'
	FROM
		(
		SELECT *
		FROM (
			SELECT *
			FROM #data where resellerName IN ('Zelianta')
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
END