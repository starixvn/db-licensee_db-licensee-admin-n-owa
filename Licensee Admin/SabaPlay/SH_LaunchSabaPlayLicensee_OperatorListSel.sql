/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

CREATE PROCEDURE [dbo].[SH_LaunchSabaPlayLicensee_OperatorListSel]
	 @UserID		INT	   = 0
	,@FunctionKey	NVARCHAR(100)	= ''
	,@PlatformId	INT  = 2 
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
	IF @PlatformId = 2
	BEGIN
		; WITH t AS
		(
			SELECT op.OldRefID AS SiteID
			FROM OAS_Party op WITH(NOLOCK)
			WHERE op.PartyType = 1 AND op.PlatformId = @PlatformId
		)
		SELECT  s.SiteID, s.SiteName 
		FROM	bodb_licenseeReport.dbo.SabaPlay_Operators s WITH(NOLOCK)
		LEFT JOIN t ON s.SiteID = t.SiteID
		WHERE  (t.SiteID IS NULL AND @PlatformId = 2)
	END

	IF @PlatformId = 3
	BEGIN
		SELECT s.OWSiteName AS SiteName 
		FROM  bodb_licenseeReport.dbo.SabaPlay_Operators s
		LEFT JOIN OAS_Party op ON op.PartyName = s.OWSiteName
		WHERE s.OWSiteName IS NOT NULL AND s.OWSiteName <> '' AND op.PartyID IS NULL

	END



GO