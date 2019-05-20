/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[OAS_Users_GetByUserID]
	@UserID INT
AS

/*
	Created by: [20111512@Kos]
	Task: Get user information by user ID
	DB: DBCUST.bodb_Licensee
	
	Revisions:
		- 20190510@Percy: Move SP to DBCUST.bodb_Licensee [RedmineID: #103658]
	
	Param's Explanation:
		- @UserID: User ID
*/

BEGIN
	SET NOCOUNT ON

	SELECT
		 u.UserID,
		 u.Username,
		 u.DisplayName,
		 u.Role,
		 u.IsActive,
	 	 u.IsTest,
		 u.Creator,
		 u.CreatedDate,
		 u.ModifiedDate,
		 pu.Username AS CreatorName
	FROM dbo.OAS_Users u WITH (NOLOCK)
		 INNER JOIN dbo.OAS_Users pu WITH (NOLOCK) ON u.Creator = pu.UserID
	WHERE u.UserID = @UserID
END
GO