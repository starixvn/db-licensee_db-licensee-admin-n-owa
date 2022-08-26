/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE [dbo].[LA_LicenseeGroupSel]
AS
/*  
	 Created: 20190514@Bruce[#111587]
	 Task : Manage licensee group
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20190514@Bruce: Create SP
		- 20220817@Malcolm: Add PathCode [RedmineId : #176437]
*/

BEGIN
	SET NOCOUNT ON
	
	SELECT c.GroupId, c.GroupName, ISNULL(p.GroupId, 0) AS ParentId, c.PathCode
	FROM dbo.LA_CombinedGroup c WITH(NOLOCK)
	LEFT JOIN dbo.LA_CombinedGroup p WITH(NOLOCK) ON c.PathCode LIKE ('%/' + CAST(p.GroupId AS VARCHAR(5)) + '/')
	WHERE c.PathCode = '/'			-- top level
		OR p.GroupId IS NOT NULL	-- any child has valid parent id
END
GO