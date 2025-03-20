/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

CREATE PROCEDURE [dbo].[SH_LaunchSabaPlayLicensee_PayerListSel]
	@PayerPlatformID INT --2: SabaPlay, 3: SabaPlay And SabaSports
AS

/*
	Created: 20250319@Danny
	Task : get List Party of SabaPlay
	DB: DBLIC.bodb_Licensee
   
	Revisions:
		- 20250319@Danny: get List Payer of SabaPlay

*/

SET NOCOUNT ON
	
	SELECT PartyID, PartyName
	FROM OAS_Party op WITH(NOLOCK)
	WHERE op.PartyType = 5 AND op.PlatformId = @PayerPlatformID



GO