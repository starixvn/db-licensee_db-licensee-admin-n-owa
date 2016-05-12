USE [bodb_LicenseeReport]
GO
/****** Object:  StoredProcedure [dbo].[Task_Microgaming_Bettrans]    Script Date: 12/30/2015 04:18:11 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.Task_Microgaming_Bettrans    Script Date: 12/11/2015 4:24:24 PM ******/
ALTER PROCEDURE [dbo].[Task_Microgaming_Bettrans] @Winlossdate DATE
AS
/*
	 Creator: 20150731@Florent
	 Task: Generate data for MicroGaming Casino
	 DB: DBLIC/bodb_LicenseeReport
	 Revisions: 		
		- 20150930@Florent: support Microgaming RNG
		- 20151208@Jim: seperate MicroGame into 2 products (#45454)
	 Param's Explanation:
*/

BEGIN
	SET NOCOUNT ON
	IF @Winlossdate IS NULL
		RETURN
	IF NOT EXISTS(SELECT TOP 1 1 FROM bodb02.dbo.bettrans WITH (NOLOCK) WHERE winlostdate = @Winlossdate)
		RETURN
	DELETE dbo.rpt_ThirdPartyWL_ExtraGMT WITH(ROWLOCK, UPDLOCK)
	WHERE RptDate = @Winlossdate

	--bettype mapping
	DECLARE @Bettype AS TABLE(Bettype INT)
    INSERT INTO @Bettype (Bettype)
    SELECT Bettype
	FROM bodb_licensee.dbo.Sport_Bettype_Reference WITH (NOLOCK)
	WHERE Sporttype IN (203,205) 

	INSERT INTO dbo.rpt_ThirdPartyWL_ExtraGMT(RptDate, RptDate3rd, SiteId, BetTypeId, CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm)
	(
		SELECT CAST(b.winlostdate AS DATE)	AS Rptdate
			, CAST(b.checktime AS DATE)	AS RptDate3rd
			, ISNULL(site.SiteID, -1) AS siteid
			, b.bettype	 AS BetTypeId		
			, b.currency
			, b.statusID
			, COUNT(1) AS BetCount
			, SUM(ABS(b.stake)) AS Turnover
			, SUM(winlost - actual_stake) AS Winloss		
			, SUM(b.comm) AS AComm
			, SUM(b.playercomm) AS PComm
		FROM bodb02.dbo.bettrans b WITH (NOLOCK)
			INNER JOIN @Bettype bt ON b.bettype = bt.Bettype
			LEFT JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON b.recommend = c.custid AND c.roleid = 2
			LEFT JOIN bodb02.dbo.Site s WITH (NOLOCK) ON c.site = s.site
			LEFT JOIN bodb_licensee.dbo.view_site_list [site] (NOLOCK) ON s.siteid = site.IbcSiteID			
		WHERE b.winlostdate = @Winlossdate	
			AND b.statusID NOT IN (0, 1, 101, 102, 121)
			AND b.bettype NOT IN (2008, 2009)
		GROUP BY CAST(b.winlostdate AS DATE), CAST(b.checktime AS DATE), ISNULL(site.SiteID,-1), b.bettype
			, b.currency, b.statusID
		UNION
		SELECT CAST(b.winlostdate AS DATE)	AS Rptdate
			, CAST(b.Transdate3rd AS DATE)	AS RptDate3rd
			, ISNULL(site.SiteID, -1) AS siteid
			, b.gameID	 AS BetTypeId		
			, b.currency
			, b.statusID
			, COUNT(1) AS BetCount
			, SUM(ABS(b.stake)) AS Turnover
			, SUM(winlost - actual_stake) AS Winloss		
			, SUM(b.comm) AS AComm
			, SUM(b.playercomm) AS PComm
		FROM bodb02.dbo.bettransRnG b WITH (NOLOCK)			
			LEFT JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON b.recommend = c.custid AND c.roleid = 2
			LEFT JOIN bodb02.dbo.Site s WITH (NOLOCK) ON c.site = s.site
			LEFT JOIN bodb_licensee.dbo.view_site_list [site] (NOLOCK) ON s.siteid = site.IbcSiteID			
		WHERE b.winlostdate = @Winlossdate
			AND b.statusID NOT IN (0, 1, 101, 102, 121)
			AND b.gameID IN (2008, 2009)
		GROUP BY CAST(b.winlostdate AS DATE), CAST(b.Transdate3rd AS DATE), ISNULL(site.SiteID, -1), b.gameID
			, b.currency, b.statusID		
	)OPTION (MAXDOP 1)
END
GO
GRANT EXECUTE ON [dbo].[Task_Microgaming_Bettrans] TO [bodbAdminNet] AS [dbo]
GO
GRANT VIEW DEFINITION ON [dbo].[Task_Microgaming_Bettrans] TO [vnteam] AS [dbo]