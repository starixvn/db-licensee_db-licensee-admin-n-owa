/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_DiscountSettingInfoSel]
@PartyIds			VARCHAR(4000)
AS
/*
	Created: 20190711@Parsons
	Task : Validate billing configuration
	DB: DBCUST.bodb_Licensee

	Revisions:
	- 20190711@Parsons: Validate billing configuration [#109600]
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
		LEFT JOIN LA_DiscountGroupAssignment_UAT dga WITH(NOLOCK) ON p.PartyID = dga.PartyId
		LEFT JOIN LA_DiscountGroupHeader_UAT dg WITH(NOLOCK) ON dga.DiscountGroupId = dg.DiscountGroupId
		LEFT JOIN LA_DiscountGroupProduct_UAT dgp WITH(NOLOCK) ON dga.DiscountGroupId = dgp.DiscountGroupId
		LEFT JOIN LA_DiscountGroupDetail_UAT dgd WITH(NOLOCK) ON dga.DiscountGroupId = dgd.DiscountGroupId
	WHERE p.PartyId IN (SELECT val FROM dbo.strSplit(@PartyIds,','))
			AND p.PartyID NOT IN (1, 9, 11, 98)
			AND p.PartyID NOT IN (SELECT cl.PartyId FROM @CreditLicensees cl)
			AND (dg.DiscountGroupType IS NULL OR dg.DiscountGroupType != 2) -- Rebate
END
GO