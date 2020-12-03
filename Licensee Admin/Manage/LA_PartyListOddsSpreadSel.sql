/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_PartyListOddsSpreadSel]
	 @PartyIds		VARCHAR(1000) = ''
AS

/*
	Created: 20201110@Parsons
	Task : Get list of Party Odds Spread
	DB: DBLIC.bodb_Licensee
   
	Revisions:
		- 20201110@Parsons: Change-Request-Of-Odds-Spread [#142345]

	Params:
		+ @PartyIds:
			- Empty: get all
		+ Ex: EXEC LA_PartyListOddsSpreadSel @PartyIds='14,389'
*/

SET NOCOUNT ON

	;WITH cte_SiteIds AS 
	(
		SELECT vsl.SiteID, vsl.SiteName
		FROM  DBPRO.bodb02.dbo.LicSiteSetting ss WITH(NOLOCK)
		INNER JOIN DBCUST.SiteConfig.dbo.LicVendorProfile vp WITH(NOLOCK) ON ss.SiteId = vp.SiteId
		INNER JOIN bodb_licensee.dbo.view_site_list vsl ON vp.SiteName = vsl.SiteName
	)
	SELECT	p.PartyID, p.PartyName, p.OldRefID AS SiteId
	FROM bodb_licensee.dbo.OAS_Party p WITH(NOLOCK)
	INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd WITH(NOLOCK) ON p.PartyID = pd.PartyID
	INNER JOIN cte_SiteIds s ON p.OldRefID = s.SiteID
	LEFT JOIN bodb02.dbo.strSplit(@PartyIds, ',') p2 ON p.PartyID = p2.val 
	WHERE @PartyIds = '' OR p2.val IS NOT NULL

GO