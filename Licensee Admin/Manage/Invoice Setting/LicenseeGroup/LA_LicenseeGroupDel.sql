/*<info serverAlias="DBCUST-bodb_Licensee" executers="bodbAdminNet" isFunction="0" isNested="0"></info>*/
USE bodb_Licensee
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

ALTER PROCEDURE [dbo].[LA_LicenseeGroupDel]
	@GroupId	INT,
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
	DECLARE @StartRun DATETIME, @Duration INT, @LogSPData NVARCHAR(MAX), @LogSPOldData NVARCHAR(MAX), @endRun DATETIME

	SET @startRun = GETDATE()

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
	
	DELETE dbo.LA_CombinedGroup WITH (ROWLOCK, UPDLOCK) WHERE GroupId = @GroupId
	DELETE dbo.LA_CombinedGroupAssignment WITH (ROWLOCK, UPDLOCK) WHERE GroupId = @GroupId

	SET @endRun = GETDATE()
	SET @duration = DATEDIFF(MILLISECOND, @startRun, @endRun)

	

	-- Write Log
	EXEC CustDB.dbo.LA_WriteLog_UserLog_RunSP_Wrapper
		@UserId			= @UserID
		,@IP			= @LoginIp
		,@SPName		= 'LA_LicenseeGroupDel'
		,@CustId		= @GroupId
		,@Duration		= @duration
		,@TrackingValue2 = @LogSPData
		,@TrackingValue = @LogSPOldData
		,@ActionID		 = 1902
END
GO