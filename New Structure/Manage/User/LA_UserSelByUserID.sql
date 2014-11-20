USE [bodb_licensee]
GO
/****** Object:  StoredProcedure [dbo].[LA_UserSelByUserID]    Script Date: 9/8/2014 5:02:56 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/****** Object:  Stored Procedure dbo.OA_UsersGetAll    Script Date: 10/21/2011 7:48:20 PM ******/
ALTER PROCEDURE [dbo].[LA_UserSelByUserID]
	@UserID	 int,
	@GroupID	 int = 0
AS
/*  
 * Created: 20140820@Florent
 * Task : get user by UserID
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:   
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
GRANT VIEW DEFINITION ON [dbo].[LA_UserSelByUserID] TO [vnteam] 
GRANT EXECUTE ON [dbo].[LA_UserSelByUserID] TO bodbAdminNet 

