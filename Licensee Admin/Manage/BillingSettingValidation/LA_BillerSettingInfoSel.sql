/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_BillerSettingInfoSel]
@PartyIds			VARCHAR(4000)
AS
/*
	Created: 20190618@Parsons
	Task : Validate billing configuration
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190618@Parsons: Validate billing configuration [#109600]
*/
BEGIN
	SET NOCOUNT ON
	
	SELECT b.PartyId AS BillerId, b.BillerName, Address1, 
			CASE WHEN ISNULL(DATALENGTH(Logo), 0) > 0 THEN 1 ELSE 0 END HasLogo, 
			ISNULL(p.PartyType, 0) AS PartyType
	FROM LA_BillerInfo b WITH(NOLOCK)
	LEFT JOIN OAS_Party p WITH(NOLOCK) ON b.PartyId = p.PartyID
	WHERE b.PartyId IN (SELECT val FROM dbo.strSplit(@PartyIds,','))
END
GO