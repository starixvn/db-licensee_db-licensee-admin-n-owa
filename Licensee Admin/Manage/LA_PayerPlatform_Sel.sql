/*<info serverAlias="DBLIC-bodb_Licensee" executers="wsv_nap" isFunction="0" isNested="0"></info>*/
CREATE PROCEDURE [dbo].[LA_PayerPlatform_Sel]
AS

/*
	Created: 20250319@Eddie
	DB: DBLIC-bodb_Licensee
	Description: Get Payer Platform

	Revisions:
		- 20250319@Eddie: Initialize SP [RedmineID: #217740]
*/

BEGIN
	SET NOCOUNT ON

	SELECT PlatformId, PlatformName
	FROM dbo.LA_f_PayerPlatform_Sel()
	ORDER BY PlatformId ASC
END
GO