/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_licensee]
GO

ALTER PROCEDURE [dbo].[LA_PayerGroupPartyListSel] 
	@PayerGroupId SMALLINT = 0		
	, @UserId INT = 0
	, @FunctionId INT = 0
AS
/*  
	 Created: 20150423@Florent
	 Task : Get list payer list
	 DB: DBCUST.bodb_Licensee
	 
	 Revisions:     
		- 20180716@bruce: add new group TEST for credit [#98126]
		- 20180327@Parsons: Apply min fee rule for discount calculation [#109997]   
		
	 Params:
		+ UserID : 
			- 0 get list Party of All user
		+ FunctionID : 
			- 0 get list Party when config in manage User	
	exec [LA_PayerGroupPartyListSel] 54
*/
BEGIN
	SET NOCOUNT ON	
	 
	DECLARE @CurrenDate DATE = GETDATE(), @MinFeeType TINYINT =  1
	DECLARE @PartyList TABLE(PartyId INT, PartyName VARCHAR(100), BrandName VARCHAR(100), ParentId INT, TotalMinFee MONEY)
	
	INSERT INTO @PartyList(PartyId, PartyName, BrandName, ParentId)
	EXEC dbo.LA_PartyListSel @UserId = @UserId, @FunctionId = @FunctionId
	DELETE @PartyList WHERE ParentId IN (0, 999)

	;WITH cte_MinFee AS(
		SELECT p.PartyId, SUM(ISNULL(FeeAmount, 0)) AS TotalMinFee 
		FROM @PartyList p
		INNER JOIN LA_MinFee mf WITH(NOLOCK) ON p.PartyId = mf.PartyId 
		WHERE mf.FeeTypeId = @MinFeeType AND @CurrenDate BETWEEN mf.FromDate AND mf.ToDate
		GROUP BY p.PartyId)
	UPDATE p
	SET p.TotalMinFee = ISNULL(mf.TotalMinFee, 0)
	FROM @PartyList p
		LEFT JOIN cte_MinFee mf ON p.PartyId = mf.PartyId 

	DECLARE @PartyInGroup TABLE (PartyId INT, PartyGroupId SMALLINT)
	INSERT INTO @PartyInGroup(PartyId, PartyGroupId)
	SELECT DISTINCT a.PartyId, a.PartyGroupId
	FROM dbo.LA_PartyGroupAssignment a WITH(NOLOCK)
	WHERE a.PartyGroupId = @PayerGroupId 		

	--list of payers not in group
	SELECT p.PartyId, p.PartyName, p.BrandName, p.TotalMinFee
	FROM @PartyList p
		INNER JOIN dbo.OAS_Party pp WITH (NOLOCK) ON p.PartyId = pp.PartyID AND pp.PartyType IN (1)
	WHERE p.PartyId NOT IN (SELECT PartyId FROM @PartyInGroup)

	--list of payer in group	
	SELECT p.PartyId, p.PartyName, p.BrandName, p.TotalMinFee
	FROM @PartyList p
		INNER JOIN dbo.OAS_Party pp WITH (NOLOCK) ON p.PartyId = pp.PartyID AND pp.PartyType IN (1)
		INNER JOIN @PartyInGroup ppp ON p.PartyId = ppp.PartyId
END
GO