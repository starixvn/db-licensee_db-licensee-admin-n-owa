USE bodb_licensee
GO

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
		SELECT DISTINCT h.RebateGroupHeaderId, h.GroupName, 0
		FROM dbo.LA_RebateGroupHeader h WITH(NOLOCK)
		INNER JOIN dbo.LA_RebateGroupAssignment a WITH(NOLOCK) ON a.RebateGroupHeaderId=h.RebateGroupHeaderId
		INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON a.PartyId=p.PartyID -- remove empty group
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

	;WITH Single AS (
		SELECT g1.Id, g1.ParentId, g2.[Name] + '('+g1.[Name]+')' AS GroupName -- group has 1 party then concat payername and group name
		FROM @RebateGroup g1
		INNER JOIN @RebateGroup g2 ON g1.ParentId = g2.Id
		WHERE g2.ParentId = 0 AND g2.Id IN (
			SELECT ParentId FROM @RebateGroup g WHERE g.ParentId > 0
			GROUP BY ParentId HAVING COUNT(ParentId) = 1
		)) 
	MERGE @RebateGroup rg
	USING Single s ON s.ParentId = rg.Id OR s.Id = rg.Id
	WHEN MATCHED AND rg.ParentId = 0 THEN UPDATE SET rg.[Name] = s.GroupName
	WHEN MATCHED AND rg.ParentId > 0 THEN DELETE;

	SELECT * FROM @RebateGroup WHERE Id > 0

END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_CumulativeRebateGroupInfoSel] TO [vnteam]
GO

GRANT EXECUTE ON [dbo].[LA_CumulativeRebateGroupInfoSel] TO bodbAdminNet
GO