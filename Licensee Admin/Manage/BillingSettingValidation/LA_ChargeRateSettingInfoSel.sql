/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
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
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190625@Parsons: Validate billing configuration [#109600]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @CreditLicensees AS TABLE(PartyId INT)
	DECLARE @Deposits AS TABLE(ParentId INT)

	INSERT INTO @CreditLicensees SELECT PartyId FROM dbo.OAS_PartyDetail WITH(NOLOCK) WHERE IsDeposit = 0
	INSERT INTO @Deposits(ParentId) VALUES(1), (9), (11), (98)

	SELECT p.PartyId, p.PartyName, p.PartyType, ci.FromDate, ci.ToDate, 
		ISNULL(ci.ProductId, -1)		AS ProductId, 
		ISNULL(ci.Rate, 0)			AS Rate, 
		ISNULL(ci.FromParty, 0)		AS FromParty, 
		ISNULL(ci.ToParty, 0)		AS ToParty,
		ISNULL(ci.ChargeType, 0)	AS ChargeType,
		ISNULL(ci.ChargeID, 0)		AS ChargeID,
		ISNULL(cs.ChargeID, 0)		AS SystemMappingChargeId
	FROM dbo.OAS_Party p WITH(NOLOCK) 
	LEFT JOIN dbo.OAS_ChargeInfo ci WITH(NOLOCK) ON p.PartyID = ci.FromParty
	LEFT JOIN LA_ChargeInfo_SystemMapping cs WITH(NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
	WHERE (@PartyId = 0 OR @PartyId = p.PartyID)
		AND p.PartyType IN (1,5) -- 1-official, 5-non-offcial
		AND (ci.ChargeType IS NULL OR ci.ChargeType NOT IN (2, 3)) -- odd type & type no longer use
		AND (ci.ToParty IS NULL OR ci.ToParty IN (SELECT ParentId FROM @Deposits))
		AND PartyID NOT IN (SELECT ParentId FROM @Deposits)
		AND PartyID NOT IN (SELECT cl.PartyId FROM @CreditLicensees cl)
END
GO