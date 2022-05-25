/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
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
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20180529@Parsons: Get list payer list [#94282]
		- 20220210@Percy: Support Tier Rebate [RedmineID: #163495]
		- 20220506@Percy: Add new rebate type: Rebate on Licensee WL [RedmineID: #1732342]

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
	INSERT INTO @PartyList(PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	DECLARE @DiscountGroupType TINYINT = 0
	SELECT  @DiscountGroupType = DiscountGroupType FROM dbo.LA_DiscountGroupHeader WITH (NOLOCK) WHERE DiscountGroupId = @GroupId

	IF @GroupId <> 0 AND @DiscountGroupType IN (2, 22) AND @FromDate IS NOT NULL AND @ToDate IS NOT NULL
	BEGIN
		DECLARE @ExistPartyList TABLE (PartyId INT)
		INSERT INTO @ExistPartyList (PartyId)
		SELECT DISTINCT a.PartyId
		FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
			INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId			
		WHERE h.DiscountGroupType IN (2, 22) -- Rebate on Lic Fee/WL
			AND h.DiscountGroupType <> @DiscountGroupType
			AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate

		DELETE p
		FROM @PartyList p
			INNER JOIN @ExistPartyList ep ON p.PartyId = ep.PartyId
	END

	-- Return party list
	SELECT PartyId, PartyName, BrandName
	FROM @PartyList
	WHERE ParentId IN (1, 9, 11, 98) -- Deposit
END
GO