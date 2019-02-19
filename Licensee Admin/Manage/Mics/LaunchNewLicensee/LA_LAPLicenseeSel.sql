/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_LAPLicenseeSel]
AS
/*
	Created: 20190102@Parsons
	Task : Launch new licensee
	DB: DB052.bodb_Licensee

	Revisions:
	- 20190102@Parsons: Launch new licensee

	Params:

	Explannation: EXEC LA_LAPLicenseeSel
*/
BEGIN
	SET NOCOUNT ON

	SELECT l.LicenseeID AS PartyId, l.LicenseeName AS PartyName, l.BrandName
	FROM dbo.Licensees l WITH(NOLOCK)
	LEFT JOIN dbo.OAS_Party p WITH(NOLOCK) ON l.LicenseeID = p.OldRefID
	WHERE p.PartyID IS NULL
END
GO