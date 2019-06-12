/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_LicenseeGroupDel]
	@GroupId INT
AS
/*  
	 Created: 20190514@Bruce[#111587]
	 Task : Manage licensee group
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20190514@Bruce: Create SP
*/

BEGIN
	SET NOCOUNT ON
	
	DELETE dbo.LA_CombinedGroup WITH (ROWLOCK, UPDLOCK) WHERE GroupId = @GroupId
	DELETE dbo.LA_CombinedGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE GroupId = @GroupId
END
GO