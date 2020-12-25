/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_ChargeRateSettingInfoSel]
@PartyIds			VARCHAR(4000)
AS
/*
	Created: 20190625@Parsons
	Task : Validate billing configuration
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190625@Parsons: Validate billing configuration [#109600]
	- 20201225@Mason: Integrate Leap Gaming Virtual Sports [#145339]
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @CreditLicensees AS TABLE(PartyId INT)
	INSERT INTO @CreditLicensees SELECT PartyId FROM dbo.OAS_PartyDetail WITH(NOLOCK) WHERE IsDeposit = 0

	SELECT p.PartyId, p.PartyName, p.PartyType, ci.FromDate, ci.ToDate, 
		ISNULL(ci.ProductId, -1)	AS ProductId, 
		ISNULL(ci.Rate, 0)			AS Rate, 
		ISNULL(ci.FromParty, 0)		AS FromParty, 
		ISNULL(ci.ToParty, 0)		AS ToParty,
		ISNULL(ci.ChargeType, 0)	AS ChargeType,
		ISNULL(ci.ChargeID, 0)		AS ChargeID,
		ISNULL(cs.ChargeID, 0)		AS SystemMappingChargeId,
		(SELECT COUNT(ivs.ToPartyId)
			FROM LA_InvoiceSetting ivs WITH(NOLOCK)
			WHERE ci.FromParty IS NOT NULL
				  AND ci.FromParty = ivs.FromPartyId 
				  AND ci.ProductID = ivs.ProductId) AS PartyBillingCount
	FROM dbo.OAS_Party p WITH(NOLOCK) 
	LEFT JOIN dbo.OAS_ChargeInfo ci WITH(NOLOCK) ON p.PartyID = ci.FromParty
	LEFT JOIN LA_ChargeInfo_SystemMapping cs WITH(NOLOCK) ON ci.ChargeID = cs.ChargeID AND cs.SystemID = 2
	WHERE p.PartyId IN (SELECT val FROM dbo.strSplit(@PartyIds,','))
		AND p.PartyType IN (1,5) -- 1-official, 5-non-offcial
		AND (ci.ChargeType IS NULL OR ci.ChargeType NOT IN (2, 3)) -- odd type & type no longer use
		AND (ci.ToParty IS NULL OR ci.ToParty IN (SELECT bg.PartyID FROM LA_f_BillingGroupSel() bg))
		AND p.PartyID NOT IN (SELECT bg.PartyID FROM LA_f_BillingGroupSel() bg)
		AND p.PartyID NOT IN (SELECT cl.PartyId FROM @CreditLicensees cl)
END
GO