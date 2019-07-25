/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_RebateSettingInfoSel]
@PartyId INT = 0
AS
/*
	Created: 20190626@Parsons
	Task : Validate billing configuration
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190626@Parsons: Validate billing configuration [#109600]
*/
BEGIN
	SET NOCOUNT ON
	
	DECLARE @CreditLicensees AS TABLE(PartyId INT)
	INSERT INTO @CreditLicensees SELECT PartyId FROM dbo.OAS_PartyDetail WITH(NOLOCK) WHERE IsDeposit = 0

	SELECT p.PartyID, PartyName, PartyType, dgd.Rate, dgp.ProductID, ISNULL(dg.DiscountGroupId, 0)	AS RebateGroupId, dg.DiscountGroupName AS RebateGroupName, dg.FromDate, dg.ToDate
	FROM OAS_Party p WITH(NOLOCK) 
		LEFT JOIN LA_DiscountGroupAssignment dga WITH(NOLOCK) ON p.PartyID = dga.PartyId
		LEFT JOIN LA_DiscountGroupHeader dg WITH(NOLOCK) ON dga.DiscountGroupId = dg.DiscountGroupId
		LEFT JOIN LA_DiscountGroupProduct dgp WITH(NOLOCK) ON dga.DiscountGroupId = dgp.DiscountGroupId
		LEFT JOIN LA_DiscountGroupDetail dgd WITH(NOLOCK) ON dga.DiscountGroupId = dgd.DiscountGroupId
	WHERE (@PartyId = 0 OR @PartyId = p.PartyID) 
			AND p.PartyID NOT IN (SELECT bg.PartyID FROM LA_f_BillingGroupSel() bg)
			AND p.PartyID NOT IN (SELECT cl.PartyId FROM @CreditLicensees cl)
			AND (dg.DiscountGroupType IS NULL OR dg.DiscountGroupType = 2) -- Rebate
END
GO