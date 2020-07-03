/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_GroupMinFee_AvailablePartyListSel]
	@GroupMinFeeId	SMALLINT = 0,
	@FromDate	DATE = NULL, 
	@ToDate		DATE = NULL
AS
/*  
	 Created: 20200702@Mason [#134492]
	 Task : Get available parties for group min fee
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20200702@Mason: Implement Group Min Fee [#134492]

	 Explannation:
*/
BEGIN
	SET NOCOUNT ON

	DECLARE @PartyList TABLE(PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT)
	DECLARE @PartySettings TABLE(GroupMinFeeId INT, PartyId INT, ProductId INT)

	INSERT INTO @PartyList(PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel

	INSERT INTO @PartySettings(GroupMinFeeId, PartyId)
	SELECT DISTINCT h.GroupMinFeeID, a.PartyId
	FROM dbo.LA_GroupMinFeeHeader h WITH(NOLOCK)
		INNER JOIN dbo.LA_GroupMinFeeAssignment a WITH(NOLOCK) ON a.GroupMinFeeID = h.GroupMinFeeID
	WHERE (@FromDate IS NULL OR @FromDate <= h.ToDate) AND (@ToDate IS NULL OR @ToDate >= h.FromDate)
			AND (@GroupMinFeeId = 0 OR h.GroupMinFeeID = @GroupMinFeeId)
		
	--list of payer not in group
	SELECT p.PartyId, PartyName, BrandName
	FROM @PartyList p
	WHERE p.PartyId NOT IN (SELECT PartyId 
							FROM @PartySettings)
		AND p.ParentId NOT IN (0, 999)
		
	UNION

	--list of payer in group
	SELECT p.PartyId, PartyName, BrandName
	FROM @PartyList p
	WHERE p.PartyId IN (SELECT PartyId 
						FROM @PartySettings p1)
		AND p.ParentId NOT IN (0, 999)
END
GO