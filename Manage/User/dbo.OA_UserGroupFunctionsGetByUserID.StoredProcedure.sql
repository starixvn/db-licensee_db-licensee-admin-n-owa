ALTER PROCEDURE [dbo].[OA_UserGroupFunctionsGetByUserID]
	@UserID int
AS
/*  
 * Created: 20110920@Elly
 * Task : Get list of functions and its policy of a UserID and group of that User
 * DB: DB052.bodb_Licensee  
 *  
 * Revisions:     
*/  

SET NOCOUNT ON

SELECT	
	f.FunctionID,
	--LicenseeID,
	--ResellerID,	
	f.FunctionName,
	Policy,
	f.ParentID,
	f.ParentName	
FROM
	(SELECT FunctionID, Policy
	FROM dbo.OA_UserFunctions AS uf WITH(NOLOCK)
	WHERE UserID = @UserID
		
	UNION ALL
	
	SELECT FunctionID, Policy
	FROM dbo.OA_GroupFunctions AS gf WITH(NOLOCK)
		INNER JOIN dbo.OA_Users AS u WITH(NOLOCK) ON u.UserID=@UserID AND u.GroupId=gf.GroupID
	) AS uf
	INNER JOIN dbo.OA_Functions AS f WITH(NOLOCK) ON f.FunctionID=uf.FunctionID

GO
GRANT EXECUTE ON [dbo].[OA_UserGroupFunctionsGetByUserID] TO [bodbAdminNet]
GO
GRANT VIEW DEFINITION ON [dbo].[OA_UserGroupFunctionsGetByUserID] TO [vnteam]
 