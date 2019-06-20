/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_BillerSettingInfoSel]
@PartyId INT = 0
AS
/*
	Created: 20190618@Parsons
	Task : Validate billing configuration
	DB: DB052.bodb_Licensee

	Revisions:
	- 20190618@Parsons: Validate billing configuration [#109600]
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT b.BillerName, Address1, CASE WHEN ISNULL(DATALENGTH(Logo), 0) > 0 THEN 1 ELSE 0 END HasLogo, ISNULL(p.PartyID, 0) AS PartyId
	FROM LA_BillerInfo b WITH(NOLOCK)
	LEFT JOIN OAS_Party p WITH(NOLOCK) ON b.PartyId = p.PartyID AND p.PartyType = 4 -- Biller
	WHERE @PartyId = 0 or b.PartyId = @PartyId
END
GO