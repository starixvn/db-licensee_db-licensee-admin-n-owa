/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_DiscountSettingInfoSel]
@PartyId INT = 0
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

	SELECT p.PartyID, PartyName, PartyType, dgd.Rate, dgp.ProductID
		   , ISNULL(dg.DiscountGroupId, 0) AS DiscountGroupId, dg.CurrencyId AS CurrencyId
		   , ISNULL(DiscountGroupType, 0) AS DiscountGroupType
		   , ISNULL(CalculationType, 0) AS CalculationType
		   , MAX(dg.FromDate) AS FromDate, MAX(dg.ToDate) AS ToDate
	FROM OAS_Party p WITH(NOLOCK) 
		LEFT JOIN LA_DiscountGroupAssignment dga WITH(NOLOCK) ON p.PartyID = dga.PartyId
		LEFT JOIN LA_DiscountGroupHeader dg WITH(NOLOCK) ON dga.DiscountGroupId = dg.DiscountGroupId
		LEFT JOIN LA_DiscountGroupProduct dgp WITH(NOLOCK) ON dga.DiscountGroupId = dgp.DiscountGroupId
		LEFT JOIN LA_DiscountGroupDetail dgd WITH(NOLOCK) ON dga.DiscountGroupId = dgd.DiscountGroupId
	WHERE (@PartyId = 0 OR @PartyId = p.PartyID) 
			AND (dg.ToDate IS NULL OR dg.ToDate >= GETDATE())
			AND p.PartyID NOT IN (1,9,11,98, -- ParentId of deposit
										25,30,324) -- Credit 	
			AND (dg.DiscountGroupType IS NULL OR dg.DiscountGroupType != 2) -- Rebate
	GROUP BY p.PartyID, PartyName, PartyType, dgd.Rate, dgp.ProductID
			, ISNULL(dg.DiscountGroupId, 0)
			, dg.CurrencyId
			, ISNULL(DiscountGroupType, 0) 
			, ISNULL(CalculationType, 0) 
END
GO