/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_LicenseeGroupIns]
	@GroupName	VARCHAR(50),
	@ParentId	INT,
	@PartyData	VARCHAR(4000),
	@GroupId	INT = 0 OUTPUT,
	@ErrMsg		VARCHAR(200) = '' OUTPUT,
	@ErrCode	int = 0 OUTPUT
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
	
	DECLARE @PathCode VARCHAR(50) = '/'
	DECLARE @ParentIdString VARCHAR(5) = CAST(@ParentId AS VARCHAR(5))

	IF @ParentId > 0
	BEGIN
		SET @PathCode = (SELECT PathCode FROM dbo.LA_CombinedGroup WITH(NOLOCK) WHERE GroupId = @ParentId)
		IF @PathCode IS NULL
		BEGIN
			SET @ErrCode = 1
			SET @ErrMsg = 'Parent group (' + @ParentIdString + ') is not exist.'
			RETURN;
		END

		SET @PathCode = @PathCode + @ParentIdString + '/'
	END

	INSERT INTO dbo.LA_CombinedGroup(GroupName, PathCode) VALUES (@GroupName, @PathCode)
	SET @GroupId = SCOPE_IDENTITY()

	DECLARE @xml xml = @PartyData
	INSERT INTO dbo.LA_CombinedGroupAssignment(GroupId, PartyId, GroupType)
	SELECT @GroupId,
		t.Party.value('@PartyId', 'int'),
		t.Party.value('@GroupType', 'tinyint')
	FROM @xml.nodes('/Root/Party') t(Party)

	SET @ErrCode = 0
	SET @ErrMsg = ''
END
GO
