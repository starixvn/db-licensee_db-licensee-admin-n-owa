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

*/

SET NOCOUNT ON
	-- List payer already launched

	SELECT s.SiteID, s.SiteName 
	FROM bodb_licenseeReport.dbo.SabaPlay_Operators s WITH (NOLOCK)
		LEFT JOIN dbo.OAS_Party t WITH (NOLOCK) ON s.SiteID = t.OldRefID AND t.PlatformId = 2
	WHERE t.OldRefID IS NULL AND s.OWSiteName IS NULL
	ORDER BY s.SiteID
GO