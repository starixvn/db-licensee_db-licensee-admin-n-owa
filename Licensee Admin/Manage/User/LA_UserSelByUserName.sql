USE [bodb_licensee]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[LA_UserSelByUserName]
	@Username	 varchar(50),
	@GroupID	 int = 0
AS
/*  
 * Created: 20140820@Florent
 * Task : get user by User Name
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:   
    - 20141022@Florent: add column 'UserSalt'
 Param's Explanation:
	
*/
SET NOCOUNT ON

SET @Username = LTRIM(RTRIM(ISNULL(@Username,'')))

BEGIN
	SELECT
		u.UserID,
		u.UserName,
		u.UserSalt,
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
		AND ((@Username='') OR (@Username<>'' AND u.Username = @Username))
	ORDER BY g.GroupName
END
END
GO
GRANT VIEW DEFINITION ON [dbo].[LA_UserSelByUserName] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_UserSelByUserName] TO bodbAdminNet 

