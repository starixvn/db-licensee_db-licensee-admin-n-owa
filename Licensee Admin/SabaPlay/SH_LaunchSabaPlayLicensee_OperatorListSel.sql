/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

CREATE PROCEDURE [dbo].[SH_LaunchSabaPlayLicensee_OperatorListSel]
	 @UserID		INT	   = 0
	,@FunctionKey	NVARCHAR(100)	= ''
AS

/*
	Created: 20250319@Danny
	Task : get List Party of SabaPlay
	DB: DBLIC.bodb_Licensee
   
	Revisions:
		- 20250319@Danny: get List Party of SabaPlay

*/

SET NOCOUNT ON

	-- List payer already launched
	; WITH t AS
	(
		SELECT op.OldRefID AS SiteID
		FROM OAS_Party op WITH(NOLOCK)
		INNER JOIN OAS_PartyDetail opd WITH(NOLOCK) ON op.PartyID = opd.PartyID
		WHERE op.PartyType = 1 AND op.PlatformId = 2
	)
	SELECT  s.SiteID, s.SiteName 
	FROM	bodb_licenseeReport.dbo.SabaPlay_Operators s WITH(NOLOCK)
	LEFT JOIN t ON s.SiteID = t.SiteID
	WHERE t.SiteID IS NULL


GO