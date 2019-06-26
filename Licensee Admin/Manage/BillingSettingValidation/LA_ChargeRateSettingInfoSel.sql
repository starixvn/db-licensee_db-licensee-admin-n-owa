/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_ChargeRateSettingInfoSel]
@PartyId INT = 0
AS
/*
	Created: 20190625@Parsons
	Task : Validate billing configuration
	DB: DB052.bodb_Licensee

	Revisions:
	- 20190625@Parsons: Validate billing configuration [#109600]
*/
BEGIN
	SET NOCOUNT ON

	SELECT p.PartyID, p.PartyName, p.PartyType, FromDate, ToDate, ProductID, 
				ISNULL(Rate, 0)			AS Rate, 
				ISNULL(FromParty, 0)	AS FromParty, 
				ISNULL(ToParty, 0)		AS ToParty,
				ISNULL(ChargeType, 0)	AS ChargeType,
				ISNULL(SystemID, 0)		AS SystemID
	FROM OAS_Party p WITH(NOLOCK) 
	LEFT JOIN OAS_ChargeInfo ci WITH(NOLOCK) ON p.PartyID = ci.FromParty
	LEFT JOIN LA_ChargeInfo_SystemMapping cs WITH(NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
	WHERE (@PartyId = 0 OR @PartyId = p.PartyID) AND (ToDate IS NULL OR ToDate >= GETDATE())
		  AND PartyID NOT IN (1,9,11,98) 	
END
GO