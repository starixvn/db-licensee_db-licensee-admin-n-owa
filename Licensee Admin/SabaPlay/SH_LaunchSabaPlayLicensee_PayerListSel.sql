/*<info serverAlias="DBLIC-bodb_licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[SH_LaunchSabaPlayLicensee_PayerListSel]
	@PayerPlatformID INT = 2 --2: SabaPlay, 3: SabaPlay And SabaSports
AS
/*
	Created: 20250319@Danny
	Task : get List Party of SabaPlay
	DB: DBLIC.bodb_Licensee
   
	Revisions:
		- 20250319@Danny: get List Payer of SabaPlay

*/

SET NOCOUNT ON
	
	SELECT op.PartyID, op.PartyName, n.LicenseeCode, n.BaseCurrencyId AS BaseCurrency, d.InvoiceLanguage
	FROM OAS_Party op WITH(NOLOCK)
	INNER JOIN dbo.OAS_PartyDetail d WITH(NOLOCK) ON op.PartyID = d.PartyID
		OUTER APPLY (
			SELECT TOP(1) o.BaseCurrencyId, o.LicenseeCode
			FROM dbo.OAS_PartyBaseCurrency o WITH(NOLOCK)
			WHERE o.PartyID = op.PartyID
			ORDER BY o.ToDate DESC
		) AS n
	WHERE op.PartyType = 5 AND op.PlatformId = @PayerPlatformID


GO