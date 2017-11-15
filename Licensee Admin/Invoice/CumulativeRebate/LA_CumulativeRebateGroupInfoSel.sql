/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="vnteam" isFunction="0" isNested="0"></info>*/

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

	DECLARE @RebateGroup TABLE(Id INT, [Name] NVARCHAR(200))
	INSERT INTO @RebateGroup(Id, [Name])
	(
		SELECT DISTINCT h.SettingGroupHeaderId, h.GroupName
		FROM dbo.LA_SettingGroupHeader h WITH(NOLOCK)
		INNER JOIN dbo.LA_SettingGroupAssignment a WITH(NOLOCK) ON a.SettingGroupHeaderId=h.SettingGroupHeaderId
		INNER JOIN dbo.OAS_Party p WITH(NOLOCK) ON a.PartyId=p.PartyID -- remove empty group
		WHERE h.SettingGroupHeaderId IN (
			SELECT DISTINCT SettingGroupHeaderId
			FROM dbo.LA_SettingGroupDetail d WITH(NOLOCK)
			WHERE d.[Status] = 'Active'
		)
	)

	SELECT * FROM @RebateGroup WHERE Id > 0

END
GO

GRANT VIEW DEFINITION ON [dbo].[LA_CumulativeRebateGroupInfoSel] TO [vnteam]
GO

GRANT EXECUTE ON [dbo].[LA_CumulativeRebateGroupInfoSel] TO bodbAdminNet
GO