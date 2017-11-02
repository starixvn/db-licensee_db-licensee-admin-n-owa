ALTER PROCEDURE [dbo].[LA_CumulativeRebateGroupInfoSel]    
AS  
/*
Header:  
	Created: 2017.11.02 - Bruce.bui
	Task : Select rebate group info
	DB: DB052.bodb_Licensee  
     
Revisions:   
Example:  
	USE bodb_licensee   
	EXEC [LA_CumulativeRebateGroupInfoSel]   
*/  
BEGIN  
	SET NOCOUNT ON  
   
	DECLARE @RebateGroup TABLE(Id INT, [Name] NVARCHAR(200), ParentId INT)
	INSERT INTO @RebateGroup(Id, [Name], ParentId)
	(
		SELECT RebateGroupHeaderId, GroupName, 0
		FROM dbo.LA_RebateGroupHeader h WITH(NOLOCK)
		WHERE h.RebateGroupHeaderId IN (
			SELECT DISTINCT RebateGroupHeaderId
			FROM dbo.LA_RebateGroupDetail d WITH(NOLOCK)
			WHERE d.[Status] = 'Active'
		)
	)

	INSERT INTO @RebateGroup(Id, [Name], ParentId)
	(
		SELECT a.RebateGroupAssignmentId + 10000, p.PartyName, a.RebateGroupHeaderId
		FROM dbo.LA_RebateGroupAssignment a WITH(NOLOCK)
		INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON a.PartyId=p.PartyID
		WHERE a.[Status] = 'Active' 
			AND a.RebateGroupHeaderId IN (SELECT Id FROM @RebateGroup)
	)

	SELECT * FROM @RebateGroup
END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_CumulativeRebateGroupInfoSel] TO [vnteam]
GO

GRANT EXECUTE ON [dbo].[LA_CumulativeRebateGroupInfoSel] TO bodbAdminNet
GO