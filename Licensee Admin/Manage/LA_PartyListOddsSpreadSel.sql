/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_PartyListOddsSpreadSel]
	@PartyIds VARCHAR(MAX) = ''
AS

/*
	Created: 20201110@Parsons
	Task : Get list of Party Odds Spread
	DB: DBLIC.bodb_Licensee
   
	Revisions:
		- 20201110@Parsons: Change-Request-Of-Odds-Spread [#142345]
		- 20211109@Percy: Fix missing Apply Spread Adjustment setting [RedmineID: #164411]

	Params:
		+ @PartyIds:
			- Empty: get all
		+ Ex: EXEC LA_PartyListOddsSpreadSel @PartyIds='14,389'
*/

SET NOCOUNT ON

	DECLARE @tblSite TABLE (SiteName VARCHAR(100))
	INSERT INTO @tblSite (SiteName)
	SELECT DISTINCT vp.SiteName
	FROM DBPRO.bodb02.dbo.LicSiteSetting ss WITH (NOLOCK)
		INNER JOIN DBCUST.SiteConfig.dbo.LicVendorProfile vp WITH (NOLOCK) ON ss.SiteId = vp.SiteId
	WHERE ss.ApplySpreadAdjustment = 1

	SELECT p.PartyId, p.PartyName, vsl.SiteId
	FROM @tblSite s
		INNER JOIN dbo.view_site_list vsl WITH (NOLOCK) ON s.SiteName = vsl.SiteName
		INNER JOIN dbo.OAS_Party p WITH (NOLOCK) ON vsl.SiteId = p.OldRefId
		INNER JOIN dbo.OAS_PartyDetail pd WITH (NOLOCK) ON p.PartyId = pd.PartyId
		LEFT JOIN bodb02.dbo.strSplit(@PartyIds, ',') p2 ON p.PartyId = p2.val
	WHERE @PartyIds = '' OR p2.val IS NOT NULL
GO