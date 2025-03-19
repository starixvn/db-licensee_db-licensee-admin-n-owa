/*<info serverAlias="DBLIC-bodb_Licensee" selecters="wsv_nap" isFunction="1" isNested="1"></info>*/
CREATE FUNCTION [dbo].[LA_f_PayerPlatform_Sel]
(
)
RETURNS TABLE
AS
/*
	Created: 20250319@Eddie
	DB: DBLIC-bodb_Licensee
	Task: Get Payer Platform

	Revisions:
		- 20250319@Eddie: Initialize Function [RedmineID: #217740]
*/

RETURN
	SELECT PlatformId, PlatformName
	FROM (
		VALUES
			(1, N'Saba Sports')
			,(2, N'SabaPlay')
			,(3, N'SabaSports&SabaPlay')
	) AS Payer_Plarform (PlatformId, PlatformName)
GO