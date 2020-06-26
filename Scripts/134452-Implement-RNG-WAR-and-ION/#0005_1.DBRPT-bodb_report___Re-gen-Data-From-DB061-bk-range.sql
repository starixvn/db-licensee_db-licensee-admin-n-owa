/*<info serverAlias="DBRPT-bodb_report"></info>*/
/*   
	Creator: 20200626@Parsons
	Task:   Generate data of SAG for 18/06 - Now [#FeatureID 134452]
	DB:	    DBRPT-bodb_report
	Remark:	Re-gen data for SAG for - range bettrans_bk
*/

USE bodb_report
GO

BEGIN
	DECLARE @WinlostDate DATE = '2020-06-18' -- Current BU Date - 1 (BU = 2020-06-19)

	DECLARE @Sitelist TABLE (IbcSiteID INT, SiteID INT)	
	INSERT INTO @Sitelist (IbcSiteID, SiteID)
	SELECT IbcSiteID, SiteID
	FROM bodb_Licensee.dbo.view_site_list WITH (NOLOCK)	
	
	DELETE FROM dbo.rpt_ThirdPartyWL_ExtraGMT WITH(ROWLOCK)
	WHERE rptDate = @WinlostDate AND 
			BetTypeId BETWEEN 3001 AND 3099 -- SAG
				
	INSERT INTO dbo.rpt_ThirdPartyWL_ExtraGMT(RptDate, RptDate3rd, SiteId, BetTypeId, CurrencyId, StatusId, BetCount, Turnover, Winloss, AComm, PComm, ProgressiveContribution, ProgressivePayout,ValidBetAmount)
	SELECT CAST(b.winlostdate AS DATE)	AS Rptdate
		, CAST(b.Transdate3rd AS DATE)	AS RptDate3rd
		, ISNULL(site.SiteID, -1) AS siteid
		, b.gameID AS BetTypeId		
		, b.currency
		, b.statusID
		, COUNT(1) AS BetCount
		, SUM(ABS(b.stake)) AS Turnover
		, SUM(winlost - actual_stake) AS Winloss		
		, SUM(b.comm) AS AComm
		, SUM(b.playercomm) AS PComm
		, 0 AS ProgressiveContribution
		, 0 AS ProgressivePayout
		, SUM(ISNULL(b.NetStake, 0)) AS ValidBetAmount
	FROM bodb_Archive.dbo.bettransLC_bk b WITH (NOLOCK)
		LEFT JOIN bodb02.dbo.Customer c WITH (NOLOCK) ON b.recommend = c.custid AND c.roleid = 2
		LEFT JOIN bodb02.dbo.Site s WITH (NOLOCK) ON c.site = s.site
		LEFT JOIN @Sitelist [site] ON s.siteid = site.IbcSiteID
	WHERE b.winlostdate = @Winlostdate AND 
			b.statusID IN (111, 112, 113) AND
			BetTypeId BETWEEN 3001 AND 3099 -- SAG
	GROUP BY CAST(b.winlostdate AS DATE), CAST(b.Transdate3rd AS DATE), ISNULL(site.SiteID, -1), b.gameID, b.currency, b.statusID	
END
GO