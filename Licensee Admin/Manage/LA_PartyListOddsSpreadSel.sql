/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="1"></info>*/
USE [bodb_licensee]
GO

CREATE PROCEDURE [dbo].[LA_PartyListOddsSpreadSel]
	 @PartyID		INT	   = 0
AS

/*
	Created: 20201110@Parsons
	Task : Get list of Party Odds Spread
	DB: DBLIC.bodb_Licensee
   
	Revisions:
		- 20201110@Parsons: Change-Request-Of-Odds-Spread [#142345]

	Params:
		+ PartyID:
			- 0 get all
		+ Ex: EXEC LA_PartyListOddsSpreadSel @PartyID=14
*/

SET NOCOUNT ON

	;WITH cte_SiteIds AS 
	(
		SELECT vsl.SiteID, vsl.SiteName
		FROM  DBPRO.bodb02.dbo.LicSiteSetting ss WITH(NOLOCK)
		INNER JOIN DBCUST.SiteConfig.dbo.LicVendorProfile vp WITH(NOLOCK) ON ss.SiteId = vp.SiteId
		INNER JOIN bodb_licensee.dbo.view_site_list vsl ON vp.SiteName = vsl.SiteName
		WHERE ss.ApplyDeductedSpread = 1
	)
	SELECT	p.PartyID, p.PartyName, p.OldRefID AS SiteId
	FROM bodb_licensee.dbo.OAS_Party p
	INNER JOIN bodb_licensee.dbo.OAS_PartyDetail pd ON p.PartyID = pd.PartyID
	INNER JOIN cte_SiteIds s ON p.OldRefID = s.SiteID
	WHERE @PartyID = 0 OR @PartyID = p.PartyID

GO