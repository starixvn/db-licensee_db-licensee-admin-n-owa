/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_Discount_AvailablePartyListSel]
	@GroupId	SMALLINT = 0,
	@FromDate	DATE = NULL, 
	@ToDate		DATE = NULL,
	@ProductIds	NVARCHAR(512) = ''
AS
/*  
	 Created: 20180702@Parsons [#94282]
	 Task : Enhance Manage Discount group function to support more discount schemes
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20180702@Parsons: Get payer list [#94282]
		- 20220509@Danny: Use String_split built-in function [RemineID: #171831]
		- 20220206@Danny: Return more party detail (SuspendedDate, TerminatedDate) [RedmineID: #169160]

	 Explannation:
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @PartyList TABLE(PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT, SuspendedDate DATE, TerminatedDate DATE)
	DECLARE @PartySettings TABLE(DiscountGroupId INT, PartyId INT, ProductId INT)

	INSERT INTO @PartyList(PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	UPDATE p
	SET p.SuspendedDate = op.SuspendedDate,
		p.TerminatedDate = op.TerminatedDate
	FROM @PartyList p
	INNER JOIN dbo.OAS_partydetail op WITH(NOLOCK) ON p.PartyId = op.PartyId

	INSERT INTO @PartySettings(DiscountGroupId, PartyId, ProductId)
	SELECT DISTINCT h.DiscountGroupId, a.PartyId, dp.ProductId
	FROM dbo.LA_DiscountGroupHeader h WITH(NOLOCK)
		INNER JOIN dbo.LA_DiscountGroupAssignment a WITH(NOLOCK) ON a.DiscountGroupId = h.DiscountGroupId
		INNER JOIN dbo.LA_DiscountGroupProduct dp WITH(NOLOCK) ON dp.DiscountGroupId = h.DiscountGroupId
	WHERE h.DiscountGroupType IN (1,3,11,13)
		AND (@FromDate IS NULL OR @FromDate <= h.ToDate)
		AND (@ToDate IS NULL OR @ToDate >= h.FromDate)
		
	--list of payer not in group
	SELECT p.PartyId, PartyName, BrandName, SuspendedDate, TerminatedDate
	FROM @PartyList p
	WHERE p.PartyId NOT IN (SELECT PartyId 
							FROM @PartySettings
							WHERE ProductId IN (SELECT value FROM STRING_SPLIT(@ProductIds, ',') WHERE value != ''))
			AND p.ParentId NOT IN (999, 0)

	UNION

	--list of payer in group
	SELECT p.PartyId, PartyName, BrandName, SuspendedDate, TerminatedDate
	FROM @PartyList p
	WHERE p.PartyId IN (SELECT PartyId 
						FROM @PartySettings p1
						WHERE DiscountGroupId = @GroupId 
						AND NOT EXISTS (SELECT p2.PartyId 
									FROM @PartySettings p2 
									WHERE p2.PartyId = p1.PartyId AND DiscountGroupId != @GroupId 
									AND ProductId IN (SELECT value FROM STRING_SPLIT(@ProductIds, ',') WHERE value != '')))
END
GO