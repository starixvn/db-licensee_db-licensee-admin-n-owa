/*<info serverAlias="DBCUST-bodb_licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

ALTER PROCEDURE [dbo].[LA_UserSelByUserID]
	@UserID		int,
	@GroupID	int = 0
AS
/*
	Created: 20140820@Florent
	Task : get user by UserID
	DB: DBCUST.bodb_Licensee  
	
	Revisions:
		- 20140820@Florent: Initialize SP

	Param's Explanation:
*/
SET NOCOUNT ON

BEGIN
	SELECT
		u.UserID,
		u.UserName,
		u.DisplayName,		
		u.StatusID IsActive,
		u.CreatedDate,
		u.ModifiedDate,
		u.Creator,
		isnull(p.username,'') AS CreatorName,
		g.GroupID,
		g.GroupName
	FROM
		dbo.LA_User AS u WITH(NOLOCK)
		INNER JOIN dbo.LA_Group AS g WITH(NOLOCK) ON u.GroupID=g.GroupID
		LEFT JOIN dbo.LA_User AS p WITH (NOLOCK) ON u.creator = p.userID
	WHERE	
		((@GroupID=0) OR (@GroupID<>0 AND g.GroupID = @GroupID))
		AND u.UserID = @UserID
	ORDER BY g.GroupName
END
GO