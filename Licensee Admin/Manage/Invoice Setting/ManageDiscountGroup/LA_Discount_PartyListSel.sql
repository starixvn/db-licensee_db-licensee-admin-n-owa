/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Discount_PartyListSel]
	@GroupId	SMALLINT = 0,
	@FromDate	DATE = NULL, 
	@ToDate		DATE = NULL,
	@ProductIds	NVARCHAR(512) = ''
AS
/*  
	 Created: 20180702@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DB052.bodb_licensee   

	 Revisions:  
		- 20180702@Parsons: Get payer list [#94282]

	 Explannation:
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @PartyList TABLE(PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT)

	INSERT INTO @PartyList(PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	-- Get Parties in any group
	DECLARE @PartiesInAnyGroup TABLE (PartyId INT, DiscountGroupId SMALLINT)
	INSERT INTO @PartiesInAnyGroup(PartyId, DiscountGroupId)
	SELECT DISTINCT a.PartyId, a.DiscountGroupId
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
		INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
		INNER JOIN dbo.LA_DiscountGroupProduct dp WITH(NOLOCK) ON dp.DiscountGroupId = h.DiscountGroupId
		INNER JOIN bodb02.dbo.strSplit(@ProductIds, ',') p ON dp.ProductId = p.val
	WHERE h.DiscountGroupType IN (1,3,11,13)
		AND (@FromDate IS NULL OR @FromDate <= h.ToDate)
		AND (@ToDate IS NULL OR @ToDate >= h.FromDate)

	--list of payer not in group
	SELECT p.PartyId, PartyName, BrandName
	FROM @PartyList p
	WHERE p.ParentId NOT IN (999, 0)
		AND p.PartyId NOT IN (999)
		AND p.PartyId NOT IN (SELECT PartyId FROM @PartiesInAnyGroup)

	UNION	

	--list of payer in group
	SELECT a.PartyId, pp.PartyName, ppp.BrandName
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
		INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
		INNER JOIN dbo.OAS_Party pp WITH(NOLOCK) ON a.PartyId = pp.PartyID
		INNER JOIN dbo.OAS_PartyDetail ppp WITH(NOLOCK) ON a.PartyId = ppp.PartyID
	WHERE h.DiscountGroupId = @GroupId		
END
GO