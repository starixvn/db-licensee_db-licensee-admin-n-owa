/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="1" isNested="0"></info>*/
USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER PROCEDURE [dbo].[LA_PayerGroupPartyListSel] 
	@PayerGroupId SMALLINT = 0		
	, @UserId INT = 0
	, @FunctionId INT = 0
AS
/*  
	 Created: 20150423@Florent
	 Task : Get list payer list
	 DB: DB052.bodb_Licensee
	 Revisions:     
		- 20180716@bruce: add new group TEST for credit [#98126]
		
	 Params:
		+ UserID : 
			- 0 get list Party of All user
		+ FunctionID : 
			- 0 get list Party when config in manage User	
	exec [LA_PayerGroupPartyListSel] 10
*/
BEGIN
	SET NOCOUNT ON	

	DECLARE @PartyList TABLE(PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT)
	
	INSERT INTO @PartyList(PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel @UserId = @UserId, @FunctionId = @FunctionId

	DECLARE @PartyIds TABLE (PartyId INT, PartyGroupId SMALLINT)

	INSERT INTO @PartyIds(PartyId, PartyGroupId)
		SELECT DISTINCT a.PartyId, a.PartyGroupId
		FROM dbo.LA_PartyGroupAssignment a WITH(NOLOCK)
			INNER JOIN dbo.LA_PartyGroup h WITH(NOLOCK) ON a.PartyGroupId = h.PartyGroupId		

	--list of payers not in group
	SELECT p.PartyId, p.PartyName, p.BrandName--, ParentId
	FROM @PartyList p
		INNER JOIN dbo.OAS_Party pp WITH (NOLOCK) ON p.PartyId = pp.PartyID AND pp.PartyType IN (1)
	WHERE p.ParentId NOT IN (999) 
		AND p.PartyId NOT IN (999)
		AND p.PartyId NOT IN (SELECT PartyId FROM @PartyIds)

	--list of payer in group	
	BEGIN
		SELECT p.PartyId, pp.PartyName, ppp.BrandName
		FROM @PartyIds p
			INNER JOIN dbo.OAS_Party pp WITH(NOLOCK) ON p.PartyId = pp.PartyID
			INNER JOIN dbo.OAS_PartyDetail ppp WITH(NOLOCK) ON p.PartyId = ppp.PartyID
		WHERE p.PartyGroupId = @PayerGroupId
	END
	
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_PayerGroupPartyListSel] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_PayerGroupPartyListSel] TO bodbAdminNet 
Go