/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE PROCEDURE [dbo].[LA_LicenseeGroupDel]
	@GroupId INT
AS
/*  
	 Created: 20190514@Bruce[#111587]
	 Task : Manage licensee group
	 DB: DBLIC.bodb_licensee   

	 Revisions:  
		- 20190514@Bruce: Create SP

*/

BEGIN
	SET NOCOUNT ON
	
	DELETE dbo.LA_CombinedGroup WHERE GroupId = @GroupId
	DELETE dbo.LA_CombinedGroupAssignment WHERE GroupId = @GroupId
END
GO
