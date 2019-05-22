/*<info serverAlias="DBLIC-bodb_licensee" executers="bodbAdminNet" viewers="" isFunction="0" isNested="0"></info>*/
USE bodb_licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_LicenseeGroupUpd]
	@GroupName	VARCHAR(50),
	@ParentId	INT,
	@PartyData	VARCHAR(4000),
	@GroupId	INT,
	@ErrMsg		VARCHAR(200) = '' OUTPUT,
	@ErrCode	int = 0 OUTPUT
AS
/*  
	 Created: 20190515@Mason[#111587]
	 Task : Manage licensee group
	 DB: DBLIC.bodb_licensee   

	 Revisions:  
		- 20190515@Mason: Create SP

*/

BEGIN
	SET NOCOUNT ON
	
	DECLARE @PathCode VARCHAR(50) = '/'
	DECLARE @ParentIdString VARCHAR(5) = CAST(@ParentId AS VARCHAR(5))

	IF @GroupId = 0
	BEGIN
		SET @ErrCode = 1
		SET @ErrMsg = 'GROUP ID NOT EXISTS'
		RETURN;
	END
	
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
	
	UPDATE dbo.LA_CombinedGroup 
		SET GroupName = @GroupName, PathCode = @PathCode
	WHERE GroupId = @GroupId
	
	DECLARE @xml xml = @PartyData
	DECLARE  @TemporaryTable TABLE( GroupId int, PartyId int, GroupType tinyint);
	INSERT INTO @TemporaryTable (GroupId, PartyId, GroupType)
	SELECT @GroupId,
		t.Party.value('@PartyId', 'int') as PartyId,
		t.Party.value('@GroupType', 'tinyint') as GroupType
	FROM @xml.nodes('/Root/Party') t(Party)
	
	MERGE INTO dbo.LA_CombinedGroupAssignment AS TAB1
	USING @TemporaryTable As TAB2 ON TAB1.PartyId = TAB2.PartyId AND TAB1.GroupId = TAB2.GroupId
	WHEN NOT MATCHED BY SOURCE AND TAB1.GroupId = @GroupId THEN 
		DELETE
	WHEN NOT MATCHED BY TARGET THEN
		INSERT(GroupId, PartyId, GroupType) VALUES(TAB2.GroupId, TAB2.PartyId, TAB2.GroupType);

	SET @ErrCode = 0
	SET @ErrMsg = ''
END
