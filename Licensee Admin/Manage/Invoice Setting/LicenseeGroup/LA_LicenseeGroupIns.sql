/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
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
	@ErrCode	INT = 0 OUTPUT,
	@UserId		INT, 
	@LoginIp	VARCHAR (50)	= ''
AS
/*  
	 Created: 20190514@Bruce[#111587]
	 Task : Manage licensee group
	 DB: DBCUST.bodb_licensee   

	 Revisions:  
		- 20190514@Bruce: Create SP
		- 20230524@Danny: Insert new log with more information [#FeatureID 175125]
*/

BEGIN
	SET NOCOUNT ON
	
	DECLARE @PathCode VARCHAR(50) = '/'
	DECLARE @ParentIdString VARCHAR(5) = CAST(@ParentId AS VARCHAR(5))
	DECLARE @StartRun DATETIME, @Duration INT, @LogSPData NVARCHAR(MAX), @LogSPOldData NVARCHAR(MAX), @endRun DATETIME

	SET @startRun = GETDATE()

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
		,@SPName		= 'LA_LicenseeGroupIns'
		,@CustId		= @GroupId
		,@Duration		= @duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue = @LogSPOldData
		,@ActionID		 = 1900
END
GO