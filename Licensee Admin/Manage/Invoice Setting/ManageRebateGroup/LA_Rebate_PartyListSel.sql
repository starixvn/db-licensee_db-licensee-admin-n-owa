/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Rebate_PartyListSel]
	@GroupId	SMALLINT = 0,
	@FromDate	DATE = NULL, 
	@ToDate		DATE = NULL
AS
/*  
	 Created: 20180529@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DBLIC.bodb_licensee   

	 Revisions:  
		- 20180529@Parsons: Get list payer list [#94282]

	 Params:
		 + UserID : 
			- 0 get list Party of All user
		 + FunctionID : 
			- 0 get list Party when config in manage User	
	 Explannation:
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @PartyList TABLE(PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT)
	DECLARE	@RebateGroupType INT = 2
	
	INSERT INTO @PartyList(PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	DECLARE @PartiesInAnyGroup TABLE (PartyId INT, DiscountId SMALLINT)
	INSERT INTO @PartiesInAnyGroup(PartyId, DiscountId)
	SELECT DISTINCT a.PartyId, a.DiscountGroupId
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
		INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId			
	WHERE h.DiscountGroupType = @RebateGroupType
		AND (@FromDate IS NULL OR @FromDate <= h.ToDate)
		AND (@ToDate IS NULL OR @ToDate >= h.FromDate)			

	--list of payers not in group
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