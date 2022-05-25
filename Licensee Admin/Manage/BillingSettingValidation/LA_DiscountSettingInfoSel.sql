/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_DiscountSettingInfoSel]
	@PartyIds VARCHAR(4000)
AS

/*
	Created: 20190711@Parsons
	Task : Validate billing configuration
	DB: DBCUST.bodb_Licensee

	Revisions:
		- 20190711@Parsons: Validate billing configuration [#109600]
		- 20220210@Percy: Support Tier Rebate [RedmineID: #163495]
		- 20220506@Percy: Change way get discount group type [RedmineID: #1732342]
*/

BEGIN
	SET NOCOUNT ON
	
	DECLARE @CreditLicensees AS TABLE(PartyId INT)
	INSERT INTO @CreditLicensees SELECT PartyId FROM dbo.OAS_PartyDetail WITH(NOLOCK) WHERE IsDeposit = 0

	SELECT p.PartyID, PartyName, PartyType, dgd.Rate, dgp.ProductID
		   , ISNULL(dg.DiscountGroupId, 0) AS DiscountGroupId, dg.CurrencyId AS CurrencyId, dg.DiscountGroupName
		   , ISNULL(DiscountGroupType, 0) AS DiscountGroupType
		   , CalculationType
		   , dg.FromDate
		   , dg.ToDate
		   , dgd.FromAmount
		   , dgd.ToAmount
		   , dgd.DiscountGroupDetailId
		   , dga.IsApplyDiscount
	FROM OAS_Party p WITH(NOLOCK) 
		LEFT JOIN LA_DiscountGroupAssignment dga WITH(NOLOCK) ON p.PartyID = dga.PartyId
		LEFT JOIN LA_DiscountGroupHeader dg WITH(NOLOCK) ON dga.DiscountGroupId = dg.DiscountGroupId
		LEFT JOIN LA_DiscountGroupProduct dgp WITH(NOLOCK) ON dga.DiscountGroupId = dgp.DiscountGroupId
		LEFT JOIN LA_DiscountGroupDetail dgd WITH(NOLOCK) ON dga.DiscountGroupId = dgd.DiscountGroupId
	WHERE p.PartyId IN (SELECT val FROM dbo.strSplit(@PartyIds,','))
			AND p.PartyID NOT IN (SELECT bg.PartyID FROM LA_f_BillingGroupSel() bg)
			AND p.PartyID NOT IN (SELECT cl.PartyId FROM @CreditLicensees cl)
			AND (dg.DiscountGroupType IS NULL OR dg.DiscountGroupType IN (1, 3, 11, 13)) -- Discount
END
GO