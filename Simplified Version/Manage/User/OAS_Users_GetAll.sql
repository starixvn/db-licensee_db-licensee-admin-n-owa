/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE [bodb_Licensee]
GO

ALTER PROCEDURE [dbo].[OAS_Users_GetAll]
AS

/*
	Created by: [20111512@Kos]
	Task: Get all users
	DB: DBCUST.bodb_Licensee
	
	Revisions:
		- 20190510@Percy: Move SP to DBCUST.bodb_Licensee [RedmineID: #103658]
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
		 u.CreatedDate,
		 u.ModifiedDate,
		 u.Creator,
		 ISNULL(p.Username, '') AS CreatorName
	FROM dbo.OAS_Users AS u WITH (NOLOCK)
		 LEFT JOIN dbo.OAS_Users AS p WITH (NOLOCK) ON u.Creator = p.UserID
END
GO