/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
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
	@ErrCode	int = 0 OUTPUT,
	@UserId		INT, 
	@LoginIp	VARCHAR (50)	= ''
AS
/*  
	 Created: 20190515@Mason[#111587]
	 Task : Manage licensee group
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20190515@Mason: Create SP
		- 20230524@Danny: Insert new log with more information [#FeatureID 175125]
*/

BEGIN
	SET NOCOUNT ON
	
	DECLARE @PathCode VARCHAR(50) = '/'
	DECLARE @ParentIdString VARCHAR(5) = CAST(@ParentId AS VARCHAR(5))
	DECLARE @StartRun DATETIME, @Duration INT, @LogSPData NVARCHAR(MAX), @LogSPOldData NVARCHAR(MAX), @endRun DATETIME

	SET @startRun = GETDATE()

	IF NOT EXISTS (SELECT GroupId FROM dbo.LA_CombinedGroup WITH(NOLOCK) WHERE GroupId = @GroupId)
	BEGIN
		SET @ErrCode = 1
		SET @ErrMsg = 'Group Id does not exist.'
		RETURN;
	END
	
	IF @GroupId = 0
	BEGIN
		SET @ErrCode = 1
		SET @ErrMsg = 'Group Id is invalid.'
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

	SELECT @LogSPOldData = 
	(
		SELECT  c.GroupName 'gi.lg', 
				ISNULL(p.GroupName, 0) 'gi.ulg', 
				STRING_AGG(op.PartyName,', ') AS 'gi.lig', 
				STRING_AGG(CAST(op.PartyID AS VARCHAR(50)),',') AS 'gi.pid'
		FROM dbo.LA_CombinedGroup c WITH(NOLOCK)
		LEFT JOIN dbo.LA_CombinedGroup p WITH(NOLOCK) ON c.PathCode LIKE ('%/' + CAST(p.GroupId AS VARCHAR(5)) + '/')
		LEFT JOIN LA_CombinedGroupAssignment lc WITH(NOLOCK) ON c.GroupId = lc.GroupId
		LEFT JOIN OAS_party op WITH(NOLOCK) ON op.PartyID = lc.PartyId
		WHERE c.GroupId = @GroupId
		GROUP BY c.GroupId, c.GroupName, ISNULL(p.GroupName, 0)  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER 
	)
	
	UPDATE dbo.LA_CombinedGroup WITH (ROWLOCK)
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

	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

	SELECT @LogSPData = 
	(
		SELECT  c.GroupName 'gi.lg', 
				ISNULL(p.GroupName, 0) 'gi.ulg', 
				STRING_AGG(op.PartyName,', ') AS 'gi.lig', 
				STRING_AGG(CAST(op.PartyID AS VARCHAR(50)),',') AS 'gi.pid'
		FROM dbo.LA_CombinedGroup c WITH(NOLOCK)
		LEFT JOIN dbo.LA_CombinedGroup p WITH(NOLOCK) ON c.PathCode LIKE ('%/' + CAST(p.GroupId AS VARCHAR(5)) + '/')
		LEFT JOIN LA_CombinedGroupAssignment lc WITH(NOLOCK) ON c.GroupId = lc.GroupId
		LEFT JOIN OAS_party op WITH(NOLOCK) ON op.PartyID = lc.PartyId
		WHERE c.GroupId = @GroupId
		GROUP BY c.GroupId, c.GroupName, ISNULL(p.GroupName, 0)  FOR JSON PATH, WITHOUT_ARRAY_WRAPPER 
	)

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIp
		,@SPName		= 'LA_LicenseeGroupUpd'
		,@CustId		= @GroupId
		,@Duration		= @duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue = @LogSPOldData
		,@ActionID		 = 1901
END
GO