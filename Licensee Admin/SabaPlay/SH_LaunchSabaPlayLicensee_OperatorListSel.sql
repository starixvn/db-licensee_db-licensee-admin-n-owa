/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[SH_LaunchSabaPlayLicensee_OperatorListSel]
AS
/*
	Created: 20250319@Danny
	Task : get List Party of SabaPlay
	DB: DBLIC.bodb_Licensee
   
	Revisions:
		- 20250319@Danny: get List Party of SabaPlay
		- 20250527@Eddie: Remove mix mode [RedmineID: #228189]
		- 20250709@Danny: Return NonOfficialPartyId [RedmineID: #232176]

*/

SET NOCOUNT ON
	-- List payer already launched

	SELECT s.SiteID, s.SiteName , t5.PartyID AS NonOfficialPartyId
	FROM bodb_licenseeReport.dbo.SabaPlay_Operators s WITH (NOLOCK)
		LEFT JOIN dbo.OAS_Party t WITH (NOLOCK) ON s.SiteID = t.OldRefID AND t.PlatformId = 2 AND t.PartyType = 1
		LEFT JOIN dbo.OAS_Party t5 WITH (NOLOCK) ON s.SiteName = t5.PartyName AND t5.PlatformId = 2 AND t5.PartyType = 5
	WHERE t.OldRefID IS NULL AND s.OWSiteName IS NULL
	ORDER BY s.SiteID
GO